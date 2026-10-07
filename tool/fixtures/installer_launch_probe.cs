using System;
using System.IO;
using System.Security.Principal;

// Inert, isolated CI payload. This is not the Bloomstep app.
class InstallerLaunchProbe {
  static void Main() {
    var identity = WindowsIdentity.GetCurrent();
    var elevated = new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
    var destination = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "launch-proof-private.jsonl");
    File.AppendAllText(destination, "{\"sid\":\"" + identity.User.Value +
      "\",\"elevated\":" + (elevated ? "true" : "false") + "}" + Environment.NewLine);
  }
}
