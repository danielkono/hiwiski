import 'package:flutter/material.dart';

import '../theme/hiwiski_metrics.dart';
import '../l10n/generated/app_localizations.dart';

/// The app icon as the screen's logo: 56×56, its corners rounded like a card.
class HiwiskiMark extends StatelessWidget {
  const HiwiskiMark({super.key, this.size = HiwiskiMetrics.logoSize});

  /// The app icon's master, scaled down: the same picture as on the home screen.
  static const _icon = 'assets/brand/hiwiski_icon.png';

  final double size;

  @override
  Widget build(BuildContext context) =>
      // Left-aligned and at its own size: the surrounding column is set to `stretch`,
      // and without this `Align` the square turns into a full-width bar.
      Align(
        alignment: Alignment.centerLeft,
        child: ClipRRect(
          borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
          child: Image.asset(
            _icon,
            width: size,
            height: size,
            fit: .cover,
            // The product's name to a screen reader, not a picture.
            semanticLabel: L.of(context).appName,
          ),
        ),
      );
}
