import 'package:clock/clock.dart';
import 'package:kolo/core/utils/time_source.dart';

/// Horloge figée, avançable à la main.
class FakeTime {
  FakeTime([DateTime? start]) : _now = start ?? DateTime.utc(2026, 10, 9, 12);

  DateTime _now;

  DateTime get now => _now;

  void advance(Duration d) => _now = _now.add(d);

  void set(DateTime value) => _now = value;

  TimeSource get source => TimeSource(Clock(() => _now));
}

/// Générateur d'identifiants déterministe : `id-1`, `id-2`…
class SequentialIds {
  SequentialIds([this.prefix = 'id']);

  final String prefix;
  int _next = 1;

  String call() => '$prefix-${_next++}';
}
