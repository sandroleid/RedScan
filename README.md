# RedScan

**Netzwerk-Scanner für macOS und Windows – im roten Design.**
RedScan findet alle Geräte im lokalen Netz und sammelt so viele Informationen wie möglich: Hersteller, Namen, Modell,
Betriebssystem, offene Ports, Dienste, Webseiten und Zertifikate.

| Plattform | Technik | Ordner | Release-Tag |
|---|---|---|---|
| **macOS** | Swift / SwiftUI, ohne Abhängigkeiten | Stammverzeichnis | `v…` (z. B. `v1.0.2`) |
| **Windows** | C# / .NET 8, WinUI 3 | [`windows/`](windows/) | `windows-v…` (z. B. `windows-v1.0.0`) |

## Funktionen (beide Plattformen)

- **Geräteerkennung** per Ping-Sweep und ARP-Tabelle (findet auch Geräte, die Ping blockieren), Netze bis /16
- **Hersteller** aus der MAC-Adresse (~58.000 Einträge), Erkennung privater/zufälliger MAC-Adressen
- **Namen** über mDNS/Bonjour, NetBIOS (Windows/Samba), Reverse-DNS und UPnP
- **Bonjour-Dienste** inkl. TXT-Daten (AirPlay, HomeKit, Drucker, Google Cast, Spotify Connect …) und Apple-Modellkennung
- **UPnP/SSDP**: Gerätename, Hersteller, Modell, Seriennummer, Admin-URL
- **Port-Scan** (~70 typische Ports, parallel) und **Tiefenscan** pro Gerät (Ports 1–1024 + bekannte Dienst-Ports)
- **Banner & Web**: SSH/FTP/MySQL-Versionen, HTTP-Server, Seitentitel, TLS-Zertifikat
- **Automatische Einordnung** als Smartphone, Router, Drucker, TV, NAS, Kamera, Smart-Home-Gerät … plus OS-Schätzung
- **Verlauf**: jeder Scan wird gespeichert, neue und verschwundene Geräte werden markiert, „zuerst/zuletzt gesehen“
- **Wake-on-LAN**: Geräte per Magic Packet aufwecken – auch offline Geräte aus dem Verlauf
- Suche, Detailansicht pro Gerät, **Export als JSON oder CSV**
- **Hell/Dunkel-Modus**: Darstellung unten in der Seitenleiste umschalten (Standard: Dunkel), wirkt sofort und wird gespeichert

## Installation

Alle Downloads findest du unter [Releases](https://github.com/sandroleid/RedScan/releases).

### macOS

1. Das neueste Release **RedScan-macOS** (Tag `v…`) öffnen, `RedScan-macOS-<Version>.zip` herunterladen und entpacken.
2. `RedScan.app` nach **Programme** ziehen.
3. Die App ist nicht von Apple notarisiert. Beim ersten Start daher **Rechtsklick → Öffnen** oder im Terminal:
   ```sh
   xattr -dr com.apple.quarantine /Applications/RedScan.app
   ```
4. Beim ersten Scan den Zugriff auf das **lokale Netzwerk erlauben**
   (oder später unter *Systemeinstellungen → Datenschutz & Sicherheit → Lokales Netzwerk*).
   Ohne diese Freigabe blendet macOS die ARP-Tabelle aus – dann fehlen MAC-Adressen und Hersteller.

Voraussetzung: macOS 14 (Sonoma) oder neuer, Apple Silicon.

### Windows

1. Das neueste Windows-Release (Tag `windows-v…`) öffnen, `RedScan-Windows.zip` herunterladen und entpacken.
2. `RedScan.exe` starten. Die App ist self-contained – .NET oder das Windows App SDK müssen **nicht** installiert sein.
3. Die App ist nicht signiert. Zeigt **Windows SmartScreen** eine Warnung, „Weitere Informationen → Trotzdem ausführen“ wählen.
4. Fragt die **Windows-Firewall** nach, den Zugriff im **privaten Netzwerk** erlauben, damit Antworten der Geräte ankommen.

Voraussetzung: Windows 10 (ab 1809) oder Windows 11, 64-Bit.

## Bedienung

| Aktion | macOS | Windows |
|---|---|---|
| Netzwerk scannen | ⌘R oder Button „Netzwerk scannen“ | Button „Netzwerk scannen“ |
| Scan abbrechen | ⌘. | Button „Scan abbrechen“ |
| Geräte / Verlauf | ⌘1 / ⌘2 | Buttons „Geräte“ / „Verlauf“ |
| Export | ⌘E (JSON), Menü „Scan“ (CSV) | Export-Button oben rechts |
| Eigenes Ziel scannen | CIDR ins Feld „Ziel“ eintragen, z. B. `192.168.1.0/24` | ebenso |
| Hell/Dunkel | Umschalter „Darstellung“ unten in der Seitenleiste | ebenso |

Der Verlauf wird lokal gespeichert:
macOS unter `~/Library/Application Support/RedScan/history.json`,
Windows unter `%LOCALAPPDATA%\RedScan\history.json`.
Die gewählte Darstellung (Hell/Dunkel) merkt sich macOS in den App-Einstellungen (UserDefaults, Schlüssel `appearance`),
Windows in `%LOCALAPPDATA%\RedScan\settings.json`. Beim Start lässt sie sich mit `--theme light` bzw. `--theme dark`
einmalig überschreiben.

## Selbst bauen

### macOS

Benötigt nur die Xcode Command Line Tools (`xcode-select --install`), kein volles Xcode:

```sh
git clone https://github.com/sandroleid/RedScan.git
cd RedScan
./build.sh
open build/RedScan.app
```

Scan ohne Oberfläche starten und als JSON speichern:

```sh
open -a RedScan --args --autoscan --dump ~/Desktop/scan.json
```

### Windows

Benötigt das **.NET 8 SDK** und **Visual Studio 2022** mit der Workload „.NET-Desktopentwicklung“
(die WinUI-Ressourcen-Tasks liegen in der VS-MSBuild-Installation). Vom Stammverzeichnis aus:

```powershell
# Logik-Tests
dotnet test windows/src/RedScan.Tests/RedScan.Tests.csproj -c Release

# App bauen (x64, self-contained)
msbuild windows/src/RedScan.App/RedScan.App.csproj /t:Restore /p:Configuration=Release /p:Platform=x64
msbuild windows/src/RedScan.App/RedScan.App.csproj /t:Publish /p:Configuration=Release /p:Platform=x64 ^
  /p:RuntimeIdentifier=win-x64 /p:SelfContained=true /p:WindowsAppSDKSelfContained=true /p:WindowsPackageType=None
```

Die Windows-Version wird automatisch über GitHub Actions (`.github/workflows/windows.yml`) auf echtem Windows
getestet und gebaut. Ein Tag `windows-v*` erzeugt automatisch ein Release mit der fertigen App.

### Hersteller-Datenbank aktualisieren

```sh
curl -sSLo /tmp/manuf https://www.wireshark.org/download/automated/data/manuf
python3 Tools/make_oui.py /tmp/manuf Resources/oui.txt
cp Resources/oui.txt windows/src/RedScan.Core/Resources/oui.txt
```

## Projektstruktur

```
Sources/RedScan/            macOS-App (Swift/SwiftUI)
  RedScanApp.swift          App-Einstieg, Fenster, Navigation
  NetScanner.swift          Ablauf des Scans, Geräte-Updates, Export, Wake-on-LAN
  Net.swift                 Netzwerk-Erkennung, IPv4-/UDP-Hilfen, Hersteller-DB
  Probes.swift              Ping, ARP, Port-Scan, Banner, NetBIOS, mDNS, DNS, SSDP/UPnP, HTTP/TLS
  Bonjour.swift             Bonjour-Suche und -Auflösung
  Classifier.swift          Gerätetyp-Heuristik
  History.swift             Verlauf und Wake-on-LAN
  *View.swift, Theme        Oberfläche
Resources/                  Info.plist, Icon, Hersteller-Datenbank (macOS)
Tools/                      Icon-Generator, Konverter für die Hersteller-DB
build.sh                    Baut RedScan.app

windows/                    Windows-App (C#/.NET, WinUI 3)
  src/RedScan.Core/         Scan-Logik: Ping, ARP (iphlpapi), Ports, mDNS, SSDP, NetBIOS, Verlauf …
  src/RedScan.Tests/        xUnit-Tests (laufen in CI auf echtem Windows)
  src/RedScan.App/          WinUI-Oberfläche im roten Design

.github/workflows/windows.yml   Test, Build und Release der Windows-Version
```

## Rechtlicher Hinweis

Scanne nur Netzwerke, die dir gehören oder für die du ausdrücklich eine Erlaubnis hast.
Port-Scans fremder Netze können verboten sein und gegen Nutzungsbedingungen (z. B. Schul- oder Firmennetz) verstoßen.

## Lizenz

[GNU General Public License v3.0](LICENSE).
Die Hersteller-Datenbank (`Resources/oui.txt` und `windows/src/RedScan.Core/Resources/oui.txt`) wurde aus der
[Wireshark](https://www.wireshark.org)-Datei `manuf` erzeugt (GPL-2.0-or-later), die auf den öffentlichen IEEE-Registern basiert.
