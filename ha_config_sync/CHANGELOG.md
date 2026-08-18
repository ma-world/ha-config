# Changelog

All notable changes to **HA Config Sync** are documented in this file.

## 3.5.2

- Fixed the ingress-relative editor save endpoint and added request diagnostics plus a form-encoded fallback for save requests.

## 3.5.1

- Replaced the Git Ignore Editor’s form submission with a JSON save API to prevent ingress from dropping multi-line textarea content.
- The editor now shows the exact character count while saving and confirms the byte count returned after server-side verification.

## 3.5.0

- Corrected Home Assistant mount paths: the Home Assistant configuration source is `/homeassistant`, while the persistent add-on configuration folder is `/config`.
- The visible user-managed ignore file is now `/config/gitignore` and is shared directly by the editor and sync process.

## 3.4.2

- Fixed the `homeassistant_config` map by explicitly mounting it at `/config` inside the add-on container.

## 3.4.1

- Fixed the Home Assistant configuration mount path by using the Supervisor-provided `HOMEASSISTANT_CONFIG` location instead of assuming `/config`.
- Added a clear startup error when the Home Assistant configuration directory is unavailable.

## 3.4.0

- Added a Diagnostics section to the Web UI with log previews and secure view/download links for selected `/data` diagnostic logs.
- Added persistent sync diagnostic logging with rotation for easier troubleshooting.

## 3.3.0

- Moved the user-managed Git ignore file back to `/config/ha_config_sync.gitignore`, which persists across add-on updates.
- Existing Git ignore files are never overwritten during startup or upgrades; defaults are created only if the file does not exist.

## 3.2.1

- Fixed the Git Ignore Editor and sync process to use the same fixed Home Assistant add-on configuration directory.

## 3.2.0

- Moved the visible Git ignore file to the mounted Home Assistant add-on configuration folder.
- Kept Git metadata, index, status, and logs in the add-on’s normal persistent `/data` area.

## 3.1.7

- Replaced the deprecated `config` map with `homeassistant_config`.
- Added diagnostic logs for Git ignore file creation, reading, saving, index rebuilding, and staged path counts.

## 3.1.6

- Fixed Git Ignore Editor save handling and added a visible error message if `/config/ha_config_sync.gitignore` cannot be written.

## 3.1.5

- Fixed first-commit creation for an empty private backup repository by ensuring all Git plumbing commands use the isolated Git metadata directory.

## 3.1.4

- Fixed setup for a new private repository with no branch or commits yet. The add-on now detects and initializes an empty remote repository instead of failing while fetching a missing branch.

## 3.1.3

- Fixed recovery for existing isolated Git metadata directories that were missing the `origin` remote.

## 3.1.2

- Fixed an s6 environment conflict caused by assigning the reserved `GIT_DIR` environment variable.
- All Git commands now use explicit `--git-dir` and `--work-tree` arguments instead of setting `GIT_DIR` in the process environment.

## 3.1.1

- Fixed initialization of the isolated Git metadata directory on first startup.

## 3.1.0

- Added a safe direct `/config` source-tree mode: Git metadata and indexes are isolated under `/data`, while `/config` is treated as read-only.
- The add-on does not use `git reset`, `git clean`, `git checkout`, `git restore`, or any other worktree-mutating operation against `/config`.
- Moved the editable ignore file to `/config/ha_config_sync.gitignore`, where it is visible in File Editor and Studio Code Server.
- This version backs up `/config` only; it does not include external add-on data such as Zigbee2MQTT or ESPHome directories outside `/config`.

## 3.0.1

- Emergency rollback of the unsafe direct `/config` Git worktree implementation introduced in 3.0.0.
- The add-on no longer sets `/config` as a Git worktree and no longer runs Git reset or clean operations against Home Assistant configuration files.
- Restored the isolated snapshot workflow while recovery of affected Home Assistant configurations is performed from backups.

## 2.0.2

- Fixed persistent Git ignore storage by maintaining a compatibility copy in the add-on `/data` folder and synchronizing it with Home Assistant add-on configuration storage.
- The web editor now saves to its writable persistent location immediately, so saved changes remain visible after reloading the editor.

## 2.0.1

- Fixed ignore enforcement: Git now removes ignored paths from the snapshot before staging, without attempting an unreliable rsync filter translation.
- Added `homeassistant/www/community/` to the default ignore rules to exclude downloaded community frontend plugins.

## 2.0.0

- Moved the persistent Git ignore file into Home Assistant add-on configuration storage instead of the add-on data directory.
- Applied Git ignore rules during file copying, so excluded paths are no longer copied into the local Git cache before staging.

## 1.9.1

- Fixed the Git Ignore Editor so saved rules remain authoritative instead of being replaced by an older local checkout.
- Saving rules now updates the local checkout `.gitignore` immediately, before the next scheduled sync.

## 1.9.0

- Added default ignore rules for common large media, archive, ESPHome build, and Zigbee2MQTT database/log files.
- Made the editor show the active repository `.gitignore` after synchronization, preventing stale editor values from overwriting it.
- Added **Clear local Git cache** to discard local cloned data and unpushed commits; the next sync downloads the backup repository again.
- Automatically removes files from the local Git index when they become ignored, so old tracked data is no longer retried for push.

## 1.8.0

- Added an **Open private backup repository** button to the Git Ignore Editor when a GitHub backup remote is configured.

## 1.7.4

- Updated the displayed add-on repository maintainer to `ma-world`.

## 1.7.3

- Added an in-app Documentation tab containing the add-on README.

## 1.7.2

- Fixed the add-on information-page link to point to the public HA Config Sync repository.

## 1.7.1

- Added Home Assistant add-on update notes through this changelog.

## 1.7.0

- Added clear Git Ignore Editor warnings when the `include_secrets` setting and the `secrets.yaml` ignore rule do not match.
- Kept `include_secrets` as an explicit safety confirmation before secrets can be copied.

## 1.6.3

- Added the add-on version and a GitHub project link to the Git Ignore Editor.

## 1.6.2

- Restored secure default ignore rules when an older version left the editor state empty.
- Standardized the displayed sync timestamps to UTC.

## 1.6.1

- Preserved existing `.gitignore` rules when upgrading to the editor-based configuration.
- Displayed existing local backup commits even if they predate status tracking.

## 1.6.0

- Added last-check and last-commit timestamps to the Git Ignore Editor.
- Added an in-app hint to use **Open Web UI** for editing Git ignore rules.

## 1.5.2

- Fixed Git Ignore Editor rendering.
- Improved logging when a Git push fails.

## 1.5.1

- Removed the single-line `gitignore` field from the add-on configuration page.

## 1.5.0

- Moved the Git Ignore Editor to the add-on's **Open Web UI** page.

## 1.4.1

- Added safe initialization of an empty private backup repository with a README.

## 1.4.0

- Added a dedicated Git Ignore Editor with a multi-line, scrollable editor.

## 1.3.0

- Added verification that the destination GitHub repository is private before copying or pushing configuration data.

## 1.2.0

- Added configurable Git ignore rules.

## 1.1.0

- Added a configurable synchronization interval.
- The add-on now runs continuously and performs scheduled synchronization itself.

## 1.0.0

- Initial release.
