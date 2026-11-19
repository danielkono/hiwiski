package de.danielkononov.hiwiski.widgets

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * What the app hands the home screen widgets (`HomeWidgetBridge` in Dart): the settings, its
 * own picture of each widget's content, the session to ask the server with — or the order to
 * forget everything. Every write redraws the widgets; a new session or new settings also ask
 * the server at once.
 */
class HomeWidgetBridge(context: Context) : MethodChannel.MethodCallHandler {
    private val context = context.applicationContext

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val store = WidgetStore(context)
        when (call.method) {
            "setConfig" -> {
                val json = call.argument<String>("json")
                // The app sends its settings with every picture; only a change of them
                // makes what the server said about the old ones void, and asks it anew.
                if (json != store.config) {
                    store.config = json
                    store.forgetGone()
                    HomeWidgets.refreshNow(context)
                }
                HomeWidgets.drawSoon(context)
            }
            "setSnapshot" -> {
                val kind = HomeWidgetKind.of(call.argument<String>("kind"))
                if (kind != null) store.setAppSnapshot(kind, call.argument<String>("json"))
                HomeWidgets.drawSoon(context)
            }
            "setCredentials" -> {
                val server = call.argument<String>("server")
                val token = call.argument<String>("token")
                val credentials = if (server != null && token != null) Credentials(server, token) else null
                if (credentials != store.credentials()) {
                    store.setCredentials(credentials)
                    if (credentials != null) {
                        HomeWidgets.schedule(context)
                        HomeWidgets.refreshNow(context)
                    }
                }
            }
            "clear" -> {
                store.clear()
                HomeWidgets.cancel(context)
                HomeWidgets.drawSoon(context)
            }
            else -> {
                result.notImplemented()
                return
            }
        }
        result.success(null)
    }

    companion object {
        const val CHANNEL = "de.danielkononov.hiwiski/home_widgets"
    }
}
