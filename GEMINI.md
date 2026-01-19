# StarCraft: Brood War for iOS (OpenBW Port)

## Project Overview
This project is a native iOS port of StarCraft: Brood War, utilizing the **OpenBW** open-source engine and a modified **BWAPI** fork. It aims to run StarCraft on iPhone and iPad with a custom touch interface and Metal-based rendering.

**Key Technologies:**
*   **OpenBW**: C++ header-only library implementing the core StarCraft engine.
*   **SwiftUI**: Used for the application UI and game views.
*   **Metal**: Used for high-performance rendering of the game state.
*   **Objective-C++**: Bridges the C++ game engine with the Swift UI.
*   **CMake**: Manages the build process for the C++ static libraries.

## Architecture
The application follows a three-layer architecture to bridge C++ and Swift:

1.  **OpenBW Core** (`ios/OpenBW-iOS/Sources/OpenBWCore/`)
    *   Contains the C++ game engine implementation.
    *   `ios_platform.mm`, `MetalRenderer.mm`: iOS-specific platform integration.
    *   `openbw_instantiate.cpp`: Instantiates OpenBW templates.
    *   Compiled into `libopenbw_core.a`.

2.  **Objective-C++ Bridge** (`ios/OpenBW-iOS/Sources/OpenBWBridge/`)
    *   Exposes a Swift-friendly API (`OpenBWEngine`, `OpenBWGameState`).
    *   Handles data marshaling between C++ engine structures and Swift objects.
    *   Compiled into `libopenbw_bridge.a`.

3.  **Swift UI Layer** (`ios/OpenBW-iOS/Sources/StarCraftApp/`)
    *   `StarCraftApp.swift`: App entry point.
    *   `GameView.swift` & `MetalGameView.swift`: Views for rendering the game.
    *   `TouchInputManager.swift`: Maps touch gestures to RTS commands.

## Directory Structure
*   `ios/` - Main iOS project directory containing Xcode project (`StarCraft.xcodeproj`), source code (`OpenBW-iOS/`), and build scripts.
*   `openbw/` - The OpenBW core engine (submodule/dependency). Mostly header-only C++.
*   `bwapi/` - Modified BWAPI fork. **Note:** Currently not integrated into the iOS build (intended for future bot support).
*   `ios/Assets/` - Directory for runtime assets (MPQ files).

## Building and Running

### Prerequisites
*   **Xcode 13+**
*   **CMake 3.21+**
*   **Game Assets**: You must provide `Stardat.mpq`, `Broodat.mpq`, and `Patch_rt.mpq` (from StarCraft v1.16.1 or v1.18).

### 1. Build C++ Static Libraries
The C++ libraries must be built via CMake *before* running the Xcode project.

**For iOS Simulator:**
```bash
cd ios
mkdir -p build-sim && cd build-sim
cmake .. -DCMAKE_TOOLCHAIN_FILE=../ios-simulator.toolchain.cmake \
         -DCMAKE_BUILD_TYPE=Debug \
         -GXcode
cmake --build . --config Debug
```

**For iOS Device:**
```bash
cd ios
mkdir -p build-device && cd build-device
cmake .. -DCMAKE_TOOLCHAIN_FILE=../ios.toolchain.cmake \
         -DCMAKE_BUILD_TYPE=Release \
         -GXcode
cmake --build . --config Release
```

### 2. Build iOS App
1.  Open `ios/StarCraft.xcodeproj` in Xcode.
2.  Ensure `LIBRARY_SEARCH_PATHS` points to your build directory (e.g., `build-sim/Debug-iphonesimulator` or `build-device/Release-iphoneos`).
3.  Select the target (Simulator or Device) and Run (`Cmd+R`).

## Development Conventions

*   **Swift**: Follow standard Apple conventions (CamelCase). Use `@Published` for reactive state in SwiftUI.
*   **Objective-C++ (.mm)**: Use ARC. Prefix bridge classes with `OpenBW` (e.g., `OpenBWEngine`). Ensure `NS_ASSUME_NONNULL` blocks are used.
*   **C++**: C++14 standard. Follow OpenBW style (often header-only, file-scoped types).
*   **Rendering**: The project uses a custom Metal renderer (`MetalRenderer.mm`), bypassing OpenBW's default SDL/software rendering.
*   **Input**: Touch inputs are processed in Swift (`TouchInputManager`) and translated to game commands via the Bridge.

## Key Files
*   `CLAUDE.md`: Comprehensive project documentation and guide.
*   `ios/CMakeLists.txt`: Build configuration for the C++ layers.
*   `ios/OpenBW-iOS/Package.swift`: Swift package definition (if used via SPM).
*   `ios/OpenBW-iOS/Sources/StarCraftApp/StarCraftApp.swift`: Main application entry point.
