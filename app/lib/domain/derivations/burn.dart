import 'package:equatable/equatable.dart';

import '../event.dart';
import '../event_type.dart';

/// Money over a date range (PRD §4 Money, PLAN §3).
class Burn extends Equatable {
  const Burn({
    required this.days,
    this.dayToDay,
    this.total,
    this.delivery,
    this.deliveryCount = 0,
    this.other,
    this.oneOffs,
    this.oneOffLabels = const [],
    this.payLater,
    this.payLaterCount = 0,
    this.entries = 0,
  });

  final int days;

  /// Σ amount where category ∉ {bills, one_off}. Null with no spend at all.
  final double? dayToDay;

  /// Σ every amount, one-offs included.
  final double? total;
  final double? delivery;
  final int deliveryCount;

  /// Day-to-day minus delivery.
  final double? other;

  /// bills + one_off.
  final double? oneOffs;
  final List<String> oneOffLabels;

  /// Σ amount where source = lazypay.
  final double? payLater;
  final int payLaterCount;
  final int entries;

  double? get perDay => dayToDay == null ? null : dayToDay! / days;

  /// Share of [total] for the stacked bar (0–1). Null with no total.
  double? share(double? part) =>
      (total == null || total == 0 || part == null) ? null : part / total!;

  /// Delivery as a share of day-to-day spend.
  double? get deliveryShareOfDayToDay =>
      (dayToDay == null || dayToDay == 0 || delivery == null)
      ? null
      : delivery! / dayToDay!;

  @override
  List<Object?> get props => [
    days,
    dayToDay,
    total,
    delivery,
    deliveryCount,
    other,
    oneOffs,
    oneOffLabels,
    payLater,
    payLaterCount,
    entries,
  ];
}

/// [events] must be effective (no dev rows, no voids); [from]–[to] inclusive.
Burn burn(Iterable<Event> events, {required String from, required String to}) {
  final days = DateTime.parse(to).difference(DateTime.parse(from)).inDays + 1;
  final paid = events
      .where(
        (e) =>
            e.amountInr != null &&
            e.date.compareTo(from) >= 0 &&
            e.date.compareTo(to) <= 0,
      )
      .toList();
  if (paid.isEmpty) return Burn(days: days);
  double sum(Iterable<Event> es) =>
      es.fold<double>(0, (a, e) => a + e.amountInr!);
  final nonBurn = paid.where((e) => SpendCategory.nonBurn.contains(e.category));
  final burnable = paid.where(
    (e) => !SpendCategory.nonBurn.contains(e.category),
  );
  final delivery = burnable.where((e) => e.category == SpendCategory.delivery);
  final lazy = paid.where((e) => e.source == 'lazypay');
  final labels = <String>[];
  for (final e in nonBurn) {
    final l = e.label?.trim();
    if (l != null && l.isNotEmpty && !labels.contains(l)) labels.add(l);
  }
  return Burn(
    days: days,
    dayToDay: sum(burnable),
    total: sum(paid),
    delivery: sum(delivery),
    deliveryCount: delivery.length,
    other: sum(burnable) - sum(delivery),
    oneOffs: sum(nonBurn),
    oneOffLabels: labels,
    payLater: lazy.isEmpty ? null : sum(lazy),
    payLaterCount: lazy.length,
    entries: paid.length,
  );
}
