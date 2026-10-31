enum DistanceUnit { kilometers, miles }

enum WearState { healthy, nudge, retire }

enum DomainErrorCode {
  invalidDistance,
  invalidTarget,
  duplicateCategory,
  unknownGear,
  invalidDate,
  duplicateId,
}

class DomainError implements Exception {
  const DomainError(this.code);
  final DomainErrorCode code;
}

class GearItem {
  GearItem({
    required this.id,
    required this.category,
    required this.retireMeters,
    this.archived = false,
  }) {
    if (id.isEmpty || category.isEmpty || retireMeters <= 0) {
      throw const DomainError(DomainErrorCode.invalidTarget);
    }
  }

  final String id;
  final String category;
  final int retireMeters;
  final bool archived;
}

class Activity {
  Activity({
    required this.id,
    required this.atUtc,
    required List<String> gearIds,
    this.meters,
  }) : gearIds = List.unmodifiable(gearIds) {
    if (id.isEmpty || !atUtc.isUtc) {
      throw const DomainError(DomainErrorCode.invalidDate);
    }
    if (meters != null && meters! <= 0) {
      throw const DomainError(DomainErrorCode.invalidDistance);
    }
  }

  final String id;
  final DateTime atUtc;
  final int? meters; // null means unknown; never contributes to an odometer.
  final List<String> gearIds;
}

class ActivityLedger {
  ActivityLedger(Iterable<GearItem> items)
    : gear = {for (final item in items) item.id: item};

  final Map<String, GearItem> gear;
  final Map<String, Activity> activities = {};

  void save(Activity activity) {
    Mileage.validate(activity, gear);
    activities[activity.id] = activity;
  }

  void delete(String id) => activities.remove(id);

  int odometer(String id) => Mileage.odometer(id, activities.values);
}

class Mileage {
  // 1 mile = 1609.344 meters. Nine decimal places round-trip every
  // integer meter through the display/input pair, even at wear thresholds.
  static int fromDisplay(String text, DistanceUnit unit) {
    final value = double.tryParse(text.trim());
    if (value == null || !value.isFinite || value <= 0) {
      throw const DomainError(DomainErrorCode.invalidDistance);
    }
    final scaled = value * (unit == DistanceUnit.miles ? 1609.344 : 1000);
    if (!scaled.isFinite || scaled > 9007199254740991) {
      throw const DomainError(DomainErrorCode.invalidDistance);
    }
    final meters = scaled.round();
    if (meters <= 0) {
      throw const DomainError(DomainErrorCode.invalidDistance);
    }
    return meters;
  }

  static String display(int meters, DistanceUnit unit) {
    if (meters <= 0) {
      throw const DomainError(DomainErrorCode.invalidDistance);
    }
    return (meters / (unit == DistanceUnit.miles ? 1609.344 : 1000))
        .toStringAsFixed(9);
  }

  static void validate(Activity activity, Map<String, GearItem> gear) {
    final seenIds = <String>{};
    final seenCategories = <String>{};
    for (final id in activity.gearIds) {
      if (!seenIds.add(id)) {
        throw const DomainError(DomainErrorCode.duplicateId);
      }
      final item = gear[id];
      if (item == null) {
        throw const DomainError(DomainErrorCode.unknownGear);
      }
      if (!seenCategories.add(item.category)) {
        throw const DomainError(DomainErrorCode.duplicateCategory);
      }
    }
  }

  static int odometer(String gearId, Iterable<Activity> activities) {
    var total = 0;
    for (final activity in activities) {
      if (activity.gearIds.contains(gearId)) {
        total += activity.meters ?? 0;
      }
    }
    return total;
  }

  static WearState wear(int meters, int retireMeters) {
    if (meters < 0 || retireMeters <= 0) {
      throw const DomainError(DomainErrorCode.invalidTarget);
    }
    // Compare cross-products: avoid float drift at 85%/100%.
    if (meters >= retireMeters) return WearState.retire;
    if (meters * 100 >= retireMeters * 85) return WearState.nudge;
    return WearState.healthy;
  }

  static Map<String, int> rotation(
    Iterable<GearItem> gear,
    Iterable<Activity> activities,
    DateTime nowUtc,
  ) {
    if (!nowUtc.isUtc) throw const DomainError(DomainErrorCode.invalidDate);
    final active = {
      for (final item in gear)
        if (!item.archived) item.id: 0,
    };
    final start = nowUtc.subtract(const Duration(days: 28));
    for (final activity in activities) {
      if (activity.atUtc.isBefore(start) || activity.atUtc.isAfter(nowUtc)) {
        continue;
      }
      for (final id in activity.gearIds) {
        if (active.containsKey(id)) {
          active[id] = active[id]! + (activity.meters ?? 0);
        }
      }
    }
    return active;
  }
}
