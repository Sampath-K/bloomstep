#ifndef AppArch
  #define AppArch "arm64"
#endif
#ifndef AppVersion
  #define AppVersion "0.1.0-preview"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\" + AppArch + "\runner\Release"
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
DisableWelcomePage=no
DisableDirPage=no
DisableProgramGroupPage=yes
WizardImageFile=assets\wizard-garden.bmp
WizardSmallImageFile=assets\wizard-seed.bmp
UninstallDisplayIcon={app}\bloomstep.exe
CloseApplications=yes
RestartApplications=no
#if AppArch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif

[Messages]
WelcomeLabel1=Welcome to Bloomstep
WelcomeLabel2=Anchor a routine.%nMake a tiny habit part of your day.%n%nAnchor: after pouring my morning drink%nTiny action: take one slow breath%nCelebration: relax my shoulders and smile%n%nAnchor: after opening my laptop%nTiny action: write my one next step%nCelebration: say "I have a starting point"%n%nFree Windows download. Limited preview. Sign-in required.%nNext: plant a tiny recipe.
ReadyLabel1=Ready to install this unsigned Bloomstep preview.
FinishedHeadingLabel=Bloomstep is installed
FinishedLabel=Bloomstep is ready for sign-in. Try one safe, tiny action after a familiar routine, then celebrate in your own way. Your plant keeps its growth even on a "not today" day.%n%nThis is a limited unsigned preview, not the complete verified MVP or medical advice. Opening the app below is optional.

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "assets\education-seed.bmp"; Flags: dontcopy
Source: "assets\education-growth.bmp"; Flags: dontcopy

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
  TMeasurementGuid = record
    D1: LongWord;
    D2, D3: Word;
    D4: array[0..7] of Byte;
  end;
  TMeasurementTime = record
    Year, Month, DayOfWeek, Day, Hour, Minute, Second, Milliseconds: Word;
  end;
  TWindowStationFlags = record
    Inherit, Reserved, Flags: LongWord;
  end;

function CoCreateGuid(var Guid: TMeasurementGuid): Integer;
  external 'CoCreateGuid@ole32.dll stdcall';
procedure GetSystemTime(var Time: TMeasurementTime);
  external 'GetSystemTime@kernel32.dll stdcall';
function GetProcessWindowStation(): THandle;
  external 'GetProcessWindowStation@user32.dll stdcall';
function GetUserObjectInformation(Handle: THandle; Index: Integer;
  var Flags: TWindowStationFlags; Size: LongWord; var Needed: LongWord): Boolean;
  external 'GetUserObjectInformationW@user32.dll stdcall';

var
  RecipePage, GrowPage: TWizardPage;
  MeasurementPage: TWizardPage;
  MeasurementCheckBox: TNewCheckBox;
  MeasurementStarted: Boolean;
  MeasurementConsentAt, MeasurementStartEvent, MeasurementOwnerId: String;
  InstallationSucceeded, LaunchAttempted, InteractiveDesktop: Boolean;

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
  if (CurPageID = wpFinished) and IsAdmin then
    WizardForm.FinishedLabel.Caption := WizardForm.FinishedLabel.Caption +
      #13#10#13#10 + 'Automatic launch is unavailable from an elevated installer. Close Setup and open Bloomstep normally from your Windows account.';
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := WizardSilent and ((PageID = RecipePage.ID) or (PageID = GrowPage.ID));
end;

function MeasurementPath(): String;
begin
  Result := ExpandConstant('{localappdata}\Bloomstep\measurement\installer-receipt.json');
end;

function MeasurementUtc(): String;
var
  Time: TMeasurementTime;
begin
  GetSystemTime(Time);
  Result := Format('%.4d-%.2d-%.2dT%.2d:%.2d:%.2d.%.3dZ', [Time.Year,
    Time.Month, Time.Day, Time.Hour, Time.Minute, Time.Second, Time.Milliseconds]);
end;

function MeasurementId(): String;
var
  Guid: TMeasurementGuid;
begin
  if CoCreateGuid(Guid) <> 0 then
    RaiseException('Optional measurement ID could not be created.');
  Result := Lowercase(Format('%.8x-%.4x-%.4x-%.2x%.2x-%.2x%.2x%.2x%.2x%.2x%.2x', [Guid.D1,
     Guid.D2, Guid.D3, Guid.D4[0], Guid.D4[1],
     Guid.D4[2], Guid.D4[3], Guid.D4[4], Guid.D4[5], Guid.D4[6], Guid.D4[7]]));
end;

function MeasurementEvent(Name, At, Id: String): String;
begin
  Result := '{"id":"' + Id + '","name":"' + Name + '","ts":"' + At + '"}';
end;

procedure WriteMeasurement(Events: String);
var
  Filename, Body: String;
begin
  Filename := MeasurementPath();
  Body := '{"schemaVersion":1,"source":"installer","consentedAt":"' +
    MeasurementConsentAt + '","events":[' + Events + ']}';
  if not ForceDirectories(ExtractFileDir(Filename)) then
    RaiseException('Optional measurement directory could not be created.');
  if not SaveStringToFile(Filename + '.pending', Body, False) then
    RaiseException('Optional measurement receipt could not be saved.');
  if FileExists(Filename) and not DeleteFile(Filename) then
    RaiseException('Previous optional measurement receipt could not be replaced.');
  if not RenameFile(Filename + '.pending', Filename) then
    RaiseException('Optional measurement receipt could not be finalized.');
end;

procedure MeasurementFailure();
begin
  MeasurementStarted := False;
  MsgBox('Optional local measurement failed. Installation is independent and will continue. No data was sent. Clear the local installer receipt in Bloomstep before linking it if an incomplete receipt remains.', mbError, MB_OK);
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo,
  MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
var
  ReadyMemoNote: String;
begin
  ReadyMemoNote := 'A familiar routine, one tiny action, a personal celebration.' + NewLine +
    'For example: after setting down my mug, I do one gentle shoulder roll and smile.' + NewLine +
    'In Bloomstep, pair the routine and action in a recipe; check in without streak pressure.' + NewLine + NewLine +
    'Bloomstep is an independent app inspired by the Tiny Habits method; not affiliated with or endorsed by BJ Fogg or Tiny Habits.' + NewLine +
    'Optional learning (not required): https://tinyhabits.com and https://tinyhabits.com/book/' + NewLine + NewLine +
    'Limited unsigned preview. Sign-in required; features and sign-in options are still being refined. Not the complete verified MVP or medical advice. No Microsoft Store version yet.' + NewLine + NewLine;
  Result := MemoUserInfoInfo;
  if MemoDirInfo <> '' then Result := Result + MemoDirInfo;
  if MemoTypeInfo <> '' then Result := Result + NewLine + NewLine + MemoTypeInfo;
  if MemoComponentsInfo <> '' then Result := Result + NewLine + NewLine + MemoComponentsInfo;
  if MemoGroupInfo <> '' then Result := Result + NewLine + NewLine + MemoGroupInfo;
  if MemoTasksInfo <> '' then Result := Result + NewLine + NewLine + MemoTasksInfo;
  Result := Result + NewLine + NewLine + ReadyMemoNote;
end;

procedure AddEducation(Page: TWizardPage; ImageName, Body, Card: String);
var
  Art: TBitmapImage;
  Text, Example: TNewStaticText;
begin
  ExtractTemporaryFile(ImageName);
  Art := TBitmapImage.Create(Page);
  Art.Parent := Page.Surface;
  Art.Width := ScaleX(112);
  Art.Height := ScaleY(112);
  Art.Stretch := True;
  Art.Bitmap.LoadFromFile(ExpandConstant('{tmp}\' + ImageName));
  Text := TNewStaticText.Create(Page);
  Text.Parent := Page.Surface;
  Text.Left := Art.Width + ScaleX(16);
  Text.Width := Page.SurfaceWidth - Text.Left;
  Text.AutoSize := False;
  Text.WordWrap := True;
  Text.Caption := Body;
  Text.AdjustHeight();
  Example := TNewStaticText.Create(Page);
  Example.Parent := Page.Surface;
  Example.Top := Art.Height + ScaleY(12);
  Example.Width := Page.SurfaceWidth;
  Example.AutoSize := False;
  Example.WordWrap := True;
  Example.Caption := Card;
  Example.AdjustHeight();
  if (Text.Height > Art.Height) or (Example.Top + Example.Height > Page.SurfaceHeight) then
    RaiseException('Education text does not fit the scaled wizard. Cancel and report the display scale; no installation has started.');
end;

procedure InitializeWizard();
var
  Disclosure: TNewStaticText;
  StationFlags: TWindowStationFlags;
  Needed: LongWord;
begin
  if not GetUserObjectInformation(GetProcessWindowStation(), 1, StationFlags, 12, Needed) then
    RaiseException('Windows desktop state could not be verified. Cancel setup and open it normally from your Windows account.');
  InteractiveDesktop := (StationFlags.Flags and 1) <> 0;
  WizardForm.ReadyMemo.WordWrap := True;
  WizardForm.ReadyMemo.ScrollBars := ssVertical;
  RecipePage := CreateCustomPage(wpWelcome, 'Plant a tiny recipe',
    'Choose one small action. Make it smaller if it feels difficult.');
  AddEducation(RecipePage, 'education-seed.bmp',
    'Pair an existing routine with a tiny action.' + #13#10 +
    'Celebrate in your own way.',
    'Anchor: after pouring my morning drink' + #13#10 +
    'Tiny action: take one slow breath' + #13#10 +
    'Celebration: relax my shoulders and smile' + #13#10#13#10 +
    'Anchor: after opening my laptop' + #13#10 +
    'Tiny action: write my one next step' + #13#10 +
    'Celebration: say "I have a starting point"' + #13#10#13#10 +
    'These are examples. You choose and edit your own recipe in Bloomstep.');
  GrowPage := CreateCustomPage(RecipePage.ID, 'Celebrate and grow',
    'Small habits form a garden. Rest is part of the rhythm.');
  AddEducation(GrowPage, 'education-growth.bmp',
    'Celebrate your moment.' + #13#10 +
    'Not today preserves your plant''s growth.',
    'Your plant can grow: seed, sprout, sapling, budding, bloom.' + #13#10#13#10 +
    'Check in with Did it or Did more. Choose Not today when you need rest.' + #13#10#13#10 +
    'Each recipe has its own plant. Together, your habits make a garden.' + #13#10#13#10 +
    'Next: choose where to install. Optional observations stay off unless you choose them.');
  MeasurementPage := CreateCustomPage(wpSelectDir,
    'Optional local installation observations',
    'Off by default. Nothing is sent by this installer.');
  Disclosure := TNewStaticText.Create(MeasurementPage);
  Disclosure.Parent := MeasurementPage.Surface;
  Disclosure.AutoSize := False;
  Disclosure.WordWrap := True;
  Disclosure.Width := MeasurementPage.SurfaceWidth;
  Disclosure.Caption := 'If selected, this device saves fixed event names, random IDs and UTC times for the installation phase, completion and first app launch/sign-in view. No email, habit text, paths, URLs or invitation codes. The receipt expires after seven days and is removed on next access. Linking to a signed-in account requires separate in-app product-event consent and explicit confirmation. Selecting this replaces a prior installer receipt; silent installers never collect observations.';
  Disclosure.AdjustHeight();
  MeasurementCheckBox := TNewCheckBox.Create(MeasurementPage);
  MeasurementCheckBox.Parent := MeasurementPage.Surface;
  MeasurementCheckBox.Top := Disclosure.Top + Disclosure.Height + ScaleY(12);
  MeasurementCheckBox.Width := MeasurementPage.SurfaceWidth;
  MeasurementCheckBox.Height := ScaleY(32);
  MeasurementCheckBox.Caption := 'Save optional local observations (unchecked by default)';
  MeasurementCheckBox.Checked := False;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Completed: String;
begin
  if CurStep = ssPostInstall then InstallationSucceeded := True;
  if WizardSilent then Exit;
  if not MeasurementCheckBox.Checked then Exit;
  if CurStep = ssInstall then begin
    try
      MeasurementConsentAt := MeasurementUtc();
      MeasurementOwnerId := MeasurementId();
      MeasurementStartEvent := MeasurementEvent('installer_started', MeasurementConsentAt, MeasurementOwnerId);
      WriteMeasurement(MeasurementStartEvent);
      MeasurementStarted := True;
    except
      MeasurementFailure();
    end;
  end;
  if (CurStep = ssPostInstall) and MeasurementStarted then begin
    try
      Completed := MeasurementEvent('install_completed', MeasurementUtc(), MeasurementId());
      WriteMeasurement(MeasurementStartEvent + ',' + Completed);
      if not SaveStringToFile(ExpandConstant('{app}\measurement-owner.txt'), MeasurementOwnerId, False) then
        RaiseException('Optional measurement ownership marker could not be saved.');
    except
      MeasurementFailure();
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
