import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/l10n/generated/app_localizations.dart';
import '../../../../../core/routing/item_navigation.dart';
import '../../../../../core/theme/hiwiski_metrics.dart';
import '../../../../../core/theme/hiwiski_symbols.dart';
import '../../../../../core/theme/hiwiski_tokens.dart';
import '../../../../../domain/wiki/wiki_page.dart';
import '../../../view/mindmap/mindmap_members.dart';
import '../../../view/mindmap/mindmap_scene.dart';
import '../../page_view_model.dart';

/// The mind map below a page's text, as a picture: the whole canvas fitted into a
/// card, nothing on it to tap. A tap on the card — or its "Full screen" button, as on
/// a picture — opens the canvas, where it is moved around and edited.
class MindmapPreviewCard extends ConsumerWidget {
  const MindmapPreviewCard({
    super.key,
    required this.page,
    required this.state,
  });

  final WikiPage page;
  final PageState state;

  /// Full screen, growing out of the card.
  void _open(BuildContext context) {
    final box = context.findRenderObject();
    final from = box is RenderBox
        ? box.localToGlobal(Offset.zero) & box.size
        : Offset.zero & MediaQuery.sizeOf(context);
    // The route answers nothing here.
    openMindmap(context, pageId: page.id, from: from).ignore();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final scheme = Theme.of(context).colorScheme;
    final map = state.mindmap;
    final area = MindmapScene.areaOf(map);
    return Padding(
      padding: const .only(top: HiwiskiMetrics.space20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = map.isEmpty
              ? HiwiskiMetrics.mindmapPreviewMinHeight
              : (width * area.height / area.width).clamp(
                  HiwiskiMetrics.mindmapPreviewMinHeight,
                  HiwiskiMetrics.mindmapPreviewMaxHeight,
                );
          return Material(
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            clipBehavior: .antiAlias,
            child: InkWell(
              onTap: () => _open(context),
              child: SizedBox(
                height: height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: map.isEmpty
                          ? _Empty(writable: state.writable)
                          : Semantics(
                              label: l.mindmapPreview(map.nodes.length),
                              child: ExcludeSemantics(
                                child: Padding(
                                  padding: const .all(HiwiskiMetrics.space12),
                                  child: FittedBox(
                                    child: MindmapMembers(
                                      members: state.members,
                                      child: MindmapScene(
                                        map: map,
                                        area: area,
                                        linkTarget: (target) =>
                                            state.mindmapTargets[target],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                    Positioned(
                      top: HiwiskiMetrics.space8,
                      right: HiwiskiMetrics.space8,
                      child: IconButton.filledTonal(
                        tooltip: l.mindmapFullscreen,
                        icon: const Icon(HiwiskiSymbols.openInFull),
                        onPressed: () => _open(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.writable});

  final bool writable;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Center(
      child: Padding(
        padding: const .all(HiwiskiMetrics.space24),
        child: Column(
          mainAxisSize: .min,
          children: [
            Icon(
              HiwiskiSymbols.hub,
              size: HiwiskiMetrics.icon48,
              color: context.scheme.onSurfaceVariant,
            ),
            const SizedBox(height: HiwiskiMetrics.space8),
            Text(l.mindmapEmpty, textAlign: .center),
            if (writable)
              Text(
                l.mindmapEmptyHint,
                textAlign: .center,
                style: context.texts.bodySmall?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
