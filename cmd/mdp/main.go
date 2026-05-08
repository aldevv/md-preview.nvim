// Command mdp renders a markdown file to HTML and opens it in a browser.
//
// One-shot static preview: writes HTML to a stable temp file (sha1 of the
// input path) and launches a browser. Mirrors the Python scripts/mdp CLI.
package main

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"syscall"

	"github.com/aldevv/md-preview/internal/config"
	"github.com/aldevv/md-preview/internal/render"
)

// Environment groups the OS-touching dependencies of run so tests can fake
// them. Production wiring lives in realEnv.
type Environment struct {
	LookPath func(string) (string, error)
	GOOS     string
	Stat     func(string) (os.FileInfo, error)
	TempDir  func() string
	Getwd    func() (string, error)
	// FzfPick returns the user's pick (absolute or relative) or "" on
	// cancellation. Returns an error if fzf itself is unavailable.
	FzfPick func(ctx context.Context, cwd string) (string, error)
	// LoadConfig returns the parsed config and a non-nil error only on
	// parse failure (missing file is not an error).
	LoadConfig func() (config.Config, error)
	// Spawn launches a detached browser process. Tests substitute a no-op.
	Spawn func(argv []string) error
	// Exec replaces the current process (used for nvim handoff). Tests
	// substitute a recorder.
	Exec func(path string, argv []string, env []string) error
}

func realEnv() Environment {
	return Environment{
		LookPath:   exec.LookPath,
		GOOS:       runtime.GOOS,
		Stat:       os.Stat,
		TempDir:    os.TempDir,
		Getwd:      func() (string, error) { return os.Getwd() },
		FzfPick:    config.FzfPick,
		LoadConfig: config.Load,
		Spawn:      spawnDetached,
		Exec:       syscall.Exec,
	}
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr, realEnv()))
}

const usage = `Usage: mdp [flags] [file]

Render a markdown file in a browser.

Flags:
  -e, --edit       Also open the file in nvim after launching the preview
      --no-edit    Override config to skip opening nvim
  -t, --theme      Theme: "dark" or "light" (default: from config or "dark")
  -p, --print      Print HTML path instead of opening a browser
  -h, --help       Show this help
`

// run executes the CLI with the given args and IO. Returns the exit code.
func run(args []string, _ io.Reader, stdout, stderr io.Writer, env Environment) int {
	if len(args) > 0 && args[0] == "serve" {
		fmt.Fprintln(stderr, "mdp: serve subcommand not yet wired (will be added by coordinator)")
		return 2
	}

	fs := flag.NewFlagSet("mdp", flag.ContinueOnError)
	fs.SetOutput(stderr)
	fs.Usage = func() { fmt.Fprint(stderr, usage) }

	var (
		editLong   = fs.Bool("edit", false, "")
		editShort  = fs.Bool("e", false, "")
		_          = fs.Bool("no-edit", false, "")
		themeLong  = fs.String("theme", "", "")
		themeShort = fs.String("t", "", "")
		printLong  = fs.Bool("print", false, "")
		printShort = fs.Bool("p", false, "")
	)

	if err := fs.Parse(args); err != nil {
		return 1
	}

	// Track which forms were explicitly passed so -e and --no-edit can
	// be reliably distinguished from defaults.
	editSet, noEditSet := false, false
	fs.Visit(func(f *flag.Flag) {
		switch f.Name {
		case "edit", "e":
			editSet = true
		case "no-edit":
			noEditSet = true
		}
	})

	if editSet && noEditSet {
		fmt.Fprintln(stderr, "mdp: -e/--edit and --no-edit conflict")
		return 1
	}

	editFlagOn := *editLong || *editShort
	printPath := *printLong || *printShort

	theme := *themeLong
	if theme == "" {
		theme = *themeShort
	}

	cfg, err := env.LoadConfig()
	if err != nil {
		fmt.Fprintf(stderr, "mdp: config: %v\n", err)
	}

	var edit bool
	switch {
	case editSet:
		edit = editFlagOn
	case noEditSet:
		edit = false
	default:
		edit = cfg.Edit
	}

	file := ""
	if fs.NArg() > 0 {
		file = fs.Arg(0)
	}

	if file == "" {
		cwd, err := env.Getwd()
		if err != nil {
			fmt.Fprintf(stderr, "mdp: %v\n", err)
			return 1
		}
		pick, err := env.FzfPick(context.Background(), cwd)
		if err != nil {
			fmt.Fprint(stderr, usage)
			fmt.Fprintln(stderr, "\nmdp: fzf is not installed — pass a file argument, or install fzf to pick interactively.")
			return 1
		}
		if pick == "" {
			return 0
		}
		file = pick
	}

	src, err := filepath.Abs(file)
	if err != nil {
		fmt.Fprintf(stderr, "mdp: %v\n", err)
		return 1
	}
	info, err := env.Stat(src)
	if err != nil || info.IsDir() {
		fmt.Fprintf(stderr, "mdp: file not found: %s\n", src)
		return 1
	}

	if theme == "" {
		theme = cfg.Theme
	}
	if theme == "" {
		theme = "dark"
	}
	if theme != "dark" && theme != "light" {
		fmt.Fprintf(stderr, "mdp: invalid theme %q, using 'dark'\n", theme)
		theme = "dark"
	}

	body, _ := render.RenderBody(src)
	page := render.BuildPage(body, theme, 0, config.ExtraCSS(cfg, stderr))

	tmpPath := tmpHTMLPath(env.TempDir(), src)
	if err := os.WriteFile(tmpPath, []byte(page), 0o644); err != nil {
		fmt.Fprintf(stderr, "mdp: writing tmp: %v\n", err)
		return 1
	}

	if printPath {
		fmt.Fprintln(stdout, tmpPath)
		return 0
	}

	argv := config.BrowserCmd(cfg.Browser, "file://"+tmpPath, env.LookPath, env.GOOS, stderr)
	if err := env.Spawn(argv); err != nil {
		fmt.Fprintf(stderr, "mdp: launching browser: %v\n", err)
		return 1
	}

	if !edit {
		return 0
	}

	editor := ""
	for _, c := range []string{"nvim", "vim"} {
		if p, err := env.LookPath(c); err == nil && p != "" {
			editor = p
			break
		}
	}
	if editor == "" {
		fmt.Fprintln(stderr, "mdp: nvim/vim not found on PATH; preview opened, edit skipped.")
		return 0
	}
	if err := env.Exec(editor, []string{filepath.Base(editor), src}, os.Environ()); err != nil {
		fmt.Fprintf(stderr, "mdp: exec %s: %v\n", editor, err)
		return 1
	}
	return 0
}

// tmpHTMLPath returns a stable temp HTML path so re-runs on the same source
// overwrite rather than accumulate.
func tmpHTMLPath(tmpdir, src string) string {
	sum := sha1.Sum([]byte(src))
	digest := hex.EncodeToString(sum[:])[:12]
	return filepath.Join(tmpdir, "mdp-"+digest+".html")
}

// spawnDetached starts argv in its own session so closing the terminal does
// not kill the browser. Output is discarded.
func spawnDetached(argv []string) error {
	if len(argv) == 0 {
		return fmt.Errorf("empty browser command")
	}
	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.Stdout = nil
	cmd.Stderr = nil
	cmd.Stdin = nil
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	return cmd.Start()
}
