import Foundation

/// The kinds of home screen widget. Their names are the keys the app writes (`HomeWidgetKind`
/// in Dart, docs/development/home-widgets.md).
enum HomeWidgetKind: String, CaseIterable {
  case agenda, shopping, tasks, kanban
}

/// What one widget is set to show, as the app writes it. The fields it does not use keep their
/// defaults, so the configuration a picture was made for compares with the current one.
struct KindConfig: Codable, Equatable {
  var calendarIds: [String] = []
  var days: Int = 7
  var listId: String?
  var columnId: String?

  init(calendarIds: [String] = [], days: Int = 7, listId: String? = nil, columnId: String? = nil) {
    self.calendarIds = calendarIds
    self.days = days
    self.listId = listId
    self.columnId = columnId
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    calendarIds = try values.decodeIfPresent([String].self, forKey: .calendarIds) ?? []
    days = try values.decodeIfPresent(Int.self, forKey: .days) ?? 7
    listId = try values.decodeIfPresent(String.self, forKey: .listId)
    columnId = try values.decodeIfPresent(String.self, forKey: .columnId)
  }
}

/// A picture of what a widget shows — the app's own or one fetched from the server.
protocol Picture {
  var config: KindConfig { get }
  /// The server's change position the picture stands at.
  var position: Int64 { get }
  var saved: Date { get }
  /// The app still waits to send a change to what this shows.
  var isPending: Bool { get }
}

/// The picture a widget shows, of the app's and the one fetched from the server.
///
/// Only one made for the current settings counts. **The app's wins while it still waits to send
/// a change** to what the widget shows: the server's answer would show the state before it —
/// the milk ticked off in the shop would come back. Otherwise the newer one wins, by the
/// server's change position, and between two at the same position the one made later.
func choose<P: Picture>(_ config: KindConfig, app: P?, server: P?) -> P? {
  let own = app.flatMap { $0.config == config ? $0 : nil }
  let fetched = server.flatMap { $0.config == config ? $0 : nil }
  guard let own else { return fetched }
  guard let fetched, !own.isPending else { return own }
  if fetched.position != own.position { return fetched.position > own.position ? fetched : own }
  return fetched.saved > own.saved ? fetched : own
}

/// The app's settings document: one entry per kind that is set up. A broken entry costs only
/// its widget.
func parseConfigs(_ raw: String?) -> [HomeWidgetKind: KindConfig] {
  guard let data = raw?.data(using: .utf8),
    let document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  else { return [:] }
  var configs: [HomeWidgetKind: KindConfig] = [:]
  for (key, value) in document {
    guard let kind = HomeWidgetKind(rawValue: key), JSONSerialization.isValidJSONObject(value),
      let entry = try? JSONSerialization.data(withJSONObject: value),
      let config = try? JSONDecoder().decode(KindConfig.self, from: entry)
    else { continue }
    configs[kind] = config
  }
  return configs
}

/// An ISO 8601 instant as the app (`2026-11-12T19:00:00.000Z`) or the widget writes it.
func parseInstant(_ raw: String) -> Date? {
  let withFraction = ISO8601DateFormatter()
  withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return withFraction.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
}
