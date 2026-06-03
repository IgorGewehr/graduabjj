import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:graduabjj/widgets/common/back_button_handler.dart';

void main() {
  group('parentLocation (pure path logic)', () {
    test('single-segment root returns null', () {
      expect(parentLocation('/admin'), isNull);
      expect(parentLocation('/portal'), isNull);
    });

    test('nested admin path strips last segment', () {
      expect(parentLocation('/admin/alunos/123'), '/admin/alunos');
      expect(parentLocation('/admin/alunos'), '/admin');
    });

    test('nested portal path strips last segment', () {
      expect(parentLocation('/portal/competicoes/123'), '/portal/competicoes');
      expect(parentLocation('/portal/competicoes'), '/portal');
    });

    test('null / empty / trailing-slash edge cases', () {
      expect(parentLocation(null), isNull);
      expect(parentLocation(''), isNull);
      // Trailing slash: empty segments are filtered, so this is single-segment.
      expect(parentLocation('/admin/'), isNull);
    });
  });

  group('BackButtonHandler widget', () {
    // Captures calls to SystemNavigator.pop (channel flutter/platform).
    late int systemPopCount;

    setUp(() {
      systemPopCount = 0;
    });

    void installPlatformMock(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'SystemNavigator.pop') {
            systemPopCount++;
          }
          return null;
        },
      );
    }

    /// Pumps a BackButtonHandler wrapped in a MaterialApp + GoRouter so that
    /// context.go / context.canPop resolve, plus a ScaffoldMessenger for the
    /// double-tap snackbar. Returns the captured go() destinations.
    Future<List<String>> pumpHandler(
      WidgetTester tester, {
      required bool isRootRoute,
      required String currentLocation,
    }) async {
      final goLog = <String>[];
      final router = GoRouter(
        initialLocation: currentLocation,
        routes: [
          GoRoute(
            path: '/portal',
            builder: (c, s) => _Host(
              child: BackButtonHandler(
                isRootRoute: isRootRoute,
                currentLocation: currentLocation,
                child: const Scaffold(body: SizedBox.expand()),
              ),
            ),
          ),
          GoRoute(
            path: '/portal/competicoes',
            builder: (c, s) {
              goLog.add('/portal/competicoes');
              return const Scaffold(body: Text('competicoes'));
            },
          ),
          GoRoute(
            path: '/portal/competicoes/:id',
            builder: (c, s) => _Host(
              child: BackButtonHandler(
                isRootRoute: isRootRoute,
                currentLocation: currentLocation,
                child: const Scaffold(body: SizedBox.expand()),
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();
      return goLog;
    }

    testWidgets('root: first back shows hint (no exit), second within window exits',
        (tester) async {
      installPlatformMock(tester);
      await pumpHandler(
        tester,
        isRootRoute: true,
        currentLocation: '/portal',
      );

      // First system back press.
      final handled1 = await tester.binding.handlePopRoute();
      await tester.pump();
      expect(handled1, isTrue, reason: 'PopScope should intercept the pop');
      expect(systemPopCount, 0, reason: 'first back must NOT exit the app');

      // Second back press within the 2s window.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(systemPopCount, 1, reason: 'second back within window exits once');
    });

    // NOTE: the "after window" reset path uses DateTime.now() (real wall
    // clock), which tester.pump(Duration) cannot advance. We therefore use a
    // real delay slightly longer than the 2s window so the timer genuinely
    // resets. Kept short by sharing the same expiry semantics.
    testWidgets('root: back AFTER window resets timer (no exit)',
        (tester) async {
      installPlatformMock(tester);
      await pumpHandler(
        tester,
        isRootRoute: true,
        currentLocation: '/portal',
      );

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(systemPopCount, 0);

      // Wait past the real 2s double-tap window (wall clock).
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2100)),
      );

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(systemPopCount, 0,
          reason: 'back after the window resets the timer, no exit');
    });

    testWidgets('sub-route: back navigates to parent location', (tester) async {
      installPlatformMock(tester);
      final goLog = await pumpHandler(
        tester,
        isRootRoute: false,
        currentLocation: '/portal/competicoes/123',
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // No app exit on a sub-route; instead it navigated to the parent.
      expect(systemPopCount, 0);
      expect(goLog, contains('/portal/competicoes'));
      expect(find.text('competicoes'), findsOneWidget);
    });
  });
}

/// Minimal host that provides a ScaffoldMessenger ancestor for the snackbar
/// shown on the first root back-press.
class _Host extends StatelessWidget {
  const _Host({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
