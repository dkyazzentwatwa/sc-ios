// openbw_instantiate.cpp
// Instantiates OpenBW's header-only templates for the iOS build

// OpenBW is a header-only library, but we need at least one translation unit
// to compile. This file includes the main headers which triggers template
// instantiation.

// Prevent OpenBW from pulling in SDL2 UI
#define OPENBW_HEADLESS 1
#define OPENBW_NO_SDL_IMAGE 1
#define OPENBW_NO_SDL_MIXER 1

// Core game engine
#include "bwgame.h"
#include "actions.h"
#include "replay.h"
#include "replay_saver.h"

// Data loading (MPQ file handling)
#include "data_loading.h"

// Utility headers
#include "util.h"
#include "strf.h"
#include "containers.h"

// Synchronization for multiplayer (ASIO-based)
// Note: ASIO networking may need adaptation for iOS
#include "sync.h"

// This is a minimal instantiation to ensure the library compiles.
// Actual game instances are created by the iOS platform layer.

namespace openbw_ios {
    // Version info for debugging
    const char* getOpenBWVersion() {
        return "OpenBW (iOS Port)";
    }

    // Placeholder to ensure symbols are exported
    void initOpenBW() {
        // Initialization will be done by the platform layer
    }
}
