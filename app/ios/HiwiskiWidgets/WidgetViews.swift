import SwiftUI
import WidgetKit

/// The widgets in the system's own look: system fonts and colors, the system background and
/// margins, the accent colors of the app's calendars. As plain as they can be — a tap anywhere
/// opens what the widget shows, or its settings when it has none.
///
/// **Only as many rows as fit.** The content sits in a frame of exactly the widget's size:
/// a taller one grew the frame past the widget, which was then centered — the first line
/// ended up against the rounded edge and the title above it was cut off.
struct WidgetEntryView: View {
  let entry: WidgetEntry

  var body: some View {
    GeometryReader { space in
      content(height: space.size.height)
        .frame(width: space.size.width, height: space.size.height, alignment: .topLeading)
        .clipped()
    }
    .containerBackground(.background, for: .widget)
    .widgetURL(entry.state.link(entry.kind))
  }

  @ViewBuilder private func content(height: CGFloat) -> some View {
    switch entry.state {
    case .content(let snapshot):
      if let agenda = snapshot.agenda {
        AgendaView(agenda: agenda, saved: snapshot.saved, now: entry.date, height: height)
      } else if let list = snapshot.list {
        ListView(list: list, kind: entry.kind, saved: snapshot.saved, now: entry.date, height: height)
      } else {
        Message(kind: entry.kind, text: "widget.waiting")
      }
    case .waiting: Message(kind: entry.kind, text: "widget.waiting")
    case .gone: Message(kind: entry.kind, text: "widget.gone")
    case .setUp: Message(kind: entry.kind, text: "widget.setUp")
    }
  }
}

/// The heights the rows are counted in, from the fonts below; a little generous, since a
/// row too many is cut off at the bottom.
private enum Rows {
  static let spacing: CGFloat = 4
  static let headline: CGFloat = 22
  static let row: CGFloat = 20
  static let caption: CGFloat = 16
  static let dayHeader: CGFloat = 15
}

private struct Message: View {
  let kind: HomeWidgetKind
  let text: LocalizedStringKey

  var body: some View {
    VStack(alignment: .leading, spacing: Rows.spacing) {
      Text(title(kind)).font(.headline).lineLimit(2)
      Text(text).font(.caption).foregroundStyle(.secondary)
    }
  }
}

private struct AgendaView: View {
  let agenda: Agenda
  let saved: Date
  let now: Date
  let height: CGFloat

  var body: some View {
    let footer = Footer(saved: saved, now: now)
    let lines = fitting(Shown.upcoming(agenda.occurrences, at: now), footer: footer.shown)
    VStack(alignment: .leading, spacing: Rows.spacing) {
      if lines.isEmpty {
        Text("widget.agenda.name").font(.headline)
        Text("widget.noEvents").font(.caption).foregroundStyle(.secondary)
      }
      ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
        switch line {
        case .day(let day):
          Text(dayLabel(day, now: now)).font(.caption.weight(.semibold)).foregroundStyle(.tint)
        case .occurrence(let item):
          OccurrenceRow(item: item)
        }
      }
      Spacer(minLength: 0)
      footer
    }
  }

  private enum Line {
    case day(Date)
    case occurrence(Shown)
  }

  /// The day headers and rows that fit into the height — each day that has a row starts
  /// with its header.
  private func fitting(_ upcoming: [Shown], footer: Bool) -> [Line] {
    var left = height - (footer ? Rows.caption + Rows.spacing : 0)
    var lines: [Line] = []
    var day: Date?
    for item in upcoming {
      let header = item.day != day
      let cost = Rows.row + Rows.spacing + (header ? Rows.dayHeader + Rows.spacing : 0)
      if cost > left { break }
      left -= cost
      if header { lines.append(.day(item.day)) }
      lines.append(.occurrence(item))
      day = item.day
    }
    return lines
  }
}

/// One line: the calendar's color, the time, the title.
private struct OccurrenceRow: View {
  let item: Shown

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(Image(systemName: "circle.fill")).font(.system(size: 7))
        .foregroundStyle(accent(item.occurrence.colorToken))
      if let time = item.time {
        Text(time).font(.caption).monospacedDigit().foregroundStyle(.secondary)
      }
      Text(item.occurrence.title).font(.subheadline).lineLimit(1)
    }
  }
}

private struct ListView: View {
  let list: ListSummary
  let kind: HomeWidgetKind
  let saved: Date
  let now: Date
  let height: CGFloat

  var body: some View {
    let footer = Footer(saved: saved, now: now)
    let rows = fitting(footer: footer.shown)
    let more = total - rows
    VStack(alignment: .leading, spacing: Rows.spacing) {
      // The name and, under it, how many are open and done — beside it they wrapped onto a
      // line of their own in a small widget.
      VStack(alignment: .leading, spacing: 0) {
        Text(heading).font(.headline).lineLimit(1)
        Text(String(format: NSLocalizedString("widget.counts", comment: ""), list.openCount, list.doneCount))
          .font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      if list.items.isEmpty {
        Text("widget.nothingOpen").font(.caption).foregroundStyle(.secondary)
      }
      ForEach(Array(list.items.prefix(rows).enumerated()), id: \.offset) { _, item in
        ItemRow(item: item)
      }
      if more > 0 && !list.items.isEmpty {
        Text(String(format: NSLocalizedString("widget.more", comment: ""), more))
          .font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      footer
    }
  }

  private var heading: String {
    guard kind == .kanban, let column = list.column else { return list.name }
    return "\(list.name) · \(column.name)"
  }

  /// What there is to show: the column's cards, or the list's open entries.
  private var total: Int { list.column.map { $0.count ?? list.items.count } ?? list.openCount }

  /// How many rows fit below the heading — with room for "+3 more" when not all do.
  private func fitting(footer: Bool) -> Int {
    var left = height - Rows.headline - Rows.caption - Rows.spacing
    if footer { left -= Rows.caption + Rows.spacing }
    let rows = Int(max(0, left) / (Rows.row + Rows.spacing))
    let all = min(list.items.count, total)
    return all <= rows ? all : max(0, rows - 1)
  }
}

private struct ItemRow: View {
  let item: ListSummaryItem

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
        .font(.caption).foregroundStyle(.secondary)
      Text(item.title).font(.subheadline).lineLimit(1)
      Spacer(minLength: 4)
      if let amount {
        Text(amount).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
    }
  }

  private var amount: String? {
    let number = item.amount.map { value in
      value == value.rounded() ? String(Int(value)) : value.formatted()
    }
    let parts = [number, item.unit].compactMap { $0 }.filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: " ")
  }
}

/// How old the picture is — only once it is older than an hour: the server was out of reach.
private struct Footer: View {
  let saved: Date
  let now: Date

  var shown: Bool { now.timeIntervalSince(saved) > 60 * 60 }

  var body: some View {
    if shown {
      let label =
        Calendar.current.isDate(saved, inSameDayAs: now)
        ? saved.formatted(date: .omitted, time: .shortened)
        : saved.formatted(.dateTime.day().month(.abbreviated))
      Text(String(format: NSLocalizedString("widget.asOf", comment: ""), label))
        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
    }
  }
}

/// An occurrence with its times read; one the widget cannot read is left out.
private struct Shown {
  let occurrence: AgendaOccurrence
  let start: Date
  let end: Date
  /// The day it is listed under: today for one that began earlier and still runs.
  let day: Date

  /// The start; until when, for one that began on an earlier day; nothing for a whole day.
  var time: String? {
    if occurrence.allDay { return nil }
    if start < day {
      return String(
        format: NSLocalizedString("widget.until", comment: ""),
        end.formatted(date: .omitted, time: .shortened))
    }
    return start.formatted(date: .omitted, time: .shortened)
  }

  /// What is not over at [now] — the picture may be hours old, and what is over leaves the
  /// agenda without asking anyone.
  static func upcoming(_ occurrences: [AgendaOccurrence], at now: Date) -> [Shown] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    return occurrences.compactMap { occurrence in
      guard let start = localDate(occurrence.start) else { return nil }
      let end = localDate(occurrence.end) ?? start
      let over = occurrence.allDay ? calendar.startOfDay(for: end) < today : end < now
      if over { return nil }
      return Shown(
        occurrence: occurrence, start: start, end: end,
        day: max(calendar.startOfDay(for: start), today))
    }
  }
}

private func dayLabel(_ day: Date, now: Date) -> String {
  let calendar = Calendar.current
  if calendar.isDate(day, inSameDayAs: now) { return NSLocalizedString("widget.today", comment: "") }
  if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) {
    return NSLocalizedString("widget.tomorrow", comment: "")
  }
  return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
}

private func title(_ kind: HomeWidgetKind) -> LocalizedStringKey {
  switch kind {
  case .agenda: "widget.agenda.name"
  case .shopping: "widget.shopping.name"
  case .tasks: "widget.tasks.name"
  case .kanban: "widget.kanban.name"
  }
}

/// A calendar's color token as the app draws it, in the light and the dark theme
/// (`hiwiski_theme.dart`). An unknown token falls back to slate, as everywhere.
private func accent(_ token: String?) -> Color {
  let (light, dark): (UInt32, UInt32) =
    switch token {
    case "BLUE": (0x1F6FB2, 0x8FC7F5)
    case "RUST": (0xB3541E, 0xFFB68C)
    case "VIOLET": (0x7B4FA8, 0xD5BAFF)
    case "GREEN": (0x2E7D5B, 0x8ADCB4)
    case "PINK": (0xC2185B, 0xFFB0C8)
    case "OCHRE": (0x8D6E00, 0xE5C44C)
    case "TEAL": (0x00696D, 0x80D4D8)
    default: (0x5F6368, 0xC4C7C5)
    }
  return Color(
    UIColor { traits in
      let value = traits.userInterfaceStyle == .dark ? dark : light
      return UIColor(
        red: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1)
    })
}
