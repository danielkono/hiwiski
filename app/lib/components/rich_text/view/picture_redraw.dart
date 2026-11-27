/// Draws a picture again, smaller where it must be, in a format the server takes:
/// `redrawPicture(bytes, edge:)`. On a device with the app's own engine; in the
/// browser with the browser's, which reads what it shows — a HEIC in Safari.
library;

export 'picture_redraw_io.dart'
    if (dart.library.js_interop) 'picture_redraw_web.dart';
