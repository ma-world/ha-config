# Home Assistant Configuration Sync

This is a **public Home Assistant add-on repository**. The add-on backs up Home Assistant configuration to a private Git repository. It runs entirely inside Home Assistant.

## Architecture

- **Home Assistant configuration source:** `/homeassistant`
- **Git metadata and diagnostics:** `/data`
- **Web UI:** status, active rule preview, logs, cache reset, and repository link
- **Optional all app configurations:** dynamically discovered when explicitly enabled

The add-on treats `/homeassistant` as a read-only source tree. It does not run Git cleanup, checkout, restore, or reset operations against Home Assistant configuration files.

## Initial setup

1. Add this repository in Home Assistant under **Settings → Apps → App Store → Repositories**.
2. Install **HA Config Sync**.
3. Set `repository_url` to your **private** GitHub repository, for example:

   ```text
   https://github.com/<YOUR USER NAME>/homeassistant-config-files.git
   ```

4. Create a GitHub fine-grained personal access token with **Contents: Read and write** access to that repository. Enter it as `github_token` in the app configuration.
5. Set `sync_interval_hours` between 1 and 168 hours. The default is 4.
6. Set `gitignore_host_path` to the path you use to edit the persistent Git ignore file on the Home Assistant host. The default is:

   ```text
   /addon_configs/<installation-specific-addon-slug>/gitignore
   ```

7. Start the add-on. It syncs immediately and then repeats at the configured interval.

If the selected private repository is empty, the add-on initializes its configured branch with an English README linking to HA Config Sync before the first configuration sync.

## What is backed up

The add-on builds an isolated Git index from the mounted Home Assistant configuration source at `/homeassistant` and pushes changes to the configured branch.

By default, external add-on configuration folders are not included.

### Optional: include all app configurations

Set `include_all_app_configs: true` only when you deliberately want to back up every Supervisor-managed app configuration folder. The add-on uses Home Assistant’s official `all_app_configs:rw` map and stores these files under:

```text
addon_configs/
```

in the private backup repository.

> **Security warning:** This may include settings and credentials for other apps. Keep the destination repository private and review the active Git ignore rules before enabling this option.

## Git ignore rules

The Web UI displays the active Git ignore rules used for synchronization. To change them, edit this persistent file with File Editor or Studio Code Server:

```text
/addon_configs/<ADDON_SLUG>/gitignore
```

The add-on never overwrites an existing rule file during startup or update.

The default rules exclude runtime data, logs, credentials, selected large media files, community frontend assets, ESPHome build artifacts, and common Zigbee2MQTT database/log files.

> **Security note:** Keep `secrets.yaml` ignored unless you fully understand the implications and use a private repository. Git ignore rules do not remove files already committed in Git history.

## Web UI and diagnostics

Open **HA Config Sync → Open Web UI** for:

- last sync check and last commit time,
- active Git ignore rule preview,
- link to the private backup repository,
- sync log preview and download,
- **Clear local Git cache**.

**Clear sync debug log** clears the persistent sync diagnostic log.

**Clear local Git cache** removes only the add-on’s local Git metadata, index, and transient snapshots from `/data`. It does not change `/homeassistant` or the remote GitHub repository. Locally created commits that have not been pushed are discarded.

## Changelog

Home Assistant displays the release notes from [`ha_config_sync/CHANGELOG.md`](ha_config_sync/CHANGELOG.md) whenever an add-on update is available.
