# Linnet

A native macOS music player with local AI integration. Plays music from the local filesystem with an Apple Music-inspired UI and uses MLX on Apple Silicon for smart playlist generation, recommendations, auto-tagging, and folder organization.

## Requirements

- macOS 15.0+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build

```bash
brew install xcodegen
xcodegen generate
xcodebuild build -project Linnet.xcodeproj -scheme Linnet -configuration Debug
```

## Test

```bash
swift test --package-path Packages/LinnetAudio
swift test --package-path Packages/LinnetLibrary
swift test --package-path Packages/LinnetAI
```

## Project Structure

```
Linnet/                  Main app target (SwiftUI)
Packages/
  LinnetAudio/           Audio engine — AVAudioEngine, gapless playback, EQ, queue
  LinnetLibrary/         Library management — SwiftData models, metadata, folder scanning
  LinnetAI/              AI features — MLX Swift, embeddings, recommendations, playlists
```

## Tech Stack

- Swift 6, SwiftUI, AVAudioEngine, SwiftData
- MLX Swift for on-device ML inference
- XcodeGen for project generation
- GitHub Actions CI with parallel package testing

## CI

Push to `main` or open a PR to run tests and build. Tag with `v*.*.*` to trigger a signed archive.
