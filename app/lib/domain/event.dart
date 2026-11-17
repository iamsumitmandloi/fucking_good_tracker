import 'package:equatable/equatable.dart';

import '../core/cells.dart';
import 'event_type.dart';

/// One row of the `Events` tab (PRD §6.1).
class Event extends Equatable {
  const Event({
    required this.id,
    required this.date,
    required this.type,
    this.time,
    this.endTime,
    this.qty,
    this.unit,
    this.label,
    this.amountInr,
    this.category,
    this.approx = false,
    this.source = 'app',
    this.note,
    this.createdAt,
  });

  final String id;

  /// `yyyy-MM-dd`, IST.
  final String date;

  /// `HH:mm`, IST. Null when unknown.
  final String? time;
  final String? endTime;
  final EventType type;
  final double? qty;
  final String? unit;
  final String? label;
  final double? amountInr;
  final String? category;
  final bool approx;
  final String source;
  final String? note;

  /// ISO UTC, set by the server.
  final String? createdAt;

  /// Parses a row from the API, where every value is a display string.
  /// Returns null for rows without an id, date or known type.
  static Event? fromSheetRow(Map<String, dynamic> row) {
    final id = cellStrOrNull(row['id']);
    final date = cellDate(row['date']);
    final type = EventType.fromWire(cellStrOrNull(row['type']));
    if (id == null || date == null || type == null) return null;
    return Event(
      id: id,
      date: date,
      time: cellTime(row['time']),
      endTime: cellTime(row['end_time']),
      type: type,
      qty: cellDouble(row['qty']),
      unit: cellStrOrNull(row['unit']),
      label: cellStrOrNull(row['label']),
      amountInr: cellDouble(row['amount_inr']),
      category: cellStrOrNull(row['category']),
      approx: cellBool(row['approx']),
      source: cellStrOrNull(row['source']) ?? 'app',
      note: cellStrOrNull(row['note']),
      createdAt: cellStrOrNull(row['created_at']),
    );
  }

  /// Same parser; accepts typed or string values.
  static Event? fromJson(Map<String, dynamic> json) => fromSheetRow(json);

  /// POST body shape. Nulls are omitted; `created_at` is server-set.
  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date,
    'type': type.wire,
    'time': ?time,
    'end_time': ?endTime,
    'qty': ?qty,
    'unit': ?unit,
    'label': ?label,
    'amount_inr': ?amountInr,
    'category': ?category,
    'approx': approx,
    'source': source,
    'note': ?note,
  };

  /// Sort key: date, then time (unknown last), then server time.
  String get sortKey => '$date ${time ?? '99:99'} ${createdAt ?? ''}';

  /// qty, defaulting to 1 for count-type events logged without one.
  double get count => qty ?? 1;

  Event copyWith({String? id, String? note, String? label}) => Event(
    id: id ?? this.id,
    date: date,
    type: type,
    time: time,
    endTime: endTime,
    qty: qty,
    unit: unit,
    label: label ?? this.label,
    amountInr: amountInr,
    category: category,
    approx: approx,
    source: source,
    note: note ?? this.note,
    createdAt: createdAt,
  );

  @override
  List<Object?> get props => [
    id,
    date,
    time,
    endTime,
    type,
    qty,
    unit,
    label,
    amountInr,
    category,
    approx,
    source,
    note,
    createdAt,
  ];
}

int compareEvents(Event a, Event b) => a.sortKey.compareTo(b.sortKey);
