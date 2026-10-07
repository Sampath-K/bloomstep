using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;

public static class ProcessTokenProbe {
  [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool GetTokenInformation(IntPtr token, int type, IntPtr buffer, int size, out int needed);
  static IntPtr Token(int pid) {
    var process = OpenProcess(0x1000, false, pid);
    if (process == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
    try {
      IntPtr token;
      if (!OpenProcessToken(process, 8, out token)) throw new Win32Exception(Marshal.GetLastWin32Error());
      return token;
    } finally { CloseHandle(process); }
  }
  public static bool Elevated(int pid) {
    var token = Token(pid);
    var buffer = Marshal.AllocHGlobal(4);
    try {
      int needed;
      if (!GetTokenInformation(token, 20, buffer, 4, out needed)) throw new Win32Exception(Marshal.GetLastWin32Error());
      return Marshal.ReadInt32(buffer) != 0;
    } finally { Marshal.FreeHGlobal(buffer); CloseHandle(token); }
  }
  public static string Sid(int pid) {
    var token = Token(pid);
    IntPtr buffer = IntPtr.Zero;
    try {
      int needed;
      GetTokenInformation(token, 1, IntPtr.Zero, 0, out needed);
      if (needed <= 0) throw new Win32Exception(Marshal.GetLastWin32Error());
      buffer = Marshal.AllocHGlobal(needed);
      if (!GetTokenInformation(token, 1, buffer, needed, out needed)) throw new Win32Exception(Marshal.GetLastWin32Error());
      return new SecurityIdentifier(Marshal.ReadIntPtr(buffer)).Value;
    } finally { if (buffer != IntPtr.Zero) Marshal.FreeHGlobal(buffer); CloseHandle(token); }
  }
}
