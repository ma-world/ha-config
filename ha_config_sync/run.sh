#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
set -Eeuo pipefail

readonly CONFIG_DIR=/homeassistant
readonly GIT_METADATA_DIR=/data/git
readonly INDEX_FILE=/data/index
readonly STATUS_FILE=/data/sync-status.json
readonly SYNC_DEBUG_LOG=/data/sync-debug.log
readonly OPTIONS_FILE=/data/options.json
readonly ADDON_CONFIG_DIR=/config
readonly GITIGNORE_FILE="${ADDON_CONFIG_DIR}/gitignore"
readonly LEGACY_GITIGNORE_FILE=/data/gitignore
readonly SNAPSHOT_DIR=/data/snapshots

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

# The user-managed ignore file is stored in the Supervisor-managed add-on
# configuration folder. It is shared with the host-visible path documented in
# the Web UI and is never overwritten when it already exists.
if [[ ! -d "${ADDON_CONFIG_DIR}" ]]; then
  bashio::log.fatal "Add-on configuration directory is not mounted: ${ADDON_CONFIG_DIR}."
  exit 1
fi
if [[ ! -e "${GITIGNORE_FILE}" && -f "${LEGACY_GITIGNORE_FILE}" ]]; then
  cp "${LEGACY_GITIGNORE_FILE}" "${GITIGNORE_FILE}"
  chmod 600 "${GITIGNORE_FILE}"
  bashio::log.info "Migrated existing Git ignore rules from ${LEGACY_GITIGNORE_FILE} to ${GITIGNORE_FILE}."
elif [[ ! -e "${GITIGNORE_FILE}" ]]; then
  bashio::log.warning "Git ignore file not found; creating defaults at ${GITIGNORE_FILE}."
  create_default_gitignore
elif [[ ! -f "${GITIGNORE_FILE}" ]]; then
  bashio::log.fatal "Git ignore path exists but is not a regular file: ${GITIGNORE_FILE}."
  exit 1
else
  bashio::log.info "Using existing Git ignore file without modification: ${GITIGNORE_FILE} ($(wc -c < "${GITIGNORE_FILE}") bytes)."
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

safe_git() {
  # Git metadata and the transient index live in /data. /homeassistant is used
  # only as a read-only source tree. Do not add reset, clean, checkout, restore, or
  # any worktree-mutating command to this add-on.
  GIT_INDEX_FILE="${INDEX_FILE}" \
  GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0=core.excludesfile \
  GIT_CONFIG_VALUE_0="${GITIGNORE_FILE}" \
  git --git-dir="${GIT_METADATA_DIR}" --work-tree="${CONFIG_DIR}" "$@"
}

debug_log() {
  local message="$1"
  local timestamp
  timestamp="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  printf '%s %s\n' "${timestamp}" "${message}" >>"${SYNC_DEBUG_LOG}"
  chmod 600 "${SYNC_DEBUG_LOG}"
  # Keep at most the latest 512 KiB without relying on external log rotation.
  if (( $(wc -c < "${SYNC_DEBUG_LOG}") > 524288 )); then
    tail -c 524288 "${SYNC_DEBUG_LOG}" >"${SYNC_DEBUG_LOG}.tmp"
    mv "${SYNC_DEBUG_LOG}.tmp" "${SYNC_DEBUG_LOG}"
    chmod 600 "${SYNC_DEBUG_LOG}"
  fi
}

mask_value() {
  local value="$1"
  local length=${#value}
  if (( length <= 8 )); then
    printf '%s' '[redacted]'
  else
    printf '%s…%s' "${value:0:4}" "${value:length-4:4}"
  fi
}

log_mount_diagnostics() {
  local path option_slug mount_lines
  debug_log '=== Startup mount diagnostics ==='
  for path in /homeassistant /config /data; do
    if [[ -d "${path}" ]]; then
      debug_log "container directory ${path}: present ($(ls -ld "${path}" 2>/dev/null || true))"
      debug_log "container directory ${path}: entries=$(ls -A "${path}" 2>/dev/null | tr '\n' ',' | sed 's/,$//' || true)"
    else
      debug_log "container directory ${path}: missing"
    fi
  done
  if [[ -d "${ADDON_CONFIG_DIR}" ]]; then
    debug_log "addon_config mount is available at ${ADDON_CONFIG_DIR}; active ignore file=${GITIGNORE_FILE}"
  else
    debug_log "addon_config mount is unavailable at ${ADDON_CONFIG_DIR}"
  fi

  debug_log "options file: ${OPTIONS_FILE}"
  if [[ -r "${OPTIONS_FILE}" ]]; then
    option_slug="$(jq -r '.slug // "unknown"' "${OPTIONS_FILE}" 2>/dev/null || printf 'unknown')"
    debug_log "options-file slug field: ${option_slug}"
    debug_log "configured repository_url: ${repository_url}"
    debug_log "configured branch: ${branch}"
    debug_log "configured git_name: ${git_name}"
    debug_log "configured git_email: ${git_email}"
    debug_log 'github_token: [configured; value not logged]'
  else
    debug_log 'options file is not readable'
  fi

  debug_log 'relevant /proc/self/mountinfo entries:'
  if [[ -r /proc/self/mountinfo ]]; then
    mount_lines="$(grep -E ' /homeassistant | /config | /data ' /proc/self/mountinfo || true)"
    if [[ -n "${mount_lines}" ]]; then
      while IFS= read -r mount_line; do
        debug_log "mountinfo: ${mount_line}"
      done <<< "${mount_lines}"
    else
      debug_log 'mountinfo: no entries matched /homeassistant, /config, or /data'
    fi
  else
    debug_log 'mountinfo: /proc/self/mountinfo is not readable'
  fi
  debug_log '=== End startup mount diagnostics ==='
}

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
  bashio::log.info "Remote branch '${branch}' does not exist yet; initializing the private backup repository."
  local empty_tree commit
  empty_tree="$(git --git-dir="${GIT_METADATA_DIR}" mktree </dev/null)"
  commit="$(git --git-dir="${GIT_METADATA_DIR}" commit-tree "${empty_tree}" -m 'Initialize Home Assistant configuration backup repository')"
  git --git-dir="${GIT_METADATA_DIR}" update-ref "refs/heads/${branch}" "${commit}"
  if ! git --git-dir="${GIT_METADATA_DIR}" push --set-upstream origin "refs/heads/${branch}:refs/heads/${branch}"; then
    bashio::log.fatal 'Could not push the initial commit to the backup repository.'
    return 1
  fi
  git --git-dir="${GIT_METADATA_DIR}" fetch --prune origin
}


rebuild_index_from_config() {
  bashio::log.info 'Rebuilding isolated Git index from the read-only /homeassistant source tree.'
  # Rebuilding only the index applies ignore changes immediately without
  # modifying a single file under /homeassistant.
  rm -f "${INDEX_FILE}"
  safe_git read-tree --empty
  safe_git add -A -- .
  bashio::log.info "Staged $(GIT_INDEX_FILE="${INDEX_FILE}" git --git-dir="${GIT_METADATA_DIR}" diff --cached --name-only | wc -l | tr -d ' ') path(s) after applying ignore rules."

  # Preserve a copy of the rules in the private repository under a neutral name.
  # The original file remains in persistent /data and is ignored by its own rules.
  mkdir -p "${SNAPSHOT_DIR}"
  cp "${GITIGNORE_FILE}" "${SNAPSHOT_DIR}/ha_config_sync.gitignore.backup"
  GIT_INDEX_FILE="${INDEX_FILE}" git --git-dir="${GIT_METADATA_DIR}" --work-tree="${SNAPSHOT_DIR}" add -f ha_config_sync.gitignore.backup 2>/dev/null || true
  rm -f "${SNAPSHOT_DIR}/ha_config_sync.gitignore.backup"
}

sync_configuration() {
  debug_log "sync started; repository=${repository_url}; branch=${branch}; active_ignore_file=${GITIGNORE_FILE}"
  write_status last_check
  if ! verify_private_repository; then
    debug_log 'sync stopped: private repository verification failed'
    return 1
  fi

  mkdir -p "${GIT_METADATA_DIR}"
  if [[ ! -f "${GIT_METADATA_DIR}/HEAD" ]]; then
    git init --bare --initial-branch="${branch}" "${GIT_METADATA_DIR}"
  fi

  # A previous add-on version may have created the bare metadata directory
  # before the origin remote was added. Ensure origin exists on every run.
  if git --git-dir="${GIT_METADATA_DIR}" remote get-url origin >/dev/null 2>&1; then
    git --git-dir="${GIT_METADATA_DIR}" remote set-url origin "${repository_url}"
  else
    git --git-dir="${GIT_METADATA_DIR}" remote add origin "${repository_url}"
  fi

  git --git-dir="${GIT_METADATA_DIR}" config user.name "${git_name}"
  git --git-dir="${GIT_METADATA_DIR}" config user.email "${git_email}"

  # Fetch all remote references. Fetching a specific branch fails with
  # "couldn't find remote ref" when a newly created private repository has no
  # first commit yet; that empty state is initialized safely below.
  if ! git --git-dir="${GIT_METADATA_DIR}" fetch --prune origin; then
    debug_log 'sync stopped: remote fetch failed'
    bashio::log.warning 'Remote repository could not be fetched; the next run will retry.'
    return 1
  fi

  if git --git-dir="${GIT_METADATA_DIR}" show-ref --verify --quiet "refs/remotes/origin/${branch}"; then
    git --git-dir="${GIT_METADATA_DIR}" update-ref "refs/heads/${branch}" "refs/remotes/origin/${branch}"
  else
    initialize_empty_remote_repository || return 1
  fi

  rebuild_index_from_config

  local parent_tree parent_commit new_tree commit_message new_commit
  parent_commit="$(git --git-dir="${GIT_METADATA_DIR}" rev-parse "refs/heads/${branch}")"
  parent_tree="$(git --git-dir="${GIT_METADATA_DIR}" rev-parse "${parent_commit}^{tree}")"
  new_tree="$(GIT_INDEX_FILE="${INDEX_FILE}" git --git-dir="${GIT_METADATA_DIR}" write-tree)"

  if [[ "${new_tree}" == "${parent_tree}" ]]; then
    debug_log 'sync completed: no configuration changes detected'
    bashio::log.info 'No configuration changes to sync.'
    return 0
  fi

  commit_message="Home Assistant configuration sync $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  new_commit="$(GIT_INDEX_FILE="${INDEX_FILE}" git --git-dir="${GIT_METADATA_DIR}" commit-tree "${new_tree}" -p "${parent_commit}" -m "${commit_message}")"
  git --git-dir="${GIT_METADATA_DIR}" update-ref "refs/heads/${branch}" "${new_commit}" "${parent_commit}"

  if ! git --git-dir="${GIT_METADATA_DIR}" push origin "refs/heads/${branch}:refs/heads/${branch}"; then
    debug_log "sync push failed; local_commit=${new_commit}"
    bashio::log.error 'Configuration commit was created locally, but the push failed. The next scheduled sync will retry.'
    return 1
  fi

  write_status last_commit
  debug_log "sync completed successfully; commit=${new_commit}"
  bashio::log.info 'Configuration was committed and pushed successfully.'
}

python3 /web.py &
web_pid=$!

log_mount_diagnostics
interval_seconds=$((sync_interval_hours * 3600))
bashio::log.info "Sync starts immediately and repeats every ${sync_interval_hours} hour(s)."
while true; do
  if ! sync_configuration; then
    bashio::log.warning 'Configuration sync failed; retrying at the next scheduled interval.'
  fi
  sleep "${interval_seconds}"
done
