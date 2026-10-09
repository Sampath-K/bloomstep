type
  TStaticVisual = record
    Steps, Garden: TBitmapImage;
    Words: array[0..2] of TNewStaticText;
    Title, Value, Context: TNewStaticText;
  end;
var
  WelcomeVisual: TStaticVisual;

procedure InitializeInstallMotion();
var
  I, Width, Top, Left: Integer;
  Words: array[0..2] of String;
begin
  if WizardSilent then Exit;
  Words[0] := 'Anchor';
  Words[1] := 'Action';
  Words[2] := 'Celebrate';
  ExtractTemporaryFile('welcome-steps.bmp');
  ExtractTemporaryFile('welcome-garden.bmp');
  Width := WizardForm.WelcomePage.Width - ScaleX(24);
  if Width > ((WizardForm.WelcomePage.Height - ScaleY(124)) * 1000) div 500 then
    Width := ((WizardForm.WelcomePage.Height - ScaleY(124)) * 1000) div 500;
  Left := (WizardForm.WelcomePage.Width - Width) div 2;
  Top := ScaleY(66);
  WelcomeVisual.Title := TNewStaticText.Create(WizardForm);
  WelcomeVisual.Title.Parent := WizardForm.WelcomePage;
  WelcomeVisual.Title.Caption := 'Welcome to Bloomstep';
  WelcomeVisual.Title.Font.Style := [fsBold];
  WelcomeVisual.Title.SetBounds(ScaleX(12), ScaleY(8), WizardForm.WelcomePage.Width - ScaleX(24), ScaleY(20));
  WelcomeVisual.Value := TNewStaticText.Create(WizardForm);
  WelcomeVisual.Value.Parent := WizardForm.WelcomePage;
  WelcomeVisual.Value.Caption := 'A little is enough. Grow from there.' + #13#10 +
    'Tiny habits around your existing routines.';
  WelcomeVisual.Value.SetBounds(ScaleX(12), ScaleY(30), WizardForm.WelcomePage.Width - ScaleX(24), ScaleY(32));
  WelcomeVisual.Context := TNewStaticText.Create(WizardForm);
  WelcomeVisual.Context.Parent := WizardForm.WelcomePage;
  WelcomeVisual.Context.Caption := 'Limited Windows preview. Select Next to continue.';
  WelcomeVisual.Context.SetBounds(ScaleX(12), WizardForm.WelcomePage.Height - ScaleY(24),
    WizardForm.WelcomePage.Width - ScaleX(24), ScaleY(20));
  WelcomeVisual.Steps := TBitmapImage.Create(WizardForm);
  WelcomeVisual.Steps.Parent := WizardForm.WelcomePage;
  WelcomeVisual.Steps.SetBounds(Left, Top, Width, (Width * 200) div 1000);
  WelcomeVisual.Steps.Stretch := True;
  WelcomeVisual.Steps.Bitmap.LoadFromFile(ExpandConstant('{tmp}\welcome-steps.bmp'));
  for I := 0 to 2 do
  begin
    WelcomeVisual.Words[I] := TNewStaticText.Create(WizardForm);
    WelcomeVisual.Words[I].Parent := WizardForm.WelcomePage;
    WelcomeVisual.Words[I].Caption := Words[I];
    WelcomeVisual.Words[I].AutoSize := True;
    WelcomeVisual.Words[I].Font.Style := [fsBold];
    WelcomeVisual.Words[I].Top := Top + WelcomeVisual.Steps.Height + ScaleY(4);
    WelcomeVisual.Words[I].Left := Left + (Width * (137 + I * 363)) div 1000 -
      WelcomeVisual.Words[I].Width div 2;
  end;
  WelcomeVisual.Garden := TBitmapImage.Create(WizardForm);
  WelcomeVisual.Garden.Parent := WizardForm.WelcomePage;
  WelcomeVisual.Garden.SetBounds(Left, Top + WelcomeVisual.Steps.Height + ScaleY(28),
    Width, (Width * 300) div 1000);
  WelcomeVisual.Garden.Stretch := True;
  WelcomeVisual.Garden.Bitmap.LoadFromFile(ExpandConstant('{tmp}\welcome-garden.bmp'));
  WizardForm.WizardBitmapImage.Visible := False;
  WizardForm.WelcomeLabel1.Visible := False;
  WizardForm.WelcomeLabel2.Visible := False;
end;

procedure ShowVisualForPage(CurPageID: Integer);
begin
  if CurPageID = wpWelcome then
    Log('Bloomstep static welcome; user selects Next to continue.');
end;
