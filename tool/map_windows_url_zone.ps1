param(
  [Parameter(Mandatory = $true)]
  [uri]$Url
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[ComImport]
[Guid("79EAC9EE-BAF9-11CE-8C82-00AA004BA90B")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IInternetSecurityManager
{
    void SetSecuritySite(IntPtr site);
    void GetSecuritySite(out IntPtr site);
    [PreserveSig]
    int MapUrlToZone(
        [MarshalAs(UnmanagedType.LPWStr)] string url,
        out int zone,
        int flags);
}

public static class UrlZone
{
    [DllImport("urlmon.dll", PreserveSig = true)]
    static extern int CoInternetCreateSecurityManager(
        IntPtr serviceProvider,
        out IInternetSecurityManager manager,
        int reserved);

    public static int Map(string url)
    {
        IInternetSecurityManager manager;
        Marshal.ThrowExceptionForHR(
            CoInternetCreateSecurityManager(IntPtr.Zero, out manager, 0));
        int zone;
        Marshal.ThrowExceptionForHR(manager.MapUrlToZone(url, out zone, 0));
        return zone;
    }
}
'@

[UrlZone]::Map($Url.AbsoluteUri)
