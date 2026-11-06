#define MyAppName "Jarvis"
#define MyAppVersion "0.2.0"
#define BundleDir "build\installer-bundle"

[Setup]
AppId={{A4B2CC7A-39C1-4B6A-9C0B-6D8A1C6D0F22}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={tmp}\JarvisInstaller
DisableProgramGroupPage=yes
Uninstallable=no
OutputDir=build\installer-output
OutputBaseFilename=Jarvis-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64

[Files]
Source: "{#BundleDir}\*"; DestDir: "{tmp}\JarvisBundle"; Flags: recursesubdirs createallsubdirs ignoreversion

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{tmp}\JarvisBundle\Install-Jarvis.ps1"""; Flags: waituntilterminated
