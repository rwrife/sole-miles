import 'dart:io';
import 'dart:typed_data';

import 'backup.dart';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../domain/mileage.dart';

/// Stable IDs at the storage boundary are UUIDs; the pure domain stays agnostic.
abstract interface class MileageRepository {
  List<GearItem> get gear;
  List<Activity> get activities;
  void saveGear(GearItem item);
  void saveActivities(Iterable<Activity> activities);
  void deleteActivity(String id);
  void close();
}

class SqliteMileageRepository implements MileageRepository {
  SqliteMileageRepository._(this._db, this._directory);

  final Database _db;
  final Directory _directory;
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static Future<SqliteMileageRepository> openPrivate() async {
    final directory = await getApplicationSupportDirectory();
    return openAt(directory);
  }

  /// [directory] is app-private in production; caller-owned in tests.
  static SqliteMileageRepository openAt(Directory directory) {
    directory.createSync(recursive: true);
    final db = sqlite3.open(
      '${directory.path}${Platform.pathSeparator}mileage.sqlite',
    );
    try {
      db.execute('PRAGMA foreign_keys = ON');
      final version =
          db.select('PRAGMA user_version').single.columnAt(0) as int;
      if (version > 3) {
        throw StateError('Unsupported database version $version');
      }
      if (version == 0) {
        _transaction(db, () {
          db.execute('''CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE gear (id TEXT PRIMARY KEY, category TEXT NOT NULL,
              retire_meters INTEGER NOT NULL CHECK(retire_meters > 0),
              archived INTEGER NOT NULL DEFAULT 0 CHECK(archived IN (0, 1)));
            CREATE TABLE activities (id TEXT PRIMARY KEY, at_utc TEXT NOT NULL,
              meters INTEGER CHECK(meters > 0));
            CREATE TABLE activity_gear (activity_id TEXT NOT NULL REFERENCES activities(id)
              ON DELETE CASCADE, gear_id TEXT NOT NULL REFERENCES gear(id),
              PRIMARY KEY(activity_id, gear_id));''');
          db.execute('INSERT INTO metadata VALUES (?, ?)', [
            'installed_at_utc',
            DateTime.now().toUtc().toIso8601String(),
          ]);
          db.execute('PRAGMA user_version = 1');
        });
      }
      if (version < 2) {
        _transaction(db, () {
          db.execute('ALTER TABLE gear ADD COLUMN photo_path TEXT');
          db.execute('PRAGMA user_version = 2');
        });
      }
      if (version < 3) {
        _transaction(db, () {
          db.execute(
            "ALTER TABLE gear ADD COLUMN name TEXT NOT NULL DEFAULT ''",
          );
          db.execute(
            "ALTER TABLE gear ADD COLUMN brand TEXT NOT NULL DEFAULT ''",
          );
          db.execute(
            "ALTER TABLE gear ADD COLUMN unit TEXT NOT NULL DEFAULT 'kilometers'",
          );
          db.execute('ALTER TABLE gear ADD COLUMN successor_id TEXT');
          db.execute(
            "ALTER TABLE activities ADD COLUMN note TEXT NOT NULL DEFAULT ''",
          );
          db.execute(
            "ALTER TABLE activities ADD COLUMN category TEXT NOT NULL DEFAULT 'running'",
          );
          db.execute('PRAGMA user_version = 3');
        });
      }
      return SqliteMileageRepository._(db, directory);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  static void _transaction(Database db, void Function() body) {
    db.execute('BEGIN IMMEDIATE');
    try {
      body();
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  static void _checkId(String id) {
    if (!_uuid.hasMatch(id)) throw FormatException('Expected UUID: $id');
  }

  @override
  List<GearItem> get gear => [
    for (final row in _db.select('SELECT * FROM gear ORDER BY id'))
      GearItem(
        id: row['id'] as String,
        category: row['category'] as String,
        retireMeters: row['retire_meters'] as int,
        archived: row['archived'] == 1,
        name: row['name'] as String,
        brand: row['brand'] as String,
        unit: DistanceUnit.values.byName(row['unit'] as String),
        successorId: row['successor_id'] as String?,
      ),
  ];

  @override
  List<Activity> get activities => [
    for (final row in _db.select('SELECT * FROM activities ORDER BY id'))
      Activity(
        id: row['id'] as String,
        atUtc: DateTime.parse(row['at_utc'] as String),
        meters: row['meters'] as int?,
        note: row['note'] as String,
        category: row['category'] as String,
        gearIds: [
          for (final assignment in _db.select(
            'SELECT gear_id FROM activity_gear WHERE activity_id = ? ORDER BY gear_id',
            [row['id']],
          ))
            assignment['gear_id'] as String,
        ],
      ),
  ];

  @override
  void saveGear(GearItem item) {
    _checkId(item.id);
    if (item.successorId != null) {
      _checkId(item.successorId!);
      if (!item.archived ||
          !_db.select('SELECT 1 FROM gear WHERE id = ? AND archived = 0', [
            item.successorId,
          ]).isNotEmpty) {
        throw const DomainError(DomainErrorCode.unknownGear);
      }
    }
    _transaction(_db, () {
      _db.execute(
        '''INSERT INTO gear (id, category, retire_meters, archived, name, brand, unit, successor_id)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET
          category = excluded.category, retire_meters = excluded.retire_meters,
          archived = excluded.archived, name = excluded.name,
          brand = excluded.brand, unit = excluded.unit,
          successor_id = excluded.successor_id''',
        [
          item.id,
          item.category,
          item.retireMeters,
          item.archived ? 1 : 0,
          item.name,
          item.brand,
          item.unit.name,
          item.successorId,
        ],
      );
      // Reject category edits that would invalidate existing assignments.
      for (final activity in activities) {
        Mileage.validate(activity, {
          for (final gearItem in gear) gearItem.id: gearItem,
        });
      }
    });
  }

  @override
  void saveActivities(Iterable<Activity> newActivities) {
    _transaction(_db, () {
      final byId = {for (final item in gear) item.id: item};
      for (final activity in newActivities) {
        _checkId(activity.id);
        Mileage.validate(activity, byId);
        final prior = _db.select('SELECT 1 FROM activities WHERE id = ?', [
          activity.id,
        ]);
        for (final gearId in activity.gearIds) {
          final item = byId[gearId]!;
          if (item.archived && prior.isEmpty) {
            throw const DomainError(DomainErrorCode.unknownGear);
          }
        }
        _db.execute(
          '''INSERT INTO activities (id, at_utc, meters, note, category)
          VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET
          at_utc = excluded.at_utc, meters = excluded.meters,
          note = excluded.note, category = excluded.category''',
          [
            activity.id,
            activity.atUtc.toIso8601String(),
            activity.meters,
            activity.note,
            activity.category,
          ],
        );
        _db.execute('DELETE FROM activity_gear WHERE activity_id = ?', [
          activity.id,
        ]);
        for (final gearId in activity.gearIds) {
          _db.execute('INSERT INTO activity_gear VALUES (?, ?)', [
            activity.id,
            gearId,
          ]);
        }
      }
    });
  }

  @override
  void deleteActivity(String id) {
    _checkId(id);
    _db.execute('DELETE FROM activities WHERE id = ?', [id]);
  }

  /// Photo remains outside SQLite; failed DB update removes new file.
  void savePhoto(String gearId, Uint8List bytes) {
    _checkId(gearId);
    if (bytes.isEmpty) throw const FormatException('Empty photo');
    if (!_db.select('SELECT 1 FROM gear WHERE id = ?', [gearId]).isNotEmpty) {
      throw const DomainError(DomainErrorCode.unknownGear);
    }
    final photos = Directory(
      '${_directory.path}${Platform.pathSeparator}photos',
    )..createSync(recursive: true);
    final path =
        '${photos.path}${Platform.pathSeparator}$gearId-${DateTime.now().microsecondsSinceEpoch}.bin';
    final file = File(path);
    final old = photoPath(gearId);
    try {
      file.writeAsBytesSync(bytes, flush: true);
      _transaction(_db, () {
        _db.execute('UPDATE gear SET photo_path = ? WHERE id = ?', [
          path,
          gearId,
        ]);
      });
    } catch (_) {
      if (file.existsSync()) file.deleteSync();
      rethrow;
    }
    if (old != null && old != path && File(old).existsSync()) {
      File(old).deleteSync();
    }
  }

  String? photoPath(String gearId) {
    _checkId(gearId);
    final rows = _db.select('SELECT photo_path FROM gear WHERE id = ?', [
      gearId,
    ]);
    return rows.isEmpty ? null : rows.single['photo_path'] as String?;
  }

  String get installedAtUtc =>
      _db
              .select(
                "SELECT value FROM metadata WHERE key = 'installed_at_utc'",
              )
              .single['value']
          as String;

  MileageBackup backup({bool includePhotos = false}) {
    final photos = <String, Uint8List>{};
    if (includePhotos) {
      for (final item in gear) {
        final path = photoPath(item.id);
        if (path != null) photos[item.id] = File(path).readAsBytesSync();
      }
    }
    return MileageBackup(gear, activities, photos);
  }

  /// Validate before touching storage. Conflicting IDs in a merge never overwrite.
  /// A private full snapshot precedes both operations, including omitted photos.
  File restore(MileageBackup incoming, {required bool replace}) {
    // Re-validate even when caller constructs a backup instead of parsing JSON.
    final parsed = MileageBackup.parse(incoming.encode());
    final oldGear = gear;
    final oldActivities = activities;
    if (!replace &&
        (parsed.gear.any((g) => oldGear.any((old) => old.id == g.id)) ||
            parsed.activities.any(
              (a) => oldActivities.any((old) => old.id == a.id),
            ))) {
      throw const FormatException('Merge ID conflict; existing data unchanged');
    }
    final snapshot = File(
      '${_directory.path}${Platform.pathSeparator}pre-restore-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    final snapshotBytes = backup(includePhotos: true).encode();
    snapshot.writeAsStringSync(snapshotBytes, flush: true);
    if (snapshot.readAsStringSync() != snapshotBytes) {
      throw const FileSystemException('Safety snapshot verification failed');
    }
    final created = <File>[];
    final priorPhotos = replace
        ? [
            for (final g in oldGear)
              if (photoPath(g.id) case final String p) p,
          ]
        : <String>[];
    try {
      final paths = <String, String>{};
      for (final entry in parsed.photos.entries) {
        final directory = Directory(
          '${_directory.path}${Platform.pathSeparator}photos',
        )..createSync(recursive: true);
        final file = File(
          '${directory.path}${Platform.pathSeparator}${entry.key}-${DateTime.now().microsecondsSinceEpoch}.bin',
        );
        file.writeAsBytesSync(entry.value, flush: true);
        created.add(file);
        paths[entry.key] = file.path;
      }
      _transaction(_db, () {
        if (replace) {
          _db.execute('DELETE FROM activity_gear');
          _db.execute('DELETE FROM activities');
          _db.execute('DELETE FROM gear');
        }
        for (final g in parsed.gear) {
          _db.execute(
            '''INSERT INTO gear
            (id, category, retire_meters, archived, name, brand, unit, successor_id, photo_path)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
            [
              g.id,
              g.category,
              g.retireMeters,
              g.archived ? 1 : 0,
              g.name,
              g.brand,
              g.unit.name,
              g.successorId,
              paths[g.id],
            ],
          );
        }
        for (final a in parsed.activities) {
          _db.execute(
            '''INSERT INTO activities (id, at_utc, meters, note, category)
            VALUES (?, ?, ?, ?, ?)''',
            [a.id, a.atUtc.toIso8601String(), a.meters, a.note, a.category],
          );
          for (final id in a.gearIds) {
            _db.execute('INSERT INTO activity_gear VALUES (?, ?)', [a.id, id]);
          }
        }
      });
      for (final path in priorPhotos) {
        final file = File(path);
        // Only unlink files owned by this repository, not arbitrary legacy paths.
        if (file.path.startsWith(
              '${_directory.path}${Platform.pathSeparator}photos${Platform.pathSeparator}',
            ) &&
            file.existsSync()) {
          try {
            file.deleteSync();
          } on FileSystemException {
            /* orphan is safe */
          }
        }
      }
      return snapshot;
    } catch (_) {
      for (final file in created) {
        if (file.existsSync()) file.deleteSync();
      }
      rethrow;
    }
  }

  @override
  void close() => _db.close();
}
