import 'package:file_picker/file_picker.dart';

/// The system's file dialog on the device.
///
/// One file at a time here: the dialog on the device offers no more anyway — [single]
/// is for the browser's.
Future<List<PlatformFile>> pickFiles({
  FileType type = .any,
  List<String>? allowedExtensions,
  bool single = false,
}) => FilePicker.pickFiles(
  type: type,
  allowedExtensions: allowedExtensions,
  // An iPhone keeps its photos as HEIC, which the server does not take (JPEG, PNG,
  // GIF, WebP): every picture from the photo library was refused. "Compatible" has
  // iOS hand over a JPEG instead, converting where it must. It applies to the photo
  // library only — a HEIC chosen in the Files app, on a Mac or on Android still
  // arrives as it is, and the server's refusal says which formats it takes.
  darwinOptions: const DarwinOptions(assetRepresentationMode: .compatible),
);
