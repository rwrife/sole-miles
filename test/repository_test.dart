import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sole_miles/data/mileage_repository.dart';
import 'package:sole_miles/domain/mileage.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  const shoeId = 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d';
  const courtId = 'b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e';
  const act1Id = 'c3d4e5f6-a7b8-4c9d-0e1f-2a3b4c5d6e7f';
  const act2Id = 'd4e5f6a7-b8c9-4d0e-1f2a-3b4c5d6e7f8a';

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sole_miles_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('fresh database initializes schema metadata and user_version = 2', () {
    final repo = SqliteMileageRepository.openAt(tempDir);
    expect(repo.gear, isEmpty);
    expect(repo.activities, isEmpty);
    expect(DateTime.tryParse(repo.installedAtUtc)?.isUtc, isTrue);

    repo.close();

    final db = sqlite3.open(
      '${tempDir.path}${Platform.pathSeparator}mileage.sqlite',
    );
    expect(db.select('PRAGMA user_version').single.columnAt(0), 2);
    db.close();
  });

  test('additive migration upgrades v1 schema to v2 without data loss', () {
    // 1. Manually craft a v1 database fixture
    final dbFile = '${tempDir.path}${Platform.pathSeparator}mileage.sqlite';
    final rawDb = sqlite3.open(dbFile);
    rawDb.execute('''
      CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE gear (
        id TEXT PRIMARY KEY,
        category TEXT NOT NULL,
        retire_meters INTEGER NOT NULL CHECK(retire_meters > 0),
        archived INTEGER NOT NULL DEFAULT 0 CHECK(archived IN (0, 1))
      );
      CREATE TABLE activities (
        id TEXT PRIMARY KEY,
        at_utc TEXT NOT NULL,
        meters INTEGER CHECK(meters > 0)
      );
      CREATE TABLE activity_gear (
        activity_id TEXT NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
        gear_id TEXT NOT NULL REFERENCES gear(id),
        PRIMARY KEY(activity_id, gear_id)
      );
      INSERT INTO metadata VALUES ('installed_at_utc', '2026-01-01T00:00:00.000Z');
      INSERT INTO gear (id, category, retire_meters, archived)
        VALUES ('$shoeId', 'running', 500000, 0);
      INSERT INTO activities (id, at_utc, meters)
        VALUES ('$act1Id', '2026-01-02T10:00:00.000Z', 10000);
      INSERT INTO activity_gear VALUES ('$act1Id', '$shoeId');
      PRAGMA user_version = 1;
    ''');
    rawDb.close();

    // 2. Open via repository; migration should run and preserve data
    final repo = SqliteMileageRepository.openAt(tempDir);
    expect(repo.installedAtUtc, '2026-01-01T00:00:00.000Z');
    expect(repo.gear.length, 1);
    expect(repo.gear.first.id, shoeId);
    expect(repo.photoPath(shoeId), isNull);
    expect(repo.activities.length, 1);
    expect(repo.activities.first.id, act1Id);
    expect(repo.activities.first.meters, 10000);
    expect(repo.activities.first.gearIds, [shoeId]);

    // Test that new v2 column works with migrated rows
    repo.savePhoto(shoeId, Uint8List.fromList([1, 2, 3]));
    expect(repo.photoPath(shoeId), isNotNull);
    repo.close();

    final verifyDb = sqlite3.open(dbFile);
    expect(verifyDb.select('PRAGMA user_version').single.columnAt(0), 2);
    verifyDb.close();
  });

  test('validates UUID format on all operations', () {
    final repo = SqliteMileageRepository.openAt(tempDir);
    expect(
      () => repo.saveGear(
        GearItem(id: 'non-uuid', category: 'running', retireMeters: 100),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => repo.deleteActivity('invalid-id'),
      throwsA(isA<FormatException>()),
    );
    repo.close();
  });

  test(
    'CRUD gear items and activities with persistence across close/reopen',
    () {
      final repo = SqliteMileageRepository.openAt(tempDir);

      final shoe = GearItem(
        id: shoeId,
        category: 'running',
        retireMeters: 500000,
      );
      final court = GearItem(
        id: courtId,
        category: 'court',
        retireMeters: 200000,
      );
      repo.saveGear(shoe);
      repo.saveGear(court);
      expect(repo.gear.length, 2);

      final act1 = Activity(
        id: act1Id,
        atUtc: DateTime.utc(2026, 2, 1, 8, 30),
        meters: 5000,
        gearIds: [shoeId],
      );
      final act2 = Activity(
        id: act2Id,
        atUtc: DateTime.utc(2026, 2, 2, 9, 0),
        meters: null, // unknown distance
        gearIds: [courtId],
      );
      repo.saveActivities([act1, act2]);

      expect(repo.activities.length, 2);
      expect(repo.activities.firstWhere((a) => a.id == act1Id).meters, 5000);
      expect(repo.activities.firstWhere((a) => a.id == act2Id).meters, isNull);

      // Reopen DB
      repo.close();
      final reopened = SqliteMileageRepository.openAt(tempDir);
      expect(reopened.gear.length, 2);
      expect(reopened.activities.length, 2);

      // Delete activity
      reopened.deleteActivity(act1Id);
      expect(reopened.activities.length, 1);
      expect(reopened.activities.first.id, act2Id);

      // Verify activity_gear row also removed (cascade)
      reopened.close();
      final checkDb = sqlite3.open(
        '${tempDir.path}${Platform.pathSeparator}mileage.sqlite',
      );
      expect(
        checkDb.select('SELECT * FROM activity_gear WHERE activity_id = ?', [
          act1Id,
        ]),
        isEmpty,
      );
      checkDb.close();
    },
  );

  test(
    'transactional multi-record rollback leaves database completely untouched',
    () {
      final repo = SqliteMileageRepository.openAt(tempDir);
      final shoe = GearItem(
        id: shoeId,
        category: 'running',
        retireMeters: 500000,
      );
      repo.saveGear(shoe);

      final validAct = Activity(
        id: act1Id,
        atUtc: DateTime.utc(2026, 2, 1),
        meters: 1000,
        gearIds: [shoeId],
      );
      final invalidAct = Activity(
        id: act2Id,
        atUtc: DateTime.utc(2026, 2, 2),
        meters: 2000,
        gearIds: ['00000000-0000-0000-0000-000000000000'], // unknown gear
      );

      expect(
        () => repo.saveActivities([validAct, invalidAct]),
        throwsA(isA<DomainError>()),
      );

      // Neither activity should have been committed
      expect(repo.activities, isEmpty);
      repo.close();
    },
  );

  test('gear category change that causes conflict with existing activity is rolled back', () {
    final repo = SqliteMileageRepository.openAt(tempDir);
    final shoe1 = GearItem(
      id: shoeId,
      category: 'running',
      retireMeters: 500000,
    );
    final court = GearItem(
      id: courtId,
      category: 'court',
      retireMeters: 200000,
    );
    repo.saveGear(shoe1);
    repo.saveGear(court);

    // Activity wearing both shoe1 (running) and court (court)
    repo.saveActivities([
      Activity(
        id: act1Id,
        atUtc: DateTime.utc(2026, 2, 1),
        meters: 5000,
        gearIds: [shoeId, courtId],
      ),
    ]);

    // Attempt to change court's category to 'running' -> duplicate category on act1!
    expect(
      () => repo.saveGear(
        GearItem(id: courtId, category: 'running', retireMeters: 200000),
      ),
      throwsA(isA<DomainError>()),
    );

    // Court's category should still be 'court'
    expect(repo.gear.firstWhere((g) => g.id == courtId).category, 'court');
    repo.close();
  });

  test(
    'optional photo storage writes file and cleans up on overwrite or DB error',
    () {
      final repo = SqliteMileageRepository.openAt(tempDir);
      final shoe = GearItem(
        id: shoeId,
        category: 'running',
        retireMeters: 500000,
      );
      repo.saveGear(shoe);

      final bytes1 = Uint8List.fromList([10, 20, 30, 40]);
      repo.savePhoto(shoeId, bytes1);
      final path1 = repo.photoPath(shoeId)!;
      expect(File(path1).existsSync(), isTrue);
      expect(File(path1).readAsBytesSync(), bytes1);

      // Replace photo
      final bytes2 = Uint8List.fromList([50, 60, 70]);
      repo.savePhoto(shoeId, bytes2);
      final path2 = repo.photoPath(shoeId)!;
      expect(path2, isNot(path1));
      expect(File(path2).existsSync(), isTrue);
      expect(File(path2).readAsBytesSync(), bytes2);
      // Old file should be deleted
      expect(File(path1).existsSync(), isFalse);

      // Saving photo for non-existent gear fails and creates no file
      expect(
        () => repo.savePhoto('99999999-9999-9999-9999-999999999999', bytes1),
        throwsA(isA<DomainError>()),
      );

      repo.close();
    },
  );
}
