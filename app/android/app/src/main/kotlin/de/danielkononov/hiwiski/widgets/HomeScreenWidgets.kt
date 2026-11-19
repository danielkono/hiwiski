package de.danielkononov.hiwiski.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.text.format.DateFormat
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import de.danielkononov.hiwiski.MainActivity
import de.danielkononov.hiwiski.R
import de.danielkononov.hiwiski.widgets.api.models.AgendaOccurrence
import de.danielkononov.hiwiski.widgets.api.models.ListSummary
import de.danielkononov.hiwiski.widgets.api.models.ListSummaryItem
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * The four home screen widgets. Drawn with Glance in the system's own look — Material You
 * colors, the system's corner radius — and as plain as they can be: a tap anywhere opens what
 * the widget shows, or its settings when it has none.
 */
abstract class HomeScreenWidget(private val kind: HomeWidgetKind) : GlanceAppWidget() {
    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            val view = currentState(HomeWidgets.VIEW)?.let {
                runCatching { widgetJson.decodeFromString<WidgetView>(it) }.getOrNull()
            }
            GlanceTheme { WidgetBody(kind, view) }
        }
    }
}

class AgendaWidget : HomeScreenWidget(HomeWidgetKind.AGENDA)

class ShoppingWidget : HomeScreenWidget(HomeWidgetKind.SHOPPING)

class TasksWidget : HomeScreenWidget(HomeWidgetKind.TASKS)

class KanbanWidget : HomeScreenWidget(HomeWidgetKind.KANBAN)

/**
 * Placed, updated or removed by the launcher. A widget just placed is drawn at once and asks
 * the server; the quarter-hourly refresh runs while any widget stands on a home screen.
 */
abstract class HomeScreenWidgetReceiver : GlanceAppWidgetReceiver() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        HomeWidgets.schedule(context)
        HomeWidgets.drawSoon(context)
        HomeWidgets.refreshNow(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        HomeWidgets.cancelIfUnused(context)
    }
}

class AgendaWidgetReceiver : HomeScreenWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = AgendaWidget()
}

class ShoppingWidgetReceiver : HomeScreenWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ShoppingWidget()
}

class TasksWidgetReceiver : HomeScreenWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = TasksWidget()
}

class KanbanWidgetReceiver : HomeScreenWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = KanbanWidget()
}

/**
 * Where a tap leads: an address of the app (`HomeWidgetsRoute`, `TodoListRoute`,
 * `CalendarRoute`), which Flutter hands its router as the link's path.
 */
internal fun linkFor(kind: HomeWidgetKind, view: WidgetView?): String {
    val listId = view?.config?.listId
    val setUp = "hiwiski://widget/account/home-widgets?kind=${kind.key}"
    return when {
        view == null || view.state == WidgetView.State.SET_UP || view.state == WidgetView.State.GONE -> setUp
        kind == HomeWidgetKind.AGENDA -> "hiwiski://widget/calendar"
        listId != null -> "hiwiski://widget/tasks/list/$listId"
        else -> setUp
    }
}

/** A picture older than this says how old it is — the server was out of reach for a while. */
private val STALE_AFTER: Duration = Duration.ofHours(1)

private const val MAX_TITLE_LINES = 1

@Composable
private fun WidgetBody(kind: HomeWidgetKind, view: WidgetView?) {
    val context = LocalContext.current
    val open = actionStartActivity(
        Intent(Intent.ACTION_VIEW, Uri.parse(linkFor(kind, view))).setClass(context, MainActivity::class.java),
    )
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .appWidgetBackground()
            .background(GlanceTheme.colors.widgetBackground)
            .cornerRadius(android.R.dimen.system_app_widget_background_radius)
            .padding(12.dp)
            .clickable(open),
    ) {
        val snapshot = view?.snapshot
        when {
            view?.state == WidgetView.State.CONTENT && snapshot?.agenda != null ->
                AgendaBody(snapshot.agenda.occurrences, snapshot, open)
            view?.state == WidgetView.State.CONTENT && snapshot?.list != null ->
                ListBody(kind, snapshot.list, snapshot, open)
            view?.state == WidgetView.State.GONE -> Message(kind, context.getString(R.string.widget_gone))
            view?.state == WidgetView.State.WAITING -> Message(kind, context.getString(R.string.widget_waiting))
            else -> Message(kind, context.getString(R.string.widget_set_up))
        }
    }
}

@Composable
private fun Message(kind: HomeWidgetKind, text: String) {
    val context = LocalContext.current
    Column(modifier = GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
        Text(context.getString(titleOf(kind)), style = titleStyle())
        Spacer(GlanceModifier.height(4.dp))
        Text(text, style = secondaryStyle())
    }
}

@Composable
private fun AgendaBody(occurrences: List<AgendaOccurrence>, snapshot: Snapshot, open: Action) {
    val context = LocalContext.current
    val now = LocalDateTime.now()
    val today = now.toLocalDate()
    // What is over leaves the agenda without asking anyone: the picture may be hours old.
    val upcoming = occurrences.mapNotNull { Shown.of(it) }.filter { it.notOverAt(now) }
    val days = upcoming.groupBy { maxOf(it.start.toLocalDate(), today) }.toSortedMap()
    Column(modifier = GlanceModifier.fillMaxSize()) {
        Text(context.getString(R.string.widget_agenda_name), style = titleStyle())
        Spacer(GlanceModifier.height(6.dp))
        if (days.isEmpty()) {
            Text(context.getString(R.string.widget_no_events), style = secondaryStyle(), modifier = GlanceModifier.clickable(open))
        } else {
            LazyColumn(modifier = GlanceModifier.defaultWeight()) {
                for ((day, shown) in days) {
                    item { DayHeader(day, today, open) }
                    items(shown) { OccurrenceRow(it, day, open) }
                }
            }
        }
        Footer(snapshot)
    }
}

@Composable
private fun DayHeader(day: LocalDate, today: LocalDate, open: Action) {
    val context = LocalContext.current
    val label = when (day) {
        today -> context.getString(R.string.widget_today)
        today.plusDays(1) -> context.getString(R.string.widget_tomorrow)
        else -> DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(Locale.getDefault(), "EEEdMMM")).format(day)
    }
    Text(
        label,
        style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Medium, color = GlanceTheme.colors.primary),
        modifier = GlanceModifier.padding(top = 4.dp, bottom = 2.dp).clickable(open),
    )
}

@Composable
private fun OccurrenceRow(shown: Shown, day: LocalDate, open: Action) {
    val context = LocalContext.current
    val time = when {
        shown.occurrence.allDay -> context.getString(R.string.widget_all_day)
        // Began on an earlier day: only when it ends.
        shown.start.toLocalDate().isBefore(day) -> context.getString(R.string.widget_until, clock(context, shown.end))
        shown.end == shown.start -> clock(context, shown.start)
        else -> "${clock(context, shown.start)}–${clock(context, shown.end)}"
    }
    val detail = listOfNotNull(time, shown.occurrence.location?.takeIf { it.isNotBlank() }).joinToString(" · ")
    Row(
        modifier = GlanceModifier.fillMaxWidth().padding(vertical = 3.dp).clickable(open),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = GlanceModifier.width(4.dp).height(30.dp).cornerRadius(2.dp).background(accent(shown.occurrence.colorToken)),
        ) {}
        Spacer(GlanceModifier.width(8.dp))
        Column {
            Text(shown.occurrence.title, style = itemStyle(), maxLines = MAX_TITLE_LINES)
            Text(detail, style = secondaryStyle(), maxLines = MAX_TITLE_LINES)
        }
    }
}

@Composable
private fun ListBody(kind: HomeWidgetKind, list: ListSummary, snapshot: Snapshot, open: Action) {
    val context = LocalContext.current
    val column = list.column
    val title = if (kind == HomeWidgetKind.KANBAN && column != null) "${list.name} · ${column.name}" else list.name
    Column(modifier = GlanceModifier.fillMaxSize()) {
        // The name and, under it, how many are open and done — beside it they wrapped onto a
        // line of their own in a small widget.
        Text(title, style = titleStyle(), maxLines = MAX_TITLE_LINES)
        Text(
            context.getString(R.string.widget_counts, list.openCount, list.doneCount),
            style = secondaryStyle(),
            maxLines = MAX_TITLE_LINES,
        )
        Spacer(GlanceModifier.height(6.dp))
        if (list.items.isEmpty()) {
            Text(context.getString(R.string.widget_nothing_open), style = secondaryStyle(), modifier = GlanceModifier.clickable(open))
        } else {
            val more = (column?.count ?: if (column == null) list.openCount else list.items.size) - list.items.size
            LazyColumn(modifier = GlanceModifier.defaultWeight()) {
                items(list.items) { ItemRow(it, open) }
                if (more > 0) {
                    item {
                        Text(context.getString(R.string.widget_more, more), style = secondaryStyle(), modifier = GlanceModifier.padding(top = 4.dp).clickable(open))
                    }
                }
            }
        }
        Footer(snapshot)
    }
}

@Composable
private fun ItemRow(item: ListSummaryItem, open: Action) {
    val amount = listOfNotNull(item.amount?.stripTrailingZeros()?.toPlainString(), item.unit).joinToString(" ")
    Row(
        modifier = GlanceModifier.fillMaxWidth().padding(vertical = 3.dp).clickable(open),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            provider = ImageProvider(if (item.done) R.drawable.widget_item_done else R.drawable.widget_item_open),
            contentDescription = null,
            colorFilter = ColorFilter.tint(GlanceTheme.colors.onSurfaceVariant),
            modifier = GlanceModifier.size(18.dp),
        )
        Spacer(GlanceModifier.width(8.dp))
        Text(item.title, style = itemStyle(), maxLines = MAX_TITLE_LINES, modifier = GlanceModifier.defaultWeight())
        if (amount.isNotEmpty()) Text(amount, style = secondaryStyle())
    }
}

/** How old the picture is — only once it is older than an hour. */
@Composable
private fun Footer(snapshot: Snapshot) {
    val saved = snapshot.saved
    if (Duration.between(saved, Instant.now()) < STALE_AFTER) return
    val context = LocalContext.current
    val local = LocalDateTime.ofInstant(saved, ZoneId.systemDefault())
    val label = if (local.toLocalDate() == LocalDate.now()) {
        clock(context, local)
    } else {
        DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(Locale.getDefault(), "dMMM")).format(local)
    }
    Text(context.getString(R.string.widget_as_of, label), style = secondaryStyle(), modifier = GlanceModifier.padding(top = 4.dp))
}

/** An occurrence with its times read; one the widget cannot read is left out. */
private data class Shown(val occurrence: AgendaOccurrence, val start: LocalDateTime, val end: LocalDateTime) {
    fun notOverAt(now: LocalDateTime): Boolean =
        if (occurrence.allDay) !end.toLocalDate().isBefore(now.toLocalDate()) else !end.isBefore(now)

    companion object {
        fun of(occurrence: AgendaOccurrence): Shown? {
            val start = runCatching { LocalDateTime.parse(occurrence.start) }.getOrNull() ?: return null
            val end = runCatching { LocalDateTime.parse(occurrence.end) }.getOrNull() ?: start
            return Shown(occurrence, start, end)
        }
    }
}

private fun clock(context: Context, time: LocalDateTime): String =
    DateTimeFormatter.ofPattern(if (DateFormat.is24HourFormat(context)) "HH:mm" else "h:mm a").format(time)

private fun titleOf(kind: HomeWidgetKind): Int = when (kind) {
    HomeWidgetKind.AGENDA -> R.string.widget_agenda_name
    HomeWidgetKind.SHOPPING -> R.string.widget_shopping_name
    HomeWidgetKind.TASKS -> R.string.widget_tasks_name
    HomeWidgetKind.KANBAN -> R.string.widget_kanban_name
}

@Composable
private fun titleStyle() = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium, color = GlanceTheme.colors.onSurface)

@Composable
private fun itemStyle() = TextStyle(fontSize = 14.sp, color = GlanceTheme.colors.onSurface)

@Composable
private fun secondaryStyle() = TextStyle(fontSize = 12.sp, color = GlanceTheme.colors.onSurfaceVariant)

/**
 * A calendar's color token as the app draws it, in the light and the dark theme
 * (`hiwiski_theme.dart`). An unknown token falls back to slate, as everywhere.
 */
private fun accent(token: String?): androidx.glance.unit.ColorProvider = when (token) {
    "BLUE" -> ColorProvider(day = Color(0xFF1F6FB2), night = Color(0xFF8FC7F5))
    "RUST" -> ColorProvider(day = Color(0xFFB3541E), night = Color(0xFFFFB68C))
    "VIOLET" -> ColorProvider(day = Color(0xFF7B4FA8), night = Color(0xFFD5BAFF))
    "GREEN" -> ColorProvider(day = Color(0xFF2E7D5B), night = Color(0xFF8ADCB4))
    "PINK" -> ColorProvider(day = Color(0xFFC2185B), night = Color(0xFFFFB0C8))
    "OCHRE" -> ColorProvider(day = Color(0xFF8D6E00), night = Color(0xFFE5C44C))
    "TEAL" -> ColorProvider(day = Color(0xFF00696D), night = Color(0xFF80D4D8))
    else -> ColorProvider(day = Color(0xFF5F6368), night = Color(0xFFC4C7C5))
}
