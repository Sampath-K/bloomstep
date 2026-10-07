// Native callbacks and controls documented by Inno; no Delphi TTimer dependency.
function SetTimer(Window: HWND; Id: UINT_PTR; Interval: UINT; Callback: LongWord): UINT_PTR;
  external 'SetTimer@user32.dll stdcall';
function KillTimer(Window: HWND; Id: UINT_PTR): Boolean;
  external 'KillTimer@user32.dll stdcall';
function SystemParametersInfo(Action, Parameter: UINT; var Value: Integer; Flags: UINT): Boolean;
  external 'SystemParametersInfoW@user32.dll stdcall';
function GetTickCount64(): Int64;
  external 'GetTickCount64@kernel32.dll stdcall';

var
  ProgressTimer: UINT_PTR;
  ProgressStartedAt: Int64;
  ProgressActive, MotionAllowed: Boolean;
  ProgressArt: TBitmapImage;
  ProgressCaption: TNewStaticText;
  ProgressBaseLeft, ProgressScene: Integer;
  ProgressImages: array[0..2] of TBitmap;

procedure StopInstallMotion();
begin
  ProgressActive := False;
  if ProgressTimer <> 0 then
  begin
    if not KillTimer(0, ProgressTimer) then
      Log('Bloomstep progress timer disposal failed; callback is inactive and Setup will dispose its thread.');
    ProgressTimer := 0;
    Log('Bloomstep install presentation stopped.');
  end;
end;

procedure ShowProgressScene(Scene: Integer);
var
  Identity, Phase: String;
  Elapsed: Int64;
begin
  if ProgressScene = Scene then Exit;
  ProgressScene := Scene;
  ProgressArt.Bitmap.Assign(ProgressImages[Scene]);
  case Scene of
    0: begin
      Identity := 'seed-to-flower';
      ProgressCaption.Caption := 'A little is enough. Grow from there.';
    end;
    1: begin
      Identity := 'routine-action-celebration';
      ProgressCaption.Caption := 'After a familiar routine, try one tiny action. Celebrate your start.';
    end;
    2: begin
      Identity := 'growing-garden';
      ProgressCaption.Caption := 'Your practice grows a garden. Not today leaves your growth intact.';
    end;
  end;
  ProgressCaption.AdjustHeight();
  ProgressArt.Repaint();
  Log('Bloomstep install scene ' + IntToStr(Scene) + '.');
  Phase := 'initialization';
  Elapsed := 0;
  if WizardForm.CurPageID = wpInstalling then
  begin
    Phase := 'installing';
    Elapsed := GetTickCount64() - ProgressStartedAt;
  end;
  Log('Bloomstep scene identity=' + Identity + '; phase=' + Phase +
    '; elapsedMilliseconds=' + IntToStr(Elapsed) + '.');
end;

procedure ProgressTimerTick(Window: HWND; Message: UINT; Id: UINT_PTR; Tick: DWORD);
var
  Elapsed: Int64;
  Scene, Drift: Integer;
  Animations: Integer;
begin
  if not ProgressActive or (Id <> ProgressTimer) then Exit;
  if (WizardForm.CurPageID <> wpInstalling) or not WizardForm.Enabled then
  begin
    StopInstallMotion();
    Exit;
  end;
  // Also honor a preference changed while installation is running.
  if not SystemParametersInfo($1042, 0, Animations, 0) or (Animations = 0) then
  begin
    Log('Bloomstep progress motion disabled: Windows animation preference is off or unavailable.');
    StopInstallMotion();
    ProgressArt.Left := ProgressBaseLeft;
    ShowProgressScene(0);
    Exit;
  end;
  Elapsed := GetTickCount64() - ProgressStartedAt;
  Scene := Elapsed div 600;
  if Scene > 2 then Scene := 2;
  ShowProgressScene(Scene);
  Drift := (Elapsed div 150) mod 8;
  if Drift > 4 then Drift := 8 - Drift;
  ProgressArt.Left := ProgressBaseLeft + ScaleX(Drift);
  ProgressArt.Repaint();
end;

procedure StartInstallMotion();
var
  Animations: Integer;
begin
  StopInstallMotion();
  if WizardSilent then Exit;
  ProgressStartedAt := GetTickCount64();
  ProgressArt.Left := ProgressBaseLeft;
  ProgressScene := -1;
  ShowProgressScene(0);
  MotionAllowed := False;
  if SystemParametersInfo($1042, 0, Animations, 0) then
    MotionAllowed := Animations <> 0
  else
    Log('Bloomstep animation preference query failed; static art retained.');
  if not MotionAllowed then
  begin
    Log('Bloomstep static install presentation: Windows animations disabled or unavailable.');
    Exit;
  end;
  ProgressTimer := SetTimer(0, 0, 150, CreateCallback(@ProgressTimerTick));
  if ProgressTimer = 0 then
  begin
    Log('Bloomstep progress timer could not be created; static art retained.');
    Exit;
  end;
  ProgressActive := True;
  Log('Bloomstep real-install motion started.');
end;

procedure InitializeInstallMotion();
var
  Names: array[0..2] of String;
  I, AvailableHeight: Integer;
begin
  if WizardSilent then Exit;
  Names[0] := 'education-seed.bmp';
  Names[1] := 'education-recipe.bmp';
  Names[2] := 'education-growth.bmp';
  for I := 0 to 2 do
  begin
    ExtractTemporaryFile(Names[I]);
    ProgressImages[I] := TBitmap.Create();
    ProgressImages[I].LoadFromFile(ExpandConstant('{tmp}\' + Names[I]));
  end;
  ProgressArt := TBitmapImage.Create(WizardForm);
  ProgressArt.Parent := WizardForm.InstallingPage;
  ProgressArt.Top := WizardForm.ProgressGauge.Top + WizardForm.ProgressGauge.Height + ScaleY(12);
  AvailableHeight := WizardForm.InstallingPage.Height - ProgressArt.Top - ScaleY(48);
  ProgressArt.Width := WizardForm.InstallingPage.Width - ScaleX(16);
  ProgressArt.Height := (ProgressArt.Width * 420) div 1000;
  if ProgressArt.Height > AvailableHeight then
  begin
    ProgressArt.Height := AvailableHeight;
    ProgressArt.Width := (AvailableHeight * 1000) div 420;
  end;
  if AvailableHeight < ScaleY(40) then
    RaiseException('Bloomstep illustration does not fit this display scale. Cancel Setup and use a larger display area; installation has not started.');
  ProgressBaseLeft := (WizardForm.InstallingPage.Width - ProgressArt.Width) div 2 - ScaleX(2);
  ProgressArt.Left := ProgressBaseLeft;
  ProgressArt.Stretch := True;
  ProgressCaption := TNewStaticText.Create(WizardForm);
  ProgressCaption.Parent := WizardForm.InstallingPage;
  ProgressCaption.Top := ProgressArt.Top + ProgressArt.Height + ScaleY(8);
  ProgressCaption.Width := WizardForm.InstallingPage.Width;
  ProgressCaption.AutoSize := False;
  ProgressCaption.WordWrap := True;
  ProgressScene := -1;
  ShowProgressScene(0);
end;

procedure DeinitializeSetup();
var
  I: Integer;
begin
  StopInstallMotion();
  for I := 0 to 2 do
    if ProgressImages[I] <> nil then ProgressImages[I].Free();
end;
