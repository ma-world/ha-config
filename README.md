# Home Assistant Configuration Sync

Dieses Repository ist zugleich ein **lokales Home-Assistant-Add-on-Repository** und das Ziel für Konfigurations-Snapshots. Die Ausführung findet vollständig in Home Assistant statt:

1. Die Home-Assistant-Automation startet das Add-on beim Systemstart sowie alle vier Stunden (00:00, 04:00, 08:00, …).
2. Das Add-on liest `/config`, übernimmt nur ausgewählte Konfigurationsdateien in den Ordner `homeassistant/`, erstellt bei Änderungen einen Commit und pusht ihn nach `main`.

## Einmalig einrichten

1. Dieses Repository zuerst nach GitHub pushen.
2. In Home Assistant unter **Einstellungen → Add-ons → Add-on-Shop → Repositories** `https://github.com/ma-world/ha-config` hinzufügen.
3. Das Add-on **HA Config Sync** installieren.
4. In der Add-on-Konfiguration einen GitHub Fine-grained Personal Access Token eintragen. Er benötigt für dieses Repository mindestens **Contents: Read and write**. Der Token wird ausschließlich in der Add-on-Konfiguration gespeichert und niemals in das Git-Repository geschrieben.
5. Die Datei [`homeassistant/packages/ha_config_sync.yaml`](homeassistant/packages/ha_config_sync.yaml) nach `/config/packages/ha_config_sync.yaml` kopieren. Falls Packages noch nicht aktiviert sind, in `/config/configuration.yaml` ergänzen:

   ```yaml
   homeassistant:
     packages: !include_dir_named packages
   ```

6. Home Assistant neu starten oder die Automation neu laden. Die Automation `HA Config Sync – alle 4 Stunden` führt den ersten Lauf direkt nach dem Start aus.

## Gesicherte Inhalte

Standardmäßig werden unter `homeassistant/` gesichert: `configuration.yaml`, Automationen, Skripte, Szenen, Packages, Blueprints, Themes, `custom_components`, ESPHome-, Zigbee2MQTT- und WWW-Dateien sowie optional die Lovelace-Dashboarddefinitionen.

Nicht gesichert werden Laufzeitdaten, Datenbanken, Logs, Authentifizierungsdaten, Tokens und `secrets.yaml`. Das verhindert, dass Zugangsdaten versehentlich nach GitHub gelangen. `secrets.yaml` kann in den Add-on-Optionen bewusst aktiviert werden – empfohlen ist dafür ausschließlich ein privates Repository.

## Manuell ausführen

In **Entwicklerwerkzeuge → Aktionen** die Aktion `hassio.addon_start` mit folgendem Datenfeld ausführen:

```yaml
addon: local_ha_config_sync
```

Das Add-on beendet sich nach einem erfolgreichen oder unveränderten Lauf wieder. Details stehen im Add-on-Protokoll.
