// swift-tools-version: 5.9
import PackageDescription

// Only here to run the generator of the home screen widgets' Swift client
// (app/tool/generate_widget_client.sh). Nothing in the app links against it: the widgets link
// the runtime, which the Xcode project names itself.
let package = Package(
  name: "WidgetClientGenerator",
  platforms: [.macOS(.v13)],
  dependencies: [
    .package(url: "https://github.com/apple/swift-openapi-generator", exact: "1.14.3")
  ],
  targets: [
    // SwiftPM resolves a package's dependencies only for a package with a target.
    .target(name: "WidgetClientGenerator", path: "Sources")
  ]
)
