import 'package:equatable/equatable.dart';

import '../event.dart';
import '../event_type.dart';

/// Label used for the breakfast-protein tile (`meal`, unit `g`).
const proteinLabel = 'Breakfast protein';

bool isProtein(Event e) =>
    (e.type == EventType.meal || e.type == EventType.snack) &&
    e.unit?.toLowerCase() == 'g';

/// Canonical key for comparing supplement names across sheet variants
/// (e.g. "Vitamin D3 and K2" vs "Vitamin D3 + K2", "Vitamin B (B-complex)" vs "Vitamin B-complex").
String supplementKey(String label) {
  final s = label.toLowerCase().trim();
  if (s.contains('d3') && s.contains('k2')) return 'vitamind3k2';
  if (s.contains('b-complex') ||
      s.contains('b complex') ||
      s.contains('vitamin b') ||
      s.contains('becosules') ||
      s.contains('neurokind')) {
    return 'vitaminbcomplex';
  }
  if (s.contains('omega')) return 'omega3';
  if (s.contains('ashwagandha')) return 'ashwagandha';
  if (s.contains('magnesium')) return 'magnesiumglycinate';
  if (s.contains('creatine')) return 'creatine';
  if (s.contains('tyrosine')) return 'ltyrosine';
  if (s.contains('theanine')) return 'ltheanine';
  return s.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// One day's numbers. Every metric is null when nothing was logged.
class DaySummary extends Equatable {
  const DaySummary({
    required this.date,
    this.cigs,
    this.teas,
    this.coffees,
    this.waterMl,
    this.proteinG,
    this.weightKg,
    this.steps,
    this.energy,
    this.meals = const [],
    this.supplements = const {},
    this.spend,
    this.spendEntries = 0,
    this.studySessions = 0,
    this.approx = false,
  });

  final String date;
  final double? cigs;
  final double? teas;
  final double? coffees;
  final double? waterMl;
  final double? proteinG;
  final double? weightKg;
  final double? steps;
  final double? energy;
  final List<Event> meals;
  final Set<String> supplements;
  final double? spend;
  final int spendEntries;
  final int studySessions;
  final bool approx;

  Event? get lastMeal => meals.isEmpty ? null : meals.last;

  bool hasSupplement(String name) {
    final want = supplementKey(name);
    return supplements.any((s) => supplementKey(s) == want);
  }

  int supplementsMatched(List<String> configured) =>
      configured.where(hasSupplement).length;

  @override
  List<Object?> get props => [
    date,
    cigs,
    teas,
    coffees,
    waterMl,
    proteinG,
    weightKg,
    steps,
    energy,
    meals,
    supplements,
    spend,
    spendEntries,
    studySessions,
    approx,
  ];
}

double? _sum(Iterable<Event> es, double Function(Event) f) =>
    es.isEmpty ? null : es.fold<double>(0, (a, e) => a + f(e));

double? _max(Iterable<Event> es, double Function(Event) f) {
  if (es.isEmpty) return null;
  var best = f(es.first);
  for (final e in es.skip(1)) {
    final v = f(e);
    if (v > best) best = v;
  }
  return best;
}

/// [effective] must already exclude dev rows and voids.
DaySummary summarize(Iterable<Event> effective, String date) {
  final day = effective.where((e) => e.date == date).toList()
    ..sort(compareEvents);
  Iterable<Event> of(EventType t) => day.where((e) => e.type == t);
  final paid = day.where((e) => e.amountInr != null);
  final weights = of(EventType.weight).where((e) => e.qty != null).toList();
  final energy = of(EventType.energy).where((e) => e.qty != null).toList();
  return DaySummary(
    date: date,
    cigs: _sum(of(EventType.cigarette), (e) => e.count),
    teas: _sum(of(EventType.tea), (e) => e.count),
    coffees: _sum(of(EventType.coffee), (e) => e.count),
    waterMl: _sum(of(EventType.waterMl), (e) => e.qty ?? 250),
    proteinG: _sum(day.where(isProtein), (e) => e.qty ?? 0),
    weightKg: weights.isEmpty ? null : weights.last.qty,
    steps: _max(of(EventType.steps).where((e) => e.qty != null), (e) => e.qty!),
    energy: energy.isEmpty ? null : energy.last.qty,
    meals: [
      for (final e in day)
        if ((e.type == EventType.meal || e.type == EventType.snack) &&
            !isProtein(e))
          e,
    ],
    supplements: {
      for (final e in of(EventType.supplement))
        if (e.label != null) e.label!,
    },
    spend: _sum(paid, (e) => e.amountInr!),
    spendEntries: paid.length,
    studySessions: of(EventType.study).where((e) => e.note == 'session').length,
    approx: day.any((e) => e.approx),
  );
}

/// First date anything was logged, for the "Day N" header.
String? firstDate(Iterable<Event> effective) {
  String? first;
  for (final e in effective) {
    if (first == null || e.date.compareTo(first) < 0) first = e.date;
  }
  return first;
}
