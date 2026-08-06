# Home Assistant Configuration Sync

Dieses Repository ist ein **öffentliches lokales Home-Assistant-Add-on-Repository**. Die Konfigurations-Snapshots werden getrennt und standardmäßig in das private Repository `ma-world/homeassistant-config-files` geschrieben. Die Ausführung findet vollständig in Home Assistant statt:

1. Das Add-on startet beim Start von Home Assistant automatisch.
2. Es synchronisiert sofort nach dem Start und danach im in der Add-on-Konfiguration festgelegten Intervall (standardmäßig alle vier Stunden).
3. Es liest `/config`, übernimmt nur ausgewählte Konfigurationsdateien in den Ordner `homeassistant/`, erstellt bei Änderungen einen Commit und pusht ihn nach `main`.

## Einmalig einrichten

1. Das Add-on-Repository `ma-world/ha-config` ist öffentlich verfügbar.
2. In Home Assistant unter **Einstellungen → Add-ons → Add-on-Shop → Repositories** `https://github.com/ma-world/ha-config` hinzufügen.
3. Das Add-on **HA Config Sync** installieren.
4. In der Add-on-Konfiguration einen GitHub Fine-grained Personal Access Token eintragen. Er benötigt für dieses Repository mindestens **Contents: Read and write**. Der Token wird ausschließlich in der Add-on-Konfiguration gespeichert und niemals in das Git-Repository geschrieben.
5. In der Add-on-Konfiguration **`sync_interval_hours`** auf das gewünschte Intervall setzen (zulässig: 1 bis 168 Stunden; Standard: 4).
6. Das Add-on starten. Es führt sofort einen ersten Lauf durch und bleibt anschließend aktiv, um nach jedem konfigurierten Intervall erneut zu sichern.

## Gesicherte Inhalte

Standardmäßig werden unter `homeassistant/` gesichert: `configuration.yaml`, Automationen, Skripte, Szenen, Packages, Blueprints, Themes, `custom_components`, ESPHome-, Zigbee2MQTT- und WWW-Dateien sowie optional die Lovelace-Dashboarddefinitionen.

Nicht gesichert werden Laufzeitdaten, Datenbanken, Logs, Authentifizierungsdaten, Tokens und `secrets.yaml`. Das verhindert, dass Zugangsdaten versehentlich nach GitHub gelangen. `secrets.yaml` kann in den Add-on-Optionen bewusst aktiviert werden – empfohlen ist dafür ausschließlich ein privates Repository.

## Intervall ändern

Öffne das Add-on **HA Config Sync**, ändere `sync_interval_hours` und speichere die Konfiguration. Starte das Add-on anschließend neu, damit das neue Intervall gilt. Details zu jedem Lauf stehen im Add-on-Protokoll.
