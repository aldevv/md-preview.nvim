package server

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"sync"

	"github.com/aldevv/md-preview/internal/render"
)

// state holds the server's mutable shared state. All access is guarded
// by mu; broadcast iterates over a snapshot of wsClients so a slow
// client cannot block others.
type state struct {
	mu            sync.Mutex
	file          string
	htmlCache     string
	renderVersion int
	theme         string
	port          int
	wsClients     map[net.Conn]struct{}
}

// newState constructs a state with the given initial file, port, and theme.
func newState(file string, port int, theme string) *state {
	return &state{
		file:      file,
		port:      port,
		theme:     theme,
		wsClients: make(map[net.Conn]struct{}),
	}
}

// doRender re-renders the currently watched file, updates the cache and
// version counter, and returns the new version.
func (s *state) doRender() int {
	s.mu.Lock()
	filepath := s.file
	s.mu.Unlock()

	body, _ := render.RenderBody(filepath)

	s.mu.Lock()
	s.htmlCache = body
	s.renderVersion++
	v := s.renderVersion
	s.mu.Unlock()
	return v
}

// addClient registers a connected WebSocket client.
func (s *state) addClient(c net.Conn) {
	s.mu.Lock()
	s.wsClients[c] = struct{}{}
	s.mu.Unlock()
}

// removeClient unregisters a WebSocket client.
func (s *state) removeClient(c net.Conn) {
	s.mu.Lock()
	delete(s.wsClients, c)
	s.mu.Unlock()
}

// broadcast sends msg as a single text frame to every connected client.
// Clients whose write fails are dropped from the registry.
func (s *state) broadcast(msg string) {
	frame := wsEncode(msg)
	s.mu.Lock()
	clients := make([]net.Conn, 0, len(s.wsClients))
	for c := range s.wsClients {
		clients = append(clients, c)
	}
	s.mu.Unlock()

	var dead []net.Conn
	for _, c := range clients {
		if _, err := c.Write(frame); err != nil {
			dead = append(dead, c)
		}
	}
	if len(dead) > 0 {
		s.mu.Lock()
		for _, c := range dead {
			delete(s.wsClients, c)
		}
		s.mu.Unlock()
	}
}

// newHandler builds the HTTP handler tree for a state. Exposed at package
// level (lowercase) so tests can drive routes directly without spawning
// the full server.
func newHandler(s *state) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/":
			handleIndex(s, w, r)
		case "/reload":
			handleReload(s, w, r)
		case "/ws":
			handleWS(s, w, r)
		case "/render":
			handleRender(s, w, r)
		case "/scroll":
			handleScroll(s, w, r)
		default:
			http.NotFound(w, r)
		}
	})
	return mux
}

func handleIndex(s *state, w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.NotFound(w, r)
		return
	}
	s.mu.Lock()
	body := s.htmlCache
	theme := s.theme
	port := s.port
	s.mu.Unlock()

	page := render.BuildPage(body, theme, port, "")
	encoded := []byte(page)
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Content-Length", strconv.Itoa(len(encoded)))
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(encoded)
}

func handleReload(s *state, w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.NotFound(w, r)
		return
	}
	s.mu.Lock()
	v := s.renderVersion
	s.mu.Unlock()
	writeJSON(w, map[string]any{"version": v})
}

func handleRender(s *state, w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.NotFound(w, r)
		return
	}
	data := readJSONBody(r)
	if fp, _ := data["file"].(string); fp != "" {
		s.mu.Lock()
		s.file = fp
		s.mu.Unlock()
	}
	v := s.doRender()
	payload, _ := json.Marshal(map[string]any{"type": "reload", "version": v})
	s.broadcast(string(payload))
	writeJSON(w, map[string]any{"ok": true, "version": v})
}

func handleScroll(s *state, w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.NotFound(w, r)
		return
	}
	data := readJSONBody(r)
	line := jsonInt(data["line"])
	payload, _ := json.Marshal(map[string]any{"type": "scroll", "line": line})
	s.broadcast(string(payload))
	writeJSON(w, map[string]any{"ok": true, "line": line})
}

func handleWS(s *state, w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.NotFound(w, r)
		return
	}
	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "hijacking not supported", http.StatusInternalServerError)
		return
	}
	key := r.Header.Get("Sec-WebSocket-Key")
	conn, brw, err := hj.Hijack()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	resp := "HTTP/1.1 101 Switching Protocols\r\n" +
		"Upgrade: websocket\r\n" +
		"Connection: Upgrade\r\n" +
		"Sec-WebSocket-Accept: " + wsAccept(key) + "\r\n\r\n"
	if _, err := brw.WriteString(resp); err != nil {
		_ = conn.Close()
		return
	}
	if err := brw.Flush(); err != nil {
		_ = conn.Close()
		return
	}

	s.addClient(conn)
	defer func() {
		s.removeClient(conn)
		_ = conn.Close()
	}()

	for {
		opcode, _ := wsReadFrame(brw.Reader)
		if opcode == 8 {
			return
		}
	}
}

// readJSONBody decodes the request body into a string-keyed map. Empty or
// invalid bodies yield an empty map (mirrors the Python lenient parsing).
func readJSONBody(r *http.Request) map[string]any {
	out := map[string]any{}
	if r.Body == nil {
		return out
	}
	defer r.Body.Close()
	body, err := io.ReadAll(r.Body)
	if err != nil || len(body) == 0 {
		return out
	}
	_ = json.Unmarshal(body, &out)
	return out
}

// jsonInt coerces a JSON-decoded value (typically float64) to int. Defaults
// to 0 for missing or non-numeric inputs.
func jsonInt(v any) int {
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	case int64:
		return int(n)
	case json.Number:
		i, _ := n.Int64()
		return int(i)
	}
	return 0
}

func writeJSON(w http.ResponseWriter, data any) {
	encoded, _ := json.Marshal(data)
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Content-Length", strconv.Itoa(len(encoded)))
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(encoded)
}

// readStdin consumes JSON commands from stdin one per line. Blank or
// invalid lines are silently skipped. The quit callback is invoked on
// {"type":"quit"} and the loop returns immediately.
func readStdin(s *state, stdin io.Reader, quit func()) {
	scanner := bufio.NewScanner(stdin)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		line := bytes.TrimSpace(scanner.Bytes())
		if len(line) == 0 {
			continue
		}
		var msg map[string]any
		if err := json.Unmarshal(line, &msg); err != nil {
			continue
		}
		mtype, _ := msg["type"].(string)
		switch mtype {
		case "quit":
			quit()
			return
		case "render":
			if fp, _ := msg["file"].(string); fp != "" {
				s.mu.Lock()
				s.file = fp
				s.mu.Unlock()
			}
			v := s.doRender()
			payload, _ := json.Marshal(map[string]any{"type": "reload", "version": v})
			s.broadcast(string(payload))
		case "scroll":
			line := jsonInt(msg["line"])
			payload, _ := json.Marshal(map[string]any{"type": "scroll", "line": line})
			s.broadcast(string(payload))
		}
	}
}

// serve runs the HTTP server and stdin reader concurrently. It returns
// when the HTTP server stops (port-in-use error, ctx cancellation, etc.)
// or when stdin closes/quits via the quit callback.
//
// quit is invoked from the stdin reader on {"type":"quit"}; production
// wires this to os.Exit(0). Tests pass a no-op or signaling channel.
func serve(ctx context.Context, s *state, stdin io.Reader, quit func()) error {
	s.doRender()

	addr := fmt.Sprintf("127.0.0.1:%d", s.port)
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return err
	}

	srv := &http.Server{
		Handler:  newHandler(s),
		ErrorLog: log.New(io.Discard, "", 0),
	}

	fmt.Fprintf(os.Stdout, "[md-preview] Serving on http://localhost:%d/\n", s.port)

	stdinDone := make(chan struct{})
	go func() {
		readStdin(s, stdin, quit)
		close(stdinDone)
	}()

	srvErr := make(chan error, 1)
	go func() {
		err := srv.Serve(ln)
		if err == http.ErrServerClosed {
			err = nil
		}
		srvErr <- err
	}()

	select {
	case <-ctx.Done():
		_ = srv.Close()
		return <-srvErr
	case <-stdinDone:
		_ = srv.Close()
		return <-srvErr
	case err := <-srvErr:
		return err
	}
}

// Run starts the HTTP server on 127.0.0.1:port with the initial file and
// theme, reads JSON commands from stdin, broadcasts reload/scroll
// messages over WebSockets to connected browser clients, and blocks
// until stdin closes or the process is interrupted. Returns the first
// fatal error (e.g., port in use). On a {"type":"quit"} stdin command
// the process exits with status 0.
//
// The startup line "[md-preview] Serving on http://localhost:<port>/" is
// written to stdout so external tooling parsing it keeps working.
func Run(file string, port int, theme string) error {
	s := newState(file, port, theme)
	return serve(context.Background(), s, os.Stdin, func() { os.Exit(0) })
}
