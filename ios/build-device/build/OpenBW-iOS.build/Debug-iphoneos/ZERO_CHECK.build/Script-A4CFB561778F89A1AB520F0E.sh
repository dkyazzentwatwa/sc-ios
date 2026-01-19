#!/bin/sh
set -e
if test "$CONFIGURATION" = "Debug"; then :
  cd /Users/cypher/Documents/Development/coding/sc-ios/ios/build-device
  make -f /Users/cypher/Documents/Development/coding/sc-ios/ios/build-device/CMakeScripts/ReRunCMake.make
fi
if test "$CONFIGURATION" = "Release"; then :
  cd /Users/cypher/Documents/Development/coding/sc-ios/ios/build-device
  make -f /Users/cypher/Documents/Development/coding/sc-ios/ios/build-device/CMakeScripts/ReRunCMake.make
fi
if test "$CONFIGURATION" = "MinSizeRel"; then :
  cd /Users/cypher/Documents/Development/coding/sc-ios/ios/build-device
  make -f /Users/cypher/Documents/Development/coding/sc-ios/ios/build-device/CMakeScripts/ReRunCMake.make
fi
if test "$CONFIGURATION" = "RelWithDebInfo"; then :
  cd /Users/cypher/Documents/Development/coding/sc-ios/ios/build-device
  make -f /Users/cypher/Documents/Development/coding/sc-ios/ios/build-device/CMakeScripts/ReRunCMake.make
fi

