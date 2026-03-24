#!/bin/bash
set -euo pipefail

# Build KanbeiAgentCore.xcframework (static, macOS + iOS + iOS Simulator)

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$REPO_ROOT/build"
DERIVED_MACOS="$BUILD_DIR/DerivedData"
DERIVED_IOS="$BUILD_DIR/DerivedData-iOS"
DERIVED_SIM="$BUILD_DIR/DerivedData-iOSSim"
FRAMEWORKS_DIR="$BUILD_DIR/frameworks"
OUTPUT="$BUILD_DIR/KanbeiAgentCore.xcframework"

# --- Info.plist template ---
make_info_plist() {
  local platform="$1"
  local min_version="$2"
  local platform_key="$3"

  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>KanbeiAgentCore</string>
  <key>CFBundleIdentifier</key>
  <string>com.kanbeiagent.KanbeiAgentCore</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>KanbeiAgentCore</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>$platform_key</string>
  </array>
  <key>MinimumOSVersion</key>
  <string>$min_version</string>
</dict>
</plist>
EOF
}

# --- Build .framework bundle from DerivedData products ---
make_framework() {
  local name="$1"          # e.g. "macOS"
  local products_dir="$2"  # path to DerivedData/.../Products/Release[-iphoneos]
  local platform="$3"      # "macOS" | "iOS" | "iOSSimulator"
  local min_version="$4"   # "14.0" | "17.0"
  local platform_key="$5"  # "MacOSX" | "iPhoneOS" | "iPhoneSimulator"

  local fw_dir="$FRAMEWORKS_DIR/$name/KanbeiAgentCore.framework"
  local modules_dir="$fw_dir/Modules/KanbeiAgentCore.swiftmodule"

  echo "→ Building $name framework bundle..."

  rm -rf "$FRAMEWORKS_DIR/$name"
  mkdir -p "$modules_dir"

  # Static library (ar archive stored with .o extension by Xcode SPM build)
  cp "$products_dir/KanbeiAgentCore.o" "$fw_dir/KanbeiAgentCore"

  # Swift module interfaces
  cp "$products_dir/KanbeiAgentCore.swiftmodule"/*.swiftinterface \
     "$products_dir/KanbeiAgentCore.swiftmodule"/*.swiftdoc \
     "$products_dir/KanbeiAgentCore.swiftmodule"/*.swiftmodule \
     "$modules_dir/" 2>/dev/null || true

  # Private/package interfaces (if present)
  find "$products_dir/KanbeiAgentCore.swiftmodule" -name "*.private.swiftinterface" \
    -o -name "*.package.swiftinterface" | xargs -I{} cp {} "$modules_dir/" 2>/dev/null || true

  # Info.plist
  make_info_plist "$platform" "$min_version" "$platform_key" > "$fw_dir/Info.plist"

  # Resource bundle (copy alongside framework)
  local bundle_src="$products_dir/KanbeiAgentCore_KanbeiAgentCore.bundle"
  if [ -d "$bundle_src" ]; then
    cp -r "$bundle_src" "$FRAMEWORKS_DIR/$name/"
    echo "  ✓ Resource bundle included"
  fi

  echo "  ✓ $name framework bundle ready at $fw_dir"
}

# --- Step 1: Build all platforms if DerivedData doesn't exist ---
cd "$REPO_ROOT"

if [ ! -f "$DERIVED_MACOS/Build/Products/Release/KanbeiAgentCore.o" ]; then
  echo "Building macOS..."
  xcodebuild build \
    -scheme KanbeiAgentCore \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_MACOS" \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    MACH_O_TYPE=staticlib \
    CONFIGURATION=Release | tail -3
fi

if [ ! -f "$DERIVED_IOS/Build/Products/Release-iphoneos/KanbeiAgentCore.o" ]; then
  echo "Building iOS..."
  xcodebuild build \
    -scheme KanbeiAgentCore \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED_IOS" \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    MACH_O_TYPE=staticlib \
    CONFIGURATION=Release | tail -3
fi

if [ ! -f "$DERIVED_SIM/Build/Products/Release-iphonesimulator/KanbeiAgentCore.o" ]; then
  echo "Building iOS Simulator..."
  xcodebuild build \
    -scheme KanbeiAgentCore \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$DERIVED_SIM" \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    MACH_O_TYPE=staticlib \
    CONFIGURATION=Release | tail -3
fi

# --- Step 2: Create framework bundles ---
make_framework "macOS" \
  "$DERIVED_MACOS/Build/Products/Release" \
  "macOS" "14.0" "MacOSX"

make_framework "iOS" \
  "$DERIVED_IOS/Build/Products/Release-iphoneos" \
  "iOS" "17.0" "iPhoneOS"

make_framework "iOSSimulator" \
  "$DERIVED_SIM/Build/Products/Release-iphonesimulator" \
  "iOSSimulator" "17.0" "iPhoneSimulator"

# --- Step 3: Create xcframework ---
rm -rf "$OUTPUT"

echo "→ Creating xcframework..."
xcodebuild -create-xcframework \
  -framework "$FRAMEWORKS_DIR/macOS/KanbeiAgentCore.framework" \
  -framework "$FRAMEWORKS_DIR/iOS/KanbeiAgentCore.framework" \
  -framework "$FRAMEWORKS_DIR/iOSSimulator/KanbeiAgentCore.framework" \
  -output "$OUTPUT"

# --- Step 4: Copy resource bundles into xcframework platform dirs ---
echo "→ Adding resource bundles to xcframework..."
declare -A PLATFORM_PRODUCTS=(
  ["macos-arm64_x86_64"]="$DERIVED_MACOS/Build/Products/Release"
  ["ios-arm64"]="$DERIVED_IOS/Build/Products/Release-iphoneos"
  ["ios-arm64_x86_64-simulator"]="$DERIVED_SIM/Build/Products/Release-iphonesimulator"
)
BUNDLE_NAME="KanbeiAgentCore_KanbeiAgentCore.bundle"
for platform_dir in "${!PLATFORM_PRODUCTS[@]}"; do
  src="${PLATFORM_PRODUCTS[$platform_dir]}/$BUNDLE_NAME"
  dst="$OUTPUT/$platform_dir/$BUNDLE_NAME"
  if [ -d "$src" ]; then
    rm -rf "$dst"
    cp -r "$src" "$dst"
    echo "  ✓ $platform_dir/$BUNDLE_NAME"
  fi
done

# --- Step 5: Patch Info.plist with AdditionalContentPaths ---
echo "→ Patching xcframework Info.plist..."
/usr/libexec/PlistBuddy "$OUTPUT/Info.plist" \
  -c "Add :AvailableLibraries:0:AdditionalContentPaths array" \
  -c "Add :AvailableLibraries:0:AdditionalContentPaths:0 string $BUNDLE_NAME" \
  -c "Add :AvailableLibraries:1:AdditionalContentPaths array" \
  -c "Add :AvailableLibraries:1:AdditionalContentPaths:0 string $BUNDLE_NAME" \
  -c "Add :AvailableLibraries:2:AdditionalContentPaths array" \
  -c "Add :AvailableLibraries:2:AdditionalContentPaths:0 string $BUNDLE_NAME" \
  2>/dev/null || true

echo ""
echo "✅ Done: $OUTPUT"
find "$OUTPUT" -maxdepth 3 | sed 's|'"$OUTPUT"'|KanbeiAgentCore.xcframework|'
