// Synthetic prior product. Shares only the isolated journey AppId, never public identity.
#ifndef SourceDir
  #error Upgrade fixture requires the synthetic payload directory.
#endif
[Setup]
AppId={{A6690692-4D92-475A-9EAC-1AD867AB0635}
AppName=Prior product upgrade fixture
AppVersion=0.0.0
DefaultDirName={localappdata}\Programs\Prior product upgrade fixture
DefaultGroupName=Prior product upgrade fixture
UsePreviousAppDir=no
UsePreviousGroup=no
PrivilegesRequired=lowest
DisableWelcomePage=yes
DisableDirPage=yes
DisableProgramGroupPage=yes
#ifdef UpgradeRenamedExecutableFixture
UninstallDisplayIcon={app}\budlark.exe
OutputBaseFilename=renamed-product-upgrade-fixture
#else
UninstallDisplayIcon={app}\Prior product upgrade fixture.exe
OutputBaseFilename=prior-product-upgrade-fixture
#endif
#if AppArch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
[Files]
#ifdef UpgradeRenamedExecutableFixture
Source: "{#SourceDir}\budlark.exe"; DestDir: "{app}"
#else
Source: "{#SourceDir}\budlark.exe"; DestDir: "{app}"; DestName: "Prior product upgrade fixture.exe"
#endif
[Icons]
#ifdef UpgradeRenamedExecutableFixture
Name: "{group}\Budlark"; Filename: "{app}\budlark.exe"
Name: "{group}\Uninstall Budlark"; Filename: "{uninstallexe}"
#else
Name: "{group}\Prior product upgrade fixture"; Filename: "{app}\Prior product upgrade fixture.exe"
Name: "{group}\Uninstall prior product upgrade fixture"; Filename: "{uninstallexe}"
Name: "{userdesktop}\Prior product upgrade fixture"; Filename: "{app}\Prior product upgrade fixture.exe"
#endif
