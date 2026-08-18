# Home Assistant Configuration Sync

This is a **public Home Assistant add-on repository**. The add-on copies selected files from `/config`, creates a Git commit when changes are detected, and pushes the snapshot to the Git repository you configure. Everything runs inside Home Assistant.

1. The add-on starts automatically when Home Assistant starts.
2. It runs one sync immediately, then repeats at the interval configured in the add-on settings (four hours by default).
3. It stores the selected configuration files under `homeassistant/` in the configured Git repository and pushes changes to the configured branch.

## Initial setup

1. Add this repository in Home Assistant under **Settings → Add-ons → Add-on Store → Repositories**.
2. Install the **HA Config Sync** add-on.
3. In the add-on configuration, set `repository_url` to your private Git repository, for example:

   ```text
   https://github.com/<YOUR USER NAME>/homeassistant-config-files.git
   ```

4. Create a GitHub fine-grained personal access token with **Contents: Read and write** access to that backup repository, then enter it as `github_token` in the add-on configuration. The add-on also uses it to verify the repository visibility before every sync. The token is stored only in the add-on configuration and is never committed to Git.
5. Set `sync_interval_hours` to the desired interval. The allowed range is 1 to 168 hours; the default is 4.
6. To edit Git ignore rules, open the **HA Config Sync** app page and select **Open Web UI**. This opens a dedicated multi-line editor. The editor has 15 visible lines, scrolls for longer rule sets, and writes the rules as `.gitignore` in your backup repository.
7. Start the add-on. If the selected private repository is empty, the add-on initializes its configured branch with a README before copying any Home Assistant files. It then performs the initial sync and remains active for subsequent scheduled syncs.

## Included files

By default, the add-on stores `configuration.yaml`, automations, scripts, scenes, packages, blueprints, themes, `custom_components`, ESPHome, Zigbee2MQTT, and WWW files. Lovelace dashboard definitions can also be included.

Before copying or pushing any configuration data, the add-on checks the GitHub API and proceeds only if the target repository is private. If visibility cannot be verified or the repository is public, it writes an error to the add-on log and does not perform a backup. If the private repository is empty, it creates and pushes an English README that identifies it as a backup destination for this add-on, then continues with the normal sync.

Runtime data, databases, logs, authentication data, tokens, and `secrets.yaml` are excluded by default. This reduces the risk of committing credentials to Git. The Git Ignore Editor warns if its `secrets.yaml` rule and the explicit `include_secrets` option do not match. Removing the ignore rule alone never enables secret backups; you must also explicitly enable `include_secrets` in the add-on configuration. Use a private backup repository if you do.

## Changing the interval or Git ignore rules

Open the **HA Config Sync** app page to change `sync_interval_hours`. To edit Git ignore rules, select **Open Web UI** on the same app page; saving there takes effect on the next sync without restarting the add-on. The Web UI also shows the most recent sync check and the timestamp of the latest commit in the local backup checkout, including commits that existed before the status display was added. The configured ignore rules apply only to files in the backup repository.

> **Security note:** Keep `homeassistant/secrets.yaml` in `gitignore` unless you fully understand the implications and use a private repository. Git ignore rules do not remove files that were committed previously; remove those files and their history separately if needed.

The add-on log shows the result of each sync.

## In-app documentation

The same documentation is available inside Home Assistant on the **Documentation** tab of the add-on page. It is maintained in [`ha_config_sync/DOCS.md`](ha_config_sync/DOCS.md).

## Changelog

Home Assistant displays the release notes from [`ha_config_sync/CHANGELOG.md`](ha_config_sync/CHANGELOG.md) whenever an add-on update is available. Add an entry there before every future version bump.
