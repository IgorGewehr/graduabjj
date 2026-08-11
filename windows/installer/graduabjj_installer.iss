; Script de Instalação Inno Setup para GraduaBJJ Desktop
; Compila todos os binários da Release (.exe, DLLs e pasta data/) em um único GraduaBJJ-Setup.exe

#ifndef AppVersion
#define AppVersion "3.4.1"
#endif

#define MyAppName "GraduaBJJ"
#define MyAppPublisher "MyDojo"
#define MyAppURL "https://mydojo.com.br"
#define MyAppExeName "graduabjj.exe"
#define MyAppIcon "..\runner\resources\app_icon.ico"
#define BuildReleaseDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{D37D57B7-99E8-41C2-824F-88997BA53123}}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=
OutputDir=..\..\build\windows\installer
OutputBaseFilename=GraduaBJJ-Setup-v{#AppVersion}
SetupIconFile={#MyAppIcon}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Copia o executável principal
Source: "{#BuildReleaseDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

; Copia todas as DLLs e a pasta data/ (incluindo file_selector_windows_plugin.dll, flutter_windows.dll, etc.)
Source: "{#BuildReleaseDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildReleaseDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{#MyAppIcon}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{#MyAppIcon}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
