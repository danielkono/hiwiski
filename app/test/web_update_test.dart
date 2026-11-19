import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/data/update/web_build_repository.dart';
import 'package:hiwiski/app/stores.dart';

/// **A tab left open across an update says so**: the build the server
/// served at the start is the running one; another one later means "Reload".
void main() {
  late _Builds builds;
  late ProviderContainer container;

  setUp(() {
    builds = _Builds();
    container = ProviderContainer(
      overrides: [
        webBuildRepositoryProvider.overrideWithValue(builds),
        // What runs in the browser; the tests run on the VM.
        servedWebAppProvider.overrideWithValue(true),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<bool> checkWith(String? served) async {
    builds.served_ = served;
    await container.read(webUpdateStoreProvider).check();
    return container.read(webUpdateProvider);
  }

  test('the same build is no update', () async {
    expect(await checkWith('a1'), isFalse);
    expect(await checkWith('a1'), isFalse);
  });

  test('another build is one, and stays one', () async {
    expect(await checkWith('a1'), isFalse);
    expect(await checkWith('b2'), isTrue);
    // Offline for a moment: still the old app in the tab.
    expect(await checkWith(null), isTrue);
  });

  test('offline at the start, the first answer is the running build', () async {
    expect(await checkWith(null), isFalse);
    expect(await checkWith('a1'), isFalse);
    expect(await checkWith('b2'), isTrue);
  });
}

class _Builds extends WebBuildRepository {
  String? served_;

  @override
  Future<String?> served() async => served_;
}
