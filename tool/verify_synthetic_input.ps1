param(
  [Parameter(Mandatory=$true)][string]$Executable,
  [Parameter(Mandatory=$true)][string]$Output
)
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -ne 'true') {throw 'Synthetic native input harness is restricted to the approved CI runner.'}
if([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'Arm64') {throw 'Synthetic input requires the existing true ARM64 runner.'}
$expected=Join-Path (Split-Path $PSScriptRoot) 'build\windows\arm64\runner\Profile\bloomstep.exe'
if([IO.Path]::GetFullPath($Executable) -ne $expected) {throw 'Only the CI-built explicit synthetic profile path is permitted.'}
$binary=[IO.File]::ReadAllBytes($expected)
$peMachine=[BitConverter]::ToUInt16($binary,[BitConverter]::ToInt32($binary,60)+4)
if($peMachine -ne 0xaa64) {throw 'Synthetic fixture architecture is not ARM64.'}
$database=Join-Path ([IO.Path]::GetTempPath()) 'bloomstep-synthetic-preview.sqlite'
$databaseFiles=@($database,($database+'-wal'),($database+'-shm'),($database+'-journal'))
foreach($path in $databaseFiles) {
  if(Test-Path -LiteralPath $path) {throw 'Existing synthetic database; refusing overwrite.'}
}
if(Test-Path -LiteralPath $Output) {throw 'Existing native result file; refusing overwrite.'}
if(!(Test-Path -LiteralPath (Split-Path $Output))) {throw 'Synthetic result parent must already exist.'}
if(Get-Process | Where-Object {$_.Path -eq $expected}) {throw 'An existing synthetic fixture owner is running; no input or cleanup permitted.'}
Add-Type -AssemblyName Accessibility,UIAutomationClient,UIAutomationTypes
Add-Type -ReferencedAssemblies Accessibility,System.Runtime,System.Collections,System.Threading.Thread -CompilerOptions '/nowarn:1701' -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class SyntheticInput {
  public delegate bool Enumerator(IntPtr window,IntPtr state);
  [StructLayout(LayoutKind.Sequential)] public struct Point { public int x,y; }
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int left,top,right,bottom; }
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr window,Enumerator callback,IntPtr state);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr window,StringBuilder text,int count);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr window,ref Point point);
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr window,out Rect rectangle);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window,out Rect rectangle);
  [DllImport("user32.dll",EntryPoint="PostMessageW")] static extern bool PostMessage(IntPtr window,uint message,IntPtr w,IntPtr l);
  [DllImport("oleacc.dll")] static extern int AccessibleObjectFromWindow(IntPtr window,uint id,ref Guid iid,[MarshalAs(UnmanagedType.Interface)] out object result);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SqlOpen([MarshalAs(UnmanagedType.LPUTF8Str)] string path,out IntPtr db,int flags,IntPtr vfs);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SqlClose(IntPtr db);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SqlPrepare(IntPtr db,[MarshalAs(UnmanagedType.LPUTF8Str)] string sql,int bytes,out IntPtr statement,IntPtr tail);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SqlBind(IntPtr statement,int index,[MarshalAs(UnmanagedType.LPUTF8Str)] string value,int bytes,IntPtr destructor);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SqlStep(IntPtr statement);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr SqlText(IntPtr statement,int column);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SqlFinalize(IntPtr statement);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SqlTimeout(IntPtr db,int milliseconds);
  public static string Scalar(string path,string library,string sql,string value) {
    IntPtr module=NativeLibrary.Load(library),db=IntPtr.Zero,statement=IntPtr.Zero;
    var close=Marshal.GetDelegateForFunctionPointer<SqlClose>(NativeLibrary.GetExport(module,"sqlite3_close"));
    var finish=Marshal.GetDelegateForFunctionPointer<SqlFinalize>(NativeLibrary.GetExport(module,"sqlite3_finalize"));
    try {
      var open=Marshal.GetDelegateForFunctionPointer<SqlOpen>(NativeLibrary.GetExport(module,"sqlite3_open_v2"));
      if(open(path,out db,1,IntPtr.Zero)!=0)throw new InvalidOperationException("Synthetic read-only SQLite open failed.");
      var timeout=Marshal.GetDelegateForFunctionPointer<SqlTimeout>(NativeLibrary.GetExport(module,"sqlite3_busy_timeout"));
      if(timeout(db,2000)!=0)throw new InvalidOperationException("Synthetic SQLite read timeout setup failed.");
      var prepare=Marshal.GetDelegateForFunctionPointer<SqlPrepare>(NativeLibrary.GetExport(module,"sqlite3_prepare_v2"));
      if(prepare(db,sql,-1,out statement,IntPtr.Zero)!=0)throw new InvalidOperationException("Synthetic SQLite scalar preparation failed.");
      if(value!=null) {
        var bind=Marshal.GetDelegateForFunctionPointer<SqlBind>(NativeLibrary.GetExport(module,"sqlite3_bind_text"));
        if(bind(statement,1,value,-1,new IntPtr(-1))!=0)throw new InvalidOperationException("Synthetic SQLite parameter bind failed.");
      }
      var step=Marshal.GetDelegateForFunctionPointer<SqlStep>(NativeLibrary.GetExport(module,"sqlite3_step"));
      if(step(statement)!=100)throw new InvalidOperationException("Synthetic SQLite readback missing or unavailable.");
      var text=Marshal.GetDelegateForFunctionPointer<SqlText>(NativeLibrary.GetExport(module,"sqlite3_column_text"));
      return Marshal.PtrToStringUTF8(text(statement,0))??"";
    } finally {
      if(statement!=IntPtr.Zero)finish(statement);
      if(db!=IntPtr.Zero)close(db);
      NativeLibrary.Free(module);
    }
  }
  public static int NodeCount(IntPtr view) {return Walk(Root(view)).Count;}
  sealed class Element {
    public Accessibility.IAccessible node; public int child,depth;
    public string Name {get{return node.get_accName(child)??"";}}
    public int Role {get {var v=node.get_accRole(child);return v is int?(int)v:0;}}
    public int State {get {var v=node.get_accState(child);return v is int?(int)v:0;}}
    public string Value {get{return node.get_accValue(child)??"";}}
  }
  static List<Element> Walk(Accessibility.IAccessible node,int depth=0) {
    var list=new List<Element>();if(node==null||depth>24)return list;
    list.Add(new Element{node=node,child=0,depth=depth});
    int count=node.accChildCount;if(count>1000)throw new InvalidOperationException("Synthetic tree bound exceeded.");
    for(int i=1;i<=count;i++) {
      var next=node.get_accChild(i) as Accessibility.IAccessible;
      if(next!=null)list.AddRange(Walk(next,depth+1));else list.Add(new Element{node=node,child=i,depth=depth+1});
    }return list;
  }
  static Accessibility.IAccessible Root(IntPtr view) {
    var iid=new Guid("618736E0-3C3D-11CF-810C-00AA00389B71");object root;
    if(AccessibleObjectFromWindow(view,0xfffffffc,ref iid,out root)!=0)throw new InvalidOperationException("Synthetic accessible root unavailable.");
    return root as Accessibility.IAccessible;
  }
  public static bool Has(IntPtr view,string label) {
    foreach(var e in Walk(Root(view)))if(e.Name.Contains(label))return true;return false;
  }
  static bool Matches(string actual,string label) {
    return actual==label||actual.StartsWith(label+"\n")||actual.StartsWith(label+" ");
  }
  static List<Element> Targets(Accessibility.IAccessible root,string label,int role) {
    var list=new List<Element>();
    foreach(var e in Walk(root))if(e.Role==role&&Matches(e.Name,label))list.Add(e);
    return list;
  }
  static Element Unique(IntPtr view,string label,int role,string fixture) {
    var root=Root(view);
    if(!string.IsNullOrEmpty(fixture)) {
      Accessibility.IAccessible scoped=null;int depth=-1;
      foreach(var parent in Walk(root)) {
        if(parent.child!=0)continue;
        bool contains=false;foreach(var e in Walk(parent.node))if(e.Name==fixture)contains=true;
        if(contains&&Targets(parent.node,label,role).Count==1&&parent.depth>depth) {scoped=parent.node;depth=parent.depth;}
      }
      if(scoped==null)throw new InvalidOperationException("Owned synthetic fixture scope missing: "+label);
      root=scoped;
    }
    var matches=Targets(root,label,role);
    if(matches.Count>1)throw new InvalidOperationException("Ambiguous synthetic control: "+label);
    if(matches.Count==0)throw new InvalidOperationException("Missing synthetic control: "+label);
    return matches[0];
  }
  static void Ownership(IntPtr view,uint owner) {
    uint pid;GetWindowThreadProcessId(view,out pid);
    if(pid!=owner||!Has(view,"ISOLATED SYNTHETIC PREVIEW"))throw new InvalidOperationException("Synthetic ownership/banner lost; no action sent.");
  }
  public static void Foreground(uint owner) {
    uint pid;GetWindowThreadProcessId(GetForegroundWindow(),out pid);
    if(pid!=owner)throw new InvalidOperationException("Host lacks synthetic interactive foreground; no policy bypass or fallback input.");
  }
  public static void Action(IntPtr view,uint owner,string label,int role,string fixture) {
    Ownership(view,owner);
    var e=Unique(view,label,role,fixture);
    if((e.State&1)!=0)throw new InvalidOperationException("Synthetic action disabled: "+label);
    e.node.accDoDefaultAction(e.child);
  }
  public static bool ScopedHas(IntPtr view,string fixture,string label) {
    foreach(var parent in Walk(Root(view))) {
      if(parent.child!=0)continue;
      bool owned=false,found=false;
      foreach(var e in Walk(parent.node)) {if(e.Name==fixture)owned=true;if(e.Name.Contains(label))found=true;}
      if(owned&&found) {
        // Require a card-scoped practice control; the full garden is not a record scope.
        if(Targets(parent.node,"Did it",43).Count==1)return true;
      }
    }return false;
  }
  public static void Scroll(IntPtr view,uint owner,int direction) {
    Ownership(view,owner);Foreground(owner);Rect bounds;
    if(!GetWindowRect(view,out bounds))throw new InvalidOperationException("Synthetic scroll bounds unavailable.");
    int x=bounds.left+(bounds.right-bounds.left)/2,y=bounds.top+(bounds.bottom-bounds.top)/2;
    if(!PostMessage(view,0x20a,new IntPtr(direction*120<<16),new IntPtr((y<<16)|(x&0xffff))))
      throw new InvalidOperationException("Targeted synthetic scroll queue rejected.");
  }
  public static string SetText(IntPtr view,uint owner,string label,string desired) {
    if(!desired.StartsWith("Bloomstep acceptance test CI ")||desired.Length>200)throw new InvalidOperationException("Non-synthetic text refused.");
    Ownership(view,owner);Foreground(owner);
    var field=Unique(view,label,42,null);string result="";
    try {field.node.set_accValue(field.child,desired);result+="setter=accepted;";}
    catch(COMException e){result+="setter_hresult="+unchecked((uint)e.HResult).ToString("x8")+";";}
    Thread.Sleep(150);field=Unique(view,label,42,null);
    if(field.Value==desired)return result+"exact_readback=true;input_route=setter;";
    try {field.node.accSelect(1,field.child);result+="take_focus=accepted;";}
    catch(COMException e){result+="take_focus_hresult="+unchecked((uint)e.HResult).ToString("x8")+";";}
    Thread.Sleep(150);field=Unique(view,label,42,null);
    if((field.State&4)==0) {
      Foreground(owner);
      int x,y,w,h;field.node.accLocation(out x,out y,out w,out h,field.child);
      var p=new Point{x=x+w/2,y=y+h/2};Rect bounds;
      if(w<=0||h<=0||!ScreenToClient(view,ref p)||!GetClientRect(view,out bounds)||p.x<0||p.y<0||p.x>=bounds.right||p.y>=bounds.bottom)
        throw new InvalidOperationException(result+"Synthetic field bounds unsafe.");
      var position=new IntPtr((p.y<<16)|(p.x&0xffff));
      if(!PostMessage(view,0x201,new IntPtr(1),position)||!PostMessage(view,0x202,IntPtr.Zero,position))
        throw new InvalidOperationException(result+"Targeted synthetic focus message rejected.");
      Thread.Sleep(250);field=Unique(view,label,42,null);result+="targeted_focus_message=true;";
    }
    if((field.State&4)==0)throw new InvalidOperationException(result+"Semantic focus not established; no characters sent.");
    int length=field.Value.Length;if(length>200)throw new InvalidOperationException("Synthetic text length unsafe.");
    Foreground(owner);
    if(!PostMessage(view,0x100,new IntPtr(0x23),new IntPtr(1))||!PostMessage(view,0x101,new IntPtr(0x23),new IntPtr(0xc0000001L)))
      throw new InvalidOperationException("Synthetic End-key queue rejected.");
    for(int i=0;i<length;i++)if(!PostMessage(view,0x102,new IntPtr(8),new IntPtr(1)))throw new InvalidOperationException("Synthetic backspace queue rejected.");
    foreach(char c in desired)if(!PostMessage(view,0x102,new IntPtr(c),new IntPtr(1)))throw new InvalidOperationException("Synthetic character queue rejected.");
    for(int i=0;i<30;i++) {
      Thread.Sleep(100);
      if(Unique(view,label,42,null).Value==desired)return result+"semantic_focus=true;exact_readback=true;input_route=targeted_window_messages;";
    }
    throw new InvalidOperationException(result+"Targeted synthetic text did not read back exactly.");
  }
}
'@
$script:app=$null
$script:view=[IntPtr]::Zero
$result=[ordered]@{
  schemaVersion=1
  scope='CI synthetic native tooling, not current account acceptance'
  customerAcceptance=$false
  cloudUsed=$false
  phase='start'
}
$failure=$null
function Close-Synthetic {
  if(!$script:app) {return}
  $script:app.Refresh()
  if(!$script:app.HasExited) {
    if((Get-Process -Id $script:app.Id).Path -ne $expected) {throw 'Synthetic owner path changed; cleanup refused.'}
    [void]$script:app.CloseMainWindow()
    if(!$script:app.WaitForExit(5000)) {
      $app=$script:app
      Stop-Process -Id $app.Id
      if(!$app.WaitForExit(5000)) {throw 'Exact synthetic process did not terminate.'}
    }
  }
  $script:app.Dispose()
  $script:app=$null
  $script:view=[IntPtr]::Zero
}
function Start-Synthetic {
  $script:app=Start-Process -FilePath $expected -WorkingDirectory (Split-Path $expected) -PassThru
  $deadline=[DateTime]::UtcNow.AddSeconds(20)
  do {
    Start-Sleep -Milliseconds 100
    $script:app.Refresh()
    if($script:app.HasExited) {throw 'Synthetic process exited before readiness.'}
  } while($script:app.MainWindowHandle -eq 0 -and [DateTime]::UtcNow -lt $deadline)
  if($script:app.MainWindowHandle -eq 0) {throw 'Synthetic window readiness timeout.'}
  $views=[Collections.Generic.List[IntPtr]]::new()
  $callback=[SyntheticInput+Enumerator]{
    param($window,$unused)
    [uint32]$owner=0
    [void][SyntheticInput]::GetWindowThreadProcessId($window,[ref]$owner)
    $kind=[Text.StringBuilder]::new(64)
    [void][SyntheticInput]::GetClassName($window,$kind,64)
    if($owner -eq $script:app.Id -and $kind.ToString() -eq 'FLUTTERVIEW') {$views.Add($window)}
    return $true
  }
  [void][SyntheticInput]::EnumChildWindows($script:app.MainWindowHandle,$callback,[IntPtr]::Zero)
  if($views.Count -ne 1) {throw 'Expected exactly one owned synthetic Flutter view.'}
  $script:view=$views[0]
  [void][SyntheticInput]::SetForegroundWindow($script:app.MainWindowHandle)
  [SyntheticInput]::Foreground([uint32]$script:app.Id)
  $result.actualForegroundVerified=$true
  $uia=[System.Windows.Automation.AutomationElement]::FromHandle($script:view)
  [void]$uia.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  $deadline=[DateTime]::UtcNow.AddSeconds(10)
  while(![SyntheticInput]::Has($script:view,'ISOLATED SYNTHETIC PREVIEW')) {
    if([DateTime]::UtcNow -ge $deadline) {
      $result.accessibleNodeCount=[SyntheticInput]::NodeCount($script:view)
      throw 'Synthetic banner readiness timeout on verified foreground; no input sent.'
    }
    Start-Sleep -Milliseconds 100
  }
  $result.syntheticBannerVerified=$true
}
function Store-Scalar([string]$Sql,[string]$Value) {
  [SyntheticInput]::Scalar($database,(Join-Path (Split-Path $expected) 'sqlite3.dll'),$Sql,$Value)
}
function Assert-Count([string]$Sql,[string]$Value,[string]$Expected,[string]$Stage) {
  if((Store-Scalar $Sql $Value) -ne $Expected) {throw "Synthetic read-only local state mismatch: $Stage"}
}
function Wait-Label([string]$Label,[bool]$Present=$true) {
  $deadline=[DateTime]::UtcNow.AddSeconds(10)
  while([SyntheticInput]::Has($script:view,$Label) -ne $Present) {
    if([DateTime]::UtcNow -ge $deadline) {throw "Synthetic state readback timeout: $Label expected=$Present"}
    Start-Sleep -Milliseconds 100
  }
}
function Action([string]$Label,[int]$Role=43,[string]$Fixture='') {
  [SyntheticInput]::Action($script:view,[uint32]$script:app.Id,$Label,$Role,$Fixture)
  Start-Sleep -Milliseconds 250
}
function Open-Builder {
  Action 'Plant a habit'
  if([SyntheticInput]::Has($script:view,'Start small')) {Action 'Plant another'}
  Wait-Label 'Plant one tiny step'
}
function Find-Fixture([string]$Label) {
  for($i=0;$i -lt 20;$i++) {
    if([SyntheticInput]::Has($script:view,$Label)) {return}
    [SyntheticInput]::Scroll($script:view,[uint32]$script:app.Id,-1)
    Start-Sleep -Milliseconds 150
  }
  throw 'Synthetic fixture not visible after bounded owned scroll.'
}
try {
  Start-Synthetic
  $seedHabitCount=Store-Scalar "SELECT count(*) FROM habits WHERE account='synthetic-preview-only'" $null
  $seedCheckinCount=Store-Scalar "SELECT count(*) FROM checkins WHERE account='synthetic-preview-only'" $null
  $result.phase='text-save'
  Open-Builder
  Action 'Calm'
  $saved='Bloomstep acceptance test CI save '+[Guid]::NewGuid().ToString('N').Substring(0,8)
  $canceled='Bloomstep acceptance test CI cancel '+[Guid]::NewGuid().ToString('N').Substring(0,8)
  $result.textEntry=[SyntheticInput]::SetText($script:view,[uint32]$script:app.Id,'I want more...',$saved)
  Action 'I practiced my celebration' 44
  Action 'Plant this seed'
  Wait-Label 'Plant one tiny step' $false
  Find-Fixture $saved
  $result.savedVisible=$true
  $result.phase='text-cancel'
  Open-Builder
  $result.cancelTextEntry=[SyntheticInput]::SetText($script:view,[uint32]$script:app.Id,'I want more...',$canceled)
  Action 'Cancel'
  Wait-Label 'Plant one tiny step' $false
  if([SyntheticInput]::Has($script:view,$canceled)) {throw 'Canceled synthetic recipe appeared in garden.'}
  $result.cancelReturnedToGarden=$true
  $result.phase='restart-save-cancel-readback'
  Close-Synthetic
  Assert-Count "SELECT count(*) FROM habits WHERE account='synthetic-preview-only' AND aspiration=?1" $saved '1' 'saved recipe'
  Assert-Count "SELECT count(*) FROM habits WHERE account='synthetic-preview-only' AND aspiration=?1" $canceled '0' 'canceled recipe'
  $fixtureId=Store-Scalar "SELECT id FROM habits WHERE account='synthetic-preview-only' AND aspiration=?1" $saved
  if($fixtureId -notmatch '^[0-9a-f-]{36}$') {throw 'Synthetic fixture identity readback malformed.'}
  $result.readOnlyLocalState=$true
  Start-Synthetic
  Find-Fixture $saved
  $result.savedPersisted=$true
  if([SyntheticInput]::Has($script:view,$canceled)) {throw 'Canceled synthetic recipe persisted after restart.'}
  $result.cancelAbsentAfterRestart=$true
  $result.phase='checkin'
  Action 'Did it' 43 $saved
  $deadline=[DateTime]::UtcNow.AddSeconds(10)
  while(![SyntheticInput]::ScopedHas($script:view,$saved,'Today is recorded. You can change it.')) {
    if([DateTime]::UtcNow -ge $deadline) {throw 'Scoped synthetic check-in readback timeout.'}
    Start-Sleep -Milliseconds 100
  }
  Assert-Count "SELECT CASE WHEN result='did' THEN 1 ELSE 0 END FROM checkins WHERE account='synthetic-preview-only' AND habitId=?1 ORDER BY ts DESC,id DESC LIMIT 1" $fixtureId '1' 'owned check-in'
  $result.scopedCheckinObserved=$true
  $result.phase='undo'
  Action 'Undo today' 43 $saved
  $deadline=[DateTime]::UtcNow.AddSeconds(10)
  while([SyntheticInput]::ScopedHas($script:view,$saved,'Undo today')) {
    if([DateTime]::UtcNow -ge $deadline) {throw 'Scoped synthetic undo readback timeout.'}
    Start-Sleep -Milliseconds 100
  }
  Assert-Count "SELECT CASE WHEN result IS NULL THEN 1 ELSE 0 END FROM checkins WHERE account='synthetic-preview-only' AND habitId=?1 ORDER BY ts DESC,id DESC LIMIT 1" $fixtureId '1' 'owned undo'
  $result.scopedUndoObserved=$true
  $result.phase='delete'
  Action 'Delete this recipe' 43 $saved
  Wait-Label 'Delete this recipe?'
  Action 'Delete recipe'
  Wait-Label 'Delete this recipe?' $false
  Wait-Label $saved $false
  $result.scopedLocalDeleteObserved=$true
  $result.phase='restart-deletion-readback'
  Close-Synthetic
  Assert-Count "SELECT count(*) FROM habits WHERE account='synthetic-preview-only' AND aspiration=?1" $saved '0' 'deleted recipe'
  Assert-Count "SELECT count(*) FROM deletions WHERE account='synthetic-preview-only' AND type='habits' AND recordId=?1" $fixtureId '1' 'owned deletion marker'
  Assert-Count "SELECT count(*) FROM checkins WHERE account='synthetic-preview-only' AND habitId=?1" $fixtureId '0' 'owned dependent check-in cleanup'
  Assert-Count "SELECT count(*) FROM habits WHERE account='synthetic-preview-only'" $null $seedHabitCount 'original seed habits'
  Assert-Count "SELECT count(*) FROM checkins WHERE account='synthetic-preview-only'" $null $seedCheckinCount 'original seed check-ins'
  $result.originalSeedCheckinsPreserved=$true
  Start-Synthetic
  for($i=0;$i -lt 12;$i++) {
    if([SyntheticInput]::Has($script:view,$saved) -or [SyntheticInput]::Has($script:view,$canceled)) {throw 'Deleted/canceled synthetic recipe reappeared after restart.'}
    [SyntheticInput]::Scroll($script:view,[uint32]$script:app.Id,-1)
    Start-Sleep -Milliseconds 100
  }
  $result.deletedAbsentAfterRestart=$true
  $result.phase='passed'
} catch {
  $errorObject=$_.Exception
  while($errorObject.InnerException) {$errorObject=$errorObject.InnerException}
  $failure=$errorObject.Message
  $result.failure=$failure
} finally {
  try {
    Close-Synthetic
    $result.exactSyntheticProcessClosed=$true
    foreach($path in $databaseFiles) {
      if(Test-Path -LiteralPath $path) {Remove-Item -LiteralPath $path}
      if(Test-Path -LiteralPath $path) {throw 'Synthetic database cleanup failed.'}
    }
    $result.onlyNewSyntheticFilesRemoved=$true
  } catch {
    $result.cleanupFailure=$_.Exception.Message
    if(!$failure) {$failure=$result.cleanupFailure}
  }
  $json=$result | ConvertTo-Json -Depth 4
  $stream=[IO.File]::Open($Output,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try {
    $bytes=[Text.Encoding]::UTF8.GetBytes($json)
    $stream.Write($bytes,0,$bytes.Length)
  } finally {$stream.Dispose()}
  Write-Output $json
}
if($failure) {throw $failure}
