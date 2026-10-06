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
AppId={{99BE7E95-0565-4C72-A4DD-46D1D5B6C679}
#endif
AppName=Bloomstep
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
WelcomeLabel2=Bloomstep pairs a familiar routine with one safe, tiny action. Celebrate in your own way.%n%nLimited unsigned Windows preview, not the complete verified MVP or medical advice. Sign-in is required; some features and sign-in options are still being refined.%n%nAn independent app inspired by the Tiny Habits method, not affiliated with or endorsed by BJ Fogg or Tiny Habits.%n%nNext reviews your install folder and optional local observations. Nothing is sent by this installer.
ReadyLabel1=Ready to install this unsigned Bloomstep preview.
FinishedHeadingLabel=Bloomstep is installed
FinishedLabel=Bloomstep is ready for sign-in. Try one safe, tiny action after a familiar routine, then celebrate in your own way. Your plant keeps its growth even on a "not today" day.%n%nThis is a limited unsigned preview, not the complete verified MVP or medical advice. Opening the app below is optional.

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
Type: files; Name: "{app}\measurement-owner.txt"

[Icons]
Name: "{group}\Bloomstep"; Filename: "{app}\bloomstep.exe"
Name: "{group}\Uninstall Bloomstep"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\bloomstep.exe"; Description: "Open Bloomstep (sign-in-gated preview)"; Flags: nowait postinstall skipifsilent unchecked

[UninstallDelete]
Type: files; Name: "{userstartup}\Bloomstep.lnk"
Type: files; Name: "{app}\measurement-owner.txt"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "Bloomstep"; Flags: uninsdeletevalue dontcreatekey
Root: HKCU; Subkey: "Software\Classes\bloomstep"; ValueType: string; ValueData: "URL:Bloomstep invitation"
Root: HKCU; Subkey: "Software\Classes\bloomstep"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\bloomstep\DefaultIcon"; ValueType: string; ValueData: "{app}\bloomstep.exe,0"
Root: HKCU; Subkey: "Software\Classes\bloomstep\shell\open\command"; ValueType: string; ValueData: """{app}\bloomstep.exe"" ""%1"""

[Code]
#ifdef OnboardingFixture
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := 'Compile-only onboarding fixture. Installation is prohibited; cancel this wizard.';
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

function CoCreateGuid(var Guid: TMeasurementGuid): Integer;
  external 'CoCreateGuid@ole32.dll stdcall';
procedure GetSystemTime(var Time: TMeasurementTime);
  external 'GetSystemTime@kernel32.dll stdcall';

var
  MeasurementPage: TWizardPage;
  MeasurementCheckBox: TNewCheckBox;
  MeasurementStarted: Boolean;
  MeasurementConsentAt, MeasurementStartEvent, MeasurementOwnerId: String;

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

procedure InitializeWizard();
var
  Disclosure: TNewStaticText;
begin
  WizardForm.ReadyMemo.WordWrap := True;
  WizardForm.ReadyMemo.ScrollBars := ssVertical;
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
