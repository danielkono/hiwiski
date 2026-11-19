import Flutter
import UIKit
import XCTest

/// Which picture a home screen widget shows — the app's or the one it fetched — and how it
/// reads the app's settings (`WidgetChoice.swift`, compiled into this target).
class RunnerTests: XCTestCase {
  private struct Fake: Picture, Equatable {
    var config: KindConfig
    var position: Int64
    var saved: Date
    var isPending = false
  }

  private let groceries = KindConfig(listId: "groceries")

  func testTheNewerPositionWins() {
    let app = Fake(config: groceries, position: 40, saved: Date(timeIntervalSince1970: 2_000))
    let server = Fake(config: groceries, position: 41, saved: Date(timeIntervalSince1970: 1_000))

    XCTAssertEqual(choose(groceries, app: app, server: server), server)
    XCTAssertEqual(choose(groceries, app: server, server: app), server)
  }

  func testTheAppsPictureWinsWhileAChangeWaitsToBeSent() {
    let app = Fake(config: groceries, position: 40, saved: Date(timeIntervalSince1970: 1_000), isPending: true)
    let server = Fake(config: groceries, position: 45, saved: Date(timeIntervalSince1970: 2_000))

    XCTAssertEqual(choose(groceries, app: app, server: server), app)
  }

  func testAtTheSamePositionTheLaterOneWins() {
    let app = Fake(config: groceries, position: 40, saved: Date(timeIntervalSince1970: 1_000))
    let server = Fake(config: groceries, position: 40, saved: Date(timeIntervalSince1970: 1_500))

    XCTAssertEqual(choose(groceries, app: app, server: server), server)
  }

  func testAPictureForOtherSettingsDoesNotCount() {
    let other = Fake(config: KindConfig(listId: "chores"), position: 40, saved: Date())

    XCTAssertNil(choose(groceries, app: other, server: nil))
  }

  func testTheSettingsReadWhatIsSetUpAndSkipTheRest() {
    let configs = parseConfigs(
      #"{"agenda":{"calendarIds":[],"days":3},"kanban":{"listId":"b","columnId":"c"},"weather":{"city":"Berlin"},"tasks":"broken"}"#
    )

    XCTAssertEqual(configs, [.agenda: KindConfig(days: 3), .kanban: KindConfig(listId: "b", columnId: "c")])
  }

  func testTheAppsTimestampsRead() {
    XCTAssertNotNil(parseInstant("2026-11-12T19:00:00.000Z"))
    XCTAssertNotNil(parseInstant("2026-11-12T19:00:00Z"))
  }
}
