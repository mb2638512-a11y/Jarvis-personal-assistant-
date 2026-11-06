; Jarvis single-file Windows bootstrap installer
#define RepoRoot GetEnv("GITHUB_WORKSPACE")
#define MyAppName "Jarvis"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Jarvis"

[Setup]
AppId={{A9F20B54-90D8-4F0D-8C74-5A1D4B0D6C21}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\Jarvis
DefaultGroupName=Jarvis
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
Uninstallable=no
OutputDir=..\dist
OutputBaseFilename=Jarvis-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=no

[Files]
; Payload is staged by the workflow at repository-root dist/Jarvis-Windows.
Source: "..\dist\Jarvis-Windows\*"; DestDir: "{tmp}\JarvisBundle"; Flags: recursesubdirs createallsubdirs deleteafterinstall

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{tmp}\JarvisBundle\Install-Jarvis.ps1"""; StatusMsg: "Installing Jarvis and configuring the Windows PC..."; Flags: runhidden waituntilterminated
