/// The kinds of calendar — and which of them are **locked**.
library;

/// Belongs to a subscription: the source fills it, nobody else.
const kindExternal = 'EXTERNAL';

/// Our own, from an import, but locked like a subscription: its events stay as the
/// file had them, and only a further import changes them.
const kindImported = 'IMPORTED';

/// Whether the calendar's events are read only and it takes no new ones. Locked
/// calendars are not offered when creating an event.
bool isLockedCalendar(String? kind) =>
    kind == kindExternal || kind == kindImported;
