"""Shared rendering for md-preview server and CLI.

Self-bootstraps a venv under ~/.local/share/nvim/md-preview-venv on first
import, then exposes:
  - render_body(filepath)      → HTML body for the file
  - build_page(body, theme, *, ws_port=None) → full HTML page; pass ws_port
    to embed the WebSocket scroll/reload client used by the Neovim plugin.
"""

import glob as _glob
import os
import subprocess as _subprocess
import sys

VENV_DIR = os.path.expanduser("~/.local/share/nvim/md-preview-venv")
VENV_PYTHON = os.path.join(VENV_DIR, "bin", "python3")


def _ensure_venv():
    if not os.path.exists(VENV_PYTHON):
        print("[md-preview] Creating venv...", flush=True)
        _subprocess.run([sys.executable, "-m", "venv", VENV_DIR], check=True)
        print("[md-preview] Installing dependencies...", flush=True)
        _subprocess.run(
            [VENV_PYTHON, "-m", "pip", "install", "-q",
             "markdown-it-py", "mdit-py-plugins", "linkify-it-py"],
            check=True,
        )
    matches = _glob.glob(os.path.join(VENV_DIR, "lib", "python*", "site-packages"))
    if matches and matches[0] not in sys.path:
        sys.path.insert(0, matches[0])


_ensure_venv()

from markdown_it import MarkdownIt  # noqa: E402
from mdit_py_plugins.tasklists import tasklists_plugin  # noqa: E402

_md = MarkdownIt("gfm-like", {"linkify": True}).enable("linkify").use(tasklists_plugin)


def _strip_frontmatter(content: str) -> str:
    lines = content.split("\n")
    if not lines or lines[0].strip() != "---":
        return content
    end = -1
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end == -1:
        return content
    return "\n".join(lines[end + 1:])


def render_body(filepath: str) -> str:
    """Parse file, annotate elements with 1-indexed source lines, return HTML body."""
    try:
        with open(filepath, encoding="utf-8") as f:
            content = f.read()
    except OSError as e:
        return f"<p>Error reading file: {e}</p>"

    content = _strip_frontmatter(content)
    tokens = _md.parse(content)

    for token in tokens:
        if token.map is not None and (
            token.type.endswith("_open")
            or token.type in ("fence", "hr", "html_block", "table")
        ):
            token.attrSet("data-line", str(token.map[0] + 1))

    return _md.renderer.render(tokens, _md.options, {})


# ── HTML template ─────────────────────────────────────────────────────────
CSS_DARK = """
:root {
  --color-bg-primary: #0d1117;
  --color-text-primary: #c9d1d9;
  --color-text-secondary: #8b949e;
  --color-border: #30363d;
  --color-bg-code: #161b22;
  --color-link: #58a6ff;
  --color-heading-border: #21262d;
}
"""

CSS_LIGHT = """
:root {
  --color-bg-primary: #ffffff;
  --color-text-primary: #24292e;
  --color-text-secondary: #586069;
  --color-border: #e1e4e8;
  --color-bg-code: #f6f8fa;
  --color-link: #0366d6;
  --color-heading-border: #eaecef;
}
"""

CSS_COMMON = """
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  background: var(--color-bg-primary);
  color: var(--color-text-primary);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
  font-size: 16px;
  line-height: 1.6;
  padding: 32px;
  max-width: 900px;
  margin: 0 auto;
}
.markdown-body h1 { font-size: 2.25em; border-bottom: 1px solid var(--color-heading-border); padding-bottom: 0.3em; margin-bottom: 1em; margin-top: 1.5em; }
.markdown-body h2 { font-size: 1.75em; border-bottom: 1px solid var(--color-heading-border); padding-bottom: 0.3em; margin-bottom: 1em; margin-top: 1.5em; }
.markdown-body h3 { font-size: 1.5em; margin-bottom: 0.75em; margin-top: 1.5em; }
.markdown-body h4 { font-size: 1.25em; margin-bottom: 0.75em; margin-top: 1.5em; }
.markdown-body h5 { font-size: 1em; margin-bottom: 0.75em; margin-top: 1.5em; }
.markdown-body h6 { font-size: 0.875em; color: var(--color-text-secondary); margin-bottom: 0.75em; margin-top: 1.5em; }
.markdown-body p { margin-bottom: 1em; }
.markdown-body a { color: var(--color-link); text-decoration: none; }
.markdown-body a:hover { text-decoration: underline; }
.markdown-body code {
  background: var(--color-bg-code);
  border-radius: 4px;
  font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
  font-size: 85%;
  padding: 0.2em 0.4em;
}
.markdown-body pre {
  background: var(--color-bg-code);
  border-radius: 6px;
  overflow: auto;
  padding: 16px;
  margin-bottom: 1em;
}
.markdown-body pre code {
  background: none;
  padding: 0;
  font-size: 100%;
  white-space: pre;
}
.markdown-body blockquote {
  border-left: 4px solid var(--color-border);
  color: var(--color-text-secondary);
  padding: 0 1em;
  margin-bottom: 1em;
}
.markdown-body ul, .markdown-body ol { padding-left: 2em; margin-bottom: 1em; }
.markdown-body li { margin-bottom: 0.25em; }
.markdown-body table { border-collapse: collapse; width: 100%; margin-bottom: 1em; }
.markdown-body th, .markdown-body td {
  border: 1px solid var(--color-border);
  padding: 6px 13px;
  text-align: left;
}
.markdown-body th { background: var(--color-bg-code); font-weight: 600; }
.markdown-body tr:nth-child(even) { background: var(--color-bg-code); }
.markdown-body hr { border: none; border-top: 1px solid var(--color-border); margin: 1.5em 0; }
.markdown-body img { max-width: 100%; }
"""

HLJS_THEME_DARK = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css"
HLJS_THEME_LIGHT = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css"


_WS_SCRIPT = """
function absDocTop(el) {
    let y = 0;
    while (el) { y += el.offsetTop; el = el.offsetParent; }
    return y;
}
let _els = [];
function cacheEls() {
    _els = [...document.querySelectorAll('[data-line]')]
        .map(el => ({ el, line: parseInt(el.dataset.line), top: absDocTop(el) }))
        .sort((a, b) => a.line - b.line);
}
window.addEventListener('load', cacheEls);

const ws = new WebSocket('ws://localhost:__PORT__/ws');
ws.onmessage = (e) => {
    const msg = JSON.parse(e.data);
    if (msg.type === 'scroll') {
        if (!_els.length) return;
        const line = msg.line;
        let prev = _els[0], next = null;
        for (let i = 0; i < _els.length; i++) {
            if (_els[i].line <= line) { prev = _els[i]; next = _els[i+1] || null; }
            else break;
        }
        let targetTop;
        if (next && next.line > prev.line) {
            const frac = (line - prev.line) / (next.line - prev.line);
            targetTop = prev.top + frac * (next.top - prev.top);
        } else {
            targetTop = prev.top;
        }
        window.scrollTo({ top: targetTop - window.innerHeight * 0.5, behavior: 'smooth' });
    }
    if (msg.type === 'reload') {
        fetch('/').then(r => r.text()).then(html => {
            const doc = new DOMParser().parseFromString(html, 'text/html');
            document.querySelector('#content').innerHTML =
                doc.querySelector('#content').innerHTML;
            hljs.highlightAll();
            cacheEls();
        });
    }
};
ws.onclose = () => setTimeout(() => location.reload(), 1000);
"""


def build_page(
    html_body: str,
    theme: str,
    *,
    ws_port: int | None = None,
    extra_css: str = "",
) -> str:
    """Wrap an HTML body in the page template.

    ws_port: embed the WebSocket scroll/reload client (Neovim plugin only).
    extra_css: appended after the default CSS so it wins via cascade.
    """
    css_vars = CSS_DARK if theme == "dark" else CSS_LIGHT
    hljs_theme = HLJS_THEME_DARK if theme == "dark" else HLJS_THEME_LIGHT
    ws_script = _WS_SCRIPT.replace("__PORT__", str(ws_port)) if ws_port else ""
    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="{hljs_theme}">
<style>
{css_vars}
{CSS_COMMON}
{extra_css}
</style>
</head>
<body>
<div id="content" class="markdown-body">
{html_body}
</div>
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<script>
hljs.highlightAll();
{ws_script}
</script>
</body>
</html>"""
