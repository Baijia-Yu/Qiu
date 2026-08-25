# Qiu release signing and notarization

Qiu is distributed outside the Mac App Store. A public release therefore requires an Apple Developer Program membership, a `Developer ID Application` certificate with its private key, Hardened Runtime, a secure timestamp, and Apple notarization.

## One-time setup

1. In the Apple Developer portal, create a `Developer ID Application` certificate.
2. Install the downloaded certificate on the build Mac. Keychain Access must show the certificate and its private key under **My Certificates**.
3. Confirm that the identity is available:

   ```bash
   security find-identity -v -p codesigning
   ```

4. Create an app-specific password for the Apple ID and store the notarization credentials in the login keychain:

   ```bash
   ./Tools/store_notary_credentials.sh qiu-notary
   ```

Do not commit certificates, private keys, passwords, API keys, or exported `.p12` files. The repository ignores common signing-secret formats.

## Build a local DMG

The following command produces an ad-hoc signed image whose filename ends in `-development.dmg`. It is only for layout testing; Gatekeeper does not treat it as a public release:

```bash
./Tools/build_dmg.sh
```

## Create the public release artifact

Use the exact identity printed by `security find-identity`:

```bash
export QIU_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export QIU_NOTARY_PROFILE='qiu-notary'
./Tools/notarize_release.sh
```

The release script:

1. Builds Qiu in Release configuration.
2. Signs `Qiu.app` with Hardened Runtime and a secure timestamp.
3. Creates a compressed DMG containing Qiu and an Applications shortcut.
4. Signs the DMG and submits it with `notarytool`.
5. Staples and validates the notarization ticket.
6. Runs code-signing and Gatekeeper assessments.

Only upload the DMG when every step succeeds. The generated filename includes the app version and build architecture.
