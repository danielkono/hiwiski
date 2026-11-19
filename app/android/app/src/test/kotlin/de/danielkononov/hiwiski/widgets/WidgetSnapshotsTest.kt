package de.danielkononov.hiwiski.widgets

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

/**
 * Which picture a widget shows — the app's or the one it fetched — and how it reads what the
 * app wrote. The JSON here is the app's, as `HomeWidgetRepository` writes it.
 */
class WidgetSnapshotsTest {
    private val groceries = KindConfig(listId = "11111111-1111-1111-1111-111111111111")

    private fun list(position: Long, savedAt: String, pending: Boolean = false, source: String = "app") =
        parseSnapshot(
            """
            {"source":"$source","savedAt":"$savedAt","pending":$pending,
             "config":{"listId":"${groceries.listId}"},
             "list":{"position":$position,"listId":"${groceries.listId}","name":"Groceries",
                     "kind":"SHOPPING","colorToken":null,"archived":false,"openCount":1,"doneCount":0,
                     "column":null,"truncated":false,"unknownField":"skipped",
                     "items":[{"todoId":"22222222-2222-2222-2222-222222222222","title":"Milk","done":false,
                               "amount":2,"unit":"l","dueDate":"2026-11-14","dueTime":null}]}}
            """.trimIndent(),
        )!!

    @Test
    fun theAppsPictureReadsWithTheGeneratedTypes() {
        val snapshot = list(position = 41, savedAt = "2026-11-12T19:00:00.000Z")

        assertEquals(41L, snapshot.position)
        assertEquals("Milk", snapshot.list!!.items.single().title)
        assertEquals(java.time.LocalDate.of(2026, 11, 14), snapshot.list!!.items.single().dueDate)
    }

    @Test
    fun theNewerPositionWins() {
        val app = list(position = 40, savedAt = "2026-11-12T19:00:00.000Z")
        val server = list(position = 41, savedAt = "2026-11-12T18:00:00Z", source = "server")

        assertSame(server, choose(groceries, app, server))

        val newerApp = list(position = 42, savedAt = "2026-11-12T17:00:00.000Z")
        val olderServer = list(position = 39, savedAt = "2026-11-12T20:00:00Z", source = "server")
        assertSame(newerApp, choose(groceries, newerApp, olderServer))
    }

    @Test
    fun theAppsPictureWinsWhileAChangeWaitsToBeSent() {
        val app = list(position = 40, savedAt = "2026-11-12T19:00:00.000Z", pending = true)
        val server = list(position = 45, savedAt = "2026-11-12T19:30:00Z", source = "server")

        assertSame(app, choose(groceries, app, server))
    }

    @Test
    fun atTheSamePositionTheLaterOneWins() {
        val app = list(position = 40, savedAt = "2026-11-12T19:00:00.000Z")
        val server = list(position = 40, savedAt = "2026-11-12T19:15:00Z", source = "server")

        assertSame(server, choose(groceries, app, server))
    }

    @Test
    fun aPictureForOtherSettingsDoesNotCount() {
        val other = KindConfig(listId = "33333333-3333-3333-3333-333333333333")

        assertNull(choose(other, list(40, "2026-11-12T19:00:00.000Z"), null))
    }

    @Test
    fun theSettingsReadWhatIsSetUpAndSkipTheRest() {
        val configs = parseConfigs(
            """
            {"agenda":{"calendarIds":[],"days":3},
             "kanban":{"listId":"b","columnId":"c"},
             "weather":{"city":"Berlin"},
             "tasks":"broken"}
            """.trimIndent(),
        )

        assertEquals(
            mapOf(
                HomeWidgetKind.AGENDA to KindConfig(days = 3),
                HomeWidgetKind.KANBAN to KindConfig(listId = "b", columnId = "c"),
            ),
            configs,
        )
    }

    @Test
    fun aTapLeadsToWhatTheWidgetShowsOrToItsSettings() {
        assertEquals("hiwiski://widget/account/home-widgets?kind=shopping", linkFor(HomeWidgetKind.SHOPPING, null))
        assertEquals(
            "hiwiski://widget/tasks/list/${groceries.listId}",
            linkFor(HomeWidgetKind.SHOPPING, WidgetView(WidgetView.State.WAITING, groceries)),
        )
        assertEquals(
            "hiwiski://widget/account/home-widgets?kind=shopping",
            linkFor(HomeWidgetKind.SHOPPING, WidgetView(WidgetView.State.GONE, groceries)),
        )
        assertEquals(
            "hiwiski://widget/calendar",
            linkFor(HomeWidgetKind.AGENDA, WidgetView(WidgetView.State.CONTENT, KindConfig())),
        )
    }
}
