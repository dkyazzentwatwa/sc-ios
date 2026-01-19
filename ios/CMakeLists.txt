cmake_minimum_required(VERSION 3.21)

project(OpenBW-iOS
    VERSION 0.1.0
    LANGUAGES C CXX OBJCXX
    DESCRIPTION "StarCraft: Brood War for iOS via OpenBW"
)

# C++ Standard
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Paths to OpenBW
set(OPENBW_DIR "${CMAKE_SOURCE_DIR}/../openbw" CACHE PATH "Path to OpenBW source")
set(BWAPI_DIR "${CMAKE_SOURCE_DIR}/../bwapi" CACHE PATH "Path to BWAPI source")

# Verify OpenBW exists
if(NOT EXISTS "${OPENBW_DIR}/bwgame.h")
    message(FATAL_ERROR "OpenBW not found at ${OPENBW_DIR}. Please set OPENBW_DIR correctly.")
endif()

message(STATUS "OpenBW directory: ${OPENBW_DIR}")
message(STATUS "BWAPI directory: ${BWAPI_DIR}")

# ============================================================================
# OpenBW Core Library (header-only + platform layer)
# ============================================================================

add_library(openbw_core STATIC
    # OpenBW is mostly header-only, but we need a translation unit
    # to instantiate templates and provide the game implementation
    ${CMAKE_SOURCE_DIR}/OpenBW-iOS/Sources/OpenBWCore/openbw_instantiate.cpp
)

target_include_directories(openbw_core PUBLIC
    ${OPENBW_DIR}
    ${OPENBW_DIR}/deps/asio/asio/include
)

target_compile_definitions(openbw_core PUBLIC
    ASIO_STANDALONE
    ASIO_NO_DEPRECATED
    # Disable UI for core library - we'll provide our own
    OPENBW_HEADLESS=1
)

# ============================================================================
# iOS Platform Layer (UIKit/Metal implementation)
# ============================================================================

add_library(openbw_ios_platform STATIC
    ${CMAKE_SOURCE_DIR}/OpenBW-iOS/Sources/OpenBWCore/ios_platform.mm
    ${CMAKE_SOURCE_DIR}/OpenBW-iOS/Sources/OpenBWCore/MetalRenderer.mm
    ${CMAKE_SOURCE_DIR}/OpenBW-iOS/Sources/OpenBWCore/OpenBWGameRunner.mm
    ${CMAKE_SOURCE_DIR}/OpenBW-iOS/Sources/OpenBWCore/MPQLoader.mm
    ${CMAKE_SOURCE_DIR}/OpenBW-iOS/Sources/OpenBWCore/OpenBWRenderer.mm
)

target_include_directories(openbw_ios_platform PUBLIC
    ${OPENBW_DIR}
    ${OPENBW_DIR}/ui
    ${CMAKE_SOURCE_DIR}/OpenBW-iOS/Sources/OpenBWCore
)

target_link_libraries(openbw_ios_platform PUBLIC
    openbw_core
    "-framework UIKit"
    "-framework Metal"
    "-framework MetalKit"
    "-framework AVFoundation"
    "-framework AudioToolbox"
)

# ============================================================================
# Swift/Objective-C++ Bridge
# ============================================================================

add_library(openbw_bridge STATIC
    ${CMAKE_SOURCE_DIR}/OpenBW-iOS/Sources/OpenBWBridge/OpenBWBridge.mm
)

target_include_directories(openbw_bridge PUBLIC
    ${OPENBW_DIR}
    ${CMAKE_SOURCE_DIR}/OpenBW-iOS/Sources/OpenBWBridge
)

target_link_libraries(openbw_bridge PUBLIC
    openbw_ios_platform
)

# Enable Objective-C++ with ARC for bridging files
set_source_files_properties(
    ${CMAKE_SOURCE_DIR}/OpenBW-iOS/Sources/OpenBWBridge/OpenBWBridge.mm
    ${CMAKE_SOURCE_DIR}/OpenBW-iOS/Sources/OpenBWCore/ios_platform.mm
    ${CMAKE_SOURCE_DIR}/OpenBW-iOS/Sources/OpenBWCore/MPQLoader.mm
    ${CMAKE_SOURCE_DIR}/OpenBW-iOS/Sources/OpenBWCore/OpenBWGameRunner.mm
    ${CMAKE_SOURCE_DIR}/OpenBW-iOS/Sources/OpenBWCore/OpenBWRenderer.mm
    PROPERTIES
    COMPILE_FLAGS "-x objective-c++ -fobjc-arc"
)

# ============================================================================
# Build Configuration
# ============================================================================

# For Xcode, set deployment target
set_target_properties(openbw_core openbw_ios_platform openbw_bridge PROPERTIES
    XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "15.0"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"  # iPhone and iPad
    XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ""
    XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
)

message(STATUS "OpenBW-iOS configured successfully")
message(STATUS "Build with: cmake --build . --config Release")
