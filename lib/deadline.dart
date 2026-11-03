import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// A single instant plus the zone in which the user chose to express it.
class Deadline {
  Deadline(DateTime at, this.zone) : at = at.toUtc() {
    if (!zones.containsKey(zone)) {
      throw const FormatException('Unknown deadline time zone');
    }
  }

  final DateTime at;
  final String zone;
  static const defaultZone = 'America/Toronto';
  static const zones = {
    'Etc/GMT+5': 'EST · fixed UTC−5',
    'America/Toronto': 'Eastern · Toronto / New York',
    'UTC': 'UTC',
  };
  static bool _initialized = false;
  static tz.Location location(String zone) {
    if (!_initialized) {
      tz_data.initializeTimeZones();
      _initialized = true;
    }
    return tz.getLocation(zone);
  }

  tz.TZDateTime get wallTime => tz.TZDateTime.from(at, location(zone));
  String get abbreviation =>
      zone == 'Etc/GMT+5' ? 'EST' : wallTime.timeZoneName;

  /// Resolve a wall-clock minute without silently shifting a DST gap or fold.
  /// Zero matches means a skipped time; two matches require an explicit choice.
  static List<DateTime> candidates(
    String zone,
    DateTime date,
    int hour,
    int minute,
  ) {
    final loc = location(zone);
    final wall = DateTime.utc(date.year, date.month, date.day, hour, minute);
    final result = <DateTime>[];
    for (final offset in loc.zones.map((z) => z.offset).toSet()) {
      final instant = wall.subtract(offset);
      final local = tz.TZDateTime.from(instant, loc);
      if (local.year == date.year &&
          local.month == date.month &&
          local.day == date.day &&
          local.hour == hour &&
          local.minute == minute) {
        result.add(instant);
      }
    }
    return result..sort();
  }

  Map<String, Object> toJson() => {'at': at.toIso8601String(), 'zone': zone};
  static Deadline? fromJson(Object? value) {
    if (value == null) return null;
    if (value is! Map || value['at'] is! String || value['zone'] is! String) {
      throw const FormatException('Invalid deadline');
    }
    final at = DateTime.tryParse(value['at'] as String);
    if (at == null || !at.isUtc || at.toIso8601String() != value['at']) {
      throw const FormatException('Invalid deadline timestamp');
    }
    return Deadline(at, value['zone'] as String);
  }

  @override
  bool operator ==(Object other) =>
      other is Deadline && at == other.at && zone == other.zone;
  @override
  int get hashCode => Object.hash(at, zone);
}
