#!/usr/bin/env python3
"""Authenticated Home Assistant ingress panel for HA Config Sync status and diagnostics."""
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from datetime import datetime, timezone
import os
import json
import subprocess
from urllib.parse import parse_qs, urlparse

CONFIG_DIR = Path("/homeassistant")
ADDON_CONFIG_DIR = Path("/config")
GITIGNORE_FILE = ADDON_CONFIG_DIR / "gitignore"
STATUS_FILE = Path("/data/sync-status.json")
WEB_DEBUG_LOG = Path("/data/web-editor-debug.log")
SYNC_DEBUG_LOG = Path("/data/sync-debug.log")
OPTIONS_FILE = Path("/data/options.json")
GIT_METADATA_DIR = Path("/data/git")
ADDON_VERSION = os.getenv("ADDON_VERSION", "unknown")
PROJECT_URL = "https://github.com/ma-world/ha-config"
DEFAULT_RULES = """# Runtime and generated Home Assistant data
home-assistant_v2.db*
*.log
.storage/*
!.storage/lovelace
!.storage/lovelace_dashboards

# Credentials are excluded unless you deliberately change this rule
secrets.yaml

# Large generated or media files that can cause slow Git pushes
www/**/*.mp4
www/**/*.zip
www/**/*.tar
www/community/
esphome/.esphome/
zigbee2mqtt/database.db*
zigbee2mqtt/logs/
"""

PAGE = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>HA Config Sync Status</title>
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
    button { margin-top: 16px; margin-right: 8px; padding: 10px 18px; border: 0; border-radius: 5px; background: #03a9f4; color: #fff; font-weight: 700; cursor: pointer; }
    .danger-button { background: #c62828; }
    .danger-button:hover { background: #b71c1c; }
    .notice { padding: 10px 12px; border-radius: 6px; background: #d9f5e5; color: #095a31; }
    .warning { padding: 10px 12px; border-radius: 6px; background: #fff1c2; color: #6a4600; line-height: 1.5; }
    .error { padding: 10px 12px; border-radius: 6px; background: #ffd9d9; color: #7a0000; line-height: 1.5; }
    .logs { margin-top: 28px; padding-top: 20px; border-top: 1px solid #c7cdd4; }
    .log-links { display: flex; flex-wrap: wrap; gap: 10px; margin-bottom: 12px; }
    .log-link { display: inline-block; padding: 8px 12px; border-radius: 5px; background: #37474f; color: #fff; font-weight: 700; text-decoration: none; }
    .log-link:hover { background: #455a64; }
    pre { max-height: 22em; overflow: auto; padding: 12px; border: 1px solid #89939e; border-radius: 6px; background: #151a1f; color: #ecf1f5; white-space: pre-wrap; overflow-wrap: anywhere; font: 12px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace; }
    .status { display: grid; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); gap: 12px; margin: 16px 0; }
    .status-item { padding: 12px; border: 1px solid #c7cdd4; border-radius: 6px; }
    .status-label { display: block; font-size: .85rem; color: #5e6b76; }
    .status-value { display: block; margin-top: 4px; font-weight: 700; }
    code { background: #e8ebef; padding: 2px 4px; border-radius: 3px; }
    @media (prefers-color-scheme: dark) { body { background: #101418; color: #ecf1f5; } section { background: #20262c; } textarea { background: #151a1f; color: #ecf1f5; } .notice { background: #153d29; color: #bff5d3; } .warning { background: #4a3612; color: #ffe2a3; } .error { background: #4a1717; color: #ffb8b8; } .logs { border-color: #48535e; } .log-link { background: #455a64; color: #fff; } .log-link:hover { background: #546e7a; } .status-item { border-color: #48535e; } .status-label, .metadata { color: #b5c0c9; } a { color: #4fc3f7; } .repository-link { background: #455a64; color: #fff; } .repository-link:hover { background: #546e7a; } .danger-button { background: #c62828; } .danger-button:hover { background: #b71c1c; } code { background: #343d46; } }
  </style>
</head>
<body>
<main><section>
  <div class="header">
    <h1>HA Config Sync Status</h1>
    <span class="metadata">Version {version} · <a href="{project_url}" target="_blank" rel="noopener noreferrer">GitHub project</a></span>
  </div>
  {notice}
  <div class="status">
    <div class="status-item"><span class="status-label">Last check</span><span class="status-value">{last_check}</span></div>
    <div class="status-item"><span class="status-label">Last commit with changes</span><span class="status-value">{last_commit}</span></div>
  </div>
  {backup_repository_link}
  <p>Home Assistant configuration source: <code>/homeassistant</code>. Git metadata and diagnostics: <code>/data</code>.</p>
  {secrets_warning}
  {all_addon_configs_warning}
  <p><strong>Security:</strong> Keep <code>secrets.yaml</code> ignored unless you deliberately want to store secrets in a private repository.</p>
  <section class="logs">
    <h2>Active Git ignore rules</h2>
    <p>Edit this persistent user-managed file with File Editor or Studio Code Server:</p>
    <pre>{host_gitignore_path}</pre>
    <p>Inside the add-on container, this same file is mounted at <code>/config/gitignore</code>. This read-only preview shows the exact rules currently applied during synchronization.</p>
    <pre>{rules}</pre>
  </section>
  <form method="post" action="clear-cache" onsubmit="return confirm('Clear the local Git cache? Unpushed local commits will be discarded. The next sync will download the repository again.');">
    <button class="danger-button" type="submit">Clear local Git cache</button>
  </form>
  <section class="logs">
    <h2>Diagnostics</h2>
    <p>These are selected diagnostic logs from the add-on’s persistent <code>/data</code> directory. Git metadata is never exposed here.</p>
    <div class="log-links">
      <a class="log-link" href="./sync-log">View sync debug log</a>
      <a class="log-link" href="./sync-log?download=1">Download sync debug log</a>
      <form method="post" action="clear-sync-log" onsubmit="return confirm('Clear the sync debug log?');">
        <button class="danger-button" type="submit">Clear sync debug log</button>
      </form>
    </div>
    <h3>Startup mount diagnostics and latest sync debug log</h3>
    <pre>{sync_log_preview}</pre>
  </section>
</section></main>
</body></html>"""


def debug_log(message: str) -> None:
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    try:
        with WEB_DEBUG_LOG.open("a", encoding="utf-8") as log_file:
            log_file.write(f"{timestamp} {message}\n")
        WEB_DEBUG_LOG.chmod(0o600)
    except OSError:
        pass


MAX_LOG_BYTES = 256 * 1024


def read_log(path: Path) -> str:
    try:
        with path.open("rb") as log_file:
            log_file.seek(0, 2)
            size = log_file.tell()
            log_file.seek(max(0, size - MAX_LOG_BYTES))
            content = log_file.read().decode("utf-8", errors="replace")
        prefix = "[Showing the last 256 KiB]\n" if size > MAX_LOG_BYTES else ""
        return prefix + content
    except FileNotFoundError:
        return "No diagnostic log has been created yet."
    except OSError as error:
        return f"Unable to read diagnostic log: {error}"


def serve_log(handler: BaseHTTPRequestHandler, path: Path, download: bool) -> None:
    content = read_log(path).encode("utf-8")
    handler.send_response(HTTPStatus.OK)
    handler.send_header("Content-Type", "text/plain; charset=utf-8")
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("X-Content-Type-Options", "nosniff")
    if download:
        handler.send_header("Content-Disposition", f'attachment; filename="{path.name}"')
    else:
        handler.send_header("Content-Disposition", f'inline; filename="{path.name}"')
    handler.send_header("Content-Length", str(len(content)))
    handler.end_headers()
    handler.wfile.write(content)


def html_escape(value: str) -> str:
    return (value.replace("&", "&amp;").replace("<", "&lt;")
                 .replace(">", "&gt;").replace('"', "&quot;"))


def host_gitignore_path() -> str:
    """Derive Studio Code's host-visible path from Supervisor mount metadata."""
    try:
        for line in Path("/proc/self/mountinfo").read_text(encoding="utf-8").splitlines():
            parts = line.split(" - ", 1)
            if len(parts) != 2:
                continue
            pre, post = parts
            fields = pre.split()
            if len(fields) < 5 or fields[4] != "/config":
                continue
            source_root = fields[3]
            marker = "/supervisor/app_configs/"
            if source_root.startswith(marker):
                slug = source_root.removeprefix(marker).strip("/")
                if slug:
                    return f"/addon_configs/{slug}/gitignore"
    except OSError:
        pass
    return "/config/gitignore (inside the add-on container)"


def backup_repository_url() -> str | None:
    try:
        output = subprocess.check_output(
            ["git", f"--git-dir={GIT_METADATA_DIR}", "remote", "get-url", "origin"],
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


def read_rules() -> tuple[str, str]:
    try:
        rules = GITIGNORE_FILE.read_text(encoding="utf-8")
    except FileNotFoundError:
        rules = ""
    except OSError as error:
        return "", f"<p class='error'><strong>Cannot read the Git ignore file:</strong> {html_escape(str(error))}</p>"

    if rules.strip():
        debug_log(f"editor read {len(rules)} bytes from {GITIGNORE_FILE}")
        return rules, ""

    debug_log(f"editor found no rules in {GITIGNORE_FILE}; creating defaults")
    try:
        GITIGNORE_FILE.write_text(DEFAULT_RULES, encoding="utf-8")
        GITIGNORE_FILE.chmod(0o600)
    except OSError as error:
        debug_log(f"editor failed to create {GITIGNORE_FILE}: {error}")
        return "", f"<p class='error'><strong>Cannot create the Git ignore file:</strong> {html_escape(str(error))}</p>"
    debug_log(f"editor created default rules at {GITIGNORE_FILE}")
    return DEFAULT_RULES, ""


def git_last_commit() -> str | None:
    if not (GIT_METADATA_DIR / "HEAD").is_file():
        return None
    try:
        return subprocess.check_output(
            ["git", f"--git-dir={GIT_METADATA_DIR}", "log", "-1", "--format=%cI"],
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
                return json.loads(OPTIONS_FILE.read_text(encoding="utf-8")).get("include_secrets") is True
    except (FileNotFoundError, ValueError):
        return False


def include_all_addon_configs_enabled() -> bool:
    try:
        return json.loads(OPTIONS_FILE.read_text(encoding="utf-8")).get("include_all_addon_configs") is True
    except (FileNotFoundError, ValueError):
        return False


def all_addon_configs_warning() -> str:
    if include_all_addon_configs_enabled():
        return ("<p class='warning'><strong>All add-on configurations are included.</strong> "
                "The backup contains configuration data for other add-ons. Keep the destination repository private and review the active Git ignore rules.</p>")
    return ""


def secrets_warning(rules: str) -> str:
    secrets_ignored = any(
        line.strip().lstrip("/") == "secrets.yaml"
        for line in rules.splitlines()
        if not line.strip().startswith("#")
    )
    if not secrets_ignored and not include_secrets_enabled():
        return ("<p class='warning'><strong>Secrets are still protected.</strong> "
                "The ignore rule for <code>secrets.yaml</code> was removed, "
                "but <strong>Include secrets</strong> is disabled in the add-on configuration. "
                "The file will not be copied or committed until you explicitly enable that option.</p>")
    if include_secrets_enabled() and secrets_ignored:
        return ("<p class='warning'><strong>Secrets will not be committed.</strong> "
                "<strong>Include secrets</strong> is enabled, but "
                "<code>secrets.yaml</code> is still ignored by these rules.</p>")
    if include_secrets_enabled() and not secrets_ignored:
        return ("<p class='warning'><strong>Secrets backup is enabled.</strong> "
                "<code>secrets.yaml</code> can be committed to your private backup repository.</p>")
    return ""


def read_status() -> dict[str, str]:
    try:
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
        parsed_url = urlparse(self.path)
        path = parsed_url.path.rstrip("/") or "/"
        query = parse_qs(parsed_url.query)
        if path == "/sync-log":
            download = "download" in query
            debug_log(f"sync debug log requested; download={download}")
            serve_log(self, SYNC_DEBUG_LOG, download)
            return
        if path != "/":
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        if "cache-cleared=1" in query:
            message = '<p class="notice">Local Git cache cleared. The next sync will download the repository again.</p>'
        elif "sync-log-cleared=1" in query:
            message = '<p class="notice">Sync debug log cleared.</p>'
        elif "sync-log-clear-error=1" in query:
            message = '<p class="error">Could not clear the sync debug log.</p>'
        else:
            message = ""
        status = read_status()
        rules, rules_error = read_rules()
        page = (PAGE.replace("{notice}", message + rules_error)
                     .replace("{secrets_warning}", secrets_warning(rules))
                     .replace("{all_addon_configs_warning}", all_addon_configs_warning())
                     .replace("{backup_repository_link}", backup_repository_link())
                     .replace("{rules}", html_escape(rules))
                     .replace("{host_gitignore_path}", html_escape(host_gitignore_path()))
                     .replace("{last_check}", html_escape(status["last_check"]))
                     .replace("{last_commit}", html_escape(status["last_commit"]))
                     .replace("{sync_log_preview}", html_escape(read_log(SYNC_DEBUG_LOG)))
                     .replace("{version}", html_escape(ADDON_VERSION))
                     .replace("{project_url}", PROJECT_URL))
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(page.encode("utf-8"))))
        self.end_headers()
        self.wfile.write(page.encode("utf-8"))

    def do_POST(self):
        path = urlparse(self.path).path.rstrip("/")
        if path == "/clear-sync-log":
            try:
                SYNC_DEBUG_LOG.write_text("", encoding="utf-8")
                SYNC_DEBUG_LOG.chmod(0o600)
                debug_log("sync debug log cleared from Web UI")
            except OSError as error:
                self.send_response(HTTPStatus.SEE_OTHER)
                self.send_header("Location", "./?sync-log-clear-error=1")
                self.end_headers()
                return
            self.send_response(HTTPStatus.SEE_OTHER)
            self.send_header("Location", "./?sync-log-cleared=1")
            self.end_headers()
            return
        if path == "/clear-cache":
            debug_log("local Git cache clear requested")
            try:
                import shutil
                shutil.rmtree(GIT_METADATA_DIR)
            except FileNotFoundError:
                pass
            for path in (Path("/data/index"), Path("/data/snapshots")):
                try:
                    if path.is_dir():
                        shutil.rmtree(path)
                    else:
                        path.unlink()
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
