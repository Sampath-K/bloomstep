import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Sends Win32 keyboard input only to this integration-test process.
Future<void> windowsKeys(
  List<int> keys, {
  bool control = false,
  bool shift = false,
}) async {
  if (!Platform.isWindows ||
      !const bool.fromEnvironment('BUDLARK_TEST_BUILD')) {
    throw StateError('Native keyboard input requires the Windows test build.');
  }
  if (keys.isEmpty || keys.any((key) => key < 1 || key > 254)) {
    throw ArgumentError.value(keys, 'keys', 'Expected virtual-key codes.');
  }
  final sequence = [
    if (control) 'Key 162 0',
    if (shift) 'Key 160 0',
    for (final key in keys) ...['Key $key 0', 'Key $key 2'],
    if (control) 'Key 162 2',
    if (shift) 'Key 160 2',
  ].join('\n');
  final script =
      '''
\$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class OwnedInput {
  [StructLayout(LayoutKind.Sequential)]
  public struct Keyboard {
    public ushort vk, scan;
    public uint flags, time;
    public UIntPtr extra;
  }
  [StructLayout(LayoutKind.Explicit, Size = 40)]
  public struct Input {
    [FieldOffset(0)] public uint type;
    [FieldOffset(8)] public Keyboard keyboard;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct Message {
    public IntPtr hwnd;
    public uint message;
    public UIntPtr wParam;
    public IntPtr lParam;
    public uint time;
    public int x, y;
    public uint lPrivate;
  }
  [DllImport("user32.dll")] public static extern bool PeekMessage(out Message message, IntPtr window, uint min, uint max, uint remove);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder name, int size);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int command);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool AttachThreadInput(uint from, uint to, bool attach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SystemParametersInfo(uint action, uint parameter, out uint value, uint flags);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint mapType);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll", SetLastError=true)]
  public static extern uint SendInput(uint n, Input[] input, int size);
}
'@
if ([IntPtr]::Size -ne 8) { throw 'Only the native x64/arm64 test runners are supported.' }
if ([Console]::ReadLine() -ne 'activate-owned-window') { throw 'Missing owned activation handshake.' }
\$owned = [Diagnostics.Process]::GetProcessById($pid).MainWindowHandle
[uint32]\$ownedPid = 0
\$ownedThread = [OwnedInput]::GetWindowThreadProcessId(\$owned, [ref]\$ownedPid)
function ClassName([IntPtr]\$window) {
  \$name = New-Object Text.StringBuilder 256
  [void][OwnedInput]::GetClassName(\$window, \$name, \$name.Capacity)
  return \$name.ToString()
}
function State([string]\$stage) {
  \$foreground = [OwnedInput]::GetForegroundWindow()
  [uint32]\$foregroundPid = 0
  [void][OwnedInput]::GetWindowThreadProcessId(\$foreground, [ref]\$foregroundPid)
  [uint32]\$lockTimeout = 0
  \$lockRead = [OwnedInput]::SystemParametersInfo(8192, 0, [ref]\$lockTimeout, 0)
  Write-Output ("owned_activation stage={0} actorPid={1} appPid={2} foreground=0x{3:X} foregroundPid={4} foregroundClass={5} owned=0x{6:X} ownedClass={7} iconic={8} visible={9} foregroundLockTimeout={10} lockRead={11} ownedPid={12}" -f \$stage, \$PID, $pid, \$foreground.ToInt64(), \$foregroundPid, (ClassName \$foreground), \$owned.ToInt64(), (ClassName \$owned), [OwnedInput]::IsIconic(\$owned), [OwnedInput]::IsWindowVisible(\$owned), \$lockTimeout, \$lockRead, \$ownedPid)
}
function ActivateOwned {
  [void][OwnedInput]::ShowWindow(\$owned, 9)
  \$activated = [OwnedInput]::SetForegroundWindow(\$owned)
  \$raised = [OwnedInput]::BringWindowToTop(\$owned)
  Write-Output "owned_activation SetForegroundWindow=\$activated BringWindowToTop=\$raised actorPid=\$PID"
}
function WaitOwned {
  \$elapsed = [Diagnostics.Stopwatch]::StartNew()
  while ([OwnedInput]::GetForegroundWindow() -ne \$owned -and \$elapsed.ElapsedMilliseconds -lt 2000) {
    Start-Sleep -Milliseconds 25
  }
  return [OwnedInput]::GetForegroundWindow() -eq \$owned
}
State 'before'
if (\$owned -eq [IntPtr]::Zero) { throw 'Owned test process has no main HWND; no keys sent.' }
if (\$ownedPid -ne $pid) { throw 'Main HWND does not belong to the test process; no keys sent.' }
ActivateOwned
\$ready = WaitOwned
if (-not \$ready) {
  # AttachThreadInput requires the helper thread to have a message queue.
  \$message = New-Object OwnedInput+Message
  [void][OwnedInput]::PeekMessage([ref]\$message, [IntPtr]::Zero, 0, 0, 0)
  \$currentThread = [OwnedInput]::GetCurrentThreadId()
  [uint32]\$foregroundPid = 0
  \$foregroundThread = [OwnedInput]::GetWindowThreadProcessId([OwnedInput]::GetForegroundWindow(), [ref]\$foregroundPid)
  \$attached = @()
  try {
    foreach (\$targetThread in @(\$foregroundThread, \$ownedThread) | Select-Object -Unique) {
      if (\$targetThread -ne 0 -and \$targetThread -ne \$currentThread) {
        \$success = [OwnedInput]::AttachThreadInput(\$currentThread, \$targetThread, \$true)
        Write-Output "owned_activation AttachThreadInput from=\$currentThread to=\$targetThread attached=\$success"
        if (\$success) { \$attached += \$targetThread }
      }
    }
    ActivateOwned
    \$ready = WaitOwned
  } finally {
    \$allDetached = \$true
    foreach (\$targetThread in \$attached) {
      \$detached = [OwnedInput]::AttachThreadInput(\$currentThread, \$targetThread, \$false)
      Write-Output "owned_activation AttachThreadInput from=\$currentThread to=\$targetThread detached=\$detached"
      if (-not \$detached) { \$allDetached = \$false }
    }
    if (-not \$allDetached) { throw 'Could not detach owned activation input threads; no keys sent.' }
  }
}
State 'after'
if (-not \$ready) { throw 'Owned test HWND could not become foreground; no keys sent.' }
function Key([uint16]\$vk, [uint32]\$flags) {
  [uint32]\$owner = 0
  \$foreground = [OwnedInput]::GetForegroundWindow()
  [void][OwnedInput]::GetWindowThreadProcessId(\$foreground, [ref]\$owner)
  if (\$foreground -ne \$owned -or \$owner -ne $pid) {
    State 'guard-denied'
    throw 'Owned test window is not foreground; no keys sent.'
  }
  \$input = New-Object OwnedInput+Input
  \$input.type = 1
  \$keyboard = New-Object OwnedInput+Keyboard
  \$keyboard.vk = \$vk
  \$scan = [OwnedInput]::MapVirtualKey(\$vk, 4)
  \$keyboard.scan = [uint16](\$scan -band 255)
  \$keyboard.flags = \$flags
  # Navigation keys share keypad scan codes; preserve their extended-key identity.
  if ((\$scan -band 65280) -eq 57344 -or \$vk -in @(33, 34, 35, 36, 37, 38, 39, 40, 45, 46)) {
    \$keyboard.flags = \$keyboard.flags -bor 1
  }
  \$input.keyboard = \$keyboard
  if ([OwnedInput]::SendInput(1, @(\$input), 40) -ne 1) { throw 'Win32 rejected native keyboard input.' }
  Start-Sleep -Milliseconds 60
}
try {
$sequence
} finally {
  # Release the modifier only while the same owned window still has focus.
  if (${control ? '\$true' : '\$false'}) { Key 162 2 }
  if (${shift ? '\$true' : '\$false'}) { Key 160 2 }
}
''';
  final helper = await Process.start('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    script,
  ]);
  final output = helper.stdout.transform(utf8.decoder).join();
  final errors = helper.stderr.transform(utf8.decoder).join();
  final permit = DynamicLibrary.open('user32.dll')
      .lookupFunction<Int32 Function(Uint32), int Function(int)>(
        'AllowSetForegroundWindow',
      );
  final allowed = permit(helper.pid) != 0;
  final permission =
      'owned_activation appPid=$pid helperPid=${helper.pid} '
      'AllowSetForegroundWindow=$allowed';
  debugPrint(permission);
  helper.stdin.writeln('activate-owned-window');
  await helper.stdin.close();
  int exitCode;
  try {
    exitCode = await helper.exitCode.timeout(const Duration(seconds: 30));
  } on TimeoutException {
    helper.kill();
    await helper.exitCode;
    throw StateError(
      'Native keyboard helper timed out; no further keys sent.\n'
      '$permission\n${await output}${await errors}',
    );
  }
  final diagnostic = await output;
  final error = await errors;
  if (exitCode != 0) {
    throw StateError(
      'Native keyboard input failed:\n$permission\n$diagnostic$error',
    );
  }
  debugPrint(diagnostic);
}
