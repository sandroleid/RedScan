# RedScan

**Native macOS-App zum Scannen des lokalen Netzwerks – im roten Design.**
RedScan findet alle Geräte im Netz und sammelt so viele Informationen wie möglich: Hersteller, Namen, Modell,
Betriebssystem, offene Ports, Dienste, Webseiten und Zertifikate. Geschrieben in Swift/SwiftUI, ohne Abhängigkeiten.

## Funktionen

- **Geräteerkennung** per Ping-Sweep und ARP-Tabelle (findet auch Geräte, die Ping blockieren)
- **Hersteller** aus der MAC-Adresse (~58.000 Einträge), Erkennung privater/zufälliger MAC-Adressen
- **Namen** über mDNS/Bonjour, NetBIOS (Windows/Samba), Reverse-DNS und UPnP
- **Bonjour-Dienste** inkl. TXT-Daten (AirPlay, HomeKit, Drucker, Google Cast, Spotify Connect …) und Apple-Modellkennung
- **UPnP/SSDP**: Gerätename, Hersteller, Modell, Seriennummer, Admin-URL
- **Port-Scan** (~70 typische Ports, parallel) und **Tiefenscan** pro Gerät (Ports 1–1024 + bekannte Dienst-Ports)
- **Banner & Web**: SSH/FTP/MySQL-Versionen, HTTP-Server, Seitentitel, TLS-Zertifikat
- **Automatische Einordnung** als Smartphone, Router, Drucker, TV, NAS, Kamera, Smart-Home-Gerät … plus OS-Schätzung
- **Verlauf**: jeder Scan wird gespeichert, neue und verschwundene Geräte werden markiert, „zuerst/zuletzt gesehen“
- **Wake-on-LAN**: Geräte per Magic Packet aufwecken – auch offline Geräte aus dem Verlauf
- Kachel- und Listenansicht, Suche, Filter nach Gerätetyp, **Export als JSON oder CSV**

## Installation

1. `RedScan-1.0.0.zip` unter [Releases](../../releases) herunterladen und entpacken.
2. `RedScan.app` nach **Programme** ziehen.
3. Die App ist nicht von Apple notarisiert. Beim ersten Start daher **Rechtsklick → Öffnen** oder im Terminal:
   ```sh
   xattr -dr com.apple.quarantine /Applications/RedScan.app
   ```
4. Beim ersten Scan den Zugriff auf das **lokale Netzwerk erlauben**
   (oder später unter *Systemeinstellungen → Datenschutz & Sicherheit → Lokales Netzwerk*).
   Ohne diese Freigabe blendet macOS die ARP-Tabelle aus – dann fehlen MAC-Adressen und Hersteller.

Voraussetzung: macOS 14 (Sonoma) oder neuer, Apple Silicon.

## Selbst bauen

Benötigt nur die Xcode Command Line Tools (`xcode-select --install`), kein volles Xcode:

```sh
git clone https://github.com/sandroleid/RedScan.git
cd RedScan
./build.sh
open build/RedScan.app
```

### Kommandozeile

```sh
# Scan sofort starten und Ergebnis als JSON speichern
open -a RedScan --args --autoscan --dump ~/Desktop/scan.json
```

### Hersteller-Datenbank aktualisieren

```sh
curl -sSLo /tmp/manuf https://www.wireshark.org/download/automated/data/manuf
python3 Tools/make_oui.py /tmp/manuf Resources/oui.txt && ./build.sh
```

## Tastenkürzel

| Kürzel | Aktion |
|---|---|
| ⌘R | Netzwerk scannen |
| ⌘. | Scan abbrechen |
| ⌘1 / ⌘2 | Geräte / Verlauf |
| ⌘E | Als JSON exportieren |

## Projektstruktur

```
Sources/RedScan/
  RedScanApp.swift     App-Einstieg, Fenster, Navigation
  NetScanner.swift     Ablauf des Scans, Geräte-Updates, Export, Wake-on-LAN
  Net.swift            Netzwerk-Erkennung, IPv4-/UDP-Hilfen, Hersteller-DB
  Probes.swift         Ping, ARP, Port-Scan, Banner, NetBIOS, mDNS, DNS, SSDP/UPnP, HTTP/TLS
  Bonjour.swift        Bonjour-Suche und -Auflösung
  Classifier.swift     Gerätetyp-Heuristik
  History.swift        Verlauf (gespeichert in ~/Library/Application Support/RedScan) und Wake-on-LAN
  *View.swift, Theme   Oberfläche
Resources/             Info.plist, Icon, Hersteller-Datenbank
Tools/                 Icon-Generator, Konverter für die Hersteller-DB
```

## Rechtlicher Hinweis

Scanne nur Netzwerke, die dir gehören oder für die du ausdrücklich eine Erlaubnis hast.
Port-Scans fremder Netze können verboten sein und gegen Nutzungsbedingungen (z. B. Schul- oder Firmennetz) verstoßen.

## Lizenz

[GNU General Public License v3.0](LICENSE).
Die Hersteller-Datenbank (`Resources/oui.txt`) wurde aus der [Wireshark](https://www.wireshark.org)-Datei `manuf` erzeugt
(GPL-2.0-or-later), die auf den öffentlichen IEEE-Registern basiert.
