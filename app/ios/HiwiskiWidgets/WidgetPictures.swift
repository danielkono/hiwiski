import Foundation

typealias Agenda = Components.Schemas.Agenda
typealias AgendaOccurrence = Components.Schemas.AgendaOccurrence
typealias ListSummary = Components.Schemas.ListSummary
typealias ListSummaryItem = Components.Schemas.ListSummaryItem

/// A picture of what a widget shows, in the types generated from the contract — the app writes
/// the same JSON the server answers with (`HomeWidgetRepository`).
struct Snapshot: Codable, Picture {
  static let sourceServer = "server"

  var source: String
  var savedAt: String
  var pending: Bool?
  var config: KindConfig
  var agenda: Agenda?
  var list: ListSummary?

  var isPending: Bool { pending ?? false }
  var position: Int64 { agenda?.position ?? list?.position ?? 0 }
  var saved: Date { parseInstant(savedAt) ?? .distantPast }

  /// One the widget fetched itself.
  init(fetched config: KindConfig, agenda: Agenda? = nil, list: ListSummary? = nil) {
    source = Snapshot.sourceServer
    savedAt = ISO8601DateFormatter().string(from: Date())
    pending = false
    self.config = config
    self.agenda = agenda
    self.list = list
  }

  static func parse(_ raw: String?) -> Snapshot? {
    guard let data = raw?.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(Snapshot.self, from: data)
  }

  func encoded() -> String? {
    (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
  }
}

/// What a widget draws.
enum WidgetState {
  /// Not set up in the app — or the member signed out, which takes the settings along.
  case setUp
  /// Set up, but no picture yet.
  case waiting(KindConfig)
  /// The list is gone, or no longer visible: it has to be chosen again.
  case gone(KindConfig)
  case content(Snapshot)

  /// From what the store holds — no network.
  static func current(_ kind: HomeWidgetKind) -> WidgetState {
    guard let config = parseConfigs(WidgetStore.config)[kind] else { return .setUp }
    if WidgetStore.gone(kind.rawValue) { return .gone(config) }
    let chosen = choose(
      config,
      app: Snapshot.parse(WidgetStore.appSnapshot(kind.rawValue)),
      server: Snapshot.parse(WidgetStore.serverSnapshot(kind.rawValue)))
    return chosen.map(WidgetState.content) ?? .waiting(config)
  }

  /// Where a tap leads: an address of the app (`HomeWidgetsRoute`, `TodoListRoute`,
  /// `CalendarRoute`), which Flutter hands its router as the link's path.
  func link(_ kind: HomeWidgetKind) -> URL {
    let setUp = URL(string: "hiwiski://widget/account/home-widgets?kind=\(kind.rawValue)")!
    switch self {
    case .setUp, .gone: return setUp
    case .waiting(let config): return Self.open(kind, config) ?? setUp
    case .content(let snapshot): return Self.open(kind, snapshot.config) ?? setUp
    }
  }

  private static func open(_ kind: HomeWidgetKind, _ config: KindConfig) -> URL? {
    if kind == .agenda { return URL(string: "hiwiski://widget/calendar") }
    return config.listId.flatMap { URL(string: "hiwiski://widget/tasks/list/\($0)") }
  }
}
