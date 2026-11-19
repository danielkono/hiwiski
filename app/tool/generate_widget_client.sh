#!/bin/sh
# Generates the iOS home screen widgets' client from the contract, like `dart run
# swagger_parser` does for the app and Gradle does for the server and the Android widgets
# (docs/development/home-widgets.md). Run after a change to api/, once the bundled spec is
# refreshed (`./gradlew :api:updateBundledSpec` in server/). The output is not checked in.
#
# Usage: app/tool/generate_widget_client.sh
set -eu

app="$(cd "$(dirname "$0")/.." && pwd)"
spec="$app/../api/openapi.bundled.yaml"
out="$app/ios/HiwiskiWidgets/Generated"

parts="$out/parts"
rm -rf "$out"
mkdir -p "$parts"
# The generator runs on the Mac: an iOS SDK in the environment (from Xcode) would build it for
# the phone instead.
env -u SDKROOT -u PLATFORM_NAME swift run --quiet -c release \
  --package-path "$app/ios/WidgetClientGenerator" \
  swift-openapi-generator generate \
  --config "$app/ios/HiwiskiWidgets/openapi-generator-config.yaml" \
  --output-directory "$parts" \
  "$spec"
# The generator's file names are not stable between its versions; one file is, and the
# Xcode project names that one.
cat "$parts"/*.swift > "$out/WidgetAPI.swift"
rm -rf "$parts"
# The Xcode build compares this with the spec and stops if the client is older than it.
shasum -a 256 "$spec" | cut -d ' ' -f 1 > "$out/spec.sha256"
