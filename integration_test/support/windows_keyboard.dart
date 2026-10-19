import 'dart:io';

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
    if (control) 'Key 17 0',
    if (shift) 'Key 16 0',
    for (final key in keys) ...['Key $key 0', 'Key $key 2'],
    if (control) 'Key 17 2',
    if (shift) 'Key 16 2',
  ].join('\n');
  final script = '''
\$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
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
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll", SetLastError=true)]
  public static extern uint SendInput(uint n, Input[] input, int size);
}
'@
if ([IntPtr]::Size -ne 8) { throw 'Only the native x64/arm64 test runners are supported.' }
function Key([uint16]\$vk, [uint32]\$flags) {
  [uint32]\$owner = 0
  [void][OwnedInput]::GetWindowThreadProcessId([OwnedInput]::GetForegroundWindow(), [ref]\$owner)
  if (\$owner -ne $pid) { throw 'Owned test window is not foreground; no keys sent.' }
  \$input = New-Object OwnedInput+Input
  \$input.type = 1
  \$keyboard = New-Object OwnedInput+Keyboard
  \$keyboard.vk = \$vk
  \$keyboard.flags = \$flags
  \$input.keyboard = \$keyboard
  if ([OwnedInput]::SendInput(1, @(\$input), 40) -ne 1) { throw 'Win32 rejected native keyboard input.' }
  Start-Sleep -Milliseconds 60
}
try {
$sequence
} finally {
  # Release the modifier only while the same owned window still has focus.
  if (${control ? '\$true' : '\$false'}) { Key 17 2 }
  if (${shift ? '\$true' : '\$false'}) { Key 16 2 }
}
''';
  final result = await Process.run(
    'powershell.exe',
    ['-NoProfile', '-NonInteractive', '-Command', script],
  ).timeout(const Duration(seconds: 20));
  if (result.exitCode != 0) {
    throw StateError('Native keyboard input failed: ${result.stderr}');
  }
}
