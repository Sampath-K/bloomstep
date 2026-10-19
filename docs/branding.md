# Budlark product identity

The product is **Budlark**, one word, at **budlark.com**. The owner authorized a
pre-launch clean break: no compatibility aliases for retired package names,
protocols, installation directories or state namespaces. Only owner trial
installations existed. Their local state is not migrated by this change.

## Source and installation

Flutter packages, platform bundle IDs, native binaries, repository links,
API authorization headers, local event/measurement namespaces, test fixtures,
configuration keys and documentation now use the Budlark identity.
`test/branding_contract_test.mjs`, run by CI, rejects the retired identity in
any tracked file or pathname, case-insensitively, with an empty allowlist.

The installer is `packaging/budlark.iss`. It installs `budlark.exe` under
`%LOCALAPPDATA%\Programs\Budlark`, creates Budlark shortcuts and registers the
`budlark:` invitation protocol. The existing AppId GUIDs are preserved so
Windows recognizes the installation for upgrades. Product state and installer
measurement receipts use the Budlark directory namespace. No retired protocol
cleanup or compatibility alias is added.

The API and app must ship together: clients and server use
`X-Budlark-Authorization`. Old deployed clients are not compatible with this
pre-launch change. No API deployment is implied by changing the source.

## Assets and evidence

The wing-and-bud mark, palette and original illustrations are retained.
Asset paths use the current name. Installer illustrations and their source
provenance must be re-exported through the existing hosted installer-art job;
do not manufacture hashes or relabel an export as a new rendering.

Historical prose and fixture identifiers have been normalized at the owner's
request. Recorded commit IDs and artifact digests are not new-build evidence.
The retired VM approach is aborted and its downloadable packages are removed.
Prior signoffs do not approve this clean-break identity: a new candidate, both
architecture installers and owner manual verification are required.

## External configuration

The coordinator owns the repository rename and Azure/Entra changes. Source
references target `Sampath-K/budlark`; this change does not rename or deploy any
external resource. Provider consent-page logos/display names, role claims,
resource names and sender identities need coordinated readback before launch.

Migrate these GitHub secrets before running provider-backed automation:

- `BUDLARK_TEST_A_EMAIL` and `BUDLARK_TEST_A_PASSWORD`
- `BUDLARK_TEST_B_EMAIL` and `BUDLARK_TEST_B_PASSWORD`
- `BUDLARK_TEST_ADMIN_EMAIL` and `BUDLARK_TEST_ADMIN_PASSWORD`

Migrate variables `BUDLARK_AUTOMATION_CLIENT_ID` and
`BUDLARK_AUTOMATION_PROVISIONING_RECEIPT` as well. The three CIAM test accounts
already exist; no additional account creation is needed. The provisioning
script migrates their exact dedicated identities in place and rotates their
passwords, without creating duplicates or changing the tenant's verified domain.
It discovers that existing domain from the pinned tenant's organization record.
The coordinator runs it only after the renamed API header and role are live.

No merge, release, deployment or installed functional redispatch is authorized.
The owner manually verifies the installed candidate and supplies
`PASS <exact installer SHA-256>`.
