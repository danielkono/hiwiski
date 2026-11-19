import 'package:clock/clock.dart';
import 'package:uuid/data.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A new id for anything the client creates.
///
/// UUIDv7: it sorts by time, so the outbox order is already in the IDs.
/// Shared vocabulary: the domain needs it as much as the outbox.
///
/// The time comes from `clock`, not from the package's own reading of the system
/// clock: the id also says when something was created ("Created …" in the info
/// panel), and a test that fixes the day must fix that too.
String newId() =>
    _uuid.v7(config: V7Options(clock.now().millisecondsSinceEpoch, null));
