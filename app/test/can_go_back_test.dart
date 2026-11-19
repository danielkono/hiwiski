import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiwiski/core/routing/item_navigation.dart';

/// **"Back" belongs to a screen with one below it.** Asked of the router, the screen
/// below an open one could go back too — the wiki's tree showed a back button while
/// the page on top was swiped away.
void main() {
  testWidgets('the screen below an open one has nothing to go back to', (
    tester,
  ) async {
    final contexts = <String, BuildContext>{};
    Widget screen(String name) => Builder(
      builder: (context) {
        contexts[name] = context;
        return Text(name);
      },
    );
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => screen('below')),
        GoRoute(path: '/top', builder: (_, _) => screen('top')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(canGoBack(contexts['below']!), isFalse);

    // The pushed screen lives until it is popped; nothing waits for that.
    router.push<void>('/top').ignore();
    await tester.pumpAndSettle();
    expect(canGoBack(contexts['top']!), isTrue);
    expect(canGoBack(contexts['below']!), isFalse);
  });
}
