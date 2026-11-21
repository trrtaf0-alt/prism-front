#ifndef AppVersion
  #define AppVersion "0.8.0"
#endif
#ifndef AppId
  #define AppId "PrismFront"
#endif
#ifndef AppName
  #define AppName "프리즘 방어선"
#endif
#ifndef OutputName
  #define OutputName "PrismFront-Setup-Windows-x64"
#endif

#ifndef GameExe
  #define GameExe "..\dist\PrismFront.exe"
#endif

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\{#AppId}
DefaultGroupName={#AppName}
SetupIconFile=..\assets\prism.ico
UninstallDisplayIcon={app}\PrismFront.exe
DisableWelcomePage=yes
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
UsePreviousTasks=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\dist
OutputBaseFilename={#OutputName}
Compression=lzma2/normal
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes

[Languages]
Name: "ko"; MessagesFile: "compiler:Languages\Korean.isl"

[Tasks]
Name: "desktopicon"; Description: "바탕화면 바로가기 만들기"

[Files]
Source: "{#GameExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "Play.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\assets\Godot-LICENSE.txt"; DestDir: "{app}\Licenses"; Flags: ignoreversion
Source: "..\assets\Godot-COPYRIGHT.txt"; DestDir: "{app}\Licenses"; Flags: ignoreversion
Source: "..\assets\OFL.txt"; DestDir: "{app}\Licenses"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\PrismFront.exe"; WorkingDir: "{app}"; IconFilename: "{app}\PrismFront.exe"; IconIndex: 0
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\PrismFront.exe"; WorkingDir: "{app}"; IconFilename: "{app}\PrismFront.exe"; IconIndex: 0; Tasks: desktopicon

[Run]
Filename: "{app}\PrismFront.exe"; WorkingDir: "{app}"; Description: "프리즘 방어선 실행"; Flags: nowait postinstall skipifsilent
