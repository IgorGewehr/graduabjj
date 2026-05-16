import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:graduabjj/api/feature_flags.dart';

void main() {
  group('TatamiFlags', () {
    test('default allOff = todas falsas', () {
      const f = TatamiFlags.allOff;
      expect(f.useTatamiIdentity, isFalse);
      expect(f.useTatamiReads, isFalse);
      expect(f.useTatamiWrites, isFalse);
      expect(f.useTatamiFinancials, isFalse);
      expect(f.useTatamiAttendance, isFalse);
      expect(f.useTatamiNotifications, isFalse);
      expect(f.useTatamiStore, isFalse);
      expect(f.useTatamiCompetitions, isFalse);
    });

    test('copyWith só substitui o campo passado', () {
      final f = TatamiFlags.allOff.copyWith(useTatamiIdentity: true);
      expect(f.useTatamiIdentity, isTrue);
      expect(f.useTatamiReads, isFalse);
      expect(f.useTatamiWrites, isFalse);
    });
  });

  group('tatamiFlagsProvider', () {
    test('default state via container = allOff', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(tatamiFlagsProvider).useTatamiIdentity, isFalse);
    });

    test('override (uso em test) liga a flag', () {
      final c = ProviderContainer(
        overrides: [
          tatamiFlagsProvider.overrideWith(
            (ref) => TatamiFlags.allOff.copyWith(useTatamiIdentity: true),
          ),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(tatamiFlagsProvider).useTatamiIdentity, isTrue);
      expect(c.read(tatamiFlagsProvider).useTatamiReads, isFalse);
    });

    test('mutação via notifier (boot da app pós Remote Config)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      c.read(tatamiFlagsProvider.notifier).state =
          TatamiFlags.allOff.copyWith(useTatamiReads: true);

      expect(c.read(tatamiFlagsProvider).useTatamiReads, isTrue);
    });
  });
}
