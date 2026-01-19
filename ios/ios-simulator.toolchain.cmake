# iOS Simulator CMake Toolchain File for OpenBW

set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_VERSION 15.0)
set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0)

# Simulator uses x86_64 for Intel Macs, arm64 for Apple Silicon
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "Target architectures for simulator")

# SDK paths - use simulator SDK
execute_process(COMMAND xcrun --sdk iphonesimulator --show-sdk-path
    OUTPUT_VARIABLE CMAKE_OSX_SYSROOT
    OUTPUT_STRIP_TRAILING_WHITESPACE)

# Compiler settings
set(CMAKE_C_COMPILER_WORKS TRUE)
set(CMAKE_CXX_COMPILER_WORKS TRUE)

# Find the compilers
execute_process(COMMAND xcrun --find clang
    OUTPUT_VARIABLE CMAKE_C_COMPILER
    OUTPUT_STRIP_TRAILING_WHITESPACE)
execute_process(COMMAND xcrun --find clang++
    OUTPUT_VARIABLE CMAKE_CXX_COMPILER
    OUTPUT_STRIP_TRAILING_WHITESPACE)

# C++ standard
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Search paths
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

message(STATUS "iOS Simulator toolchain configured:")
message(STATUS "  SDK: ${CMAKE_OSX_SYSROOT}")
message(STATUS "  Architectures: ${CMAKE_OSX_ARCHITECTURES}")
