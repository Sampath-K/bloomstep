# Bloomstep

Grow tiny habits into a flourishing garden. Inspired by the behavior design research of Dr. BJ Fogg.

Bloomstep is a Flutter app: Windows first (direct download, then Microsoft Store), then iOS/iPadOS, Android and macOS from the same code.

## Develop

```powershell
flutter pub get
flutter test
flutter run -d windows
flutter build windows --release
```

## Status

**Engineering preview, not the complete MVP.** The persistent garden and core
widget flows are implemented. Public builds are sign-in gated until real personal
identity/cloud services are provisioned and verified; there is no fake login.

See [product contract](docs/product-spec.md), [iteration/edge ledger](docs/status.md)
and [deployment prerequisites](docs/deployment.md). Windows reminders and cloud
round trips must be observed before claiming they work.

The small static website lives in `site`; authenticated Functions live in `api`.
CI tests and packages per-user unsigned Windows ARM64 and x64 preview installers
using Inno Setup. Tag releases are explicitly prereleases with checksums.

```powershell
cd api
npm ci
npm run check
npm test
```
