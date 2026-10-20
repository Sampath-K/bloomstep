// Read Inno's own prior identity before setup replaces its uninstall registration.
var
  PreviousAppPath, PreviousExecutable, PreviousOriginalExecutable,
    PreviousUninstaller, PreviousGroup: String;
  UpgradeMigrationFailed: Boolean;

function UpgradeFileAttributes(const Filename: String): LongWord;
  external 'GetFileAttributesW@kernel32.dll stdcall';

function UpgradePlainPath(const Value: String): String;
begin
  Result := RemoveBackslashUnlessRoot(Trim(Value));
  if (Length(Result) < 4) or (Copy(Result, 2, 2) <> ':\') or
     (Pos(':', Copy(Result, 3, Length(Result))) > 0) or
     (CompareText(Result, ExpandFileName(Result)) <> 0) then
    Result := '';
end;

function UpgradeOrdinaryPath(const Filename: String): Boolean;
var
  Attributes: LongWord;
begin
  Attributes := UpgradeFileAttributes(Filename);
  Result := (Attributes <> $FFFFFFFF) and ((Attributes and $400) = 0);
end;

function UpgradeUninstallerName(const Filename: String): Boolean;
var
  Name: String;
  I: Integer;
begin
  Name := Lowercase(ExtractFileName(Filename));
  Result := (Length(Name) = 12) and (Copy(Name, 1, 5) = 'unins') and
    (Copy(Name, 9, 4) = '.exe');
  if Result then
    for I := 6 to 8 do
      if (Name[I] < '0') or (Name[I] > '9') then
        Result := False;
end;

procedure CapturePreviousInstallation();
var
  Key, AppPath, Location, Icon, Uninstaller, GroupName, Programs: String;
begin
  PreviousAppPath := '';
  PreviousExecutable := '';
  PreviousOriginalExecutable := '';
  PreviousUninstaller := '';
  PreviousGroup := '';
  UpgradeMigrationFailed := False;
  Key := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' +
    ExpandConstant('{#SetupSetting("AppId")}_is1');
  if not RegQueryStringValue(HKCU, Key, 'Inno Setup: App Path', AppPath) then
    Exit;
  if not RegQueryStringValue(HKCU, Key, 'InstallLocation', Location) then
    Exit;
  AppPath := UpgradePlainPath(AppPath);
  Programs := ExpandConstant('{localappdata}\Programs');
  // Only a prior default per-user product folder is eligible for file removal.
  // Custom locations and redirected/reparse paths are left for manual review.
  if (AppPath = '') or
     (CompareText(AppPath, UpgradePlainPath(Location)) <> 0) or
     (CompareText(ExtractFileDir(AppPath), Programs) <> 0) or
     not UpgradeOrdinaryPath(Programs) or not UpgradeOrdinaryPath(AppPath) then begin
    Log('Prior installation is outside the bounded migration scope; no prior files will be deleted.');
    Exit;
  end;
  if not RegQueryStringValue(HKCU, Key, 'DisplayIcon', Icon) or
     not RegQueryStringValue(HKCU, Key, 'UninstallString', Uninstaller) then
    Exit;
  if Copy(Icon, Length(Icon) - 1, 2) = ',0' then
    Delete(Icon, Length(Icon) - 1, 2);
  Icon := UpgradePlainPath(RemoveQuotes(Icon));
  Uninstaller := UpgradePlainPath(RemoveQuotes(Uninstaller));
  if (Icon = '') or (Uninstaller = '') or
     ((CompareText(Icon, AppPath + '\' + ExtractFileName(AppPath) + '.exe') <> 0) and
      (CompareText(Icon, AppPath + '\budlark.exe') <> 0)) or
     (CompareText(ExtractFileDir(Uninstaller), AppPath) <> 0) or
     not UpgradeUninstallerName(Uninstaller) or
     not UpgradeOrdinaryPath(Icon) or not UpgradeOrdinaryPath(Uninstaller) then begin
    Log('Prior installation metadata did not establish a bounded executable identity; no prior files will be deleted.');
    Exit;
  end;
  PreviousAppPath := AppPath;
  PreviousExecutable := Icon;
  PreviousOriginalExecutable := AppPath + '\' + ExtractFileName(AppPath) + '.exe';
  PreviousUninstaller := Uninstaller;
  if RegQueryStringValue(HKCU, Key, 'Inno Setup: Icon Group', GroupName) then begin
    Programs := ExpandConstant('{userprograms}');
    if ExtractFileName(GroupName) = GroupName then
      GroupName := Programs + '\' + GroupName;
    GroupName := UpgradePlainPath(GroupName);
    if (GroupName <> '') and (CompareText(ExtractFileDir(GroupName), Programs) = 0) and
       UpgradeOrdinaryPath(Programs) and UpgradeOrdinaryPath(GroupName) then
      PreviousGroup := GroupName;
  end;
end;

procedure RegisterExtraCloseApplicationsResources();
begin
  if PreviousExecutable <> '' then begin
#if Ver >= EncodeVer(7, 0, 0)
    RegisterExtraCloseApplicationsResource(PreviousExecutable);
    if CompareText(PreviousOriginalExecutable, PreviousExecutable) <> 0 then
      RegisterExtraCloseApplicationsResource(PreviousOriginalExecutable);
#else
    RegisterExtraCloseApplicationsResource(False, PreviousExecutable);
    if CompareText(PreviousOriginalExecutable, PreviousExecutable) <> 0 then
      RegisterExtraCloseApplicationsResource(False, PreviousOriginalExecutable);
#endif
  end;
end;

procedure RemovePreviousShortcuts(const Directory: String);
var
  Found: TFindRec;
  Shell, Shortcut: Variant;
  Filename, Target: String;
begin
  if not UpgradeOrdinaryPath(Directory) then
    Exit;
  Shell := CreateOleObject('WScript.Shell');
  if FindFirst(Directory + '\*.lnk', Found) then begin
    try
      repeat
        Filename := Directory + '\' + Found.Name;
        if ((Found.Attributes and FILE_ATTRIBUTE_DIRECTORY) = 0) and
           UpgradeOrdinaryPath(Filename) then begin
          Target := '';
          try
            Shortcut := Shell.CreateShortcut(Filename);
            Target := Shortcut.TargetPath;
          except
            Log('An unreadable shortcut was retained during upgrade.');
          end;
          if (CompareText(Target, ExpandConstant('{app}\budlark.exe')) <> 0) and
             (CompareText(Target, ExpandConstant('{uninstallexe}')) <> 0) and
             ((CompareText(Target, PreviousExecutable) = 0) or
              (CompareText(Target, PreviousOriginalExecutable) = 0) or
              (CompareText(Target, PreviousUninstaller) = 0)) then
            if not DeleteFile(Filename) then
              RaiseException('The prior product shortcut could not be removed. Review the setup log; prior data was preserved.');
        end;
      until not FindNext(Found);
    finally
      FindClose(Found);
    end;
  end;
end;

procedure RetirePreviousExecutable(const Filename: String);
begin
  if CompareText(Filename, ExpandConstant('{app}\budlark.exe')) <> 0 then
    if FileExists(Filename) then
      if not UpgradeOrdinaryPath(ExpandConstant('{localappdata}\Programs')) or
         not UpgradeOrdinaryPath(PreviousAppPath) or
         not UpgradeOrdinaryPath(Filename) or
         not DeleteFile(Filename) then
        RaiseException('The prior product executable could not be retired. Review the setup log; prior data was preserved.');
end;

function UpgradeGroupHasOtherEntries(): Boolean;
var
  Found: TFindRec;
begin
  Result := False;
  if FindFirst(PreviousGroup + '\*', Found) then begin
    try
      repeat
        if (Found.Name <> '.') and (Found.Name <> '..') then
          Result := True;
      until Result or not FindNext(Found);
    finally
      FindClose(Found);
    end;
  end;
end;

procedure CompleteUpgradeMigration();
begin
  if PreviousExecutable = '' then
    Exit;
  UpgradeMigrationFailed := True;
  // Never run the old uninstaller or recursively remove its folder: either can
  // remove user-created files or owner-matched local observation receipts.
  RetirePreviousExecutable(PreviousExecutable);
  RetirePreviousExecutable(PreviousOriginalExecutable);
  if PreviousGroup <> '' then begin
    RemovePreviousShortcuts(PreviousGroup);
    if CompareText(PreviousGroup, ExpandConstant('{group}')) <> 0 then
      if not RemoveDir(PreviousGroup) and DirExists(PreviousGroup) then
        if not UpgradeGroupHasOtherEntries() then
          RaiseException('The empty prior product group could not be removed. Review the setup log; prior data was preserved.');
  end;
  RemovePreviousShortcuts(ExpandConstant('{userdesktop}'));
  Log('Prior executable and identity-matched shortcuts retired; prior data and unknown files preserved.');
  UpgradeMigrationFailed := False;
end;

function GetCustomSetupExitCode(): Integer;
begin
  Result := 0;
  if UpgradeMigrationFailed then
    Result := 10;
end;
