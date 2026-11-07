#define MyAppName "Jarvis"
#define MyAppVersion "0.2.0"
#define BundleDir "..\build\installer-bundle"

[Setup]
AppId={{A4B2CC7A-39C1-4B6A-9C0B-6D8A1C6D0F22}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={localappdata}\Programs\Jarvis
DisableDirPage=no
DirExistsWarning=no
DisableProgramGroupPage=yes
Uninstallable=no
OutputDir=..\build\installer-output
OutputBaseFilename=Jarvis-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64

[Tasks]
Name: "desktopicon"; Description: "Create a Jarvis desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{tmp}\JarvisBundle"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
; Start Menu shortcut is always created; Desktop shortcut is optional in setup.
Name: "{autoprograms}\Jarvis"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Start-Jarvis.ps1"""; WorkingDir: "{app}"
Name: "{autodesktop}\Jarvis"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Start-Jarvis.ps1"""; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{tmp}\JarvisBundle\Install-Jarvis.ps1"" -InstallRoot ""{app}"""; Flags: waituntilterminated
