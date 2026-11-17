import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/deps.dart';
import '../../app/sync_status.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/app_icon.dart';
import '../../app/widgets/common.dart';
import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../../domain/study_question.dart';
import 'log_session_dialog.dart';
import 'study_cubit.dart';

class StudyScreen extends StatelessWidget {
  const StudyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => StudyCubit(
        study: c.read(),
        events: c.read(),
        settings: c.read(),
        clock: c.read(),
        db: c.read<AppDeps>().db,
      ),
      child: const _StudyView(),
    );
  }
}

class _StudyView extends StatelessWidget {
  const _StudyView();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<StudyCubit>().state;
    final d = context.dims;
    final target = parseDate(s.targetDate);
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => context.read<StudyCubit>().refresh(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(d.screenH, d.screenTop, d.screenH, 24),
          children: [
            const SyncBanner(),
            ScreenHeader(
              caption: target == null
                  ? 'Interview prep'
                  : 'Interview prep · target ${DateFormat('d MMM').format(target)}',
              title: 'Study',
              trailing: _DaysLeft(days: s.progress?.daysLeft),
            ),
            SizedBox(height: d.gapL),
            if (!s.loaded)
              const SizedBox.shrink()
            else if (s.bank.isEmpty)
              EmptyState(
                icon: AppIcons.study,
                title: s.refreshing
                    ? 'Fetching the Study Bank…'
                    : 'Study Bank not loaded',
                message: 'Pull down to fetch it from the sheet. It stays on the phone for offline use.',
              )
            else ...[
              _AssessedCard(state: s),
              SizedBox(height: d.gapL),
              _FocusCard(state: s),
              SizedBox(height: d.gapL),
              _BusEntry(due: s.dueToday),
              SizedBox(height: d.gapL),
              _Browse(state: s),
            ],
          ],
        ),
      ),
    );
  }
}

class _DaysLeft extends StatelessWidget {
  const _DaysLeft({required this.days});
  final int? days;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            days == null ? dash : '${days! < 0 ? 0 : days}',
            style: context.text.statL.copyWith(
              fontWeight: FontWeight.w700,
              color: c.warn,
            ),
          ),
          Text(
            days == 1 ? 'day left' : 'days left',
            style: context.text.caption,
          ),
        ],
      ),
    );
  }
}

class _AssessedCard extends StatelessWidget {
  const _AssessedCard({required this.state});
  final StudyState state;

  @override
  Widget build(BuildContext context) {
    final p = state.progress!;
    final c = context.colors;
    final frac = p.total == 0 ? 0.0 : p.assessed / p.total;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text('Assessed', style: context.text.label)),
              NumberWithUnit(
                '${p.assessed} ',
                '/ ${p.total}',
                style: context.text.statM.copyWith(fontSize: 20),
                unitSize: 14,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            label: '${p.assessed} of ${p.total} assessed',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: frac == 0 ? 0.01 : frac,
                minHeight: 8,
                backgroundColor: c.track,
                color: c.accent,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Mini(
                label: 'Tier 1',
                value: '${p.tierDone(1)}/${p.tierTotal(1)}',
              ),
              const SizedBox(width: 8),
              _Mini(label: 'Sessions', value: '${p.sessions}'),
              const SizedBox(width: 8),
              _Mini(
                label: 'T1 pace',
                value: p.t1Pace == null ? dash : '${p.t1Pace}/day',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.colors.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.caption),
          const SizedBox(height: 2),
          Text(value, style: context.text.statS),
        ],
      ),
    ),
  );
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.state});
  final StudyState state;

  @override
  Widget build(BuildContext context) {
    final f = state.focus;
    final c = context.colors;
    final q = f.question;
    if (f.isEmpty) {
      return EmptyState(
        title: 'No current focus',
        message: 'Set "Current focus" and "Next action" in the Start Here tab.',
        action: PrimaryButton(
          label: 'Start 25-min session',
          onPressed: () => context.push('/session'),
        ),
      );
    }
    final idChip = [
      ?f.questionId,
      if (q != null && q.sourceTab.isNotEmpty) q.sourceTab,
      if (q?.tier != null) 'T${q!.tier}',
    ].join(' · ');
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Tag('CURRENT FOCUS', background: c.accentWell, color: c.accent),
              if (idChip.isNotEmpty) Tag(idChip),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            (q != null && q.topic.isNotEmpty) ? q.topic : (f.focusText ?? dash),
            style: context.text.statS.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          if (q != null && q.question.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(q.question, style: context.text.bodyS),
          ],
          if (f.resume != null) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: c.divider),
            const SizedBox(height: 10),
            Text('Resume here', style: context.text.caption),
            const SizedBox(height: 4),
            Text(
              f.resume!,
              style: context.text.bodyS.copyWith(color: c.text, height: 1.4),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Start 25-min session',
                  onPressed: () => context.push(
                    f.questionId == null
                        ? '/session'
                        : '/session?q=${Uri.encodeComponent(f.questionId!)}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlineButton(
                label: 'Log it',
                height: 48,
                radius: 14,
                onPressed: () =>
                    showLogSessionDialog(context, questionId: f.questionId),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BusEntry extends StatelessWidget {
  const _BusEntry({required this.due});
  final int due;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      color: c.busEntry,
      borderColor: c.busBorder,
      onTap: () => context.push('/bus'),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.busWell,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: AppIcon(AppIcons.bus, size: 22, color: c.info),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bus mode', style: context.text.body),
                const SizedBox(height: 2),
                Text(
                  due == 0
                      ? 'Nothing due today. Rated cards come back on schedule.'
                      : '$due T1 cards due. One card at a time, rate yourself, done.',
                  style: context.text.caption.copyWith(color: c.busTextMuted),
                ),
              ],
            ),
          ),
          AppIcon(AppIcons.chevron, size: 18, stroke: 2, color: c.info),
        ],
      ),
    );
  }
}

class _Browse extends StatelessWidget {
  const _Browse({required this.state});
  final StudyState state;

  @override
  Widget build(BuildContext context) {
    final sources = state.progress!.sourceCounts;
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Browse the bank', style: context.text.caption),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in sources.entries)
              SizedBox(
                height: 44,
                child: ActionChip(
                  label: Text(
                    '${e.key} · ${e.value}',
                    style: context.text.bodyS.copyWith(color: c.text),
                  ),
                  backgroundColor: c.surface2,
                  side: BorderSide(color: c.borderStrong),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  onPressed: () => _openSource(context, e.key),
                ),
              ),
          ],
        ),
      ],
    );
  }

  void _openSource(BuildContext context, String source) {
    final list = state.bank
        .where((q) => (q.sourceTab.isEmpty ? 'Other' : q.sourceTab) == source)
        .toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (context, controller) => ListView.separated(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
          itemCount: list.length + 1,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: context.colors.divider),
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('$source · ${list.length}', style: context.text.h2),
              );
            }
            return _QuestionTile(q: list[i - 1]);
          },
        ),
      ),
    );
  }
}

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({required this.q});
  final StudyQuestion q;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text(
        q.question.isEmpty ? q.topic : q.question,
        style: context.text.bodyS.copyWith(color: c.text),
      ),
      subtitle: Text(
        [q.id, q.meta].where((s) => s.isNotEmpty).join(' · '),
        style: context.text.caption,
      ),
      children: [
        if (q.followUps.isNotEmpty)
          Text(
            'Follow-ups: ${q.followUps.join(' ')}',
            style: context.text.caption,
          ),
        const SizedBox(height: 6),
        for (final p in q.answerPoints)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('•  $p', style: context.text.bodyS),
          ),
      ],
    );
  }
}
