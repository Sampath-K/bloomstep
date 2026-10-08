# Bloomstep

Grow tiny habits into a flourishing garden. Inspired by the behavior design research of Dr. BJ Fogg.

Bloomstep is a Flutter app: Windows first (direct download, then Microsoft Store), then iOS/iPadOS, Android and macOS from the same code.

## Develop

```powershell
flutter pub get
flutter test --dart-define=BLOOMSTEP_TEST_BUILD=true
flutter run -d windows
flutter build windows --release
```

## Status

**Engineering preview, not the complete MVP.** The persistent garden and core
widget flows are implemented. The first garden screen has a compact profile;
signed-out users can plant into a separate device-only garden without sync or
analytics. Real provider sign-in opens the account-owned garden; there is no fake
login or automatic transfer of device habits. Provider/cloud acceptance remains
an independent gate.

See [product contract](docs/product-spec.md), [iteration/edge ledger](docs/status.md)
and [deployment prerequisites](docs/deployment.md). The current
[MVP exit matrix](docs/mvp-exit-matrix.md) records observed evidence and exact
remaining acceptance gates. Unattended non-provider engineering checks are
separate from deferred provider, actual Windows delivery and public-launch
acceptance; adapter acknowledgments are not delivery evidence.

The [synthetic acceptance harness](docs/synthetic-automation.md) is test-only;
it is not a production sign-in path or proof of provider, Cosmos, notification,
accessibility or population acceptance.

[Authentication observability](docs/auth-observability.md) documents the bounded,
account-consented session/token stages and explicitly unknown pre-auth/provider
coverage; it is not a complete sign-in funnel.

The small static website lives in `site`; authenticated Functions live in `api`.
CI tests and packages per-user unsigned Windows ARM64 and x64 preview installers
using Inno Setup. Tag releases are explicitly prereleases with checksums.

```powershell
cd api
npm ci
npm run check
npm test
```
