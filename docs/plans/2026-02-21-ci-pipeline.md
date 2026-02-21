# CI Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a GitHub Actions CI pipeline that tests Swift packages in parallel, builds the full app, and archives on release tags.

**Architecture:** Single workflow file with three jobs chained by dependencies. Matrix strategy for parallel package testing. Conditional archive job triggered only on version tags. Apple codesigning via temporary keychain from GitHub secrets.

**Tech Stack:** GitHub Actions, macOS 15 runners, Xcode 16, XcodeGen, Swift Package Manager

**Design doc:** `docs/plans/2026-02-21-ci-pipeline-design.md`

---

## Task 1: Create the CI workflow file

**Files:**
- Create: `.github/workflows/ci.yml`

**Step 1: Create the workflow file**

```yaml
name: CI

on:
  push:
    branches: [main]
    tags: ['v*.*.*']
  pull_request:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test-packages:
    name: Test ${{ matrix.package }}
    runs-on: macos-15
    strategy:
      fail-fast: false
      matrix:
        package: [LinnetAudio, LinnetLibrary, LinnetAI]
    steps:
      - uses: actions/checkout@v4

      - name: Cache SPM
        uses: actions/cache@v4
        with:
          path: Packages/${{ matrix.package }}/.build
          key: spm-${{ matrix.package }}-${{ hashFiles('Packages/${{ matrix.package }}/Package.resolved', 'Packages/${{ matrix.package }}/Package.swift') }}
          restore-keys: spm-${{ matrix.package }}-

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.app

      - name: Run tests
        run: swift test --package-path Packages/${{ matrix.package }}

  build:
    name: Build App
    needs: test-packages
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.app

      - name: Cache Homebrew
        uses: actions/cache@v4
        with:
          path: |
            ~/Library/Caches/Homebrew
            /usr/local/Cellar/xcodegen
          key: brew-xcodegen-${{ runner.os }}

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate Xcode project
        run: xcodegen generate

      - name: Build
        run: |
          xcodebuild build \
            -project Linnet.xcodeproj \
            -scheme Linnet \
            -configuration Debug \
            -destination 'generic/platform=macOS' \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO

  archive:
    name: Archive
    needs: build
    runs-on: macos-15
    if: startsWith(github.ref, 'refs/tags/v')
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.app

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate Xcode project
        run: xcodegen generate

      - name: Install certificate and provisioning profile
        env:
          BUILD_CERTIFICATE_BASE64: ${{ secrets.BUILD_CERTIFICATE_BASE64 }}
          P12_PASSWORD: ${{ secrets.P12_PASSWORD }}
          BUILD_PROVISION_PROFILE_BASE64: ${{ secrets.BUILD_PROVISION_PROFILE_BASE64 }}
          KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          CERTIFICATE_PATH=$RUNNER_TEMP/build_certificate.p12
          PP_PATH=$RUNNER_TEMP/build_pp.provisionprofile
          KEYCHAIN_PATH=$RUNNER_TEMP/app-signing.keychain-db

          echo -n "$BUILD_CERTIFICATE_BASE64" | base64 --decode -o $CERTIFICATE_PATH
          echo -n "$BUILD_PROVISION_PROFILE_BASE64" | base64 --decode -o $PP_PATH

          security create-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
          security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH

          security import $CERTIFICATE_PATH -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k $KEYCHAIN_PATH
          security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
          security list-keychain -d user -s $KEYCHAIN_PATH

          mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
          cp $PP_PATH ~/Library/MobileDevice/Provisioning\ Profiles

      - name: Archive
        env:
          DEVELOPMENT_TEAM: ${{ secrets.DEVELOPMENT_TEAM }}
        run: |
          xcodebuild archive \
            -project Linnet.xcodeproj \
            -scheme Linnet \
            -configuration Release \
            -destination 'generic/platform=macOS' \
            -archivePath $RUNNER_TEMP/Linnet.xcarchive \
            DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"

      - name: Export archive
        run: |
          xcodebuild -exportArchive \
            -archivePath $RUNNER_TEMP/Linnet.xcarchive \
            -exportOptionsPlist ExportOptions.plist \
            -exportPath $RUNNER_TEMP/export

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: Linnet-${{ github.ref_name }}
          path: ${{ runner.temp }}/export/

      - name: Cleanup keychain
        if: always()
        run: |
          security delete-keychain $RUNNER_TEMP/app-signing.keychain-db || true
          rm -f ~/Library/MobileDevice/Provisioning\ Profiles/build_pp.provisionprofile || true
```

**Step 2: Validate the YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"`
Expected: No output (valid YAML)

**Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add GitHub Actions pipeline with test, build, and archive jobs"
```

---

## Task 2: Push and verify the pipeline runs

**Step 1: Push to main**

Run: `git push`

**Step 2: Check the workflow run**

Run: `gh run list --limit 1`
Expected: A new run appears with status "in_progress" or "completed"

**Step 3: Watch the run**

Run: `gh run watch`
Expected: test-packages (3 parallel) and build jobs succeed. Archive skipped (no tag).

---

## Summary

| Task | Description |
|------|-------------|
| 1 | Create `.github/workflows/ci.yml` with all three jobs |
| 2 | Push and verify the pipeline runs |
