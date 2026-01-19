# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

iOS port of StarCraft: Brood War using OpenBW (open-source StarCraft engine). Three main components:

1. **OpenBW** (`openbw/`) - Core StarCraft engine (header-only C++ library)
2. **BWAPI** (`bwapi/`) - Bot API fork (not currently integrated into iOS build)
3. **iOS Application** (`ios/`) - Native iOS/Swift wrapper with Metal rendering

## Architecture

### Three-Layer Bridge Design

```
Swift UI Layer (StarCraftApp/)
    ↓ Bridging Header
Objective-C++ Bridge (OpenBWBridge/)
    ↓ Direct C++ access
OpenBW Core (OpenBWCore/)
    ↓ Includes
OpenBW Engine (openbw/)
```

**OpenBW Core** (`ios/OpenBW-iOS/Sources/OpenBWCore/`):
- `OpenBWGameRunner.mm` - Main game loop, sprite collection, melee game setup
- `OpenBWRenderer.mm` - GRP sprite rendering, RLE decoder, selection circles, health bars
- `MetalRenderer.mm` - Converts indexed framebuffer to Metal textures
- `MPQLoader.mm` - StarCraft MPQ asset loading
- Built as `libopenbw_core.a` + `libopenbw_ios_platform.a`

**Objective-C++ Bridge** (`ios/OpenBW-iOS/Sources/OpenBWBridge/`):
- `OpenBWBridge.h/.mm` - Exposes `OpenBWEngine`, `OpenBWGameState`, `OpenBWUnit`, `OpenBWConfig`
- Only Objective-C compatible types exposed to Swift (no C++ in headers)
- Built as `libopenbw_bridge.a`

**Swift UI Layer** (`ios/OpenBW-iOS/Sources/StarCraftApp/`):
- `MetalGameView.swift` - Metal rendering view with game controller
- `TouchInputManager.swift` - Touch gesture handling for RTS controls
- `GameView.swift` - Main game view controller

### Rendering Pipeline

```
OpenBW game state (sprites_on_tile_line)
    ↓ collectVisibleSprites() - depth sort by elevation/y/turret
    ↓ buildSpriteRenderInfo() - extract GRP frames, positions
OpenBWRenderer (indexed 8-bit framebuffer)
    ↓ draw_grp_frame() - RLE decode with player color remap
    ↓ palette lookup
MetalRenderer (RGBA texture)
    ↓ MTLTexture upload
Metal display
```

## Build Commands

### Build C++ Libraries (Required First)

```bash
# iOS Simulator
cd ios && mkdir -p build-sim && cd build-sim
cmake .. -DCMAKE_TOOLCHAIN_FILE=../ios-simulator.toolchain.cmake -DCMAKE_BUILD_TYPE=Debug -GXcode
cmake --build . --config Debug

# iOS Device
cd ios && mkdir -p build-device && cd build-device
cmake .. -DCMAKE_TOOLCHAIN_FILE=../ios.toolchain.cmake -DCMAKE_BUILD_TYPE=Release -GXcode
cmake --build . --config Release
```

### Build iOS App

```bash
# Via Xcode
open ios/StarCraft.xcodeproj

# Via command line
cd ios && xcodebuild -project StarCraft.xcodeproj -scheme StarCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build
```

### Install and Run on Simulator

```bash
# Install app
xcrun simctl install booted /path/to/DerivedData/.../Debug-iphonesimulator/StarCraft.app

# Copy MPQ assets to app Documents folder
APP_DATA=$(xcrun simctl get_app_container booted com.openbw.starcraft data)
mkdir -p "$APP_DATA/Documents"
cp ios/Assets/*.mpq "$APP_DATA/Documents/"
cp -r ios/Assets/maps "$APP_DATA/Documents/"

# Launch
xcrun simctl launch booted com.openbw.starcraft
```

**Bundle identifier**: `com.openbw.starcraft`

## Required Assets

MPQ files from StarCraft: Brood War 1.16.1 or 1.18:
- `StarDat.mpq` (~60MB)
- `BrooDat.mpq` (~24MB)
- `Patch_rt.mpq` (~1MB)

Place in `ios/Assets/` for development, copied to simulator Documents at runtime.

## Key Dependencies

- OpenBW: Header-only, requires `ASIO_STANDALONE`, `ASIO_NO_DEPRECATED`, `OPENBW_HEADLESS=1`
- ASIO bundled in `openbw/deps/asio/`
- iOS deployment target: 15.0+, Universal (iPhone + iPad)

## Code Conventions

- **C++**: C++14, header-only OpenBW patterns
- **Objective-C++**: ARC enabled (`-fobjc-arc`), `OpenBW*` class prefix, `NS_ASSUME_NONNULL` blocks
- **Swift**: SwiftUI, Apple naming conventions, `@Published` for reactive state

## Troubleshooting

**Library not found**: Verify CMake build completed and `LIBRARY_SEARCH_PATHS` in Xcode points to `build-sim/Debug-iphonesimulator/`

**MPQ loading failures**: Check files exist in simulator's app Documents folder (use `xcrun simctl get_app_container`)

**App won't launch**: Verify correct bundle ID (`com.openbw.starcraft`), reinstall with `xcrun simctl uninstall/install`
