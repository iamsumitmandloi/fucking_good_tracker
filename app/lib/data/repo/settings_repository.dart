import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../../core/cells.dart';
import '../local/db.dart';

class AppSettings extends Equatable {
  const AppSettings({
    this.targetDate = '2026-11-30',
    this.cigBudget = 5,
    this.cigPrice = 25,
    this.teaPrice = 20,
    this.proteinTargetG = 50,
    this.supplements = const [],
    this.busRunSize = 10,
  });

  final String targetDate;
  final int cigBudget;
  final double cigPrice;
  final double teaPrice;
  final int proteinTargetG;
  final List<String> supplements;
  final int busRunSize;

  AppSettings copyWith({
    String? targetDate,
    int? cigBudget,
    double? cigPrice,
    double? teaPrice,
    int? proteinTargetG,
    List<String>? supplements,
    int? busRunSize,
  }) => AppSettings(
    targetDate: targetDate ?? this.targetDate,
    cigBudget: cigBudget ?? this.cigBudget,
    cigPrice: cigPrice ?? this.cigPrice,
    teaPrice: teaPrice ?? this.teaPrice,
    proteinTargetG: proteinTargetG ?? this.proteinTargetG,
    supplements: supplements ?? this.supplements,
    busRunSize: busRunSize ?? this.busRunSize,
  );

  Map<String, dynamic> toJson() => {
    'targetDate': targetDate,
    'cigBudget': cigBudget,
    'cigPrice': cigPrice,
    'teaPrice': teaPrice,
    'proteinTargetG': proteinTargetG,
    'supplements': supplements,
    'busRunSize': busRunSize,
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    return AppSettings(
      targetDate: cellDate(j['targetDate']) ?? d.targetDate,
      cigBudget: cellInt(j['cigBudget']) ?? d.cigBudget,
      cigPrice: cellDouble(j['cigPrice']) ?? d.cigPrice,
      teaPrice: cellDouble(j['teaPrice']) ?? d.teaPrice,
      proteinTargetG: cellInt(j['proteinTargetG']) ?? d.proteinTargetG,
      supplements: [
        if (j['supplements'] is List)
          for (final s in j['supplements'] as List)
            if (cellStr(s).isNotEmpty) cellStr(s),
      ],
      busRunSize: (cellInt(j['busRunSize']) ?? d.busRunSize).clamp(1, 50),
    );
  }

  @override
  List<Object?> get props => [
    targetDate,
    cigBudget,
    cigPrice,
    teaPrice,
    proteinTargetG,
    supplements,
    busRunSize,
  ];
}

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Stream<AppSettings> watch() => _db.watchMeta(MetaKeys.settings).map(_decode);

  Future<AppSettings> load() async =>
      _decode(await _db.readMeta(MetaKeys.settings));

  Future<void> save(AppSettings s) =>
      _db.writeMeta(MetaKeys.settings, jsonEncode(s.toJson()));

  AppSettings _decode(String? raw) {
    if (raw == null) return const AppSettings();
    try {
      final j = jsonDecode(raw);
      return j is Map<String, dynamic>
          ? AppSettings.fromJson(j)
          : const AppSettings();
    } on FormatException {
      return const AppSettings();
    }
  }
}
