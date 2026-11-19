import Flutter
import UIKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The background sync runs in an engine of its own, which needs the
    // plugins as well: the database, the keychain, the settings.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // With scenes, plugins only register after this method has returned — too late for
    // iOS, which only delivers a background task to a relaunched app whose handler was
    // registered right here.
    //
    // The sync's own task always, not only when an earlier run saved it: on a fresh
    // install, or after a sign-out (which cancels the task), the plugin would otherwise
    // register the handler from Dart once a member signs in — after launch, which iOS
    // answers by terminating the app. The identifier is the one in Info.plist
    // (`BGTaskSchedulerPermittedIdentifiers`) and in `background_sync_io.dart`.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "de.danielkononov.hiwiski.sync",
      earliestBeginInSeconds: 900
    )
    WorkmanagerPlugin.registerLaunchHandlers()
    // The reminders' delegate (flutter_local_notifications): without it iOS kept a
    // reminder due while the app was open to itself, and a tap on a delivered one
    // never reached the plugin.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The home screen widgets are native; the app hands them what they show.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HomeWidgetBridge") {
      HomeWidgetBridge.register(with: registrar.messenger())
    }
  }
}
