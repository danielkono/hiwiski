package de.danielkononov.hiwiski.widgets

import de.danielkononov.hiwiski.widgets.api.apis.CalendarApi
import de.danielkononov.hiwiski.widgets.api.apis.TodoApi
import de.danielkononov.hiwiski.widgets.api.infrastructure.ClientError
import de.danielkononov.hiwiski.widgets.api.infrastructure.ClientException
import java.time.Instant
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient

/** What asking the server came to. */
sealed interface Fetched {
    data class Fresh(val snapshot: Snapshot) : Fetched

    /** `todo.list_not_found`: the list is gone or no longer visible — the same answer for both. */
    data object Gone : Fetched

    /** `401`: the device was signed out. Nothing of the member may stay on the home screen. */
    data object SignedOut : Fetched

    /** Unreachable, or any other answer: the widget keeps what it showed. */
    data object Failed : Fetched
}

/**
 * Asks the server for what a widget shows, with the client generated from the contract
 * (`getAgenda`, `getListSummary`). A home server is often out of reach on the road — that is
 * everyday life, not an error, and the widget keeps its last picture.
 */
object WidgetFetcher {
    private val client by lazy {
        OkHttpClient.Builder()
            // The system gives a widget's work little time; a server that does not answer
            // quickly is treated as one that does not answer.
            .connectTimeout(10, TimeUnit.SECONDS)
            .callTimeout(20, TimeUnit.SECONDS)
            .build()
    }

    fun fetch(kind: HomeWidgetKind, config: KindConfig, credentials: Credentials): Fetched {
        val server = credentials.server.trimEnd('/')
        return try {
            val snapshot = when (kind) {
                HomeWidgetKind.AGENDA -> {
                    val api = CalendarApi(server, client).apply { accessTokenProvider = { credentials.token } }
                    val agenda = api.getAgenda(
                        calendarIds = config.calendarIds.mapNotNull(::uuid).ifEmpty { null },
                        days = config.days,
                        timeZone = TimeZone.getDefault().id,
                        limit = null,
                    )
                    snapshot(config, agenda = agenda)
                }
                else -> {
                    val listId = config.listId?.let(::uuid) ?: return Fetched.Gone
                    val api = TodoApi(server, client).apply { accessTokenProvider = { credentials.token } }
                    val summary = api.getListSummary(
                        listId = listId,
                        columnId = if (kind == HomeWidgetKind.KANBAN) config.columnId?.let(::uuid) else null,
                        limit = null,
                    )
                    snapshot(config, list = summary)
                }
            }
            Fetched.Fresh(snapshot)
        } catch (refused: ClientException) {
            when {
                refused.statusCode == 401 -> Fetched.SignedOut
                // Only the list's own answer: a server older than the widgets has no such
                // endpoint and answers 404 too — the widget then keeps the app's picture.
                refused.statusCode == 404 && codeOf(refused) == LIST_NOT_FOUND -> Fetched.Gone
                else -> Fetched.Failed
            }
        } catch (unreachable: Exception) {
            Fetched.Failed
        }
    }

    private fun snapshot(
        config: KindConfig,
        agenda: de.danielkononov.hiwiski.widgets.api.models.Agenda? = null,
        list: de.danielkononov.hiwiski.widgets.api.models.ListSummary? = null,
    ) = Snapshot(
        source = Snapshot.SOURCE_SERVER,
        savedAt = Instant.now().toString(),
        config = config,
        agenda = agenda,
        list = list,
    )

    private fun uuid(raw: String): UUID? = runCatching { UUID.fromString(raw) }.getOrNull()

    private const val LIST_NOT_FOUND = "todo.list_not_found"

    /** The error code of the answer (`ApiError.code`), if it has one. */
    private fun codeOf(refused: ClientException): String? {
        val body = (refused.response as? ClientError<*>)?.body as? String ?: return null
        return runCatching { widgetJson.parseToJsonElement(body).jsonObject["code"]?.jsonPrimitive?.content }.getOrNull()
    }
}
