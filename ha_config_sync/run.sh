#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
set -Eeuo pipefail

readonly CONFIG_DIR=/config
readonly WORK_DIR=/data/repository
readonly SNAPSHOT_DIR="${WORK_DIR}/homeassistant"

repository_url="$(bashio::config 'repository_url')"
branch="$(bashio::config 'branch')"
git_name="$(bashio::config 'git_name')"
git_email="$(bashio::config 'git_email')"
github_token="$(bashio::config 'github_token')"
include_secrets="$(bashio::config 'include_secrets')"
include_dashboards="$(bashio::config 'include_dashboards')"
sync_interval_hours="$(bashio::config 'sync_interval_hours')"
gitignore="$(bashio::config 'gitignore')"

if [[ -z "${repository_url}" ]]; then
  bashio::log.fatal 'repository_url must be configured.'
  exit 1
fi

if ! [[ "${sync_interval_hours}" =~ ^[1-9][0-9]*$ ]] || (( sync_interval_hours > 168 )); then
  bashio::log.fatal 'sync_interval_hours must be a whole number between 1 and 168.'
  exit 1
fi

# A GitHub token is also used to verify that the configured destination is private.
if [[ -z "${github_token}" ]]; then
  bashio::log.fatal 'github_token is required to verify that the backup repository is private.'
  exit 1
fi

askpass_file=''
cleanup() {
  [[ -n "${askpass_file}" && -f "${askpass_file}" ]] && rm -f "${askpass_file}"
}
trap cleanup EXIT

if [[ -n "${github_token}" ]]; then
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
fi

verify_private_repository() {
  local repository_slug api_response private_status

  case "${repository_url}" in
    https://github.com/*)
      repository_slug="${repository_url#https://github.com/}"
      ;;
    git@github.com:*)
      repository_slug="${repository_url#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      repository_slug="${repository_url#ssh://git@github.com/}"
      ;;
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
    bashio::log.fatal 'Could not verify the target repository visibility. No configuration data will be copied or pushed.'
    return 1
  fi

  private_status="$(printf '%s' "${api_response}" | jq -r '.private // empty')"
  if [[ "${private_status}" != 'true' ]]; then
    bashio::log.fatal 'The target repository is not private. No configuration data will be copied or pushed.'
    return 1
  fi

  bashio::log.info 'Verified that the target repository is private.'
}

copy_path() {
  local relative_path="$1"
  local source_path="${CONFIG_DIR}/${relative_path}"
  local target_path="${SNAPSHOT_DIR}/${relative_path}"

  rm -rf "${target_path}"
  if [[ -e "${source_path}" ]]; then
    mkdir -p "$(dirname "${target_path}")"
    rsync -a --delete \
      --exclude='__pycache__/' \
      --exclude='*.pyc' \
      --exclude='home-assistant_v2.db*' \
      --exclude='*.log' \
      "${source_path}" "${target_path}"
  fi
}

write_gitignore() {
  local gitignore_path="${WORK_DIR}/.gitignore"

  if [[ -z "${gitignore}" ]]; then
    rm -f "${gitignore_path}"
    return
  fi

  # This value is edited on the add-on configuration page. It is deliberately
  # written to the backup repository so Git applies it before staging a snapshot.
  printf '%s\n' "${gitignore}" >"${gitignore_path}"
}

sync_configuration() {
  verify_private_repository || return 1

  mkdir -p "${WORK_DIR}"
  if [[ ! -d "${WORK_DIR}/.git" ]]; then
    bashio::log.info 'Initializing local repository clone.'
    git -C "${WORK_DIR}" init --initial-branch="${branch}"
    git -C "${WORK_DIR}" remote add origin "${repository_url}"
  else
    git -C "${WORK_DIR}" remote set-url origin "${repository_url}"
  fi

  git -C "${WORK_DIR}" config user.name "${git_name}"
  git -C "${WORK_DIR}" config user.email "${git_email}"

  # Incorporate commits made outside Home Assistant before creating a new snapshot.
  if git -C "${WORK_DIR}" fetch --prune origin "${branch}"; then
    if git -C "${WORK_DIR}" show-ref --verify --quiet "refs/remotes/origin/${branch}"; then
      if git -C "${WORK_DIR}" rev-parse --verify --quiet HEAD >/dev/null; then
        git -C "${WORK_DIR}" rebase "origin/${branch}"
      else
        git -C "${WORK_DIR}" checkout -B "${branch}" "origin/${branch}"
      fi
    fi
  else
    bashio::log.warning 'Remote branch could not be fetched; the next run will retry.'
    return 1
  fi

  write_gitignore

  mkdir -p "${SNAPSHOT_DIR}"
  local paths=(
    automations.yaml blueprints configuration.yaml customize.yaml custom_components
    esphome groups.yaml packages scenes.yaml scripts.yaml themes www zigbee2mqtt
  )
  local path
  for path in "${paths[@]}"; do
    copy_path "${path}"
  done

  if [[ "${include_secrets}" == 'true' ]]; then
    copy_path 'secrets.yaml'
  fi

  # Only dashboard definitions are selected from .storage. Auth, tokens, and integrations remain excluded.
  if [[ "${include_dashboards}" == 'true' ]]; then
    copy_path '.storage/lovelace'
    copy_path '.storage/lovelace_dashboards'
  fi

  git -C "${WORK_DIR}" add -A -- homeassistant
  # Stage the user-managed ignore file when it exists and stage its deletion
  # when the editor was intentionally cleared.
  git -C "${WORK_DIR}" add -u -- .gitignore
  if [[ -e "${WORK_DIR}/.gitignore" ]]; then
    git -C "${WORK_DIR}" add -- .gitignore
  fi
  if git -C "${WORK_DIR}" diff --cached --quiet; then
    bashio::log.info 'No configuration changes to sync.'
    return 0
  fi

  local commit_message
  commit_message="Home Assistant configuration sync $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  git -C "${WORK_DIR}" commit -m "${commit_message}"
  git -C "${WORK_DIR}" push origin "HEAD:${branch}"
  bashio::log.info 'Configuration was committed and pushed successfully.'
}

interval_seconds=$((sync_interval_hours * 3600))
bashio::log.info "Sync starts immediately and repeats every ${sync_interval_hours} hour(s)."
while true; do
  if ! sync_configuration; then
    bashio::log.warning 'Configuration sync failed; retrying at the next scheduled interval.'
  fi
  sleep "${interval_seconds}"
done
