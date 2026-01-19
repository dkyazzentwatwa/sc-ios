# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains an iOS port of StarCraft: Brood War using OpenBW (an open-source StarCraft engine) and a modified BWAPI fork. The project consists of three main components:

1. **OpenBW** (`openbw/`) - The core StarCraft engine (header-only C++ library)
2. **BWAPI** (`bwapi/`) - Bot API for OpenBW (modified fork)
3. **iOS Application** (`ios/`) - Native iOS/Swift wrapper with Metal rendering

## Architecture

### Three-Layer Design

The iOS port uses a three-layer architecture bridging C++ to Swift:

1. **OpenBW Core** (`ios/OpenBW-iOS/Sources/OpenBWCore/`)
   - `openbw_instantiate.cpp` - Template instantiation for header-only OpenBW library
   - `ios_platform.mm` - iOS-specific platform layer
   - `MetalRenderer.mm` - Metal-based rendering implementation
   - `OpenBWGameRunner.mm` - Main game loop and state management
   - `MPQLoader.mm` - StarCraft asset (MPQ file) loading
   - Built as static library `libopenbw_core.a`

2. **Objective-C++ Bridge** (`ios/OpenBW-iOS/Sources/OpenBWBridge/`)
   - `OpenBWBridge.h` - Objective-C interface exposing game engine to Swift
   - `OpenBWBridge.mm` - Implementation of the bridge layer
   - Defines `OpenBWEngine`, `OpenBWGameState`, `OpenBWUnit`, `OpenBWConfig` classes
   - Built as static library `libopenbw_bridge.a`

3. **Swift UI Layer** (`ios/OpenBW-iOS/Sources/StarCraftApp/`)
   - `StarCraftApp.swift` - SwiftUI app entry point
   - `OpenBW.swift` - Swift-friendly wrapper around OpenBWEngine
   - `MetalGameView.swift` - Metal rendering view
   - `GameView.swift` - Main game view controller
   - `TouchInputManager.swift` - Touch gesture handling for RTS controls
   - `StarCraft-Bridging-Header.h` - Swift/Objective-C++ bridging header

### Build System

The project uses a hybrid build system:

- **CMake** (`ios/CMakeLists.txt`) - Builds the C++/Objective-C++ libraries (openbw_core, openbw_ios_platform, openbw_bridge)
- **Xcode** (`ios/StarCraft.xcodeproj`) - Builds the Swift application and links static libraries
- **Cross-compilation toolchains**:
  - `ios/ios-simulator.toolchain.cmake` - iOS Simulator (x86_64/arm64)
  - `ios/ios.toolchain.cmake` - iOS Device (arm64)

## Common Development Commands

### Building C++ Libraries for iOS Simulator

```bash
cd ios
mkdir -p build-sim
cd build-sim
cmake .. -DCMAKE_TOOLCHAIN_FILE=../ios-simulator.toolchain.cmake \
         -DCMAKE_BUILD_TYPE=Debug \
         -GXcode
cmake --build . --config Debug
```

This generates:
- `build-sim/Debug-iphonesimulator/libopenbw_core.a`
- `build-sim/Debug-iphonesimulator/libopenbw_ios_platform.a`
- `build-sim/Debug-iphonesimulator/libopenbw_bridge.a`

For Release builds, use `-DCMAKE_BUILD_TYPE=Release` and `--config Release`.

### Building the iOS Application

Open `ios/StarCraft.xcodeproj` in Xcode:

```bash
open ios/StarCraft.xcodeproj
```

Then:
1. Select the StarCraft scheme
2. Choose iOS Simulator or Device target
3. Build with ⌘B or run with ⌘R

**Important**: The Xcode project expects pre-built static libraries in `build-sim/Debug-iphonesimulator/` or `build-sim/Release-iphonesimulator/`. Build these with CMake first.

### Building for iOS Device

```bash
cd ios
mkdir -p build-device
cd build-device
cmake .. -DCMAKE_TOOLCHAIN_FILE=../ios.toolchain.cmake \
         -DCMAKE_BUILD_TYPE=Release \
         -GXcode
cmake --build . --config Release
```

Update the Xcode project's `LIBRARY_SEARCH_PATHS` to point to `build-device/Release-iphoneos/`.

## Key Dependencies

### OpenBW Configuration

- OpenBW is mostly header-only (lives in `openbw/`)
- Key headers: `bwgame.h`, `actions.h`, `bwenums.h`, `data_loading.h`
- Dependencies bundled in `openbw/deps/`:
  - ASIO (standalone networking library) - must define `ASIO_STANDALONE` and `ASIO_NO_DEPRECATED`
- Built with `OPENBW_HEADLESS=1` (no built-in UI, using custom Metal renderer)

### BWAPI Integration

BWAPI source is in `bwapi/` but is **not currently integrated** into the iOS build. The iOS port directly uses OpenBW without the BWAPI abstraction layer. BWAPI is intended for future bot integration.

To build BWAPI separately (Linux/macOS):
```bash
cd bwapi
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release \
         -DOPENBW_DIR=../../openbw \
         -DOPENBW_ENABLE_UI=1
make
```

### Required Assets

The game requires three MPQ files from StarCraft: Brood War 1.16.1 or 1.18:
- `Stardat.mpq`
- `Broodat.mpq`
- `Patch_rt.mpq`

These are loaded via `MPQLoader.mm` and must be bundled with the iOS app or downloaded at runtime.

## Code Conventions

### C++ (OpenBW Core)

- C++14 standard
- Header-only design (templates in headers)
- Namespace: Generally no explicit namespace, uses file-scoped types
- Compilation with `-x objective-c++` and `-fobjc-arc` for `.mm` files

### Objective-C++ (Bridge Layer)

- Use ARC (Automatic Reference Counting) - enabled with `-fobjc-arc`
- Prefix classes with `OpenBW` (e.g., `OpenBWEngine`, `OpenBWGameState`)
- Use `NS_ASSUME_NONNULL_BEGIN/END` for nullability annotations
- Expose only Objective-C compatible types to Swift (no C++ types in headers)

### Swift (UI Layer)

- SwiftUI for UI
- Swift 5.0+
- Use `@Published` properties for observable game state
- Follow Apple's naming conventions (camelCase, descriptive names)

## Platform-Specific Notes

### Metal Rendering

The iOS port replaces OpenBW's SDL-based rendering with Metal:
- `MetalRenderer.mm` - Converts OpenBW's frame buffer to Metal textures
- `MetalGameView.swift` - SwiftUI view displaying Metal content
- Rendering happens via `OpenBWEngine.renderToTexture(_:)` method

### Touch Input Mapping

RTS controls adapted for touchscreen:
- Single tap: Select unit
- Tap and hold: Box select
- Double tap: Select all units of same type
- Two-finger pan: Move camera
- Pinch: Zoom in/out
- Tap on minimap: Jump camera

Implemented in `TouchInputManager.swift`.

### iOS-Specific Considerations

- **Deployment target**: iOS 15.0+ (set in CMakeLists.txt and Xcode project)
- **Supported devices**: iPhone and iPad (Universal, `TARGETED_DEVICE_FAMILY = "1,2"`)
- **Orientation**: Supports portrait and landscape
- **Frameworks**: UIKit, Metal, MetalKit, AVFoundation, AudioToolbox

## Troubleshooting

### Library Linking Errors in Xcode

If you see "library not found" errors:
1. Verify CMake build completed successfully
2. Check `LIBRARY_SEARCH_PATHS` in Xcode project settings points to correct build output directory
3. Ensure build configuration (Debug/Release) matches between CMake and Xcode

### Missing OpenBW Headers

If compilation fails with missing OpenBW headers:
1. Verify `OPENBW_DIR` is set correctly in `ios/CMakeLists.txt` (default: `../openbw`)
2. Check that `openbw/bwgame.h` exists

### MPQ Loading Failures

If game fails to start with asset errors:
1. Ensure MPQ files are accessible to the app
2. Check file paths in `OpenBWConfig.mapPath`
3. Verify MPQ files are from a compatible StarCraft version (1.16.1 or 1.18)
