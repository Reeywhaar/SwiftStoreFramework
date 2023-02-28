#!/bin/bash

set -e

NAME=StoreFramework

xcodebuild archive \
  -project ./${NAME}.xcodeproj \
  -scheme ${NAME} \
  -archivePath ./archives/ios.xcarchive  \
  -sdk iphoneos \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  SKIP_INSTALL=NO

xcodebuild archive \
  ONLY_ACTIVE_ARCH=NO \
  -project ./${NAME}.xcodeproj \
  -scheme ${NAME} \
  -archivePath ./archives/sim64.xcarchive \
  -sdk iphonesimulator \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  SKIP_INSTALL=NO

rm -rf ./archives/${NAME}.xcframework || true

xcodebuild -create-xcframework \
-framework "./archives/ios.xcarchive/Products/Library/Frameworks/${NAME}.framework" \
-framework "./archives/sim64.xcarchive/Products/Library/Frameworks/${NAME}.framework" \
-output "./archives/${NAME}.xcframework"