import SwiftUI
import WidgetKit

/// The home screen widgets (docs/development/home-widgets.md).
///
/// Native, not Flutter: WidgetKit asks for a widget's timeline in a process of its own while
/// the app is closed, and only native code runs there. Each refresh asks the server, so the
/// widget is current without the app; the app redraws them at once whenever its own data
/// changes. A refresh that fails leaves the last picture.
@main
struct HiwiskiWidgetBundle: WidgetBundle {
  var body: some Widget {
    AgendaWidget()
    ShoppingWidget()
    TasksWidget()
    KanbanWidget()
  }
}

struct AgendaWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: HomeWidgetKind.agenda.rawValue, provider: Provider(kind: .agenda)) {
      WidgetEntryView(entry: $0)
    }
    .configurationDisplayName(Text("widget.agenda.name"))
    .description(Text("widget.agenda.description"))
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

struct ShoppingWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: HomeWidgetKind.shopping.rawValue, provider: Provider(kind: .shopping)) {
      WidgetEntryView(entry: $0)
    }
    .configurationDisplayName(Text("widget.shopping.name"))
    .description(Text("widget.shopping.description"))
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

struct TasksWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: HomeWidgetKind.tasks.rawValue, provider: Provider(kind: .tasks)) {
      WidgetEntryView(entry: $0)
    }
    .configurationDisplayName(Text("widget.tasks.name"))
    .description(Text("widget.tasks.description"))
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

struct KanbanWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: HomeWidgetKind.kanban.rawValue, provider: Provider(kind: .kanban)) {
      WidgetEntryView(entry: $0)
    }
    .configurationDisplayName(Text("widget.kanban.name"))
    .description(Text("widget.kanban.description"))
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

struct WidgetEntry: TimelineEntry {
  let date: Date
  let kind: HomeWidgetKind
  let state: WidgetState
}

/// A widget's timeline: one refresh from the server, then entries at the moments the picture
/// changes by itself — when an event ends, and at midnight, when "Tomorrow" becomes "Today".
struct Provider: TimelineProvider {
  let kind: HomeWidgetKind

  /// WidgetKit grants a budget of refreshes a day; it decides when this one comes.
  private static let refreshEvery: TimeInterval = 15 * 60

  /// More entries than this would only be redrawn after the next refresh anyway.
  private static let maxEntries = 24

  func placeholder(in context: Context) -> WidgetEntry {
    WidgetEntry(date: Date(), kind: kind, state: .setUp)
  }

  func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
    completion(WidgetEntry(date: Date(), kind: kind, state: .current(kind)))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
    Task {
      await WidgetRefresh.refresh(kind)
      let now = Date()
      let state = WidgetState.current(kind)
      let entries = Self.moments(state, after: now).map { WidgetEntry(date: $0, kind: kind, state: state) }
      completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(Self.refreshEvery))))
    }
  }

  /// Now, every end of an event still ahead, and the next midnight.
  private static func moments(_ state: WidgetState, after now: Date) -> [Date] {
    guard case .content(let snapshot) = state, let agenda = snapshot.agenda else { return [now] }
    let calendar = Calendar.current
    let midnight = calendar.startOfDay(for: now.addingTimeInterval(24 * 60 * 60))
    let ends = agenda.occurrences.compactMap { occurrence -> Date? in
      guard !occurrence.allDay, let end = localDate(occurrence.end) else { return nil }
      return end > now && end < midnight ? end : nil
    }
    return ([now, midnight] + ends).sorted().prefix(maxEntries).map { $0 }
  }
}

/// A local time without zone (`yyyy-MM-ddTHH:mm`), read in the device's zone.
func localDate(_ raw: String) -> Date? {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = .current
  for format in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss"] {
    formatter.dateFormat = format
    if let date = formatter.date(from: raw) { return date }
  }
  return nil
}
