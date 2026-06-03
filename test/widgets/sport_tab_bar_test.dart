import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:graduabjj/core/sports.dart';
import 'package:graduabjj/providers/portal_providers.dart';
import 'package:graduabjj/widgets/sport_tab_bar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('SportTabBar', () {
    testWidgets('renders nothing for a single sport', (tester) async {
      await tester.pumpWidget(wrap(SportTabBar(
        sports: const [SportId.bjj],
        selected: SportId.bjj,
        onSelected: (_) {},
      )));

      expect(find.byType(ChoiceChip), findsNothing);
      // The widget collapses to a SizedBox.shrink().
      final shrink = tester.widget<SizedBox>(find.byType(SizedBox));
      expect(shrink.width, 0);
      expect(shrink.height, 0);
    });

    testWidgets('renders one chip per sport and fires onSelected on tap',
        (tester) async {
      const sports = [SportId.bjj, SportId.muaythai, SportId.karate];
      SportId? picked;

      await tester.pumpWidget(wrap(SportTabBar(
        sports: sports,
        selected: SportId.bjj,
        onSelected: (s) => picked = s,
      )));

      expect(find.byType(ChoiceChip), findsNWidgets(3));

      // Tap the 2nd chip (Muay Thai).
      await tester.tap(find.text(getSport(SportId.muaythai).label));
      await tester.pump();

      expect(picked, SportId.muaythai);
    });
  });

  group('selectedSportProvider', () {
    test('defaults to null and keeps last value per screenKey', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Not chosen yet -> null.
      expect(container.read(selectedSportProvider('k')), isNull);

      // Set a value for key "k".
      container.read(selectedSportProvider('k').notifier).state =
          SportId.muaythai;
      expect(container.read(selectedSportProvider('k')), SportId.muaythai);

      // A different screenKey is independent and still null.
      expect(container.read(selectedSportProvider('k2')), isNull);
    });
  });
}
