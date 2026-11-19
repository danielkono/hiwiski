import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/ui/pick_files.dart';
import '../../../domain/transfer/transfer_bundle.dart';
import '../../../domain/transfer/transfer_models.dart';
import 'import_keys.dart';
import 'import_sheet.dart';

/// The import in the header of an area's first screen: picks Markdown files or zip
/// archives and opens what they hold as a preview.
///
/// Its symbol is the upload arrow, not a plus: a plus beside the floating "New list"
/// read as a second way of creating one, and it is not — creating is always the
/// floating button.
///
/// [place] says where it stands — a file that does not say what it is becomes a list
/// among the tasks and a page in the wiki.
class ImportButton extends StatelessWidget {
  const ImportButton({super.key, required this.place});

  final ImportPlace place;

  Future<void> _pick(BuildContext context) async {
    final picked = await pickFiles(
      // Only the browser filters reliably by extension: a phone knows no file type
      // for ".md" and greyed out every note. Elsewhere everything can be picked, and
      // the preview says what it could not read.
      type: kIsWeb ? .custom : .any,
      allowedExtensions: kIsWeb ? importExtensions : null,
    );
    if (picked.isEmpty) return;
    final source = ImportSource([
      for (final file in picked)
        TransferFile(file.name, await file.xFile.readAsBytes()),
    ], place: place);
    if (context.mounted) await showImportSheet(context, source: source);
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: ImportKeys.open,
    icon: const Icon(HiwiskiSymbols.upload),
    tooltip: L.of(context).importAction,
    onPressed: () => unawaited(_pick(context)),
  );
}
