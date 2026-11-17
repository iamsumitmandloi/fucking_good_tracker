import 'package:equatable/equatable.dart';

import '../core/cells.dart';

/// One row of `Study Bank` (PRD §6.3).
class StudyQuestion extends Equatable {
  const StudyQuestion({
    required this.id,
    required this.row,
    this.sourceTab = '',
    this.topic = '',
    this.area = '',
    this.tier,
    this.type = '',
    this.stars = '',
    this.question = '',
    this.followUps = const [],
    this.answerPoints = const [],
    this.project = '',
    this.related = '',
    this.status = '',
  });

  final String id;
  final int row;
  final String sourceTab;
  final String topic;
  final String area;
  final int? tier;
  final String type;
  final String stars;
  final String question;
  final List<String> followUps;
  final List<String> answerPoints;
  final String project;
  final String related;
  final String status;

  /// "Senior · T1 · Concept"
  String get meta => [
    area,
    if (tier != null) 'T$tier',
    type,
  ].where((s) => s.isNotEmpty).join(' · ');

  /// Header names may drift ("Answer points / rubric", "Follow-ups"), so
  /// match on a normalised prefix.
  static StudyQuestion? fromRow(Map<String, dynamic> row) {
    final norm = <String, Object?>{
      for (final e in row.entries) _norm(e.key): e.value,
    };
    Object? pick(String key) {
      if (norm.containsKey(key)) return norm[key];
      for (final e in norm.entries) {
        if (e.key.startsWith(key)) return e.value;
      }
      return null;
    }

    final id = cellStr(pick('questionid'));
    if (id.isEmpty) return null;
    return StudyQuestion(
      id: id,
      row: cellInt(row['_row']) ?? 0,
      sourceTab: cellStr(pick('sourcetab')),
      topic: cellStr(pick('topic')),
      area: cellStr(pick('area')),
      tier: parseTier(pick('tier')),
      type: cellStr(pick('type')),
      stars: cellStr(pick('stars')),
      question: cellStr(norm['question']),
      followUps: splitList(pick('followups')),
      answerPoints: splitList(pick('answerpoints')),
      project: cellStr(pick('project')),
      related: cellStr(pick('relatedquestion')),
      status: cellStr(pick('status')),
    );
  }

  static String _norm(String k) =>
      k.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  /// "T1", "1", "Tier 1" → 1.
  static int? parseTier(Object? v) {
    final m = RegExp(r'(\d+)').firstMatch(cellStr(v));
    return m == null ? null : int.parse(m[1]!);
  }

  /// `;`-separated cell → trimmed, non-empty parts.
  static List<String> splitList(Object? v) => [
    for (final s in cellStr(v).split(';'))
      if (s.trim().isNotEmpty) s.trim(),
  ];

  @override
  List<Object?> get props => [id, row, tier, question, followUps, answerPoints];
}
