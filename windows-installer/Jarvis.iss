#define MyAppName "Jarvis"
#define MyAppVersion "0.3.2"
#define BundleDir "..\build\installer-bundle"
[Setup]
AppId={{A4B2CC7A-39C1-4B6A-9C0B-6D8A1C6D0F22}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={localappdata}\Programs\Jarvis
DisableDirPage=no
DirExistsWarning=no
DisableProgramGroupPage=yes
Uninstallable=yes
OutputDir=..\build\installer-output
OutputBaseFilename=Jarvis-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64
SetupLogging=yes
[Tasks]
Name: "desktopicon"; Description: "Create a Jarvis desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: checkedonce
[Files]
Source: "{#BundleDir}\*"; DestDir: "{tmp}\JarvisBundle"; Flags: recursesubdirs createallsubdirs ignoreversion
[Registry]
Root: HKCU; Subkey: "Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\Jarvis.exe"; Flags: uninsdeletekey

[Icons]
Name: "{autoprograms}\Jarvis"; Filename: "{app}\Jarvis.exe"; WorkingDir: "{app}"; IconFilename: "{app}\Jarvis.exe"
Name: "{autodesktop}\Jarvis"; Filename: "{app}\Jarvis.exe"; WorkingDir: "{app}"; IconFilename: "{app}\Jarvis.exe"; Tasks: desktopicon
[Run]
Filename: "powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{tmp}\JarvisBundle\Install-Jarvis.ps1"" -InstallRoot ""{app}"""; StatusMsg: "Installing Jarvis desktop app and local services..."; Flags: runhidden waituntilterminated
Filename: "{app}\\Jarvis.exe"; Description: "Launch Jarvis"; Flags: postinstall nowait skipifsilent
