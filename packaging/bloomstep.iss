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
DisableWelcomePage=no
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
WelcomeLabel1=Welcome to Bloomstep
WelcomeLabel2=Your garden starts with one seed.%nFree Windows download. Limited preview. Sign-in required.%nNext: plant a tiny recipe.
ReadyLabel1=Ready to install this unsigned Bloomstep preview.
FinishedHeadingLabel=Bloomstep is installed
FinishedLabel=Next: sign in and choose your first tiny recipe.%nLimited unsigned preview. Opening the app below is optional.

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
  ReadySummary: String;
  PreviewDetailsShown: Boolean;
  PreviewDetailsButton: TNewButton;

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
  begin
    WizardForm.FinishedLabel.Caption := WizardForm.FinishedLabel.Caption + #13#10#13#10 +
      'Automatic launch is unavailable from an elevated installer. Close Setup and open Bloomstep normally from your Windows account.';
    WizardForm.FinishedLabel.AdjustHeight();
    WizardForm.RunList.Top := WizardForm.FinishedLabel.Top + WizardForm.FinishedLabel.Height + ScaleY(12);
    WizardForm.RunList.Height := WizardForm.FinishedPage.Height - WizardForm.RunList.Top - ScaleY(12);
  end;
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

function PreviewDetails(): String;
begin
  Result := 'Bloomstep is an independent app inspired by the Tiny Habits method; not affiliated with or endorsed by BJ Fogg or Tiny Habits.' + #13#10 +
    'Optional learning (not required): https://tinyhabits.com and https://tinyhabits.com/book/' + #13#10#13#10 +
    'Limited unsigned preview. Sign-in required; features and sign-in options are still being refined. Not the complete verified MVP or medical advice. No Microsoft Store version yet.';
end;

procedure TogglePreviewDetails(Sender: TObject);
begin
  PreviewDetailsShown := not PreviewDetailsShown;
  if PreviewDetailsShown then
  begin
    WizardForm.ReadyMemo.Lines.Text := ReadySummary + #13#10#13#10 + PreviewDetails();
    PreviewDetailsButton.Caption := 'Hide preview details';
  end
  else
  begin
    WizardForm.ReadyMemo.Lines.Text := ReadySummary;
    PreviewDetailsButton.Caption := 'Preview details';
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo,
  MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
var
  ReadyMemoNote: String;
begin
  ReadyMemoNote := 'Next: sign in and choose a familiar routine, one tiny action and a personal celebration.' + NewLine +
    'Limited unsigned preview. Sign-in required.';
  Result := MemoUserInfoInfo;
  if MemoDirInfo <> '' then Result := Result + MemoDirInfo;
  if MemoTypeInfo <> '' then Result := Result + NewLine + NewLine + MemoTypeInfo;
  if MemoComponentsInfo <> '' then Result := Result + NewLine + NewLine + MemoComponentsInfo;
  if MemoGroupInfo <> '' then Result := Result + NewLine + NewLine + MemoGroupInfo;
  if MemoTasksInfo <> '' then Result := Result + NewLine + NewLine + MemoTasksInfo;
  Result := Result + NewLine + NewLine + ReadyMemoNote;
  ReadySummary := Result;
  if PreviewDetailsShown then Result := Result + NewLine + NewLine + PreviewDetails();
end;

function AddNativeText(Parent: TWinControl; Left, Top, Width: Integer; Caption: String): TNewStaticText;
var
  Text: TNewStaticText;
begin
  Text := TNewStaticText.Create(WizardForm);
  Text.Parent := Parent;
  Text.Left := Left;
  Text.Top := Top;
  Text.Width := Width;
  Text.AutoSize := False;
  Text.WordWrap := True;
  Text.Caption := Caption;
  Text.AdjustHeight();
  if Text.Top + Text.Height > Parent.Height then
    RaiseException('Education text does not fit the scaled wizard. Cancel and report the display scale; no installation has started.');
  Result := Text;
end;

function AddVisualBeat(Parent: TWinControl; Width: Integer; ImageName, Progress: String): TBitmapImage;
var
  Art: TBitmapImage;
begin
  AddNativeText(Parent, 0, 0, Width, Progress);
  ExtractTemporaryFile(ImageName);
  Art := TBitmapImage.Create(WizardForm);
  Art.Parent := Parent;
  Art.Top := ScaleY(24);
  Art.Width := Width;
  Art.Height := (Width * 420) div 1000;
  Art.Stretch := True;
  Art.Bitmap.LoadFromFile(ExpandConstant('{tmp}\' + ImageName));
  Result := Art;
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
  Disclosure: TNewStaticText;
  StationFlags: TWindowStationFlags;
  Needed: LongWord;
  Art: TBitmapImage;
  Text: TNewStaticText;
  I, Width: Integer;
  Stages: array[0..4] of String;
begin
  if not GetUserObjectInformation(GetProcessWindowStation(), 1, StationFlags, 12, Needed) then
    RaiseException('Windows desktop state could not be verified. Cancel setup and open it normally from your Windows account.');
  InteractiveDesktop := (StationFlags.Flags and 1) <> 0;
  WizardForm.WizardBitmapImage.Visible := False;
  WizardForm.WelcomeLabel1.Visible := False;
  WizardForm.WelcomeLabel2.Visible := False;
  Width := WizardForm.WelcomePage.Width - ScaleX(48);
  Art := AddVisualBeat(WizardForm.WelcomePage, Width, 'education-seed.bmp',
    'Welcome to Bloomstep - Step 1 of 3');
  Art.Left := ScaleX(24);
  Art.Top := ScaleY(80);
  Text := AddNativeText(WizardForm.WelcomePage, ScaleX(24), ScaleY(30), Width,
    'Your garden starts with one seed');
  Text.Font.Size := 18;
  Text.Font.Style := [fsBold];
  Text.AdjustHeight();
  Stages[0] := 'Seed'; Stages[1] := 'Sprout'; Stages[2] := 'Sapling';
  Stages[3] := 'Budding'; Stages[4] := 'Bloom';
  for I := 0 to 4 do
    AddNativeText(WizardForm.WelcomePage, ScaleX(24) + (Width * I) div 5,
      Art.Top + (Art.Height * 79) div 100, Width div 5, Stages[I]);
  AddNativeText(WizardForm.WelcomePage, ScaleX(24), Art.Top + Art.Height + ScaleY(12), Width,
    'Free Windows download. Limited preview. Sign-in required.' + #13#10 +
    'Next: plant a tiny recipe.');
  WizardForm.ReadyMemo.WordWrap := True;
  WizardForm.ReadyMemo.ScrollBars := ssVertical;
  RecipePage := CreateCustomPage(wpWelcome, 'A tiny recipe',
    'Anchor a routine, choose a tiny action, celebrate in your own way.');
  Art := AddVisualBeat(RecipePage.Surface, RecipePage.SurfaceWidth, 'education-recipe.bmp', 'Step 2 of 3 - Pick a small beginning');
  AddNativeText(RecipePage.Surface, ScaleX(18), Art.Top + (Art.Height * 51) div 100,
    (RecipePage.SurfaceWidth div 2) - ScaleX(36),
    'Anchor: after pouring my morning drink' + #13#10 +
    'Tiny action: take one slow breath' + #13#10 +
    'Celebration: relax my shoulders and smile');
  AddNativeText(RecipePage.Surface, (RecipePage.SurfaceWidth div 2) + ScaleX(18),
    Art.Top + (Art.Height * 51) div 100, (RecipePage.SurfaceWidth div 2) - ScaleX(36),
    'Anchor: after opening my laptop' + #13#10 +
    'Tiny action: write my one next step' + #13#10 +
    'Celebration: say "I have a starting point"');
  AddNativeText(RecipePage.Surface, 0, Art.Top + Art.Height + ScaleY(8), RecipePage.SurfaceWidth,
    'Illustrated examples. You choose your own recipe in Bloomstep.');
  GrowPage := CreateCustomPage(RecipePage.ID, 'Watch it become a garden',
    'Each recipe has its own plant. Your garden reflects your practice.');
  Art := AddVisualBeat(GrowPage.Surface, GrowPage.SurfaceWidth, 'education-growth.bmp', 'Step 3 of 3 - Make room to grow');
  AddNativeText(GrowPage.Surface, 0, Art.Top + Art.Height + ScaleY(8), GrowPage.SurfaceWidth,
    'Illustration of supported plants. Not today preserves your plant''s growth.' + #13#10 +
    'Next: choose where to install. Optional observations stay off.');
  WizardForm.ReadyLabel.Visible := False;
  Art := AddGardenHero(WizardForm.ReadyPage, WizardForm.ReadyMemo.Left, 0, WizardForm.ReadyMemo.Width);
  WizardForm.ReadyMemo.Top := Art.Height + ScaleY(8);
  WizardForm.ReadyMemo.Height := WizardForm.ReadyPage.Height - WizardForm.ReadyMemo.Top - ScaleY(36);
  PreviewDetailsButton := TNewButton.Create(WizardForm);
  PreviewDetailsButton.Parent := WizardForm.ReadyPage;
  PreviewDetailsButton.Left := WizardForm.ReadyMemo.Left;
  PreviewDetailsButton.Top := WizardForm.ReadyPage.Height - ScaleY(28);
  PreviewDetailsButton.Width := ScaleX(156);
  PreviewDetailsButton.Height := ScaleY(24);
  PreviewDetailsButton.Caption := 'Preview details';
  PreviewDetailsButton.OnClick := @TogglePreviewDetails;
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
