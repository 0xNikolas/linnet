# CI Pipeline Design

## Overview

GitHub Actions pipeline for the Linnet macOS app. Single workflow file with three jobs: test packages in parallel, build the full app, and archive on release tags.

## Triggers

- **Push to main** — build + test
- **Pull requests to main** — build + test
- **Tags matching `v*.*.*`** — build + test + archive

## Jobs

### 1. `test-packages`

Runs on all triggers. Uses `macos-15` runner (Apple Silicon, Xcode 16).

Matrix strategy tests three packages in parallel:
- `swift test --package-path Packages/LinnetAudio`
- `swift test --package-path Packages/LinnetLibrary`
- `swift test --package-path Packages/LinnetAI`

Caches `~/.swiftpm` keyed on each package's `Package.resolved` hash.

### 2. `build`

Depends on `test-packages`. Runs on all triggers.

1. Install XcodeGen via Homebrew (cached)
2. Run `xcodegen generate`
3. Build with `xcodebuild build -project Linnet.xcodeproj -scheme Linnet -configuration Debug`

Validates the full app compiles with all packages linked.

### 3. `archive`

Depends on `build`. Runs only on version tags (`v*.*.*`).

1. Decode signing certificate and provisioning profile from GitHub secrets
2. Create a temporary keychain, import the certificate
3. Run `xcodebuild archive` with Release configuration
4. Export the `.app` using `ExportOptions.plist`
5. Upload the archive as a GitHub Actions artifact
6. Tear down keychain and remove provisioning profiles (runs on success or failure)

### Required Secrets

| Secret | Description |
|--------|-------------|
| `BUILD_CERTIFICATE_BASE64` | Apple Distribution certificate (.p12), base64-encoded |
| `P12_PASSWORD` | Certificate password |
| `BUILD_PROVISION_PROFILE_BASE64` | Provisioning profile, base64-encoded |
| `KEYCHAIN_PASSWORD` | Temporary keychain password |
| `DEVELOPMENT_TEAM` | Apple team ID |

## Caching

- Swift Package Manager: `~/.swiftpm` keyed on `Package.resolved` hashes
- Homebrew: cached for XcodeGen installation in the build job
