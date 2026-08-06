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
6. Use the **`gitignore` editor** on the add-on configuration page to control which copied files Git excludes. The default rules exclude runtime data and `secrets.yaml`. The configured rules are written as `.gitignore` in your backup repository.
7. Start the add-on. It performs an initial sync immediately and remains active for subsequent scheduled syncs.

## Included files

By default, the add-on stores `configuration.yaml`, automations, scripts, scenes, packages, blueprints, themes, `custom_components`, ESPHome, Zigbee2MQTT, and WWW files. Lovelace dashboard definitions can also be included.

Before copying or pushing any configuration data, the add-on checks the GitHub API and proceeds only if the target repository is private. If visibility cannot be verified or the repository is public, it writes an error to the add-on log and does not perform a backup.

Runtime data, databases, logs, authentication data, tokens, and `secrets.yaml` are excluded by default. This reduces the risk of committing credentials to Git. You can explicitly enable `secrets.yaml` in the add-on options; use a private backup repository if you do.

## Changing the interval or Git ignore rules

Open the **HA Config Sync** add-on and update `sync_interval_hours` or the multi-line `gitignore` editor. Save the configuration and restart the add-on for the new settings to take effect. The configured ignore rules apply only to files in the backup repository.

> **Security note:** Keep `homeassistant/secrets.yaml` in `gitignore` unless you fully understand the implications and use a private repository. Git ignore rules do not remove files that were committed previously; remove those files and their history separately if needed.

The add-on log shows the result of each sync.
