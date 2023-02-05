#!/bin/bash

NAME=StoreFramework

xcodebuild archive -project ./${NAME}.xcodeproj -scheme ${NAME} -arch arm64 -configuration Release SKIP_INSTALL=NO -sdk "iphoneos" BUILD_LIBRARY_FOR_DISTRIBUTION=YES OTHERCFLAGS="-fembed-bitcode" -archivePath ./archives/ios.xcarchive 
xcodebuild archive -project ./${NAME}.xcodeproj -scheme ${NAME} -arch arm64 -configuration Release SKIP_INSTALL=NO -sdk iphonesimulator BUILD_LIBRARY_FOR_DISTRIBUTION=YES OTHERCFLAGS="-fembed-bitcode" -archivePath ./archives/sim64.xcarchive

rm -rf ./archives/${NAME}.xcframework || true

xcodebuild -create-xcframework \
-framework "./archives/ios.xcarchive/Products/Library/Frameworks/${NAME}.framework" \
-framework "./archives/sim64.xcarchive/Products/Library/Frameworks/${NAME}.framework" \
-output "./archives/${NAME}.xcframework"