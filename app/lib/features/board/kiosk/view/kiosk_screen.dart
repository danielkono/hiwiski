import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/api/generated/export.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../domain/board/board_items.dart';
import '../../view/board_grid.dart';
import '../../widget_tile/view/widget_tile.dart';
import '../kiosk_view_model.dart';
import '../../../../core/ui/failure_text.dart';

/// The dashboard on the wall tablet: `…/board/<token>`.
///
/// **No sign-in, no navigation, no header, no way into the app.** A wall tablet as a full account would bring along lots of questions
/// nobody wants to answer — a token without expiry in the keychain, an app
/// that never signs out, a way out of full screen without a keyboard.
///
/// **If the server is gone, whatever was shown last stays up** with a narrow line
/// "last updated 14:32" — not an empty screen. That is the difference
/// between a tablet hanging on the wall and a page in a browser.
class KioskScreen extends ConsumerStatefulWidget {
  const KioskScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends ConsumerState<KioskScreen> {
  @override
  void initState() {
    super.initState();
    // Keep the screen awake. A wall tablet that goes black after two
    // minutes is not a wall tablet.
    unawaited(WakelockPlus.enable());
  }

  @override
  void dispose() {
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(kioskViewModelProvider(widget.token));
    return Scaffold(
      // High-contrast display.
      backgroundColor: context.scheme.surface,
      body: SafeArea(
        child: switch ((state.board, state.error)) {
          (null, final error?) => _Failure(message: error),
          (null, _) => const Center(child: CircularProgressIndicator()),
          (final board?, _) => _Board(
            board: board,
            tiles: state.tiles,
            lastUpdate: state.lastUpdate,
            stale: state.stale,
          ),
        },
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({
    required this.board,
    required this.tiles,
    required this.lastUpdate,
    required this.stale,
  });

  final BoardView board;
  final ProviderContainer tiles;
  final DateTime? lastUpdate;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).toString();

    if (board.widgets.isEmpty) {
      return Center(
        child: Padding(
          padding: const .all(HiwiskiMetrics.space32),
          child: Text(
            l.boardKioskEmpty,
            textAlign: .center,
            style: context.texts.titleMedium,
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          // Too narrow: below each other in reading order — the same board that hangs
          // on the wall can be set up on the phone.
          child: BoardGrid<WidgetView>(
            tiles: board.widgets,
            placeOf: (tile) => (
              x: tile.gridX,
              y: tile.gridY,
              width: tile.gridW,
              height: tile.gridH,
            ),
            columns: board.columns,
            tilePadding: const .all(HiwiskiMetrics.space6),
            stackedGap: HiwiskiMetrics.space12,
            stackedPadding: const .all(HiwiskiMetrics.space12),
            scrolls: true,
            tileBuilder: (tile) => UncontrolledProviderScope(
              container: tiles,
              child: _KioskCard(widget: tile),
            ),
          ),
        ),
        // The narrow line — only when the server is gone. As long as everything runs, it
        // says nothing and so takes no space either.
        if (lastUpdate case final lastUpdate? when stale)
          Container(
            width: .infinity,
            color: context.scheme.surfaceContainerHighest,
            padding: const .symmetric(
              horizontal: HiwiskiMetrics.space12,
              vertical: HiwiskiMetrics.space4,
            ),
            child: Text(
              l.boardLastUpdated(DateFormat.Hm(locale).format(lastUpdate)),
              style: context.texts.bodySmall?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// A tile in the kiosk — the same content, larger and without controls.
class _KioskCard extends StatelessWidget {
  const _KioskCard({required this.widget});

  final WidgetView widget;

  @override
  Widget build(BuildContext context) {
    // The kiosk view has no local database: it runs without sign-in and
    // gets everything via the address. That is why a row is built here that
    // `WidgetTile` understands — the same component, the same placeholders.
    final row = BoardWidget(
      id: widget.id,
      ownerId: '',
      version: 0,
      boardId: '',
      kind: widget.kind,
      config: _encode(widget.config),
      gridX: widget.gridX,
      gridY: widget.gridY,
      gridW: widget.gridW,
      gridH: widget.gridH,
      position: widget.position,
    );

    return Card(
      child: Padding(
        padding: const .all(HiwiskiMetrics.space16),
        child: SingleChildScrollView(
          child: WidgetTile(widget: row, kiosk: true),
        ),
      ),
    );
  }

  static String _encode(Map<String, dynamic>? config) =>
      config == null ? '{}' : jsonEncode(config);
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const .all(HiwiskiMetrics.space32),
      // The code turned into a sentence: "network.unreachable" on the wall told
      // nobody anything.
      child: Text(
        failureTextForCode(context, message),
        style: context.texts.titleMedium,
      ),
    ),
  );
}
