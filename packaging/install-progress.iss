// One wordless visual (Anchor -> Action -> Celebrate, one plant growing, a garden of habits).
// Native callbacks and controls documented by Inno; no Delphi TTimer dependency.
function SetTimer(Window: HWND; Id: UINT_PTR; Interval: UINT; Callback: LongWord): UINT_PTR;
  external 'SetTimer@user32.dll stdcall';
function KillTimer(Window: HWND; Id: UINT_PTR): Boolean;
  external 'KillTimer@user32.dll stdcall';
function SystemParametersInfo(Action, Parameter: UINT; var Value: Integer; Flags: UINT): Boolean;
  external 'SystemParametersInfoW@user32.dll stdcall';
function GetTickCount64(): Int64;
  external 'GetTickCount64@kernel32.dll stdcall';

const
  WelcomeAdvanceMilliseconds = 4000;
  ZeroClickVisualMilliseconds = 5000;

type
  TVisual = record
    Steps, Garden: TBitmapImage;
    Words: array[0..2] of TNewStaticText;
    StepsLeft, GardenLeft: Integer;
  end;

var
  VisualTimer: UINT_PTR;
  VisualStartedAt: Int64;
  VisualActive, MotionAllowed, WelcomeAdvanced: Boolean;
  VisualPhase: String;
  Visuals: array[0..1] of TVisual;
  StepWords: array[0..2] of String;

procedure StopInstallMotion();
begin
  VisualActive := False;
  if VisualTimer <> 0 then
  begin
    if not KillTimer(0, VisualTimer) then
      Log('Bloomstep visual timer disposal failed; callback is inactive and Setup will dispose its thread.');
    VisualTimer := 0;
    Log('Bloomstep visual timer stopped.');
  end;
end;

function VisualElapsed(): Int64;
begin
  Result := GetTickCount64() - VisualStartedAt;
end;

procedure PlaceVisual(Index, Drift: Integer);
var
  I: Integer;
begin
  Visuals[Index].Steps.Left := Visuals[Index].StepsLeft + Drift;
  Visuals[Index].Garden.Left := Visuals[Index].GardenLeft - Drift;
  for I := 0 to 2 do
    Visuals[Index].Words[I].Left := Visuals[Index].StepsLeft + Drift +
      (Visuals[Index].Steps.Width * (137 + I * 363)) div 1000 - Visuals[Index].Words[I].Width div 2;
end;

procedure AutoAdvanceWelcome();
begin
  if WelcomeAdvanced then Exit;
  WelcomeAdvanced := True;
  StopInstallMotion();
  Log('Bloomstep welcome auto-advanced after ' + IntToStr(VisualElapsed()) + ' ms.');
  WizardForm.NextButton.Visible := True;
  WizardForm.NextButton.OnClick(WizardForm.NextButton);
end;

procedure VisualTimerTick(Window: HWND; Message: UINT; Id: UINT_PTR; Tick: DWORD);
var
  Index, Drift: Integer;
begin
  if not VisualActive or (Id <> VisualTimer) then Exit;
  // A Cancel confirmation is modal; never advance underneath it.
  if not WizardForm.Enabled then Exit;
  if (WizardForm.CurPageID = wpWelcome) and (VisualElapsed() >= WelcomeAdvanceMilliseconds) then
  begin
    AutoAdvanceWelcome();
    Exit;
  end;
  if MotionAllowed then
  begin
    Index := 1;
    if WizardForm.CurPageID = wpWelcome then Index := 0;
    Drift := (VisualElapsed() div 150) mod 8;
    if Drift > 4 then Drift := 8 - Drift;
    PlaceVisual(Index, ScaleX(Drift));
  end;
end;

procedure StartVisualTimer();
var
  Animations: Integer;
begin
  StopInstallMotion();
  if WizardSilent then Exit;
  VisualStartedAt := GetTickCount64();
  MotionAllowed := False;
  if SystemParametersInfo($1042, 0, Animations, 0) then
    MotionAllowed := Animations <> 0
  else
    Log('Bloomstep animation preference query failed; static art retained.');
  if not MotionAllowed then
    Log('Bloomstep static visual: Windows animations disabled or unavailable; timing still applies.');
  Log('Bloomstep visual identity=anchor-action-celebrate-garden; phase=' + VisualPhase +
    '; elapsedMilliseconds=0.');
  // The timer always runs: reduced motion keeps the art still but still auto-advances.
  VisualTimer := SetTimer(0, 0, 150, CreateCallback(@VisualTimerTick));
  if VisualTimer = 0 then
  begin
    Log('Bloomstep visual timer could not be created; static art retained.');
    if VisualPhase = 'welcome' then AutoAdvanceWelcome();
    Exit;
  end;
  VisualActive := True;
end;

procedure ShowVisualForPage(CurPageID: Integer);
begin
  if WizardSilent then Exit;
  if CurPageID = wpWelcome then
  begin
    WizardForm.NextButton.Visible := False;
    WizardForm.BackButton.Visible := False;
    VisualPhase := 'welcome';
    StartVisualTimer();
  end
  else if CurPageID = wpInstalling then
  begin
    VisualPhase := 'installing';
    StartVisualTimer();
  end
  else
    StopInstallMotion();
end;

function SetupLabel(Parent: TWinControl; Caption: String): TNewStaticText;
begin
  Result := TNewStaticText.Create(WizardForm);
  Result.Parent := Parent;
  Result.Caption := Caption;
  Result.AutoSize := True;
  Result.Font.Size := 11;
  Result.Font.Style := [fsBold];
  Result.Font.Color := $476A38;
end;

procedure BuildVisual(Index: Integer; Parent: TWinControl; Top, AvailableHeight: Integer);
var
  Width, WordHeight, I: Integer;
begin
  WordHeight := ScaleY(26);
  Width := Parent.Width - ScaleX(16);
  if (Width * 500) div 1000 + WordHeight + ScaleY(8) > AvailableHeight then
    Width := ((AvailableHeight - WordHeight - ScaleY(8)) * 1000) div 500;
  if Width < ScaleX(160) then
    RaiseException('Bloomstep illustration does not fit this display scale. Cancel Setup and use a larger display area; installation has not started.');
  Visuals[Index].Steps := TBitmapImage.Create(WizardForm);
  Visuals[Index].Steps.Parent := Parent;
  Visuals[Index].Steps.Stretch := True;
  Visuals[Index].Steps.Width := Width;
  Visuals[Index].Steps.Height := (Width * 200) div 1000;
  Visuals[Index].Steps.Top := Top;
  Visuals[Index].Steps.Bitmap.LoadFromFile(ExpandConstant('{tmp}\welcome-steps.bmp'));
  Visuals[Index].StepsLeft := (Parent.Width - Width) div 2;
  for I := 0 to 2 do
  begin
    Visuals[Index].Words[I] := SetupLabel(Parent, StepWords[I]);
    Visuals[Index].Words[I].Top := Top + Visuals[Index].Steps.Height + ScaleY(2);
  end;
  Visuals[Index].Words[0].Caption := 'Anchor';
  Visuals[Index].Words[1].Caption := 'Action';
  Visuals[Index].Words[2].Caption := 'Celebrate';
  Visuals[Index].Garden := TBitmapImage.Create(WizardForm);
  Visuals[Index].Garden.Parent := Parent;
  Visuals[Index].Garden.Stretch := True;
  Visuals[Index].Garden.Width := Width;
  Visuals[Index].Garden.Height := (Width * 300) div 1000;
  Visuals[Index].Garden.Top := Top + Visuals[Index].Steps.Height + WordHeight + ScaleY(8);
  Visuals[Index].Garden.Bitmap.LoadFromFile(ExpandConstant('{tmp}\welcome-garden.bmp'));
  Visuals[Index].GardenLeft := Visuals[Index].StepsLeft;
  PlaceVisual(Index, 0);
end;

procedure InitializeInstallMotion();
var
  Top: Integer;
begin
  if WizardSilent then Exit;
  StepWords[0] := 'Anchor';
  StepWords[1] := 'Action';
  StepWords[2] := 'Celebrate';
  ExtractTemporaryFile('welcome-steps.bmp');
  ExtractTemporaryFile('welcome-garden.bmp');
#if InstallFlow != "zeroclick"
  WizardForm.WizardBitmapImage.Visible := False;
  WizardForm.WelcomeLabel1.Visible := False;
  WizardForm.WelcomeLabel2.Visible := False;
  BuildVisual(0, WizardForm.WelcomePage, ScaleY(24), WizardForm.WelcomePage.Height - ScaleY(36));
#endif
  WizardForm.FilenameLabel.Visible := False;
  Top := WizardForm.ProgressGauge.Top + WizardForm.ProgressGauge.Height + ScaleY(10);
  BuildVisual(1, WizardForm.InstallingPage, Top, WizardForm.InstallingPage.Height - Top - ScaleY(4));
end;

#if InstallFlow == "zeroclick"
type
  TPumpMessage = record
    Window, Message, WParam, LParam, Time, X, Y, Reserved: LongWord;
  end;

function PeekMessage(var Msg: TPumpMessage; Window: HWND; First, Last, Remove: UINT): Boolean;
  external 'PeekMessageW@user32.dll stdcall';
function TranslateMessage(var Msg: TPumpMessage): Boolean;
  external 'TranslateMessage@user32.dll stdcall';
function DispatchMessage(var Msg: TPumpMessage): LongInt;
  external 'DispatchMessageW@user32.dll stdcall';

// User-requested ~5s brand hold for the zero-click experiment. Installation work is already
// complete; the window keeps pumping messages so it never appears hung.
procedure HoldZeroClickVisual();
var
  Msg: TPumpMessage;
begin
  if WizardSilent then Exit;
  while VisualElapsed() < ZeroClickVisualMilliseconds do
  begin
    while PeekMessage(Msg, 0, 0, 0, 1) do
    begin
      TranslateMessage(Msg);
      DispatchMessage(Msg);
    end;
    Sleep(15);
  end;
  Log('Bloomstep zero-click visual held until ' + IntToStr(VisualElapsed()) + ' ms.');
end;
#endif

procedure DeinitializeSetup();
begin
  StopInstallMotion();
end;