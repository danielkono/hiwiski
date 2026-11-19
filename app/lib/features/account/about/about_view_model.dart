import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../app/stores.dart';

part 'about_view_model.g.dart';

/// Account → About: which app this is, in which version, against which server.
@immutable
class const AboutState({
  /// This build's version; empty in a development build.
  required final String appVersion,

  /// This build's number; empty in a development build.
  required final String appBuild,

  /// From the last handshake — `null` before there was one.
  required final String? serverVersion,
});

@riverpod
Future<({String version, String build})> _appVersion(Ref ref) =>
    ref.watch(appInfoRepositoryProvider).version();

@riverpod
class AboutViewModel extends _$AboutViewModel {
  @override
  Future<AboutState> build() async {
    final serverVersion = ref.watch(
      sessionProvider.select((s) => s.handshake?.serverVersion),
    );
    final app = await ref.watch(_appVersionProvider.future);
    return AboutState(
      appVersion: app.version,
      appBuild: app.build,
      serverVersion: serverVersion,
    );
  }
}
