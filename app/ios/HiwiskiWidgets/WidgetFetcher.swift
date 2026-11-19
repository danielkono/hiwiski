import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// What asking the server came to.
enum Fetched {
  case fresh(Snapshot)
  /// `todo.list_not_found`: the list is gone or no longer visible — the same answer for both.
  case gone
  /// `401`: the device was signed out. Nothing of the member may stay on the home screen.
  case signedOut
  /// Unreachable, or any other answer: the widget keeps what it showed.
  case failed
}

/// Asks the server for what a widget shows, with the client generated from the contract
/// (`getAgenda`, `getListSummary`). A home server is often out of reach on the road — that is
/// everyday life, not an error, and the widget keeps its last picture.
enum WidgetFetcher {
  static func fetch(_ kind: HomeWidgetKind, _ config: KindConfig, _ credentials: Credentials) async
    -> Fetched
  {
    var server = credentials.server
    while server.hasSuffix("/") { server.removeLast() }
    guard let url = URL(string: server) else { return .failed }
    // The system gives a widget's refresh little time; a server that does not answer quickly
    // is treated as one that does not answer.
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 10
    configuration.timeoutIntervalForResource = 20
    let client = Client(
      serverURL: url,
      transport: URLSessionTransport(configuration: .init(session: URLSession(configuration: configuration))),
      middlewares: [Bearer(token: credentials.token)])
    do {
      switch kind {
      case .agenda:
        let response = try await client.getAgenda(
          query: .init(
            calendarIds: config.calendarIds.isEmpty ? nil : config.calendarIds,
            days: config.days,
            timeZone: TimeZone.current.identifier))
        switch response {
        case .ok(let answer): return .fresh(Snapshot(fetched: config, agenda: try answer.body.json))
        case .unauthorized: return .signedOut
        default: return .failed
        }
      case .shopping, .tasks, .kanban:
        guard let listId = config.listId else { return .gone }
        let response = try await client.getListSummary(
          path: .init(listId: listId),
          query: .init(columnId: kind == .kanban ? config.columnId : nil))
        switch response {
        case .ok(let answer): return .fresh(Snapshot(fetched: config, list: try answer.body.json))
        case .unauthorized: return .signedOut
        // Only the list's own answer: a server older than the widgets has no such endpoint
        // and answers 404 too — the widget then keeps the app's picture.
        case .notFound(let answer):
          return (try? answer.body.json.code) == "todo.list_not_found" ? .gone : .failed
        default: return .failed
        }
      }
    } catch {
      return .failed
    }
  }
}

/// The device token, as every call of the app sends it.
private struct Bearer: ClientMiddleware {
  let token: String

  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    var request = request
    request.headerFields[.authorization] = "Bearer \(token)"
    return try await next(request, body, baseURL)
  }
}

/// Refreshes what the store holds for [kind]: asks the server when the app handed over a
/// session, and keeps the last picture when it cannot be reached.
enum WidgetRefresh {
  /// A picture from the server this young is not asked for again: while the app is in use it
  /// redraws the widgets on every change, and each redraw is a timeline.
  private static let fresh: TimeInterval = 5 * 60

  static func refresh(_ kind: HomeWidgetKind) async {
    guard let credentials = WidgetStore.credentials(),
      let config = parseConfigs(WidgetStore.config)[kind]
    else { return }
    if let last = Snapshot.parse(WidgetStore.serverSnapshot(kind.rawValue)), last.config == config,
      Date().timeIntervalSince(last.saved) < fresh
    {
      return
    }
    switch await WidgetFetcher.fetch(kind, config, credentials) {
    case .fresh(let snapshot):
      WidgetStore.setServerSnapshot(kind.rawValue, snapshot.encoded())
      WidgetStore.setGone(kind.rawValue, false)
    case .gone:
      WidgetStore.setServerSnapshot(kind.rawValue, nil)
      WidgetStore.setGone(kind.rawValue, true)
    case .signedOut:
      // Signed out on another device or by the administrator: the token is dead, and what the
      // widgets show belongs to someone who left.
      WidgetStore.clear()
    case .failed:
      break
    }
  }
}
