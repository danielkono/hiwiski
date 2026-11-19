import Flutter
import WidgetKit

/// What the app hands the home screen widgets (`HomeWidgetBridge` in Dart): the settings, its
/// own picture of each widget's content, the session to ask the server with — or the order to
/// forget everything. Every write asks WidgetKit to redraw them; from the app in the
/// foreground that costs nothing of the widgets' daily refresh budget.
enum HomeWidgetBridge {
  static let channel = "de.danielkononov.hiwiski/home_widgets"

  static func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: channel, binaryMessenger: messenger).setMethodCallHandler { call, result in
      let arguments = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "setConfig":
        // The app sends its settings with every picture; only a change of them makes what
        // the server said about the old ones void.
        let json = arguments["json"] as? String
        if json != WidgetStore.config {
          WidgetStore.config = json
          WidgetStore.forgetGone()
        }
      case "setSnapshot":
        guard let kind = arguments["kind"] as? String else { break }
        WidgetStore.setAppSnapshot(kind, arguments["json"] as? String)
      case "setCredentials":
        var credentials: Credentials?
        if let server = arguments["server"] as? String, let token = arguments["token"] as? String {
          credentials = Credentials(server: server, token: token)
        }
        if credentials != WidgetStore.credentials() { WidgetStore.setCredentials(credentials) }
      case "clear":
        WidgetStore.clear()
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      reloadSoon()
      result(nil)
    }
  }

  /// The app writes its settings and four pictures in a row; WidgetKit is asked once after
  /// them.
  private static var pendingReload: DispatchWorkItem?

  private static func reloadSoon() {
    pendingReload?.cancel()
    let reload = DispatchWorkItem { WidgetCenter.shared.reloadAllTimelines() }
    pendingReload = reload
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: reload)
  }
}
