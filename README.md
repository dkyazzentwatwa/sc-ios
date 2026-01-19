# StarCraft: Brood War for iOS

A native iOS port of StarCraft: Brood War using [OpenBW](https://github.com/OpenBW/openbw), bringing the classic RTS experience to iPhone and iPad with touch controls and Metal-accelerated rendering.

[![Platform](https://img.shields.io/badge/platform-iOS%2015.0%2B-blue.svg)](https://www.apple.com/ios/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## 🎮 Features

- **Full StarCraft Experience**: Play melee games with all original units, buildings, and mechanics
- **Native iOS Integration**: Built with Swift and UIKit/SwiftUI for smooth iOS performance
- **Touch Controls**: Custom RTS touch interface for unit selection, movement, and commands
- **Metal Rendering**: Hardware-accelerated graphics using Apple's Metal framework
- **Original Assets**: Uses authentic StarCraft MPQ archives for sprites, sounds, and maps
- **Universal App**: Optimized for both iPhone and iPad

## 📱 Screenshots

*Coming soon - contributions of gameplay screenshots welcome!*

## 🏗️ Architecture

The project uses a three-layer bridge architecture to connect Swift UI with the C++ OpenBW engine:

```
┌─────────────────────────────────────┐
│   Swift UI Layer                    │
│   (StarCraftApp/)                   │
│   - MetalGameView.swift             │
│   - TouchInputManager.swift         │
└─────────────────┬───────────────────┘
                  │ Bridging Header
┌─────────────────▼───────────────────┐
│   Objective-C++ Bridge              │
│   (OpenBWBridge/)                   │
│   - OpenBWBridge.h/mm               │
│   - Exposes game state to Swift     │
└─────────────────┬───────────────────┘
                  │ Direct C++ Access
┌─────────────────▼───────────────────┐
│   OpenBW Core                       │
│   (OpenBWCore/)                     │
│   - OpenBWGameRunner.mm             │
│   - OpenBWRenderer.mm               │
│   - MetalRenderer.mm                │
│   - MPQLoader.mm                    │
└─────────────────┬───────────────────┘
                  │ C++ Includes
┌─────────────────▼───────────────────┐
│   OpenBW Engine                     │
│   (openbw/ submodule)               │
│   - Header-only C++ library         │
│   - Core StarCraft game logic       │
└─────────────────────────────────────┘
```

### Key Components

#### OpenBW Core (`ios/OpenBW-iOS/Sources/OpenBWCore/`)
- **OpenBWGameRunner.mm**: Main game loop, sprite collection, melee game initialization
- **OpenBWRenderer.mm**: GRP sprite rendering with RLE decompression, selection circles, health bars
- **MetalRenderer.mm**: Converts 8-bit indexed framebuffer to RGBA Metal textures
- **MPQLoader.mm**: StarCraft MPQ asset archive loading

#### Objective-C++ Bridge (`ios/OpenBW-iOS/Sources/OpenBWBridge/`)
- **OpenBWBridge.h/.mm**: Exposes `OpenBWEngine`, `OpenBWGameState`, `OpenBWUnit` classes to Swift
- Only uses Objective-C compatible types (no C++ in headers visible to Swift)

#### Swift UI Layer (`ios/OpenBW-iOS/Sources/StarCraftApp/`)
- **MetalGameView.swift**: Metal rendering view with integrated game controller
- **TouchInputManager.swift**: Touch gesture handling optimized for RTS gameplay
- **GameView.swift**: Main game view controller

## 📋 Prerequisites

### Required Tools
- **Xcode 14.0+** with iOS SDK
- **CMake 3.20+**
- **Git** with submodules support
- **iOS 15.0+** device or simulator

### Required Assets
You must provide your own StarCraft: Brood War game files (version 1.16.1 or 1.18):

- `StarDat.mpq` (~60MB)
- `BrooDat.mpq` (~24MB)
- `Patch_rt.mpq` (~1MB)

**Note**: This project does not include game assets. You must own a legitimate copy of StarCraft: Brood War.

## 🚀 Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/sc-ios.git
cd sc-ios
git submodule update --init --recursive
```

### 2. Build C++ Libraries

The iOS app depends on C++ libraries that must be built first using CMake.

#### For iOS Simulator (x86_64/arm64)

```bash
cd ios
mkdir -p build-sim
cd build-sim
cmake .. -DCMAKE_TOOLCHAIN_FILE=../ios-simulator.toolchain.cmake \
         -DCMAKE_BUILD_TYPE=Debug \
         -GXcode
cmake --build . --config Debug
cd ../..
```

#### For iOS Device (arm64)

```bash
cd ios
mkdir -p build-device
cd build-device
cmake .. -DCMAKE_TOOLCHAIN_FILE=../ios.toolchain.cmake \
         -DCMAKE_BUILD_TYPE=Release \
         -GXcode
cmake --build . --config Release
cd ../..
```

### 3. Copy StarCraft Assets

Place your StarCraft MPQ files in the assets directory:

```bash
mkdir -p ios/Assets
cp /path/to/your/starcraft/StarDat.mpq ios/Assets/
cp /path/to/your/starcraft/BrooDat.mpq ios/Assets/
cp /path/to/your/starcraft/Patch_rt.mpq ios/Assets/
cp -r /path/to/your/starcraft/maps ios/Assets/
```

### 4. Build and Run the iOS App

#### Using Xcode (Recommended)

```bash
open ios/StarCraft.xcodeproj
```

1. Select your target device or simulator
2. Build and run (⌘R)

#### Using Command Line

```bash
cd ios
xcodebuild -project StarCraft.xcodeproj \
           -scheme StarCraft \
           -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
           -configuration Debug \
           build
```

### 5. Install Assets on Simulator

The app needs MPQ files in its Documents folder at runtime:

```bash
# Install the app
xcrun simctl install booted /path/to/DerivedData/.../Debug-iphonesimulator/StarCraft.app

# Copy assets to app's Documents directory
APP_DATA=$(xcrun simctl get_app_container booted com.openbw.starcraft data)
mkdir -p "$APP_DATA/Documents"
cp ios/Assets/*.mpq "$APP_DATA/Documents/"
cp -r ios/Assets/maps "$APP_DATA/Documents/"

# Launch the app
xcrun simctl launch booted com.openbw.starcraft
```

## 🎯 Roadmap

### Current Status
- ✅ Core game engine integration
- ✅ Basic rendering pipeline
- ✅ Touch input handling
- ✅ MPQ asset loading
- ✅ Melee game support

### Planned Features
- [ ] Multiplayer support (LAN/Internet)
- [ ] Campaign mode
- [ ] Replay system
- [ ] Sound and music playback
- [ ] Advanced touch gestures (pinch-to-zoom, multi-select)
- [ ] Game speed controls
- [ ] Save/load game state
- [ ] Settings and configuration UI
- [ ] Map editor integration
- [ ] Bot/AI integration via BWAPI

### Future Enhancements
- [ ] iPadOS optimizations (mouse/keyboard support)
- [ ] Game Center integration
- [ ] Cloud save synchronization
- [ ] Performance profiling and optimization
- [ ] Accessibility features

## 🛠️ Development

### Project Structure

```
sc-ios/
├── openbw/              # OpenBW engine (git submodule)
├── bwapi/               # BWAPI fork (not yet integrated)
├── ios/
│   ├── StarCraft.xcodeproj
│   ├── Assets/          # MPQ files (not in repo)
│   ├── OpenBW-iOS/
│   │   └── Sources/
│   │       ├── OpenBWCore/      # C++ game engine wrapper
│   │       ├── OpenBWBridge/    # Objective-C++ bridge
│   │       └── StarCraftApp/    # Swift UI layer
│   ├── build-sim/       # CMake build output (simulator)
│   └── build-device/    # CMake build output (device)
├── CLAUDE.md            # AI assistant guidance
└── README.md            # This file
```

### Building for Different Configurations

```bash
# Debug build (simulator)
cmake .. -DCMAKE_BUILD_TYPE=Debug -DCMAKE_TOOLCHAIN_FILE=../ios-simulator.toolchain.cmake
cmake --build . --config Debug

# Release build (device)
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE=../ios.toolchain.cmake
cmake --build . --config Release
```

### Code Conventions

- **C++**: C++14 standard, header-only patterns for OpenBW integration
- **Objective-C++**: ARC enabled, `OpenBW*` class prefix, `NS_ASSUME_NONNULL` blocks
- **Swift**: SwiftUI where possible, Apple naming conventions, `@Published` for reactive state

### Debugging

Enable debug logging in `OpenBWGameRunner.mm`:

```cpp
#define OPENBW_DEBUG 1
```

View console logs in Xcode's debug area or via:

```bash
xcrun simctl spawn booted log stream --predicate 'processImagePath contains "StarCraft"'
```

## 🐛 Troubleshooting

### Library Not Found Errors
Ensure CMake build completed successfully and Xcode's `LIBRARY_SEARCH_PATHS` points to:
- `$(PROJECT_DIR)/build-sim/Debug-iphonesimulator/` (simulator)
- `$(PROJECT_DIR)/build-device/Release-iphoneos/` (device)

### MPQ Loading Failures
1. Verify MPQ files exist in simulator's Documents folder:
   ```bash
   APP_DATA=$(xcrun simctl get_app_container booted com.openbw.starcraft data)
   ls -lh "$APP_DATA/Documents/"
   ```
2. Check file permissions (should be readable)
3. Verify MPQ files are from version 1.16.1 or 1.18

### App Won't Launch
1. Verify bundle identifier: `com.openbw.starcraft`
2. Reinstall the app:
   ```bash
   xcrun simctl uninstall booted com.openbw.starcraft
   xcrun simctl install booted /path/to/StarCraft.app
   ```
3. Check Xcode signing settings

### Build Errors
- **"asio.hpp not found"**: Run `git submodule update --init --recursive`
- **"Unknown type name 'OpenBWEngine'"**: Clean build folder and rebuild C++ libraries
- **Linker errors**: Ensure both `libopenbw_core.a` and `libopenbw_ios_platform.a` are built

## 🤝 Contributing

Contributions are welcome! This project needs help with:

- **iOS UI/UX**: Improving touch controls and game interface
- **Performance**: Optimizing rendering and game loop
- **Features**: Implementing sound, multiplayer, campaigns
- **Testing**: Bug reports and compatibility testing
- **Documentation**: Code comments, guides, tutorials

### How to Contribute

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test thoroughly on both simulator and device
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

Please ensure:
- Code follows existing conventions
- No game assets are committed to the repository
- Changes don't break existing functionality
- Include tests where appropriate

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

**Important**: While this code is MIT licensed, you must own a legitimate copy of StarCraft: Brood War to use this software. This project does not include or distribute any Blizzard Entertainment assets.

## 🙏 Acknowledgments

- **[OpenBW](https://github.com/OpenBW/openbw)** - The open-source StarCraft engine that makes this possible
- **[BWAPI](https://github.com/bwapi/bwapi)** - Bot API for StarCraft: Brood War
- **Blizzard Entertainment** - For creating the timeless classic that is StarCraft
- The StarCraft modding and reverse-engineering community

## 📧 Contact

- **Issues**: [GitHub Issues](https://github.com/yourusername/sc-ios/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/sc-ios/discussions)

## ⭐ Star History

If you find this project interesting, please consider giving it a star! It helps others discover the project and motivates continued development.

---

**Disclaimer**: This is an unofficial, fan-made project and is not affiliated with or endorsed by Blizzard Entertainment. StarCraft and StarCraft: Brood War are registered trademarks of Blizzard Entertainment, Inc.
