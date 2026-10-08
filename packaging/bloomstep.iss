#ifndef AppArch
  #define AppArch "arm64"
#endif
#ifdef UniversalIntegrityFixture
  #ifndef OnboardingJourneyFixture
    #error Integrity fault injection requires the isolated journey identity, never a public package.
  #endif
#endif
#ifndef InstallFlow
  #define InstallFlow "oneclick"
#endif
#if InstallFlow != "oneclick" && InstallFlow != "zeroclick"
  #error InstallFlow must be oneclick or zeroclick.
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
#if InstallFlow == "zeroclick"
OutputBaseFilename=Bloomstep-{#AppVersion}-windows-{#AppArch}-zeroclick-setup
#else
OutputBaseFilename=Bloomstep-{#AppVersion}-windows-{#AppArch}-setup
#endif
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
#if InstallFlow == "zeroclick"
DisableWelcomePage=yes
DisableDirPage=yes
#else
DisableWelcomePage=no
DisableDirPage=no
#endif
DisableReadyPage=yes
DisableFinishedPage=yes
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
SelectDirBrowseLabel=Select Install to begin. To choose a different folder, select Browse.

[Files]
#if AppArch == "universal"
Source: "{#SourceDirX64}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Check: UseX64Payload
Source: "{#SourceDirArm64}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Check: UseArm64Payload
#else
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
#endif
Source: "assets\welcome-steps.bmp"; Flags: dontcopy
Source: "assets\welcome-garden.bmp"; Flags: dontcopy
#ifdef UniversalIntegrityFixture
Source: "{#IntegrityMarker}"; DestDir: "{app}"; DestName: "integrity-probe.txt"; Flags: ignoreversion nocompression
#endif

[InstallDelete]
Type: files; Name: "{app}\measurement-owner.txt"

[Icons]
Name: "{group}\Bloomstep"; Filename: "{app}\bloomstep.exe"
Name: "{group}\Uninstall Bloomstep"; Filename: "{uninstallexe}"

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

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpSelectDir then
  begin
    WizardForm.NextButton.Visible := True;
    WizardForm.NextButton.Caption := SetupMessage(msgButtonInstall);
  end;
  ShowVisualForPage(CurPageID);
end;

function MeasurementPath(): String;
begin
  Result := ExpandConstant('{localappdata}\Bloomstep\measurement\installer-receipt.json');
end;

procedure InitializeWizard();
var
  StationFlags: TWindowStationFlags;
  Needed: LongWord;
begin
  if not GetUserObjectInformation(GetProcessWindowStation(), 1, StationFlags, 12, Needed) then
    RaiseException('Windows desktop state could not be verified. Cancel setup and open it normally from your Windows account.');
  InteractiveDesktop := (StationFlags.Flags and 1) <> 0;
  InitializeInstallMotion();
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    InstallationSucceeded := True;
#if InstallFlow == "zeroclick"
    HoldZeroClickVisual();
#endif
  end;
  if CurStep <> ssInstall then StopInstallMotion();
  if CurStep = ssDone then
  begin
    if CanLaunchBloomstep() then
    begin
      LaunchAttempted := True;
      if ExecAsOriginalUser(ExpandConstant('{app}\bloomstep.exe'), '', '', SW_SHOWNORMAL, ewNoWait, ResultCode) then
        Log('Bloomstep automatic launch started as the original non-elevated user.')
      else
        Log('Bloomstep automatic launch failed: ' + SysErrorMessage(ResultCode) + '. Open Bloomstep from the Start menu.');
    end
    else
    begin
      Log('Bloomstep automatic launch withheld (silent, elevated, non-interactive or suppressed).');
      if InstallationSucceeded and IsAdmin and not WizardSilent then
        SuppressibleMsgBox('Bloomstep is installed. Open Bloomstep from the Start menu as your normal Windows account.', mbInformation, MB_OK, IDOK);
    end;
  end;
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
