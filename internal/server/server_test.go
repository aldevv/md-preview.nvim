package server

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func writeMD(t *testing.T, dir, name, content string) string {
	t.Helper()
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatalf("write %s: %v", p, err)
	}
	return p
}

// newTestState creates a state with htmlCache primed via doRender so tests
// that exercise the / route get a real rendered body.
func newTestState(t *testing.T, file string) *state {
	t.Helper()
	s := newState(file, 0, "dark")
	s.doRender()
	return s
}

func TestHandler_GetHTML_ReturnsPage(t *testing.T) {
	dir := t.TempDir()
	file := writeMD(t, dir, "doc.md", "# Hello\n")
	s := newTestState(t, file)
	srv := httptest.NewServer(newHandler(s))
	defer srv.Close()

	resp, err := http.Get(srv.URL + "/")
	if err != nil {
		t.Fatalf("GET /: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", resp.StatusCode)
	}
	if ct := resp.Header.Get("Content-Type"); ct != "text/html; charset=utf-8" {
		t.Errorf("Content-Type = %q, want text/html; charset=utf-8", ct)
	}
	body, _ := io.ReadAll(resp.Body)
	if !strings.Contains(string(body), "<h1") {
		t.Errorf("body missing <h1: %s", body)
	}
	if !strings.Contains(string(body), "Hello") {
		t.Errorf("body missing 'Hello'")
	}
}

func TestHandler_PostRender_BumpsVersion(t *testing.T) {
	dir := t.TempDir()
	file := writeMD(t, dir, "doc.md", "# Hello\n")
	s := newTestState(t, file)
	srv := httptest.NewServer(newHandler(s))
	defer srv.Close()

	resp, err := http.Get(srv.URL + "/reload")
	if err != nil {
		t.Fatalf("GET /reload: %v", err)
	}
	var got map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&got)
	resp.Body.Close()
	if v, _ := got["version"].(float64); int(v) != 1 {
		t.Fatalf("initial version = %v, want 1", got["version"])
	}

	resp, err = http.Post(srv.URL+"/render", "application/json", strings.NewReader(`{}`))
	if err != nil {
		t.Fatalf("POST /render: %v", err)
	}
	got = map[string]any{}
	_ = json.NewDecoder(resp.Body).Decode(&got)
	resp.Body.Close()
	if ok, _ := got["ok"].(bool); !ok {
		t.Errorf("ok = %v, want true", got["ok"])
	}
	if v, _ := got["version"].(float64); int(v) != 2 {
		t.Errorf("post-render version = %v, want 2", got["version"])
	}

	resp, err = http.Get(srv.URL + "/reload")
	if err != nil {
		t.Fatalf("GET /reload (2): %v", err)
	}
	got = map[string]any{}
	_ = json.NewDecoder(resp.Body).Decode(&got)
	resp.Body.Close()
	if v, _ := got["version"].(float64); int(v) != 2 {
		t.Errorf("/reload version = %v, want 2", got["version"])
	}
}

func TestHandler_PostRender_SwitchesFile(t *testing.T) {
	dir := t.TempDir()
	first := writeMD(t, dir, "first.md", "# First\n")
	second := writeMD(t, dir, "second.md", "# Second\n")
	s := newTestState(t, first)
	srv := httptest.NewServer(newHandler(s))
	defer srv.Close()

	body, _ := json.Marshal(map[string]string{"file": second})
	resp, err := http.Post(srv.URL+"/render", "application/json", bytes.NewReader(body))
	if err != nil {
		t.Fatalf("POST /render: %v", err)
	}
	resp.Body.Close()

	resp, err = http.Get(srv.URL + "/")
	if err != nil {
		t.Fatalf("GET /: %v", err)
	}
	page, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if !strings.Contains(string(page), "Second") {
		t.Errorf("page missing 'Second' after switch: %s", page)
	}
	if strings.Contains(string(page), "First") {
		t.Errorf("page still contains 'First' after switch")
	}
}

func TestHandler_PostScroll_OK(t *testing.T) {
	dir := t.TempDir()
	file := writeMD(t, dir, "doc.md", "# Hello\n")
	s := newTestState(t, file)
	srv := httptest.NewServer(newHandler(s))
	defer srv.Close()

	resp, err := http.Post(srv.URL+"/scroll", "application/json", strings.NewReader(`{"line":42}`))
	if err != nil {
		t.Fatalf("POST /scroll: %v", err)
	}
	defer resp.Body.Close()
	var got map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&got)
	if ok, _ := got["ok"].(bool); !ok {
		t.Errorf("ok = %v, want true", got["ok"])
	}
	if line, _ := got["line"].(float64); int(line) != 42 {
		t.Errorf("line = %v, want 42", got["line"])
	}
}

func TestHandler_GetReload(t *testing.T) {
	dir := t.TempDir()
	file := writeMD(t, dir, "doc.md", "# Hello\n")
	s := newTestState(t, file)
	srv := httptest.NewServer(newHandler(s))
	defer srv.Close()

	resp, err := http.Get(srv.URL + "/reload")
	if err != nil {
		t.Fatalf("GET /reload: %v", err)
	}
	defer resp.Body.Close()
	if ct := resp.Header.Get("Content-Type"); ct != "application/json" {
		t.Errorf("Content-Type = %q, want application/json", ct)
	}
	var got map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&got)
	if v, ok := got["version"]; !ok {
		t.Errorf("missing 'version' field, got %v", got)
	} else if vf, _ := v.(float64); int(vf) != 1 {
		t.Errorf("version = %v, want 1", v)
	}
}

func TestHandler_404(t *testing.T) {
	dir := t.TempDir()
	file := writeMD(t, dir, "doc.md", "# Hello\n")
	s := newTestState(t, file)
	srv := httptest.NewServer(newHandler(s))
	defer srv.Close()

	resp, err := http.Get(srv.URL + "/nope")
	if err != nil {
		t.Fatalf("GET /nope: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Errorf("status = %d, want 404", resp.StatusCode)
	}
}

func TestStdin_RenderCommand(t *testing.T) {
	dir := t.TempDir()
	file := writeMD(t, dir, "doc.md", "# Hello\n")
	s := newTestState(t, file)
	if s.renderVersion != 1 {
		t.Fatalf("initial version = %d, want 1", s.renderVersion)
	}

	cmd := fmt.Sprintf(`{"type":"render","file":%q}`, file) + "\n"
	readStdin(s, strings.NewReader(cmd), func() {})

	if s.renderVersion != 2 {
		t.Errorf("after render: version = %d, want 2", s.renderVersion)
	}
}

func TestStdin_ScrollCommand(t *testing.T) {
	dir := t.TempDir()
	file := writeMD(t, dir, "doc.md", "# Hello\n")
	s := newTestState(t, file)
	versionBefore := s.renderVersion

	readStdin(s, strings.NewReader(`{"type":"scroll","line":7}`+"\n"), func() {})

	if s.renderVersion != versionBefore {
		t.Errorf("scroll changed version: got %d, want %d", s.renderVersion, versionBefore)
	}
}

func TestStdin_BlankLines(t *testing.T) {
	dir := t.TempDir()
	file := writeMD(t, dir, "doc.md", "# Hello\n")
	s := newTestState(t, file)
	versionBefore := s.renderVersion

	input := "\n   \nnot json\n{not:json}\n\n"
	readStdin(s, strings.NewReader(input), func() {})

	if s.renderVersion != versionBefore {
		t.Errorf("blank/invalid input changed version: got %d, want %d", s.renderVersion, versionBefore)
	}
}

func TestStdin_QuitCommand(t *testing.T) {
	dir := t.TempDir()
	file := writeMD(t, dir, "doc.md", "# Hello\n")
	s := newTestState(t, file)

	var (
		called bool
		mu     sync.Mutex
	)
	quit := func() {
		mu.Lock()
		called = true
		mu.Unlock()
	}

	done := make(chan struct{})
	go func() {
		readStdin(s, strings.NewReader(`{"type":"quit"}`+"\n"), quit)
		close(done)
	}()

	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("readStdin did not return after quit")
	}

	mu.Lock()
	defer mu.Unlock()
	if !called {
		t.Errorf("quit callback not invoked")
	}
}
