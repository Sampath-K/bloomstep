using System;
using System.Runtime.InteropServices;

public static class NativeArchitectureProbe {
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool IsWow64Process2(IntPtr process, out ushort processMachine, out ushort nativeMachine);
  [DllImport("kernel32.dll")]
  static extern IntPtr GetCurrentProcess();
  public static int Main(string[] args) {
    ushort processMachine, nativeMachine;
    if (!IsWow64Process2(GetCurrentProcess(), out processMachine, out nativeMachine)) {
      Console.Error.WriteLine("Native architecture query failed; no routing fallback.");
      return 1;
    }
    var architecture = nativeMachine == 0xaa64 ? "arm64" : nativeMachine == 0x8664 ? "x64" : "unsupported";
    Console.WriteLine("{\"nativeArchitecture\":\"" + architecture + "\",\"nativeMachine\":" + nativeMachine +
      ",\"processMachine\":" + processMachine + ",\"process64Bit\":" + Environment.Is64BitProcess.ToString().ToLowerInvariant() + "}");
    return args.Length == 1 && architecture == args[0] ? 0 : 1;
  }
}
