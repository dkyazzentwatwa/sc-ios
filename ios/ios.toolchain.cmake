# iOS CMake Toolchain File for OpenBW
# Based on ios-cmake by Alexander Widerberg

set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_VERSION 15.0)
set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0)

# Architectures
set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Target architecture")

# SDK paths
execute_process(COMMAND xcrun --sdk iphoneos --show-sdk-path
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

# iOS-specific flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fembed-bitcode")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fembed-bitcode")

# Make sure we can find frameworks
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# iOS frameworks
set(CMAKE_FIND_FRAMEWORK FIRST)

message(STATUS "iOS toolchain configured:")
message(STATUS "  SDK: ${CMAKE_OSX_SYSROOT}")
message(STATUS "  Architecture: ${CMAKE_OSX_ARCHITECTURES}")
message(STATUS "  Deployment target: ${CMAKE_OSX_DEPLOYMENT_TARGET}")
