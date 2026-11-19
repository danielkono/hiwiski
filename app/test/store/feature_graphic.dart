import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'store_style.dart';
import 'store_texts.dart';

/// The Play feature graphic, 1024 × 500: the app's icon, its name, a line about it
/// and the three areas behind five dots in the scenes' colours.
class FeatureGraphic extends StatelessWidget {
  const FeatureGraphic({
    super.key,
    required this.icon,
    required this.tagline,
    required this.areas,
  });

  static const size = Size(1024, 500);

  final ui.Image icon;
  final String tagline;
  final String areas;

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: size,
    child: ColoredBox(
      color: storeBackground,
      child: Padding(
        padding: const .only(left: 112, right: 96),
        child: Row(
          spacing: 48,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: .circular(44),
                boxShadow: [
                  BoxShadow(
                    color: storeShadow.withValues(alpha: 0.16),
                    offset: const Offset(0, 16),
                    blurRadius: cssBlur(32),
                  ),
                  BoxShadow(
                    color: storeShadow.withValues(alpha: 0.10),
                    offset: const Offset(0, 4),
                    blurRadius: cssBlur(8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: .circular(44),
                child: RawImage(
                  image: icon,
                  width: 200,
                  height: 200,
                  fit: .fill,
                  filterQuality: .medium,
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: [
                  Text(
                    'Hiwiski',
                    style: roboto(
                      96,
                      .w700,
                      storeInk,
                      height: 1,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    tagline,
                    style: roboto(32, .w400, storeSubline, height: 1.3),
                  ),
                  const SizedBox(height: 14 + 12),
                  Row(
                    spacing: 14,
                    children: [
                      Row(
                        spacing: 8,
                        children: [
                          for (final color in {...storeAccents})
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: color,
                                shape: .circle,
                              ),
                            ),
                        ],
                      ),
                      Text(areas, style: roboto(24, .w500, storePillInk)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
