#!/usr/bin/env python3
"""Authenticated Home Assistant ingress panel for editing Git ignore rules."""
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from datetime import datetime, timezone
import os
import subprocess
from urllib.parse import parse_qs, urlparse

GITIGNORE_FILE = Path("/data/gitignore")
STATUS_FILE = Path("/data/sync-status.json")
OPTIONS_FILE = Path("/data/options.json")
REPOSITORY_DIR = Path("/data/repository")
ADDON_VERSION = os.getenv("ADDON_VERSION", "unknown")
PROJECT_URL = "https://github.com/ma-world/ha-config"
DEFAULT_RULES = """# Runtime and generated Home Assistant data
homeassistant/home-assistant_v2.db*
homeassistant/*.log
homeassistant/.storage/*
!homeassistant/.storage/lovelace
!homeassistant/.storage/lovelace_dashboards

# Credentials are excluded unless you deliberately change this rule
homeassistant/secrets.yaml

# Large generated or media files that can cause slow Git pushes
homeassistant/www/**/*.mp4
homeassistant/www/**/*.zip
homeassistant/www/**/*.tar
homeassistant/esphome/.esphome/
homeassistant/zigbee2mqtt/database.db*
homeassistant/zigbee2mqtt/logs/
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
    h1 { margin: 0; font-size: 1.5rem; }
    .header { display: flex; align-items: baseline; justify-content: space-between; gap: 16px; margin-bottom: 16px; }
    .metadata { color: #5e6b76; font-size: .9rem; white-space: nowrap; }
    a { color: #0288d1; }
    p { line-height: 1.5; }
    .repository-link { display: inline-block; margin: 0 0 16px; padding: 9px 14px; border-radius: 5px; background: #37474f; color: #fff; font-weight: 700; text-decoration: none; }
    .repository-link:hover { background: #455a64; }
    textarea { box-sizing: border-box; display: block; width: 100%; min-height: 24em; resize: vertical; overflow-y: auto; padding: 12px; border: 1px solid #89939e; border-radius: 6px; font: 14px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace; }
    button { margin-top: 16px; margin-right: 8px; padding: 10px 18px; border: 0; border-radius: 5px; background: #03a9f4; color: #fff; font-weight: 700; cursor: pointer; }
    .danger-button { background: #c62828; }
    .danger-button:hover { background: #b71c1c; }
    .notice { padding: 10px 12px; border-radius: 6px; background: #d9f5e5; color: #095a31; }
    .warning { padding: 10px 12px; border-radius: 6px; background: #fff1c2; color: #6a4600; line-height: 1.5; }
    .status { display: grid; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); gap: 12px; margin: 16px 0; }
    .status-item { padding: 12px; border: 1px solid #c7cdd4; border-radius: 6px; }
    .status-label { display: block; font-size: .85rem; color: #5e6b76; }
    .status-value { display: block; margin-top: 4px; font-weight: 700; }
    code { background: #e8ebef; padding: 2px 4px; border-radius: 3px; }
    @media (prefers-color-scheme: dark) { body { background: #101418; color: #ecf1f5; } section { background: #20262c; } textarea { background: #151a1f; color: #ecf1f5; } .notice { background: #153d29; color: #bff5d3; } .warning { background: #4a3612; color: #ffe2a3; } .status-item { border-color: #48535e; } .status-label, .metadata { color: #b5c0c9; } a { color: #4fc3f7; } .repository-link { background: #455a64; color: #fff; } .repository-link:hover { background: #546e7a; } .danger-button { background: #c62828; } .danger-button:hover { background: #b71c1c; } code { background: #343d46; } }
  </style>
</head>
<body>
<main><section>
  <div class="header">
    <h1>Git Ignore Editor</h1>
    <span class="metadata">Version {version} · <a href="{project_url}" target="_blank" rel="noopener noreferrer">GitHub project</a></span>
  </div>
  {notice}
  <div class="status">
    <div class="status-item"><span class="status-label">Last check</span><span class="status-value">{last_check}</span></div>
    <div class="status-item"><span class="status-label">Last commit with changes</span><span class="status-value">{last_commit}</span></div>
  </div>
  {backup_repository_link}
  <p>These rules are copied to <code>.gitignore</code> in the private backup repository before every sync. The editor shows 15 lines and scrolls for longer rule sets.</p>
  {secrets_warning}
  <p><strong>Security:</strong> Keep <code>homeassistant/secrets.yaml</code> ignored unless you deliberately want to store secrets in a private repository.</p>
  <form method="post" action="save">
    <textarea name="gitignore" rows="15" spellcheck="false" aria-label="Git ignore rules">{rules}</textarea>
    <button type="submit">Save ignore rules</button>
  </form>
  <form method="post" action="clear-cache" onsubmit="return confirm('Clear the local Git cache? Unpushed local commits will be discarded. The next sync will download the repository again.');">
    <button class="danger-button" type="submit">Clear local Git cache</button>
  </form>
</section></main>
</body></html>"""


def html_escape(value: str) -> str:
    return (value.replace("&", "&amp;").replace("<", "&lt;")
                 .replace(">", "&gt;").replace('"', "&quot;"))


def backup_repository_url() -> str | None:
    try:
        output = subprocess.check_output(
            ["git", "-C", str(REPOSITORY_DIR), "remote", "get-url", "origin"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return None

    if output.startswith("https://github.com/"):
        return output.removesuffix(".git").rstrip("/")
    if output.startswith("git@github.com:"):
        return "https://github.com/" + output.removeprefix("git@github.com:").removesuffix(".git")
    if output.startswith("ssh://git@github.com/"):
        return "https://github.com/" + output.removeprefix("ssh://git@github.com/").removesuffix(".git")
    return None


def backup_repository_link() -> str:
    url = backup_repository_url()
    if not url:
        return ""
    safe_url = html_escape(url)
    return (f'<a class="repository-link" href="{safe_url}" target="_blank" '
            f'rel="noopener noreferrer">Open private backup repository</a>')


def repository_gitignore() -> str | None:
    path = REPOSITORY_DIR / ".gitignore"
    try:
        return path.read_text(encoding="utf-8") if path.is_file() else None
    except OSError:
        return None


def read_rules() -> str:
    # The editor cache is authoritative. It is updated immediately when the
    # user saves, and the sync process copies it into the local Git checkout.
    # This prevents an old local checkout from overwriting a newer editor value.
    try:
        saved_rules = GITIGNORE_FILE.read_text(encoding="utf-8")
    except (FileNotFoundError, OSError):
        saved_rules = ""

    if saved_rules.strip():
        return saved_rules

    repository_rules = repository_gitignore()
    rules = repository_rules or DEFAULT_RULES
    GITIGNORE_FILE.parent.mkdir(parents=True, exist_ok=True)
    GITIGNORE_FILE.write_text(rules, encoding="utf-8")
    GITIGNORE_FILE.chmod(0o600)
    return rules


def git_last_commit() -> str | None:
    if not (REPOSITORY_DIR / ".git").is_dir():
        return None
    try:
        return subprocess.check_output(
            ["git", "-C", str(REPOSITORY_DIR), "log", "-1", "--format=%cI"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip() or None
    except (OSError, subprocess.CalledProcessError):
        return None


def format_timestamp(value: str | None, fallback: str) -> str:
    if not value:
        return fallback
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    except ValueError:
        return value


def include_secrets_enabled() -> bool:
    try:
        import json
        return json.loads(OPTIONS_FILE.read_text(encoding="utf-8")).get("include_secrets") is True
    except (FileNotFoundError, ValueError):
        return False


def secrets_warning(rules: str) -> str:
    secrets_ignored = any(
        line.strip().lstrip("/") == "homeassistant/secrets.yaml"
        for line in rules.splitlines()
        if not line.strip().startswith("#")
    )
    if not secrets_ignored and not include_secrets_enabled():
        return ("<p class='warning'><strong>Secrets are still protected.</strong> "
                "The ignore rule for <code>homeassistant/secrets.yaml</code> was removed, "
                "but <strong>Include secrets</strong> is disabled in the add-on configuration. "
                "The file will not be copied or committed until you explicitly enable that option.</p>")
    if include_secrets_enabled() and secrets_ignored:
        return ("<p class='warning'><strong>Secrets will not be committed.</strong> "
                "<strong>Include secrets</strong> is enabled, but "
                "<code>homeassistant/secrets.yaml</code> is still ignored by these rules.</p>")
    if include_secrets_enabled() and not secrets_ignored:
        return ("<p class='warning'><strong>Secrets backup is enabled.</strong> "
                "<code>homeassistant/secrets.yaml</code> can be committed to your private backup repository.</p>")
    return ""


def read_status() -> dict[str, str]:
    try:
        import json
        status = json.loads(STATUS_FILE.read_text(encoding="utf-8"))
    except (FileNotFoundError, ValueError):
        status = {}
    return {
        "last_check": format_timestamp(status.get("last_check"), "Not checked yet"),
        # Fall back to the existing local Git history so the UI shows commits
        # made before this status tracking feature was introduced.
        "last_commit": format_timestamp(
            status.get("last_commit") or git_last_commit(), "No commits yet"
        ),
    }


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlparse(self.path).path.rstrip("/") or "/"
        if path != "/":
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        message = "<p class=\"notice\">Ignore rules saved.</p>" if "saved=1" in self.path else ""
        status = read_status()
        rules = read_rules()
        page = (PAGE.replace("{notice}", message)
                     .replace("{secrets_warning}", secrets_warning(rules))
                     .replace("{backup_repository_link}", backup_repository_link())
                     .replace("{rules}", html_escape(rules))
                     .replace("{last_check}", html_escape(status["last_check"]))
                     .replace("{last_commit}", html_escape(status["last_commit"]))
                     .replace("{version}", html_escape(ADDON_VERSION))
                     .replace("{project_url}", PROJECT_URL))
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(page.encode("utf-8"))))
        self.end_headers()
        self.wfile.write(page.encode("utf-8"))

    def do_POST(self):
        path = urlparse(self.path).path.rstrip("/")
        if path == "/save":
            length = int(self.headers.get("Content-Length", "0"))
            payload = self.rfile.read(length).decode("utf-8")
            rules = parse_qs(payload, keep_blank_values=True).get("gitignore", [""])[0]
            rules = rules.rstrip("\n") + "\n" if rules else ""
            GITIGNORE_FILE.parent.mkdir(parents=True, exist_ok=True)
            GITIGNORE_FILE.write_text(rules, encoding="utf-8")
            GITIGNORE_FILE.chmod(0o600)
            # Apply the saved editor content immediately to the local clone as
            # well. This makes a reload show the saved value even before the
            # next scheduled synchronization.
            if REPOSITORY_DIR.is_dir():
                (REPOSITORY_DIR / ".gitignore").write_text(rules, encoding="utf-8")
            self.send_response(HTTPStatus.SEE_OTHER)
            self.send_header("Location", "./?saved=1")
            self.end_headers()
            return
        if path == "/clear-cache":
            try:
                import shutil
                shutil.rmtree(REPOSITORY_DIR)
            except FileNotFoundError:
                pass
            self.send_response(HTTPStatus.SEE_OTHER)
            self.send_header("Location", "./?cache-cleared=1")
            self.end_headers()
            return
        self.send_error(HTTPStatus.NOT_FOUND)

    def log_message(self, _format, *_args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8099), Handler).serve_forever()
