param([string]$Output = (Join-Path $PSScriptRoot '..\site\assets\bloomstep-social.png'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$bitmap = [Drawing.Bitmap]::new(1200, 630)
$canvas = [Drawing.Graphics]::FromImage($bitmap)
$canvas.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$background = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#f7f4ef'))
$text = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#242424'))
$muted = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#5c5c5c'))
$rose = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#b11f4b'))
$green = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#16a34a'))
$soil = [Drawing.Pen]::new([Drawing.ColorTranslator]::FromHtml('#dedede'), 12)
$stem = [Drawing.Pen]::new([Drawing.ColorTranslator]::FromHtml('#16a34a'), 12)
$title = [Drawing.Font]::new('Segoe UI', 46, [Drawing.FontStyle]::Bold)
$subtitle = [Drawing.Font]::new('Segoe UI', 26)
try {
  $canvas.FillRectangle($background, 0, 0, 1200, 630)
  $canvas.DrawString('Bloomstep', $title, $text, 64, 48)
  $canvas.DrawString('A little is enough.', $subtitle, $muted, 68, 140)
  $canvas.DrawLine($soil, 64, 544, 1136, 544)
  $plants = @(@{x=240; top=460}, @{x=560; top=360}, @{x=920; top=252})
  foreach ($plant in $plants) {
    $x = $plant.x; $top = $plant.top
    $canvas.DrawLine($stem, $x, $top, $x, 534)
    $canvas.FillEllipse($green, $x - 74, $top + 20, 74, 32)
    $canvas.FillEllipse($green, $x, $top + 48, 74, 32)
  }
  foreach ($angle in @(0, 60, 120, 180, 240, 300)) {
    $radians = $angle * [Math]::PI / 180
    $canvas.FillEllipse($rose, [single](920 + 32 * [Math]::Cos($radians) - 25), [single](252 + 32 * [Math]::Sin($radians) - 25), 50, 50)
  }
  $canvas.FillEllipse($background, 898, 230, 44, 44)
  $bitmap.Save([IO.Path]::GetFullPath($Output), [Drawing.Imaging.ImageFormat]::Png)
} finally {
  $title.Dispose(); $subtitle.Dispose(); $stem.Dispose(); $soil.Dispose()
  $background.Dispose(); $text.Dispose(); $muted.Dispose(); $rose.Dispose(); $green.Dispose()
  $canvas.Dispose(); $bitmap.Dispose()
}
