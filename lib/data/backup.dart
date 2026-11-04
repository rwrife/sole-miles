import 'dart:convert';
import 'dart:typed_data';

import '../domain/mileage.dart';

class MileageBackup {
  MileageBackup(this.gear, this.activities, this.photos);

  static const version = 1;
  final List<GearItem> gear;
  final List<Activity> activities;
  final Map<String, Uint8List> photos;
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  String encode() => jsonEncode({
    'schemaVersion': version,
    'gear': [
      for (final g in gear)
        {
          'id': g.id,
          'category': g.category,
          'retireMeters': g.retireMeters,
          'archived': g.archived,
          'name': g.name,
          'brand': g.brand,
          'unit': g.unit.name,
          'successorId': g.successorId,
          'photo': photos[g.id] == null ? null : base64Encode(photos[g.id]!),
        },
    ],
    'activities': [
      for (final a in activities)
        {
          'id': a.id,
          'atUtc': a.atUtc.toIso8601String(),
          'meters': a.meters,
          'note': a.note,
          'category': a.category,
          'gearIds': a.gearIds,
        },
    ],
  });

  static MileageBackup parse(String text) {
    if (utf8.encode(text).length > 50 * 1024 * 1024) {
      throw const FormatException('Backup too large');
    }
    try {
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (data['schemaVersion'] != version) {
        throw const FormatException('Unsupported backup version');
      }
      final items = data['gear'] as List<dynamic>;
      final entries = data['activities'] as List<dynamic>;
      if (items.length > 100000 || entries.length > 1000000) {
        throw const FormatException('Too many records');
      }
      final photos = <String, Uint8List>{};
      var totalPhotoBytes = 0;
      final gear = <GearItem>[];
      final ids = <String>{};
      for (final raw in items) {
        final g = raw as Map<String, dynamic>;
        final id = g['id'] as String;
        if (!_uuid.hasMatch(id) || !ids.add(id)) {
          throw const FormatException('Duplicate or invalid gear ID');
        }
        final photo = g['photo'];
        if (photo != null) {
          final encoded = photo as String;
          if (encoded.length > 14 * 1024 * 1024) {
            throw const FormatException('Photo too large');
          }
          final bytes = base64Decode(encoded);
          if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
            throw const FormatException('Invalid photo');
          }
          totalPhotoBytes += bytes.length;
          if (totalPhotoBytes > 100 * 1024 * 1024) {
            throw const FormatException('Total photo volume exceeded');
          }
          photos[id] = bytes;
        }
        gear.add(
          GearItem(
            id: id,
            category: g['category'] as String,
            retireMeters: g['retireMeters'] as int,
            archived: g['archived'] as bool,
            name: g['name'] as String,
            brand: g['brand'] as String,
            unit: DistanceUnit.values.byName(g['unit'] as String),
            successorId: g['successorId'] as String?,
          ),
        );
      }
      for (final g in gear) {
        if (g.successorId != null &&
            (!g.archived ||
                !gear.any(
                  (next) => next.id == g.successorId && !next.archived,
                ))) {
          throw const FormatException('Invalid successor');
        }
      }
      final activities = <Activity>[];
      ids.clear();
      final byId = {for (final g in gear) g.id: g};
      for (final raw in entries) {
        final a = raw as Map<String, dynamic>;
        final id = a['id'] as String;
        if (!_uuid.hasMatch(id) || !ids.add(id)) {
          throw const FormatException('Duplicate or invalid activity ID');
        }
        final timestamp = a['atUtc'] as String;
        if (!timestamp.endsWith('Z') ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$')
                .hasMatch(timestamp)) {
          throw const FormatException('Expected UTC timestamp');
        }
        final parsedTime = DateTime.parse(timestamp);
        if (parsedTime.toIso8601String() != timestamp) {
          throw const FormatException('Noncanonical UTC timestamp');
        }
        final activity = Activity(
          id: id,
          atUtc: parsedTime,
          meters: a['meters'] as int?,
          note: a['note'] as String,
          category: a['category'] as String,
          gearIds: (a['gearIds'] as List<dynamic>).cast<String>(),
        );
        Mileage.validate(activity, byId);
        activities.add(activity);
      }
      return MileageBackup(gear, activities, photos);
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Invalid backup: $e');
    }
  }

  static String _csvCell(Object? value) {
    final text = value?.toString() ?? '';
    // Avoid spreadsheet formula injection even when imported notes begin with =,+,-,@.
    final safe = RegExp(r'^\s*[=+\-@]').hasMatch(text) || text.startsWith('\t')
        ? "'$text"
        : text;
    return '"${safe.replaceAll('"', '""')}"';
  }

  static String csvActivities(
    Iterable<Activity> activities,
    DistanceUnit unit,
  ) => [
    'id,date_utc,category,distance_${unit.name},gear_ids,note',
    for (final a in activities)
      [
        a.id,
        a.atUtc.toIso8601String(),
        a.category,
        a.meters == null ? '' : Mileage.display(a.meters!, unit),
        a.gearIds.join(';'),
        a.note,
      ].map(_csvCell).join(','),
  ].join('\r\n');

  static String csvTotals(
    Iterable<GearItem> gear,
    Iterable<Activity> activities,
    DistanceUnit unit,
  ) => [
    'id,name,brand,category,archived,retire_${unit.name},total_${unit.name}',
    for (final g in gear)
      [
        g.id,
        g.name,
        g.brand,
        g.category,
        g.archived,
        Mileage.display(g.retireMeters, unit),
        (Mileage.odometer(g.id, activities) /
                (unit == DistanceUnit.miles ? 1609.344 : 1000))
            .toStringAsFixed(9),
      ].map(_csvCell).join(','),
  ].join('\r\n');
}
