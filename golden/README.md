# Golden files

This is where **both sides check against the same truth**.

Server and client expand recurrence rules with different libraries — `lib-recur` in
Java, `rrule` in Dart. Two libraries that behave differently in edge cases are not two
opinions that can stand side by side: an event the phone shows on Monday and the server
on Tuesday is worse than no recurrence at all. Getting the two to agree was the most
expensive work in the project, and these files are what keeps them agreeing.

| File | Checked by |
| --- | --- |
| `recurrence.json` | `server/app/src/test/…/recurrence/RecurrenceGoldenTest.java` and `app/test/recurrence_golden_test.dart` |
| `recurrence-limits.json` | `server/app/src/test/…/recurrence/RecurrenceLimitsGoldenTest.java` and `app/test/recurrence_limits_golden_test.dart` — the rules both sides refuse to expand |
| `occurrences.json` | `server/app/src/test/…/calendar/internal/OccurrencesGoldenTest.java` and `app/test/occurrence_golden_test.dart` — whole events in a window: time forms, multi-day events, cancelled and moved occurrences; the server expands the home screen widgets' agenda with it |
| `links.json` | `server/app/src/test/…/link/LinkParserGoldenTest.java` and `app/test/link_parse_golden_test.dart` |

References live here for the same reason: the server parses the text to write the
`link` table, the client parses it to draw the chips and to fill the info bar offline.
References are parsed from the text, not kept by hand — which only works if there is
one reading of the text. A reference the phone shows and the server does not know is
worse than none at all.

**One file, two tests.** Whoever adds a case adds it exactly here, with a `why`;
whoever gets it green on only one side has found the difference that needs resolving.
