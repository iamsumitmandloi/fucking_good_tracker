import 'start_here.dart';
import 'study_question.dart';

/// What the Up-next card and the Study focus card show.
class FocusInfo {
  const FocusInfo({
    this.questionId,
    this.question,
    this.focusText,
    this.nextAction,
    this.resume,
  });

  final String? questionId;
  final StudyQuestion? question;

  /// Current focus with the leading id stripped.
  final String? focusText;
  final String? nextAction;
  final String? resume;

  bool get isEmpty =>
      focusText == null && question == null && nextAction == null;

  static FocusInfo resolve(StartHere sh, List<StudyQuestion> bank) {
    final id = sh.focusQuestionId;
    StudyQuestion? q;
    if (id != null) {
      for (final x in bank) {
        if (x.id == id) {
          q = x;
          break;
        }
      }
    }
    final raw = sh.currentFocus;
    final stripped = raw
        ?.replaceFirst(
          RegExp(r'^\s*[A-Z]{1,4}-?\d+(?:\.\d+)?\s*[·:—–\-|]?\s*'),
          '',
        )
        .trim();
    return FocusInfo(
      questionId: id,
      question: q,
      focusText: (stripped == null || stripped.isEmpty) ? raw : stripped,
      nextAction: sh.nextAction,
      resume: sh.whereToResume ?? sh.nextAction,
    );
  }
}
