# RedScan für Windows

**Netzwerk-Scanner für Windows (C#/.NET, WinUI 3) – im roten Design.**
Findet alle Geräte im lokalen Netz und sammelt so viele Informationen wie möglich:
Hersteller, Namen, Modell, Betriebssystem, offene Ports, Dienste, Webseiten und Zertifikate.

Dies ist die Windows-Version im selben Repo wie die macOS-App (die liegt im Projekt-Stammverzeichnis).
Gebaut und auf echtem Windows getestet über GitHub Actions.

## Funktionen

- **Geräteerkennung** per Ping-Sweep und ARP-Tabelle (Windows-IP-Helper-API)
- **Hersteller** aus der MAC-Adresse (~58.000 Einträge), Erkennung privater/zufälliger MAC-Adressen
- **Namen** über mDNS/Bonjour, NetBIOS, Reverse-DNS und UPnP
- **Bonjour-Dienste** inkl. TXT-Daten (AirPlay, HomeKit, Drucker, Google Cast, Spotify Connect …)
- **UPnP/SSDP**: Gerätename, Hersteller, Modell, Seriennummer, Admin-URL
- **Port-Scan** (~70 typische Ports) und **Tiefenscan** pro Gerät (Ports 1–1024 + bekannte Dienst-Ports)
- **Banner & Web**: SSH/FTP-Versionen, HTTP-Server, Seitentitel, TLS-Zertifikat
- **Automatische Einordnung** als Smartphone, Router, Drucker, TV, NAS, Kamera, Smart-Home-Gerät … plus OS-Schätzung
- **Verlauf**: jeder Scan wird gespeichert, neue und verschwundene Geräte werden markiert
- **Wake-on-LAN**: Geräte per Magic Packet aufwecken – auch offline Geräte aus dem Verlauf
- Kachelansicht mit Suche und Detailbereich, **Export als JSON oder CSV**

## Installation

1. Aus den [Releases](https://github.com/sandroleid/RedScan/releases) die `RedScan-Windows.zip`
   (Release mit Tag `windows-v…`) herunterladen und entpacken.
2. `RedScan.exe` starten. Die App ist self-contained – .NET oder das Windows App SDK müssen **nicht** installiert sein.
3. Beim ersten Start blendet **Windows SmartScreen** evtl. eine Warnung ein (die App ist nicht signiert):
   „Weitere Informationen“ → „Trotzdem ausführen“.

Voraussetzung: Windows 10 (ab 1809) oder Windows 11, 64-Bit.

> Manche Abfragen (ICMP-Ping, NetBIOS) funktionieren am zuverlässigsten, wenn die App als Administrator läuft
> und in der Windows-Firewall zugelassen ist. Für ein- und ausgehende Scans im eigenen Netz ist das meist nicht nötig.

## Selbst bauen

Benötigt das **.NET 8 SDK** und – für die WinUI-App – **Visual Studio 2022** mit der Workload
„.NET-Desktopentwicklung“ (die WinUI-Ressourcen-Tasks liegen in der VS-MSBuild-Installation).

Alle Befehle vom Projekt-Stammverzeichnis aus:

```powershell
# Logik-Tests
dotnet test windows/src/RedScan.Tests/RedScan.Tests.csproj -c Release

# App bauen (mit VS-MSBuild, x64)
msbuild windows/src/RedScan.App/RedScan.App.csproj /t:Restore /p:Configuration=Release /p:Platform=x64
msbuild windows/src/RedScan.App/RedScan.App.csproj /t:Publish /p:Configuration=Release /p:Platform=x64 ^
  /p:RuntimeIdentifier=win-x64 /p:SelfContained=true /p:WindowsAppSDKSelfContained=true /p:WindowsPackageType=None
```

Die GitHub-Actions-Pipeline (`.github/workflows/windows.yml`) führt beides bei jedem Push aus, der
`windows/` betrifft, und erstellt bei einem Tag `windows-v*` automatisch ein Release mit der fertigen App.

## Projektstruktur

```
src/
  RedScan.Core/     Scan-Logik (plattformunabhängige C#-Bibliothek, auf Windows getestet)
    Probes/         Ping, ARP (iphlpapi), Ports, Banner, mDNS, SSDP/UPnP, NetBIOS, Reverse-DNS
    *.cs            IPv4, Modelle, Hersteller-DB, Klassifizierung, Wake-on-LAN, Verlauf, Scanner
  RedScan.Tests/    xUnit-Tests (laufen in CI auf echtem Windows)
  RedScan.App/      WinUI-3-Oberfläche im roten Design
```

## Rechtlicher Hinweis

Scanne nur Netzwerke, die dir gehören oder für die du ausdrücklich eine Erlaubnis hast.
Port-Scans fremder Netze können verboten sein und gegen Nutzungsbedingungen verstoßen.

## Lizenz

[GNU General Public License v3.0](LICENSE).
Die Hersteller-Datenbank (`src/RedScan.Core/Resources/oui.txt`) wurde aus der
[Wireshark](https://www.wireshark.org)-Datei `manuf` erzeugt (GPL-2.0-or-later, basierend auf den IEEE-Registern).
