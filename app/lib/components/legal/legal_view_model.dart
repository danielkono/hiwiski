import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/stores.dart';
import '../../domain/legal/legal_links.dart';

part 'legal_view_model.g.dart';

/// The operator's legal pages: named by the build for the demo, which
/// has no server, and otherwise by the server in its handshake — or by nobody.
@riverpod
class LegalViewModel extends _$LegalViewModel {
  @override
  LegalLinks build() {
    final handshake = ref.watch(sessionProvider.select((s) => s.handshake));
    return .forInstance(
      notice: handshake?.legalNoticeUrl,
      privacy: handshake?.privacyUrl,
    );
  }
}
