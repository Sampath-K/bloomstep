import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';

const xml = value => value.replaceAll('&', '&amp;').replaceAll('"', '&quot;')
  .replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll("'", '&apos;');

export function packageVersion(version) {
  const match = /^(\d+)\.(\d+)\.(\d+)(?:-preview(?:\.([1-9]\d*))?)?$/.exec(version);
  if (!match || match.slice(1, 4).some(part =>
    Number(part) > 65535 || String(Number(part)) !== part) ||
    (match[4] && Number(match[4]) >= 65535)) {
    throw Error('MSIX requires canonical major.minor.patch[-preview[.N]], components <=65535 and 1<=N<65535.');
  }
  return `${match[1]}.${match[2]}.${match[3]}.${match[4] ?? (version.endsWith('-preview') ? 0 : 65535)}`;
}

function identity(options) {
  const version = packageVersion(options.version);
  if (typeof options.publisher !== 'string' || !options.publisher.startsWith('CN=') ||
    /[\r\n]/.test(options.publisher)) {
    throw Error('Supply the approved code-signing certificate Subject (CN=...), not an invented publisher.');
  }
  return {
    version,
    channel: options.version.includes('-preview') ? 'preview' : 'stable',
    name: options.version.includes('-preview') ? 'Bloomstep.Desktop.Preview' : 'Bloomstep.Desktop.Stable',
    publisher: xml(options.publisher),
  };
}

export function packageManifest(options) {
  const { version, name, publisher } = identity(options);
  if (!['x64', 'arm64'].includes(options.architecture)) throw Error('Unsupported native architecture.');
  return `<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
 xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
 xmlns:uap10="http://schemas.microsoft.com/appx/manifest/uap/windows10/10"
 xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
 IgnorableNamespaces="uap uap10 rescap">
 <Identity Name="${name}" Publisher="${publisher}" Version="${version}" ProcessorArchitecture="${options.architecture}"/>
 <Properties><DisplayName>Bloomstep</DisplayName><PublisherDisplayName>Bloomstep</PublisherDisplayName><Logo>Assets\\StoreLogo.png</Logo></Properties>
 <Resources><Resource Language="en-US"/></Resources>
 <Dependencies><TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.22621.0"/></Dependencies>
 <Applications>
  <Application Id="Bloomstep" Executable="bloomstep.exe" uap10:RuntimeBehavior="win32App" uap10:TrustLevel="mediumIL">
   <uap:VisualElements DisplayName="Bloomstep" Description="Grow tiny habits into a flourishing garden."
    Square150x150Logo="Assets\\Logo150.png" Square44x44Logo="Assets\\Logo44.png" BackgroundColor="transparent"/>
   <Extensions><uap:Extension Category="windows.protocol"><uap:Protocol Name="bloomstep"/></uap:Extension></Extensions>
  </Application>
 </Applications>
 <Capabilities><rescap:Capability Name="runFullTrust"/></Capabilities>
</Package>
`;
}

export function appInstaller(options) {
  const { version, name, publisher, channel } = identity(options);
  return `<?xml version="1.0" encoding="utf-8"?>
<AppInstaller xmlns="http://schemas.microsoft.com/appx/appinstaller/2021"
 Uri="https://github.com/Sampath-K/bloomstep/releases/download/update-${channel}/Bloomstep.appinstaller" Version="${version}">
 <MainBundle Name="${name}" Publisher="${publisher}" Version="${version}"
  Uri="https://github.com/Sampath-K/bloomstep/releases/download/v${options.version}/Bloomstep-${options.version}.msixbundle"/>
 <UpdateSettings>
  <OnLaunch HoursBetweenUpdateChecks="0" ShowPrompt="false" UpdateBlocksActivation="false"/>
  <AutomaticBackgroundTask/>
 </UpdateSettings>
</AppInstaller>
`;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [output, version, publisher, architecture] = process.argv.slice(2);
  if (!output || !version || !publisher || !architecture || process.argv.length !== 6) {
    throw Error('Usage: node tool/msix_update.mjs OUTPUT VERSION PUBLISHER x64|arm64');
  }
  const manifest = packageManifest({ version, publisher, architecture });
  const feed = appInstaller({ version, publisher, architecture });
  mkdirSync(output, { recursive: true });
  writeFileSync(join(output, 'AppxManifest.xml'), manifest);
  writeFileSync(join(output, 'Bloomstep.appinstaller'), feed);
}
