# Repository Guidelines

## Project Structure and Module Organization
- `ios/` holds the iOS app, build system, and assets. Swift UI code lives in `ios/OpenBW-iOS/Sources/StarCraftApp`, the Objective-C++ bridge in `ios/OpenBW-iOS/Sources/OpenBWBridge`, and the platform renderer in `ios/OpenBW-iOS/Sources/OpenBWCore`.
- `openbw/` contains the core OpenBW engine (mostly header-only) plus bundled deps in `openbw/deps/`.
- `bwapi/` is the OpenBW-focused BWAPI fork; C++ tests and tooling live under `bwapi/bwapi/BWAPILIBTest`.
- `ios/Assets/` contains MPQ data and map files used at runtime.

## Build, Test, and Development Commands
Build the C++/Objective-C++ static libraries for the iOS simulator:
```bash
cd ios
mkdir -p build-sim
cd build-sim
cmake .. -DCMAKE_TOOLCHAIN_FILE=../ios-simulator.toolchain.cmake \
  -DCMAKE_BUILD_TYPE=Debug -GXcode
cmake --build . --config Debug
```
Build for device (arm64) by swapping the toolchain:
```bash
cmake .. -DCMAKE_TOOLCHAIN_FILE=../ios.toolchain.cmake \
  -DCMAKE_BUILD_TYPE=Release -GXcode
cmake --build . --config Release
```
Then open the app in Xcode (expects prebuilt libs in `ios/build-sim` or `ios/build-device`):
```bash
open ios/StarCraft.xcodeproj
```

## Coding Style and Naming Conventions
- Indentation: 4 spaces, no tabs, follow existing file formatting.
- C++/Objective-C++: C++14, ARC enabled for `.mm`, and `OpenBW*` prefixes for bridge types. When editing `bwapi/`, follow `bwapi/CONTRIBUTING.md` (Allman braces, spacing rules, naming).
- Swift: follow Apple naming (camelCase, type names in UpperCamelCase) and keep UI code in SwiftUI.

## Testing Guidelines
- There is no iOS XCTest target yet; add tests under `ios/OpenBW-iOS/Tests` if you introduce new Swift logic.
- `bwapi/bwapi/BWAPILIBTest` is the existing C++ test harness; it is Visual Studio oriented. If you add BWAPI tests, keep them co-located there.

## Commit and Pull Request Guidelines
- Git history is not available in this checkout, so no repo-specific commit convention is visible. Use short, imperative subject lines and add a brief body when the change is non-trivial.
- PRs should describe the change, list build/test commands you ran, and include screenshots or screen recordings for UI or rendering changes. Call out any MPQ asset updates and licensing constraints.

## Configuration and Assets
- The app requires `Stardat.mpq`, `Broodat.mpq`, and `Patch_rt.mpq` (StarCraft 1.16.1/1.18) to load and run. Ensure `OpenBWConfig.mapPath` points to valid assets.
