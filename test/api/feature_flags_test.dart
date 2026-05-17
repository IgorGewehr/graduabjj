// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:graduabjj/api/feature_flags.dart';

void main() {
  group('TatamiFlags (pós-Fase 1: shim de compatibilidade)', () {
    test('default constructor = todas ligadas', () {
      const f = TatamiFlags();
      expect(f.useTatamiIdentity, isTrue);
      expect(f.useTatamiReads, isTrue);
      expect(f.useTatamiWrites, isTrue);
      expect(f.useTatamiFinancials, isTrue);
      expect(f.useTatamiAttendance, isTrue);
      expect(f.useTatamiNotifications, isTrue);
      expect(f.useTatamiStore, isTrue);
      expect(f.useTatamiCompetitions, isTrue);
    });

    test('allOn / allOff são equivalentes pós-migração (tudo ligado)', () {
      expect(TatamiFlags.allOff.useTatamiReads, isTrue);
      expect(TatamiFlags.allOn.useTatamiReads, isTrue);
    });

    test('copyWith ainda permite desligar campos explicitamente (testes)', () {
      final f = const TatamiFlags().copyWith(useTatamiIdentity: false);
      expect(f.useTatamiIdentity, isFalse);
      expect(f.useTatamiReads, isTrue);
      expect(f.useTatamiWrites, isTrue);
    });
  });

  group('tatamiFlagsProvider', () {
    test('default state via container = tudo ligado', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(tatamiFlagsProvider).useTatamiIdentity, isTrue);
      expect(c.read(tatamiFlagsProvider).useTatamiReads, isTrue);
    });

    test('override em test consegue forçar uma flag a false (regressão)', () {
      final c = ProviderContainer(
        overrides: [
          tatamiFlagsProvider.overrideWith(
            (ref) => const TatamiFlags().copyWith(useTatamiIdentity: false),
          ),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(tatamiFlagsProvider).useTatamiIdentity, isFalse);
      expect(c.read(tatamiFlagsProvider).useTatamiReads, isTrue);
    });

    test('mutação via notifier (boot da app pós Remote Config)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      c.read(tatamiFlagsProvider.notifier).state =
          const TatamiFlags().copyWith(useTatamiReads: false);

      expect(c.read(tatamiFlagsProvider).useTatamiReads, isFalse);
    });
  });
}
