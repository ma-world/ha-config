#!/usr/bin/env python3
"""Authenticated Home Assistant ingress panel for editing Git ignore rules."""
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

GITIGNORE_FILE = Path("/data/gitignore")
DEFAULT_RULES = """# Runtime and generated Home Assistant data
homeassistant/home-assistant_v2.db*
homeassistant/*.log
homeassistant/.storage/*
!homeassistant/.storage/lovelace
!homeassistant/.storage/lovelace_dashboards

# Credentials are excluded unless you deliberately change this rule
homeassistant/secrets.yaml
"""

PAGE = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Git Ignore Editor</title>
  <style>
    :root { color-scheme: light dark; font-family: system-ui, -apple-system, sans-serif; }
    body { margin: 0; background: #f4f6f8; color: #1f2933; }
    main { max-width: 900px; margin: 28px auto; padding: 0 20px; }
    section { background: #fff; padding: 24px; border-radius: 10px; box-shadow: 0 2px 8px #0002; }
    h1 { margin-top: 0; font-size: 1.5rem; }
    p { line-height: 1.5; }
    textarea { box-sizing: border-box; display: block; width: 100%; min-height: 24em; resize: vertical; overflow-y: auto; padding: 12px; border: 1px solid #89939e; border-radius: 6px; font: 14px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace; }
    button { margin-top: 16px; padding: 10px 18px; border: 0; border-radius: 5px; background: #03a9f4; color: #fff; font-weight: 700; cursor: pointer; }
    .notice { padding: 10px 12px; border-radius: 6px; background: #d9f5e5; color: #095a31; }
    code { background: #e8ebef; padding: 2px 4px; border-radius: 3px; }
    @media (prefers-color-scheme: dark) { body { background: #101418; color: #ecf1f5; } section { background: #20262c; } textarea { background: #151a1f; color: #ecf1f5; } .notice { background: #153d29; color: #bff5d3; } code { background: #343d46; } }
  </style>
</head>
<body>
<main><section>
  <h1>Git Ignore Editor</h1>
  {notice}
  <p>These rules are copied to <code>.gitignore</code> in the private backup repository before every sync. The editor shows 15 lines and scrolls for longer rule sets.</p>
  <p><strong>Security:</strong> Keep <code>homeassistant/secrets.yaml</code> ignored unless you deliberately want to store secrets in a private repository.</p>
  <form method="post" action="save">
    <textarea name="gitignore" rows="15" spellcheck="false" aria-label="Git ignore rules">{rules}</textarea>
    <button type="submit">Save ignore rules</button>
  </form>
</section></main>
</body></html>"""


def html_escape(value: str) -> str:
    return (value.replace("&", "&amp;").replace("<", "&lt;")
                 .replace(">", "&gt;").replace('"', "&quot;"))


def read_rules() -> str:
    if not GITIGNORE_FILE.exists():
        GITIGNORE_FILE.parent.mkdir(parents=True, exist_ok=True)
        GITIGNORE_FILE.write_text(DEFAULT_RULES, encoding="utf-8")
        GITIGNORE_FILE.chmod(0o600)
    return GITIGNORE_FILE.read_text(encoding="utf-8")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlparse(self.path).path.rstrip("/") or "/"
        if path != "/":
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        message = "<p class=\"notice\">Ignore rules saved.</p>" if "saved=1" in self.path else ""
        page = PAGE.format(notice=message, rules=html_escape(read_rules()))
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(page.encode("utf-8"))))
        self.end_headers()
        self.wfile.write(page.encode("utf-8"))

    def do_POST(self):
        if urlparse(self.path).path.rstrip("/") != "/save":
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        length = int(self.headers.get("Content-Length", "0"))
        payload = self.rfile.read(length).decode("utf-8")
        rules = parse_qs(payload, keep_blank_values=True).get("gitignore", [""])[0]
        GITIGNORE_FILE.parent.mkdir(parents=True, exist_ok=True)
        GITIGNORE_FILE.write_text(rules.rstrip("\n") + "\n" if rules else "", encoding="utf-8")
        GITIGNORE_FILE.chmod(0o600)
        self.send_response(HTTPStatus.SEE_OTHER)
        self.send_header("Location", "./?saved=1")
        self.end_headers()

    def log_message(self, _format, *_args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8099), Handler).serve_forever()
