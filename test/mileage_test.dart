import 'package:flutter_test/flutter_test.dart';
import 'package:sole_miles/domain/mileage.dart';

void main() {
  final shoe = GearItem(id: 'shoe', category: 'running', retireMeters: 500000);
  final other = GearItem(
    id: 'other',
    category: 'running',
    retireMeters: 500000,
  );
  final court = GearItem(id: 'court', category: 'court', retireMeters: 100000);
  final gear = {
    for (final item in [shoe, other, court]) item.id: item,
  };
  final now = DateTime.utc(2026, 3, 2);
  Activity run(
    String id,
    int? meters,
    DateTime at, [
    List<String> ids = const ['shoe'],
  ]) => Activity(id: id, meters: meters, atUtc: at, gearIds: ids);

  test('unit conversions retain integer meters at wear boundaries', () {
    for (final meters in [1, 2, 425000, 500000, 500001, 123456789]) {
      for (final unit in DistanceUnit.values) {
        expect(
          Mileage.fromDisplay(Mileage.display(meters, unit), unit),
          meters,
        );
      }
    }
    for (final bad in ['0', '-1', 'NaN', 'Infinity', 'abc', '0.00000000001']) {
      expect(
        () => Mileage.fromDisplay(bad, DistanceUnit.kilometers),
        throwsA(isA<DomainError>()),
      );
    }
    expect(() => run('bad', 0, now), throwsA(isA<DomainError>()));
    expect(() => run('bad', -1, now), throwsA(isA<DomainError>()));
  });

  test('odometer recomputes on edit/delete; unknown and archived history', () {
    final original = run('a', 1000, now);
    final unknown = run('b', null, now);
    final ledger = ActivityLedger([shoe, court]);
    ledger.save(original);
    ledger.save(unknown);
    expect(ledger.odometer(shoe.id), 1000);
    ledger.save(run('a', 1500, now));
    expect(ledger.odometer(shoe.id), 1500);
    ledger.delete('a');
    expect(ledger.odometer(shoe.id), 0);
    final archived = GearItem(
      id: 'shoe',
      category: 'running',
      retireMeters: 500000,
      archived: true,
    );
    expect(archived.archived, isTrue);
    expect(Mileage.odometer(archived.id, [original]), 1000);
  });

  test('85 and 100 percent inclusive boundaries', () {
    expect(Mileage.wear(424999, 500000), WearState.healthy);
    expect(Mileage.wear(425000, 500000), WearState.nudge);
    expect(Mileage.wear(500000, 500000), WearState.retire);
    expect(Mileage.wear(500001, 500000), WearState.retire);
  });

  test(
    '28-day UTC window includes start and now, excludes future, archived',
    () {
      final activities = [
        run('start', 100, now.subtract(const Duration(days: 28))),
        run(
          'before',
          900,
          now.subtract(const Duration(days: 28, microseconds: 1)),
        ),
        run('today', 200, now, ['shoe', 'court']),
        run('future', 900, now.add(const Duration(microseconds: 1))),
        run('unknown', null, now),
      ];
      expect(
        Mileage.rotation(
          [
            shoe,
            court,
            GearItem(
              id: 'old',
              category: 'run',
              retireMeters: 1,
              archived: true,
            ),
          ],
          activities,
          now,
        ),
        {'shoe': 300, 'court': 200},
      );
    },
  );

  test('one gear per category, typed rejection of invalid references', () {
    Mileage.validate(run('ok', 10, now, ['shoe', 'court']), gear);
    final ledger = ActivityLedger(gear.values);
    expect(
      () => ledger.save(run('bad', 10, now, ['shoe', 'other'])),
      throwsA(isA<DomainError>()),
    );
    expect(ledger.activities, isEmpty);
    expect(
      () => Mileage.validate(run('bad', 10, now, ['shoe', 'other']), gear),
      throwsA(
        isA<DomainError>().having(
          (e) => e.code,
          'code',
          DomainErrorCode.duplicateCategory,
        ),
      ),
    );
    expect(
      () => Mileage.validate(run('bad', 10, now, ['missing']), gear),
      throwsA(
        isA<DomainError>().having(
          (e) => e.code,
          'code',
          DomainErrorCode.unknownGear,
        ),
      ),
    );
    expect(
      () => Mileage.validate(run('bad', 10, now, ['shoe', 'shoe']), gear),
      throwsA(
        isA<DomainError>().having(
          (e) => e.code,
          'code',
          DomainErrorCode.duplicateId,
        ),
      ),
    );
  });
}
