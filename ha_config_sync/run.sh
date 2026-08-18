#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
set -Eeuo pipefail

readonly CONFIG_DIR=/config
readonly WORK_DIR=/data/repository
readonly STATUS_FILE=/data/sync-status.json
readonly GITIGNORE_FILE=/config/ha_config_sync.gitignore

repository_url="$(bashio::config 'repository_url')"
branch="$(bashio::config 'branch')"
git_name="$(bashio::config 'git_name')"
git_email="$(bashio::config 'git_email')"
github_token="$(bashio::config 'github_token')"
sync_interval_hours="$(bashio::config 'sync_interval_hours')"

if [[ -z "${repository_url}" ]]; then
  bashio::log.fatal 'repository_url must be configured.'
  exit 1
fi

if ! [[ "${sync_interval_hours}" =~ ^[1-9][0-9]*$ ]] || (( sync_interval_hours > 168 )); then
  bashio::log.fatal 'sync_interval_hours must be a whole number between 1 and 168.'
  exit 1
fi

if [[ -z "${github_token}" ]]; then
  bashio::log.fatal 'github_token is required to verify that the backup repository is private.'
  exit 1
fi

create_default_gitignore() {
  cat >"${GITIGNORE_FILE}" <<'GITIGNORE'
# Home Assistant runtime and generated data
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
GITIGNORE
  chmod 600 "${GITIGNORE_FILE}"
}

# The ignore file lives directly in /config. It is visible to File Editor and
# Studio Code Server and does not depend on any separate add-on mount.
if [[ ! -f "${GITIGNORE_FILE}" ]]; then
  create_default_gitignore
fi

askpass_file=''
web_pid=''
cleanup() {
  [[ -n "${askpass_file}" && -f "${askpass_file}" ]] && rm -f "${askpass_file}"
  [[ -n "${web_pid}" ]] && kill "${web_pid}" 2>/dev/null || true
}
trap cleanup EXIT

askpass_file="$(mktemp)"
chmod 700 "${askpass_file}"
cat >"${askpass_file}" <<'ASKPASS'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' 'x-access-token' ;;
  *) printf '%s\n' "$GITHUB_TOKEN" ;;
esac
ASKPASS
export GIT_ASKPASS="${askpass_file}"
export GIT_TERMINAL_PROMPT=0
export GITHUB_TOKEN="${github_token}"

write_status() {
  local status_key="$1"
  local timestamp
  timestamp="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  python3 - "${STATUS_FILE}" "${status_key}" "${timestamp}" <<'PYTHON'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2]
timestamp = sys.argv[3]
try:
    status = json.loads(path.read_text(encoding="utf-8"))
except (FileNotFoundError, json.JSONDecodeError):
    status = {}
status[key] = timestamp
path.write_text(json.dumps(status), encoding="utf-8")
path.chmod(0o600)
PYTHON
}

verify_private_repository() {
  local repository_slug api_response private_status

  case "${repository_url}" in
    https://github.com/*) repository_slug="${repository_url#https://github.com/}" ;;
    git@github.com:*) repository_slug="${repository_url#git@github.com:}" ;;
    ssh://git@github.com/*) repository_slug="${repository_url#ssh://git@github.com/}" ;;
    *)
      bashio::log.fatal 'The backup repository must be a GitHub repository so its private visibility can be verified.'
      return 1
      ;;
  esac

  repository_slug="${repository_slug%/}"
  repository_slug="${repository_slug%.git}"
  if ! [[ "${repository_slug}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    bashio::log.fatal 'repository_url must identify one GitHub owner/repository pair.'
    return 1
  fi

  if ! api_response="$(curl --fail --silent --show-error \
    --header "Accept: application/vnd.github+json" \
    --header "Authorization: Bearer ${github_token}" \
    "https://api.github.com/repos/${repository_slug}")"; then
    bashio::log.fatal 'Could not verify the target repository visibility. No configuration data will be committed or pushed.'
    return 1
  fi

  private_status="$(printf '%s' "${api_response}" | jq -r '.private // empty')"
  if [[ "${private_status}" != 'true' ]]; then
    bashio::log.fatal 'The target repository is not private. No configuration data will be committed or pushed.'
    return 1
  fi

  bashio::log.info 'Verified that the target repository is private.'
}

initialize_empty_remote_repository() {
  if git -C "${WORK_DIR}" show-ref --verify --quiet "refs/remotes/origin/${branch}"; then
    return 0
  fi

  bashio::log.info "Remote branch '${branch}' does not exist yet; initializing the private backup repository."
  cat >"${WORK_DIR}/README.md" <<'README'
# Home Assistant Configuration Backup

Home Assistant configuration files are backed up here by the [HA Config Sync add-on](https://github.com/ma-world/ha-config.git).
README
  git -C "${WORK_DIR}" add README.md
  git -C "${WORK_DIR}" commit -m 'Initialize Home Assistant configuration backup repository'
  git -C "${WORK_DIR}" push --set-upstream origin "HEAD:${branch}"
  git -C "${WORK_DIR}" fetch --prune origin "${branch}"
}

sync_configuration() {
  write_status last_check
  verify_private_repository || return 1

  mkdir -p "${WORK_DIR}"
  if [[ ! -d "${WORK_DIR}/.git" ]]; then
    bashio::log.info 'Initializing local Git checkout.'
    git -C "${WORK_DIR}" init --initial-branch="${branch}"
    git -C "${WORK_DIR}" remote add origin "${repository_url}"
  else
    git -C "${WORK_DIR}" remote set-url origin "${repository_url}"
  fi

  git -C "${WORK_DIR}" config user.name "${git_name}"
  git -C "${WORK_DIR}" config user.email "${git_email}"

  if ! git -C "${WORK_DIR}" fetch --prune origin "${branch}"; then
    bashio::log.warning 'Remote branch could not be fetched; the next run will retry.'
    return 1
  fi

  if git -C "${WORK_DIR}" show-ref --verify --quiet "refs/remotes/origin/${branch}"; then
    if git -C "${WORK_DIR}" rev-parse --verify --quiet HEAD >/dev/null; then
      git -C "${WORK_DIR}" reset --hard "origin/${branch}"
      git -C "${WORK_DIR}" clean -fd
    else
      git -C "${WORK_DIR}" checkout -B "${branch}" "origin/${branch}"
    fi
  else
    initialize_empty_remote_repository || return 1
  fi

  # Copy only the ignore file into the repository root. The complete Home
  # Assistant /config directory is mounted directly as a Git worktree below.
  cp "${GITIGNORE_FILE}" "${WORK_DIR}/.gitignore"
  git -C "${WORK_DIR}" config core.worktree "${CONFIG_DIR}"
  git -C "${WORK_DIR}" config core.excludesfile "${GITIGNORE_FILE}"

  # Remove stale index entries. The index is rebuilt from the directly mounted
  # /config folder on each run, so new ignore rules take effect immediately.
  rm -f "${WORK_DIR}/.git/index"
  git -C "${WORK_DIR}" read-tree --empty
  git -C "${WORK_DIR}" add -A -- .
  # The persistent ignore file is intentionally part of the backup too, but it
  # is stored under a neutral name so Git does not use it as an ignore rule.
  cp "${GITIGNORE_FILE}" "${CONFIG_DIR}/ha_config_sync.gitignore.backup"
  git -C "${WORK_DIR}" add -- ha_config_sync.gitignore.backup
  rm -f "${CONFIG_DIR}/ha_config_sync.gitignore.backup"

  if git -C "${WORK_DIR}" diff --cached --quiet; then
    bashio::log.info 'No configuration changes to sync.'
    return 0
  fi

  local commit_message
  commit_message="Home Assistant configuration sync $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  git -C "${WORK_DIR}" commit -m "${commit_message}"
  if ! git -C "${WORK_DIR}" push origin "HEAD:${branch}"; then
    bashio::log.error 'Configuration commit was created locally, but the push failed. The next scheduled sync will retry.'
    return 1
  fi

  write_status last_commit
  bashio::log.info 'Configuration was committed and pushed successfully.'
}

python3 /web.py &
web_pid=$!

interval_seconds=$((sync_interval_hours * 3600))
bashio::log.info "Sync starts immediately and repeats every ${sync_interval_hours} hour(s)."
while true; do
  if ! sync_configuration; then
    bashio::log.warning 'Configuration sync failed; retrying at the next scheduled interval.'
  fi
  sleep "${interval_seconds}"
done
