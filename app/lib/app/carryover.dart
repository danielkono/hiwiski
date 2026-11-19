import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/media/media_repository.dart';
import 'repositories.dart';
import 'stores.dart';

part 'carryover.g.dart';

/// What a device used without a server takes along that does not go through the
/// outbox: its shopping categories and the images it added, its own
/// picture among them.
///
/// After every sync while signed in: the images wait for their carriers, and those
/// arrive with the push. Each step clears itself once it is through, so after the
/// first run that gets everything there, this does nothing any more.
@Riverpod(keepAlive: true)
void carryover(Ref ref) {
  bool running = false;

  Future<void> run() async {
    if (running) return;
    final session = ref.read(sessionProvider);
    if (session.stage != .signedIn) return;
    running = true;
    try {
      await ref.read(catalogRepositoryProvider).carryOver();
      final uploaded = await ref.read(mediaRepositoryProvider).carryOver();
      final member = ref.read(sessionProvider).member;
      for (final image in uploaded) {
        // The picture chosen without a server becomes the member's — unless the
        // account it was signed in to has one already.
        if (image.ownerType == ImageOwnerTypes.member &&
            member != null &&
            member.avatarImageId == null) {
          await ref
              .read(sessionStoreProvider)
              .updateProfile(avatarImageId: image.id);
        }
      }
    } on Object catch (error) {
      // Offline or refused: the next sync tries again.
      debugPrint('hiwiski: carry-over not finished: $error');
    } finally {
      running = false;
    }
  }

  ref.listen(syncStatusProvider.select((status) => status.lastSyncedAt), (
    _,
    synced,
  ) {
    // Its failures are its own to log; the next sync tries again.
    if (synced != null) unawaited(run());
  });
}
