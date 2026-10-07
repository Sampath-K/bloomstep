function Get-InstallSceneCatalog {
  @(
    @{ index = 0; id = 'seed-to-flower'; artwork = 'education-seed.bmp';
      caption = 'A little is enough. Grow from there.' }
    @{ index = 1; id = 'routine-action-celebration'; artwork = 'education-recipe.bmp';
      caption = 'After a familiar routine, try one tiny action. Celebrate your start.' }
    @{ index = 2; id = 'growing-garden'; artwork = 'education-growth.bmp';
      caption = 'Your practice grows a garden. Not today leaves your growth intact.' }
  )
}

function Get-InstallSceneCoverage([AllowEmptyCollection()][object[]]$Frames) {
  $catalog = @(Get-InstallSceneCatalog)
  $transitions = [Collections.Generic.List[object]]::new()
  $previousScene = -1
  $previousTime = -1
  foreach ($frame in $Frames) {
    if (($frame.scene -isnot [int] -and $frame.scene -isnot [long]) -or
        $frame.scene -lt 0 -or $frame.scene -gt 2 -or
        ($frame.elapsedMilliseconds -isnot [int] -and $frame.elapsedMilliseconds -isnot [long]) -or
        $frame.elapsedMilliseconds -lt 0 -or $frame.elapsedMilliseconds -lt $previousTime) {
      throw 'Invalid scene index or nonmonotonic actual capture timestamp.'
    }
    if ($frame.scene -ne $previousScene) {
      $transitions.Add(@{ scene = $frame.scene; sceneId = $catalog[$frame.scene].id;
        firstObservedMilliseconds = $frame.elapsedMilliseconds })
      $previousScene = $frame.scene
    }
    $previousTime = $frame.elapsedMilliseconds
  }
  $observed = @($Frames | ForEach-Object { $_.scene } | Sort-Object -Unique)
  @{
    transitions = @($transitions.ToArray())
    absentSceneIds = @($catalog | Where-Object { $_.index -notin $observed } | ForEach-Object { $_.id })
    allThreeScenesObserved = $observed.Count -eq 3
    orderedTransitionsObserved = $transitions.Count -ge 3 -and
      $transitions[0].scene -eq 0 -and $transitions[1].scene -eq 1 -and $transitions[2].scene -eq 2
    expectedIntervalMilliseconds = 3000
    timestampScope = 'First actual captured frame of each transition, relative to posted Install; not exact timer-dispatch time.'
  }
}
