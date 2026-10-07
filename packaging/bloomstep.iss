#ifndef AppArch
  #define AppArch "arm64"
#endif
#ifdef UniversalIntegrityFixture
  #ifndef OnboardingJourneyFixture
    #error Integrity fault injection requires the isolated journey identity, never a public package.
  #endif
#endif
#ifndef AppVersion
  #define AppVersion "0.1.0-preview"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\" + AppArch + "\runner\Release"
#endif
#if AppArch == "universal"
  #ifndef SourceDirX64
    #error Universal packaging requires the verified x64 Release directory.
  #endif
  #ifndef SourceDirArm64
    #error Universal packaging requires the verified ARM64 Release directory.
  #endif
#endif

[Setup]
#ifdef OnboardingFixture
AppId={{8E9B101B-CB3D-4C0F-B733-FC1DFFB75129}
UsePreviousAppDir=no
#else
#ifdef OnboardingJourneyFixture
AppId={{A6690692-4D92-475A-9EAC-1AD867AB0635}
UsePreviousAppDir=no
#else
AppId={{99BE7E95-0565-4C72-A4DD-46D1D5B6C679}
UsePreviousAppDir=yes
#endif
#endif
#ifdef OnboardingJourneyFixture
AppName=Bloomstep isolated journey proof
VersionInfoProductName=Bloomstep isolated journey proof
#else
AppName=Bloomstep
#endif
AppVersion={#AppVersion}
AppPublisher=Bloomstep contributors
AppPublisherURL=https://github.com/Sampath-K/bloomstep
DefaultDirName={localappdata}\Programs\Bloomstep
DefaultGroupName=Bloomstep
PrivilegesRequired=lowest
OutputDir=..\release-output
OutputBaseFilename=Bloomstep-{#AppVersion}-windows-{#AppArch}-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableWelcomePage=yes
DisableReadyPage=yes
DisableDirPage=no
DisableProgramGroupPage=yes
WizardImageFile=assets\wizard-garden.bmp
WizardSmallImageFile=assets\wizard-seed.bmp
UninstallDisplayIcon={app}\bloomstep.exe
CloseApplications=yes
RestartApplications=no
#if AppArch == "universal"
ArchitecturesAllowed=arm64 or x64os
ArchitecturesInstallIn64BitMode=arm64 or x64os
#elif AppArch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif

[Messages]
SelectDirDesc=Choose where Bloomstep will grow.
SelectDirLabel3=Bloomstep will use this folder. Select Install to begin, Browse to choose another folder, or Cancel to leave without installing.
FinishedHeadingLabel=Bloomstep is ready
FinishedLabel=Open Bloomstep to create your first tiny habit.%nLimited unsigned Windows preview. Sign-in required. Opening the app below is optional.

[Files]
#if AppArch == "universal"
Source: "{#SourceDirX64}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Check: UseX64Payload
Source: "{#SourceDirArm64}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Check: UseArm64Payload
#else
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
#endif
Source: "assets\education-seed.bmp"; Flags: dontcopy
Source: "assets\education-growth.bmp"; Flags: dontcopy
Source: "assets\education-recipe.bmp"; Flags: dontcopy
Source: "assets\education-hero.bmp"; Flags: dontcopy
#ifdef UniversalIntegrityFixture
Source: "{#IntegrityMarker}"; DestDir: "{app}"; DestName: "integrity-probe.txt"; Flags: ignoreversion nocompression
#endif

[InstallDelete]
Type: files; Name: "{app}\measurement-owner.txt"

[Icons]
Name: "{group}\Bloomstep"; Filename: "{app}\bloomstep.exe"
Name: "{group}\Uninstall Bloomstep"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\bloomstep.exe"; Description: "Launch Bloomstep and plant your first habit"; Flags: nowait postinstall skipifsilent runasoriginaluser; Check: CanLaunchBloomstep; AfterInstall: MarkBloomstepLaunched

[UninstallDelete]
Type: files; Name: "{userstartup}\Bloomstep.lnk"
Type: files; Name: "{app}\measurement-owner.txt"

[Registry]
#ifndef OnboardingJourneyFixture
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "Bloomstep"; Flags: uninsdeletevalue dontcreatekey
Root: HKCU; Subkey: "Software\Classes\bloomstep"; ValueType: string; ValueData: "URL:Bloomstep invitation"
Root: HKCU; Subkey: "Software\Classes\bloomstep"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\bloomstep\DefaultIcon"; ValueType: string; ValueData: "{app}\bloomstep.exe,0"
Root: HKCU; Subkey: "Software\Classes\bloomstep\shell\open\command"; ValueType: string; ValueData: """{app}\bloomstep.exe"" ""%1"""
#endif

[Code]
#if AppArch == "universal"
function UseX64Payload(): Boolean;
begin
  Result := ProcessorArchitecture = paX64;
end;

function UseArm64Payload(): Boolean;
begin
  Result := ProcessorArchitecture = paArm64;
end;
#endif
#ifdef OnboardingFixture
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := 'Compile-only onboarding fixture. Installation is prohibited; cancel this wizard.';
end;
#endif
#ifdef OnboardingJourneyFixture
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), '/FORCEFIXTUREFAILURE') = 0 then
      Result := 'Isolated fixture installation failure. No files installed.';
end;
#endif

type
  TWindowStationFlags = record
    Inherit, Reserved, Flags: LongWord;
  end;

function GetProcessWindowStation(): THandle;
  external 'GetProcessWindowStation@user32.dll stdcall';
function GetUserObjectInformation(Handle: THandle; Index: Integer;
  var Flags: TWindowStationFlags; Size: LongWord; var Needed: LongWord): Boolean;
  external 'GetUserObjectInformationW@user32.dll stdcall';

var
  InstallationSucceeded, LaunchAttempted, InteractiveDesktop: Boolean;

#include "install-progress.iss"

function CanLaunchBloomstep(): Boolean;
var
  I: Integer;
begin
  Result := InstallationSucceeded and not WizardSilent and not IsAdmin and not LaunchAttempted and InteractiveDesktop;
  for I := 1 to ParamCount do
    if (CompareText(ParamStr(I), '/SUPPRESSMSGBOXES') = 0) or
       (CompareText(ParamStr(I), '/NOCANCEL') = 0) then Result := False;
end;

procedure MarkBloomstepLaunched();
begin
  LaunchAttempted := True;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpSelectDir then
    WizardForm.NextButton.Caption := SetupMessage(msgButtonInstall);
  if CurPageID = wpInstalling then StartInstallMotion()
  else StopInstallMotion();
  if (CurPageID = wpFinished) and IsAdmin then
  begin
    WizardForm.FinishedLabel.Caption := WizardForm.FinishedLabel.Caption + #13#10#13#10 +
      'Automatic launch is unavailable from an elevated installer. Close Setup and open Bloomstep normally from your Windows account.';
    WizardForm.FinishedLabel.AdjustHeight();
    WizardForm.RunList.Top := WizardForm.FinishedLabel.Top + WizardForm.FinishedLabel.Height + ScaleY(12);
    WizardForm.RunList.Height := WizardForm.FinishedPage.Height - WizardForm.RunList.Top - ScaleY(12);
  end;
end;

function MeasurementPath(): String;
begin
  Result := ExpandConstant('{localappdata}\Bloomstep\measurement\installer-receipt.json');
end;

function AddGardenHero(Parent: TWinControl; Left, Top, Width: Integer): TBitmapImage;
var
  Art: TBitmapImage;
begin
  ExtractTemporaryFile('education-hero.bmp');
  Art := TBitmapImage.Create(WizardForm);
  Art.Parent := Parent;
  Art.Left := Left;
  Art.Top := Top;
  Art.Width := Width;
  Art.Height := (Width * 260) div 1000;
  Art.Stretch := True;
  Art.Bitmap.LoadFromFile(ExpandConstant('{tmp}\education-hero.bmp'));
  Result := Art;
end;

procedure InitializeWizard();
var
  StationFlags: TWindowStationFlags;
  Needed: LongWord;
  Art: TBitmapImage;
begin
  if not GetUserObjectInformation(GetProcessWindowStation(), 1, StationFlags, 12, Needed) then
    RaiseException('Windows desktop state could not be verified. Cancel setup and open it normally from your Windows account.');
  InteractiveDesktop := (StationFlags.Flags and 1) <> 0;
  InitializeInstallMotion();
  WizardForm.WizardBitmapImage2.Visible := False;
  WizardForm.FinishedHeadingLabel.Left := ScaleX(24);
  WizardForm.FinishedHeadingLabel.Width := WizardForm.FinishedPage.Width - ScaleX(48);
  Art := AddGardenHero(WizardForm.FinishedPage, ScaleX(24), ScaleY(60), WizardForm.FinishedHeadingLabel.Width);
  WizardForm.FinishedLabel.Left := ScaleX(24);
  WizardForm.FinishedLabel.Top := Art.Top + Art.Height + ScaleY(12);
  WizardForm.FinishedLabel.Width := WizardForm.FinishedHeadingLabel.Width;
  WizardForm.FinishedLabel.AdjustHeight();
  WizardForm.RunList.Left := ScaleX(24);
  WizardForm.RunList.Width := WizardForm.FinishedHeadingLabel.Width;
  WizardForm.RunList.Top := WizardForm.FinishedLabel.Top + WizardForm.FinishedLabel.Height + ScaleY(12);
  WizardForm.RunList.Height := WizardForm.FinishedPage.Height - WizardForm.RunList.Top - ScaleY(12);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then InstallationSucceeded := True;
  if CurStep <> ssInstall then StopInstallMotion();
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Command: String;
  Owner, Receipt: AnsiString;
  Filename: String;
begin
  if CurUninstallStep = usUninstall then begin
    if LoadStringFromFile(ExpandConstant('{app}\measurement-owner.txt'), Owner) and (Length(Owner) = 36) then begin
      Filename := MeasurementPath();
      if LoadStringFromFile(Filename, Receipt) and
         (Pos('"events":[{"id":"' + Owner + '","name":"installer_started"', Receipt) > 0) then
        if not DeleteFile(Filename) then
          MsgBox('Optional owned installer measurement receipt could not be removed. Clear the local receipt manually; no data was sent by the uninstaller.', mbError, MB_OK);
      Filename := MeasurementPath() + '.pending';
      if LoadStringFromFile(Filename, Receipt) and
         (Pos('"events":[{"id":"' + Owner + '","name":"installer_started"', Receipt) > 0) then
        if not DeleteFile(Filename) then
          MsgBox('Optional owned pending measurement receipt could not be removed. Clear the local pending receipt manually.', mbError, MB_OK);
    end;
    if RegQueryStringValue(HKCU, 'Software\Classes\bloomstep\shell\open\command', '', Command) then
      if CompareText(Command, ExpandConstant('"{app}\bloomstep.exe" "%1"')) = 0 then
        RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\bloomstep');
  end;
end;

#ifdef OnboardingPreprocessOutput
#expr SaveToFile(OnboardingPreprocessOutput)
#endif
