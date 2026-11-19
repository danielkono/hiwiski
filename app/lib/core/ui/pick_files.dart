/// Opens the system's file dialog — the one way the app picks files, so the platform
/// quirks are handled in one place: `pickFiles(type:, allowedExtensions:)`.
library;

export 'pick_files_stub.dart'
    if (dart.library.js_interop) 'pick_files_web.dart';
