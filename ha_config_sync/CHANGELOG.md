# Changelog

All notable changes to **HA Config Sync** are documented in this file.

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
