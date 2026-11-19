package de.danielkononov.hiwiski.widgets

import android.content.Context
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.Constraints
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Keeps the home screen widgets current: draws them from what they hold, and asks the
 * server while the app is closed.
 *
 * Android runs a widget's refresh at most every 15 minutes (WorkManager), less often when the
 * phone sleeps; the app redraws them at once whenever its own data changes. A refresh that
 * fails leaves the last picture — on the road the home server is often out of reach.
 */
object HomeWidgets {
    /** What a widget instance draws, in its Glance state: a [WidgetView] as JSON. */
    val VIEW = stringPreferencesKey("view")

    private const val PERIODIC = "hiwiski.home_widgets.refresh"
    private const val NOW = "hiwiski.home_widgets.refresh_now"

    /** The app writes several pictures in a row; they are drawn once after them. */
    private const val SETTLE_MILLIS = 300L

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var pendingDraw: Job? = null

    fun widgetFor(kind: HomeWidgetKind): GlanceAppWidget = when (kind) {
        HomeWidgetKind.AGENDA -> AgendaWidget()
        HomeWidgetKind.SHOPPING -> ShoppingWidget()
        HomeWidgetKind.TASKS -> TasksWidget()
        HomeWidgetKind.KANBAN -> KanbanWidget()
    }

    /** The kinds that stand on a home screen right now — only those are asked for. */
    suspend fun placedKinds(context: Context): Set<HomeWidgetKind> {
        val manager = GlanceAppWidgetManager(context)
        return HomeWidgetKind.entries.filter { manager.getGlanceIds(widgetFor(it).javaClass).isNotEmpty() }.toSet()
    }

    /** What a widget of [kind] shows, from what the store holds. */
    fun view(store: WidgetStore, kind: HomeWidgetKind): WidgetView {
        val config = parseConfigs(store.config)[kind] ?: return WidgetView(WidgetView.State.SET_UP)
        if (store.gone(kind)) return WidgetView(WidgetView.State.GONE, config)
        val chosen = choose(config, parseSnapshot(store.appSnapshot(kind)), parseSnapshot(store.serverSnapshot(kind)))
            ?: return WidgetView(WidgetView.State.WAITING, config)
        return WidgetView(WidgetView.State.CONTENT, config, chosen)
    }

    /** Draws every widget from what the store holds — no network. */
    suspend fun draw(context: Context) {
        val store = WidgetStore(context)
        val manager = GlanceAppWidgetManager(context)
        for (kind in HomeWidgetKind.entries) {
            val widget = widgetFor(kind)
            val ids = manager.getGlanceIds(widget.javaClass)
            if (ids.isEmpty()) continue
            val json = widgetJson.encodeToString(WidgetView.serializer(), view(store, kind))
            for (id in ids) {
                updateAppWidgetState(context, id) { it[VIEW] = json }
                widget.update(context, id)
            }
        }
    }

    fun drawSoon(context: Context) {
        val app = context.applicationContext
        pendingDraw?.cancel()
        pendingDraw = scope.launch {
            delay(SETTLE_MILLIS)
            draw(app)
        }
    }

    /** Asks the server for every widget on a home screen, then draws them all. */
    suspend fun refresh(context: Context) {
        val store = WidgetStore(context)
        val credentials = store.credentials()
        val configs = parseConfigs(store.config)
        if (credentials != null) {
            for (kind in placedKinds(context)) {
                val config = configs[kind] ?: continue
                when (val fetched = withContext(Dispatchers.IO) { WidgetFetcher.fetch(kind, config, credentials) }) {
                    is Fetched.Fresh -> {
                        store.setServerSnapshot(kind, widgetJson.encodeToString(Snapshot.serializer(), fetched.snapshot))
                        store.setGone(kind, false)
                    }
                    Fetched.Gone -> {
                        store.setServerSnapshot(kind, null)
                        store.setGone(kind, true)
                    }
                    Fetched.SignedOut -> {
                        // Signed out on another device or by the administrator: the token is
                        // dead, and what the widgets show belongs to someone who left.
                        store.clear()
                        break
                    }
                    Fetched.Failed -> Unit
                }
            }
        }
        draw(context)
    }

    /** The refresh every quarter of an hour, for as long as widgets stand on a home screen. */
    fun schedule(context: Context) {
        // Without a network constraint: offline the refresh still redraws, and what is over
        // leaves the agenda.
        val request = PeriodicWorkRequestBuilder<WidgetRefreshWorker>(15, TimeUnit.MINUTES).build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(PERIODIC, ExistingPeriodicWorkPolicy.KEEP, request)
    }

    /** A refresh as soon as there is a network — after the settings or the session changed. */
    fun refreshNow(context: Context) {
        val request = OneTimeWorkRequestBuilder<WidgetRefreshWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(NOW, ExistingWorkPolicy.REPLACE, request)
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).apply {
            cancelUniqueWork(PERIODIC)
            cancelUniqueWork(NOW)
        }
    }

    /** The last widget was removed: nothing left to refresh. */
    fun cancelIfUnused(context: Context) {
        val app = context.applicationContext
        scope.launch { if (placedKinds(app).isEmpty()) cancel(app) }
    }
}

/** The refresh WorkManager runs, with the app closed. */
class WidgetRefreshWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        HomeWidgets.refresh(applicationContext)
        return Result.success()
    }
}
