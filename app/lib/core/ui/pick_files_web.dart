import 'dart:async';
import 'dart:js_interop';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker_web/file_picker_web.dart';
import 'package:web/web.dart' as web;

/// The browser's file dialog, opened by the app itself rather than by the plugin.
///
/// The plugin took its file input out of the page right after opening the dialog,
/// and nothing held on to it then. Safari on the iPhone dropped the input while the
/// dialog was open (converting photos to JPEG takes a while), its `change` never
/// came, and the pick ended without a word — pictures chosen, nothing added. Before
/// that, the plugin took the window regaining focus as a cancel, which Safari reports
/// before the files.
///
/// Here the input stays in the page and in [_open] until the browser answers:
/// `change` with the files, `cancel` without. A browser that never says `cancel`
/// leaves the pick open until the next one, which ends it empty.
Future<List<PlatformFile>> pickFiles({
  FileType type = .any,
  List<String>? allowedExtensions,
}) {
  _open?.call();
  final input = web.HTMLInputElement()
    ..type = _file
    ..multiple = true
    ..accept = _accept(type, allowedExtensions)
    ..style.cssText = _offscreen;
  final chosen = Completer<web.FileList?>();
  void answer(web.FileList? files) {
    if (chosen.isCompleted) return;
    chosen.complete(files);
    input.remove();
    _open = null;
  }

  _open = () => answer(null);

  input
    ..addEventListener(_change, ((web.Event _) => answer(input.files)).toJS)
    ..addEventListener(_cancel, ((web.Event _) => answer(null)).toJS);
  web.document.body?.append(input);
  input.click();
  return chosen.future.then(_read);
}

/// Ends the pick still waiting — held, too, so the input is not dropped.
VoidCallback? _open;

Future<List<PlatformFile>> _read(web.FileList? files) async {
  if (files == null) return const [];
  return [
    for (var i = 0; i < files.length; i++)
      if (files.item(i) case final file?)
        WebPlatformFile(
          name: file.name,
          uri: Uri(path: file.name),
          bytes: (await file.arrayBuffer().toDart).toDart.asUint8List(),
          bytesLength: file.size,
        ),
  ];
}

String _accept(FileType type, List<String>? allowedExtensions) =>
    switch (type) {
      .image => _images,
      .custom => [
        for (final extension in allowedExtensions ?? const <String>[])
          '.$extension',
      ].join(','),
      _ => '',
    };

const _file = 'file';
const _change = 'change';
const _cancel = 'cancel';
const _images = 'image/*';

/// In the page but out of sight; `display: none` is avoided, which older Safari
/// would not open a dialog for.
const _offscreen =
    'position:fixed;left:-100px;top:0;width:1px;height:1px;opacity:0';
