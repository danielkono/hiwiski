package de.danielkononov.hiwiski.widgets

import de.danielkononov.hiwiski.widgets.api.infrastructure.Serializer
import de.danielkononov.hiwiski.widgets.api.models.Agenda
import de.danielkononov.hiwiski.widgets.api.models.ListSummary
import java.time.Instant
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement

/**
 * The kinds of home screen widget. Their keys are the ones the app writes (`HomeWidgetKind`
 * in Dart, docs/development/home-widgets.md).
 */
enum class HomeWidgetKind(val key: String) {
    AGENDA("agenda"),
    SHOPPING("shopping"),
    TASKS("tasks"),
    KANBAN("kanban");

    companion object {
        fun of(key: String?): HomeWidgetKind? = entries.firstOrNull { it.key == key }
    }
}

/** What one widget is set to show, as the app writes it. The fields it does not use keep their defaults. */
@Serializable
data class KindConfig(
    val calendarIds: List<String> = emptyList(),
    val days: Int = 7,
    val listId: String? = null,
    val columnId: String? = null,
)

/**
 * A picture of what a widget shows — the app's own, made from its database, or one the widget
 * fetched from the server. Both carry the same generated types and the configuration they
 * were made for.
 */
@Serializable
data class Snapshot(
    val source: String,
    val savedAt: String,
    /** The app still waits to send a change to what this shows. */
    val pending: Boolean = false,
    val config: KindConfig,
    val agenda: Agenda? = null,
    val list: ListSummary? = null,
) {
    /** The server's change position the picture stands at. */
    val position: Long get() = agenda?.position ?: list?.position ?: 0

    val saved: Instant get() = runCatching { Instant.parse(savedAt) }.getOrDefault(Instant.EPOCH)

    companion object {
        const val SOURCE_SERVER = "server"
    }
}

/** What a widget draws: its state, and the picture when it has one. */
@Serializable
data class WidgetView(
    val state: State,
    val config: KindConfig? = null,
    val snapshot: Snapshot? = null,
) {
    enum class State {
        /** Not set up in the app — or the member signed out, which takes the settings along. */
        SET_UP,

        /** Set up, but no picture yet. */
        WAITING,

        /** The list is gone, or no longer visible: it has to be chosen again. */
        GONE,
        CONTENT,
    }
}

/** Tolerant: what the generated types do not know is skipped, a missing field takes its default. */
val widgetJson = Json {
    serializersModule = Serializer.kotlinxSerializationAdapters
    ignoreUnknownKeys = true
    explicitNulls = false
    isLenient = true
    coerceInputValues = true
}

/** The app's settings document: one entry per kind that is set up. A broken entry costs only its widget. */
fun parseConfigs(raw: String?): Map<HomeWidgetKind, KindConfig> {
    if (raw.isNullOrBlank()) return emptyMap()
    val document = runCatching { widgetJson.parseToJsonElement(raw) as? JsonObject }.getOrNull() ?: return emptyMap()
    return buildMap {
        for ((key, value) in document) {
            val kind = HomeWidgetKind.of(key) ?: continue
            runCatching { widgetJson.decodeFromJsonElement<KindConfig>(value) }.getOrNull()?.let { put(kind, it) }
        }
    }
}

fun parseSnapshot(raw: String?): Snapshot? =
    if (raw.isNullOrBlank()) null else runCatching { widgetJson.decodeFromString<Snapshot>(raw) }.getOrNull()

/**
 * The picture a widget shows, of the app's and the one fetched from the server.
 *
 * Only one made for the current settings counts. **The app's wins while it still waits to send
 * a change** to what the widget shows: the server's answer would show the state before it —
 * the milk ticked off in the shop would come back. Otherwise the newer one wins, by the
 * server's change position, and between two at the same position the one made later.
 */
fun choose(config: KindConfig, app: Snapshot?, server: Snapshot?): Snapshot? {
    val own = app?.takeIf { it.config == config }
    val fetched = server?.takeIf { it.config == config }
    if (own == null) return fetched
    if (fetched == null || own.pending) return own
    return when {
        fetched.position > own.position -> fetched
        fetched.position < own.position -> own
        fetched.saved.isAfter(own.saved) -> fetched
        else -> own
    }
}
