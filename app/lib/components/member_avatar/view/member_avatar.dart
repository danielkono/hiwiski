import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/generated/export.dart';
import '../../../core/theme/hiwiski_accents.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/bounded_image.dart';
import '../member_avatar_view_model.dart';

/// The avatar circle with the initial, in the member's color — or the member's picture,
/// once they have set one ("My account"). The initial stays until the picture is there.
///
/// Radius, not diameter: 13 in a row, 18 in the
/// header, 20 in a chip, 26 on the account card.
class MemberAvatar extends ConsumerWidget {
  const MemberAvatar({
    super.key,
    required this.displayName,
    required this.colorToken,
    this.imageId,
    this.radius = HiwiskiMetrics.avatarMedium,
  });

  MemberAvatar.of(
    Member member, {
    super.key,
    this.radius = HiwiskiMetrics.avatarMedium,
  }) : displayName = member.displayName,
       colorToken = _token(member.colorToken),
       imageId = member.avatarImageId;

  final String displayName;
  final AccentToken colorToken;

  /// The picture in the media store; `null` shows the initial.
  final String? imageId;
  final double radius;

  static AccentToken _token(ColorToken? token) => switch (token) {
    .blue => AccentToken.blue,
    .rust => AccentToken.rust,
    .violet => AccentToken.violet,
    .green => AccentToken.green,
    .pink => AccentToken.pink,
    .ochre => AccentToken.ochre,
    .teal => AccentToken.teal,
    // An unknown token must not cost the screen: an older app has to survive a value
    // that a newer server added to the enum.
    _ => AccentToken.slate,
  };

  String get _initial => displayName.trim().isEmpty
      ? '?'
      : displayName.trim().characters.first.toUpperCase();

  int _decodeEdge(BuildContext context) =>
      (2 * 2 * radius * MediaQuery.devicePixelRatioOf(context)).ceil();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = context.tokens.accent(colorToken);
    final id = imageId;
    final bytes = id == null
        ? null
        : ref.watch(memberAvatarViewModelProvider(id)).value;
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      // Decoded at twice the circle, so a picture that is not square still covers
      // it sharply -- never at whatever size the file declares.
      // A picture that cannot be decoded here — an animated WebP from a server
      // without previews for it, too large (R12) — leaves the initial standing.
      onForegroundImageError: bytes == null ? null : (_, _) {},
      foregroundImage: bytes == null
          ? null
          : boundedImage(
              bytes,
              width: _decodeEdge(context),
              height: _decodeEdge(context),
            ),
      child: Text(
        _initial,
        style: context.texts.labelLarge?.copyWith(
          color: context.tokens.onAccent,
          fontSize: radius,
        ),
      ),
    );
  }
}
