package de.danielkononov.hiwiski

import de.danielkononov.hiwiski.widgets.HomeWidgetBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The home screen widgets are native; the app hands them what they show.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HomeWidgetBridge.CHANNEL)
            .setMethodCallHandler(HomeWidgetBridge(applicationContext))
    }
}
