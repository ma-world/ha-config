# Home Assistant Configuration Sync

This is a **public Home Assistant add-on repository**. The add-on reads the mounted Home Assistant `/config` directory, creates a Git commit when changes are detected, and pushes it to the Git repository you configure. Git metadata is isolated inside the add-on; `/config` is never used for Git cleanup or checkout operations.

1. The add-on starts automatically when Home Assistant starts.
2. It runs one sync immediately, then repeats at the interval configured in the add-on settings (four hours by default).
3. It stores the Home Assistant `/config` files at the root of the configured Git repository and pushes changes to the configured branch.

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

The add-on backs up the mounted Home Assistant `/config` directory. External add-on data directories outside `/config` are not included.

Before copying or pushing any configuration data, the add-on checks the GitHub API and proceeds only if the target repository is private. If visibility cannot be verified or the repository is public, it writes an error to the add-on log and does not perform a backup. If the private repository is empty, it creates and pushes an English README that identifies it as a backup destination for this add-on, then continues with the normal sync.

Runtime data, databases, logs, authentication data, tokens, and `secrets.yaml` are excluded by default. This reduces the risk of committing credentials to Git. The Git Ignore Editor warns if its `secrets.yaml` rule and the explicit `include_secrets` option do not match. Removing the ignore rule alone never enables secret backups; you must also explicitly enable `include_secrets` in the add-on configuration. Use a private backup repository if you do.

## Changing the interval or Git ignore rules

Open the **HA Config Sync** app page to change `sync_interval_hours`. To edit Git ignore rules, select **Open Web UI** on the same app page; saving there updates the local Git checkout immediately and is committed during the next sync without restarting the add-on. The Git Ignore Editor saves its rules directly as `<Home Assistant config directory>/ha_config_sync.gitignore`. This is a user-managed Home Assistant configuration file: it persists across add-on updates and the add-on never overwrites it when it already exists. Git metadata remains in the add-on’s persistent `/data` area. The add-on uses the rules when building an isolated Git index from `/config`; it does not modify or clean files in `/config`. The Web UI also shows the most recent sync check, the timestamp of the latest commit in the local backup checkout, an **Open private backup repository** button when a GitHub backup remote is configured, and a **Diagnostics** section for viewing or downloading selected add-on logs. Use **Clear local Git cache** to discard the local clone and any unpushed local commits; the next sync downloads the backup repository again. The configured ignore rules apply to paths read from `/config` before they are placed in a commit.

> **Security note:** Keep `homeassistant/secrets.yaml` in `gitignore` unless you fully understand the implications and use a private repository. Git ignore rules do not remove files that were committed previously; remove those files and their history separately if needed.

The add-on log shows the result of each sync.

## In-app documentation

The same documentation is available inside Home Assistant on the **Documentation** tab of the add-on page. It is maintained in [`ha_config_sync/DOCS.md`](ha_config_sync/DOCS.md).

## Changelog

Home Assistant displays the release notes from [`ha_config_sync/CHANGELOG.md`](ha_config_sync/CHANGELOG.md) whenever an add-on update is available. Add an entry there before every future version bump.

## Safety note

Version 3.1.0 uses `/config` as a read-only Git source tree only. Git metadata and indexes remain isolated in the add-on, and the add-on must never run Git cleanup commands directly against Home Assistant configuration files.
