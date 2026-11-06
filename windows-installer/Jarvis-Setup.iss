; Jarvis single-file Windows installer
#define MyAppName "Jarvis"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Jarvis"
#define MyAppExeName "jarvis_personal_assistant.exe"

[Setup]
AppId={{A9F20B54-90D8-4F0D-8C74-5A1D4B0D6C21}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\JarvisInstaller
DefaultGroupName=Jarvis
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir=dist
OutputBaseFilename=Jarvis-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
Uninstallable=yes
CloseApplications=no

[Files]
; The payload is unpacked to a temporary folder. The bootstrap copies the app
; and backend into the per-user install directory and creates the desktop link.
Source: "dist\Jarvis-Windows\*"; DestDir: "{tmp}\JarvisBundle"; Flags: recursesubdirs createallsubdirs deleteafterinstall

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{tmp}\JarvisBundle\Install-Jarvis.ps1"""; StatusMsg: "Installing Jarvis, preparing the PC backend and configuring Windows..."; Flags: runhidden waituntilterminated
