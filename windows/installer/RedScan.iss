; Inno-Setup-Skript für den Windows-Installer von RedScan (RedScan-Setup-<Version>.exe).
;
; Gebaut wird er von GitHub Actions (.github/workflows/windows.yml) nach dem Publish der App.
; Lokal auf Windows (Inno Setup 6.3 oder neuer), vom Projekt-Stammverzeichnis aus:
;
;   ISCC.exe /DPublishDir=C:\pfad\zu\publish /DAppVersion=1.0.6 windows\installer\RedScan.iss
;
; Ergebnis: dist\RedScan-Setup-<Version>.exe im Projekt-Stammverzeichnis (oder Ordner per /O).
;
; AppVersion kommt aus <Version> in windows/src/RedScan.App/RedScan.App.csproj,
; PublishDir ist der Ausgabeordner von "msbuild /t:Publish" (enthält RedScan.exe).

#ifndef PublishDir
  #define PublishDir "..\..\publish"
#endif
#ifndef AppVersion
  ; Fallback: Version direkt aus der veröffentlichten RedScan.exe lesen
  #define AppVersion GetVersionNumbersString(AddBackslash(PublishDir) + "RedScan.exe")
#endif

#define AppName      "RedScan"
#define AppExe       "RedScan.exe"
#define AppPublisher "sandroleid"
#define AppUrl       "https://github.com/sandroleid/RedScan"

[Setup]
; Die AppId NIE ändern: Sie verknüpft neue Versionen mit der bestehenden Installation
; (Update an Ort und Stelle, ein einziger Eintrag unter "Apps & Features").
AppId={{1BF47354-12B0-4814-89C4-9CE9EF0FD3A6}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases
AppComments=Netzwerk-Scanner im roten Design
AppCopyright=GNU General Public License v3.0

; Installation nach C:\Program Files\RedScan (64-Bit), dafür Admin-Rechte (UAC)
DefaultDirName={autopf}\{#AppName}
DisableDirPage=yes
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Windows 10 1809 – wie TargetPlatformMinVersion der App
MinVersion=10.0.17763

; Laufende RedScan-Instanz vor dem Update schließen (Restart Manager)
CloseApplications=yes
CloseApplicationsFilter=*.exe,*.dll
RestartApplications=no

OutputDir=..\..\dist
OutputBaseFilename=RedScan-Setup-{#AppVersion}
SetupIconFile=..\src\RedScan.App\Assets\RedScan.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2/ultra64
SolidCompression=yes
LZMANumBlockThreads=4

; Datei-Eigenschaften der Setup-.exe
VersionInfoVersion={#AppVersion}
VersionInfoProductVersion={#AppVersion}
VersionInfoProductName={#AppName}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} Setup
VersionInfoCopyright=GNU General Public License v3.0

[Languages]
Name: "de"; MessagesFile: "compiler:Languages\German.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Bei einem Update alte Programmdateien entfernen, damit keine veralteten DLLs der
; Vorversion liegen bleiben. Nur in einem eigenen Ordner namens "RedScan" (Schutz,
; falls jemand per /DIR= einen gemeinsam genutzten Ordner angibt).
; Nutzerdaten (Verlauf, Einstellungen) liegen in %LOCALAPPDATA%\RedScan und bleiben erhalten.
Type: filesandordirs; Name: "{app}\*"; Check: IsDedicatedAppDir

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Comment: "Netzwerk-Scanner"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Comment: "Netzwerk-Scanner"; Tasks: desktopicon

[Run]
; postinstall startet die App als der ursprüngliche (nicht erhöhte) Benutzer
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
function IsDedicatedAppDir: Boolean;
begin
  Result := CompareText(ExtractFileName(RemoveBackslashUnlessRoot(ExpandConstant('{app}'))), '{#AppName}') = 0;
end;
