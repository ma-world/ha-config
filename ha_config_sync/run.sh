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

if [[ -z "${repository_url}" ]]; then
  bashio::log.fatal 'repository_url must be configured.'
  exit 1
fi

# HTTPS repositories need a GitHub fine-grained PAT with repository Contents: Read and write.
# SSH URLs use the add-on container SSH configuration instead and do not need github_token.
if [[ "${repository_url}" == https://* && -z "${github_token}" ]]; then
  bashio::log.fatal 'github_token is required when repository_url uses HTTPS.'
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
  bashio::log.warning 'Remote branch could not be fetched; continuing with the local checkout.'
fi

mkdir -p "${SNAPSHOT_DIR}"
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

# Configuration needed to recreate Home Assistant, excluding runtime databases and credentials.
paths=(
  automations.yaml
  blueprints
  configuration.yaml
  customize.yaml
  custom_components
  esphome
  groups.yaml
  packages
  scenes.yaml
  scripts.yaml
  themes
  www
  zigbee2mqtt
)

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

git -C "${WORK_DIR}" add -A homeassistant
if git -C "${WORK_DIR}" diff --cached --quiet; then
  bashio::log.info 'No configuration changes to sync.'
  exit 0
fi

commit_message="Home Assistant configuration sync $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
git -C "${WORK_DIR}" commit -m "${commit_message}"
git -C "${WORK_DIR}" push origin "HEAD:${branch}"
bashio::log.info 'Configuration was committed and pushed successfully.'
