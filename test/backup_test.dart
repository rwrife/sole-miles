import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sole_miles/data/backup.dart';
import 'package:sole_miles/data/mileage_repository.dart';
import 'package:sole_miles/domain/mileage.dart';

const a = '00000000-0000-4000-8000-000000000001';
const b = '00000000-0000-4000-8000-000000000002';
const c = '00000000-0000-4000-8000-000000000003';

void main() {
  late Directory directory;
  late SqliteMileageRepository repository;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('sole-miles-backup-');
    repository = SqliteMileageRepository.openAt(directory);
  });
  tearDown(() {
    repository.close();
    directory.deleteSync(recursive: true);
  });

  test(
    'JSON full fidelity incl optional photos; replace and safety snapshot',
    () {
      repository.saveGear(
        GearItem(
          id: a,
          category: 'trail',
          retireMeters: 900000,
          name: 'A',
          brand: 'B',
          unit: DistanceUnit.miles,
        ),
      );
      repository.savePhoto(a, Uint8List.fromList([1, 2, 3]));
      repository.saveActivities([
        Activity(
          id: b,
          atUtc: DateTime.utc(2026, 1, 2),
          gearIds: [a],
          meters: 1609,
          note: 'felt good',
        ),
      ]);
      expect(MileageBackup.parse(repository.backup().encode()).photos, isEmpty);
      final backup = MileageBackup.parse(
        repository.backup(includePhotos: true).encode(),
      );
      expect(backup.photos[a], [1, 2, 3]);
      expect(backup.gear.single.unit, DistanceUnit.miles);
      repository.deleteActivity(b);
      final snapshot = repository.restore(backup, replace: true);
      expect(snapshot.existsSync(), true);
      expect(
        MileageBackup.parse(snapshot.readAsStringSync()).activities,
        isEmpty,
      );
      expect(repository.activities.single.note, 'felt good');
      expect(repository.gear.single.brand, 'B');
      expect(repository.photoPath(a), isNotNull);
      expect(Mileage.odometer(a, repository.activities), 1609);
    },
  );

  test('bad and future JSON are rejected without changes', () {
    repository.saveGear(GearItem(id: a, category: 'trail', retireMeters: 100));
    final original = repository.backup().encode();
    for (final text in [
      '{invalid',
      original.replaceFirst('"schemaVersion":1', '"schemaVersion":2'),
      original.replaceFirst('"retireMeters":100', '"retireMeters":-2'),
      original.replaceFirst('"id":"$a"', '"id":"../evil"'),
    ]) {
      expect(() => MileageBackup.parse(text), throwsFormatException);
      expect(repository.backup().encode(), original);
    }
  });

  test('merge adds new records; conflicts never overwrite', () {
    repository.saveGear(GearItem(id: a, category: 'trail', retireMeters: 100));
    final incoming = MileageBackup(
      [GearItem(id: c, category: 'walk', retireMeters: 500)],
      [
        Activity(id: b, atUtc: DateTime.utc(2026), gearIds: [c], meters: null),
      ],
      {},
    );
    repository.restore(incoming, replace: false);
    expect(repository.gear.length, 2);
    expect(repository.activities.single.meters, isNull);
    final before = repository.backup().encode();
    expect(
      () => repository.restore(incoming, replace: false),
      throwsFormatException,
    );
    expect(repository.backup().encode(), before);
  });

  test('CSV unit selection, unknown distance and formula-safe notes', () {
    final item = GearItem(
      id: a,
      name: '=danger',
      category: 'walk',
      retireMeters: 1000,
    );
    final activity = Activity(
      id: b,
      atUtc: DateTime.utc(2026),
      gearIds: [a],
      meters: null,
      note: '=HYPERLINK("bad")',
    );
    final csv = MileageBackup.csvActivities([activity], DistanceUnit.miles);
    expect(csv, contains('"\'=HYPERLINK(""bad"")"'));
    expect(csv, contains('distance_miles'));
    expect(csv, contains('"","$a"'));
    expect(
      MileageBackup.csvTotals([item], [activity], DistanceUnit.kilometers),
      contains('"\'=danger"'),
    );
    expect(
      jsonDecode(
        MileageBackup([item], [activity], {}).encode(),
      )['schemaVersion'],
      1,
    );
  });
}
