# Releasing MouseBridge

English | [简体中文](RELEASING.zh-CN.md)

The release workflow is triggered by a semantic version tag. The tag must match
`CFBundleShortVersionString` in `Info.plist`.

## Preview release

Without Apple signing secrets, the workflow builds an ad-hoc signed archive and
publishes it as a GitHub pre-release:

```bash
git tag -a v0.2.0 -m "MouseBridge v0.2.0"
git push origin v0.2.0
```

## Signed and notarized release

Configure these GitHub Actions repository secrets before pushing the tag:

- `APPLE_CERTIFICATE_P12`: base64-encoded Developer ID Application `.p12`
- `APPLE_CERTIFICATE_PASSWORD`: password for the `.p12`
- `KEYCHAIN_PASSWORD`: optional temporary CI keychain password
- `APPLE_API_KEY_P8`: base64-encoded App Store Connect API private key
- `APPLE_API_KEY_ID`: App Store Connect API key ID
- `APPLE_API_ISSUER_ID`: App Store Connect API issuer ID

When all required Apple secrets are available, the workflow imports the
certificate into a temporary keychain, applies a hardened Developer ID
signature, submits the app to Apple's notary service, staples the ticket, and
publishes a normal GitHub Release.

Every release contains the app ZIP and a SHA-256 checksum. If any validation,
test, signature, notarization, or packaging step fails, no Release is created.
