import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/app_icon.dart';
import '../../domain/event_type.dart';
import '../../domain/study_question.dart';
import 'busmode_cubit.dart';

class BusModeScreen extends StatelessWidget {
  const BusModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => BusModeCubit(
        events: c.read(),
        study: c.read(),
        settings: c.read(),
        clock: c.read(),
      )..start(),
      child: const BusModeView(),
    );
  }
}

class BusModeView extends StatelessWidget {
  const BusModeView({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<BusModeCubit>().state;
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bgBus,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(state: s),
              const SizedBox(height: 14),
              if (s.cards.isNotEmpty) ...[
                _Segments(state: s),
                const SizedBox(height: 14),
              ],
              Expanded(
                child: switch (s.status) {
                  BusStatus.loading => const SizedBox.shrink(),
                  BusStatus.empty => _Empty(bankEmpty: s.bankEmpty),
                  BusStatus.running => _CardView(state: s),
                  BusStatus.done => _Summary(state: s),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});
  final BusState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final progress = switch (state.status) {
      BusStatus.running => 'card ${state.index + 1} of ${state.cards.length}',
      BusStatus.done => 'all done',
      _ => null,
    };
    final sub = [
      if (state.boardedAt != null) 'Boarded ${state.boardedAt}',
      ?progress,
    ].join(' · ');
    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Exit bus mode',
          child: InkResponse(
            onTap: () => context.pop(),
            radius: 24,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: c.busChip,
                borderRadius: BorderRadius.circular(22),
              ),
              alignment: Alignment.center,
              child: AppIcon(
                AppIcons.close,
                size: 18,
                stroke: 2,
                color: c.busTextMuted,
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                'Bus mode',
                style: context.text.label.copyWith(fontSize: 13, color: c.info),
              ),
              if (sub.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: context.text.caption.copyWith(color: c.busTextMuted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 44),
      ],
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({required this.state});
  final BusState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Color colorFor(int i) {
      if (i < state.ratings.length) {
        return switch (state.ratings[i]) {
          Rating.blank => c.warn,
          Rating.nailed => c.accent,
          _ => c.textMuted,
        };
      }
      return i == state.index ? c.info : c.busBorder;
    }

    final gap = state.cards.length > 12 ? 3.0 : 6.0;
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var i = 0; i < state.cards.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  color: colorFor(i),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardView extends StatelessWidget {
  const _CardView({required this.state});
  final BusState state;

  @override
  Widget build(BuildContext context) {
    final q = state.current!;
    final cubit = context.read<BusModeCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: FlashCard(question: q, revealed: state.revealed),
        ),
        const SizedBox(height: 14),
        if (!state.revealed)
          _BigButton(
            label: 'Say it out loud, then reveal',
            background: context.colors.info,
            foreground: context.colors.bgBus,
            onTap: cubit.reveal,
          )
        else
          Row(
            children: [
              Expanded(
                child: _BigButton(
                  label: 'Blank',
                  background: context.colors.warnWell,
                  foreground: context.colors.warn,
                  border: context.colors.warnBorder,
                  onTap: () => unawaited(cubit.rate(Rating.blank)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BigButton(
                  label: 'Shaky',
                  background: context.colors.surface2,
                  foreground: context.colors.text,
                  border: context.colors.borderStrong,
                  onTap: () => unawaited(cubit.rate(Rating.shaky)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BigButton(
                  label: 'Nailed it',
                  background: context.colors.accent,
                  foreground: context.colors.onAccent,
                  onTap: () => unawaited(cubit.rate(Rating.nailed)),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// FlashCard component (DESIGN.md §7).
class FlashCard extends StatelessWidget {
  const FlashCard({super.key, required this.question, required this.revealed});

  final StudyQuestion question;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = question;
    return Container(
      decoration: BoxDecoration(
        color: c.busCard,
        border: Border.all(color: c.busBorder),
        borderRadius: BorderRadius.circular(22),
      ),
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(context, q.id, c.busWell, c.info),
              if (q.meta.isNotEmpty)
                _chip(context, q.meta, c.busChip, c.busTextMuted),
            ],
          ),
          if (q.topic.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              q.topic,
              style: context.text.bodyS.copyWith(color: c.busTextMuted),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            q.question.isEmpty ? q.topic : q.question,
            style: context.text.question,
          ),
          if (q.followUps.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Follow-ups: ${q.followUps.join(' ')}',
              style: context.text.bodyS.copyWith(color: c.busTextMuted),
            ),
          ],
          if (revealed) ...[
            const SizedBox(height: 16),
            Divider(height: 1, color: c.busBorder),
            const SizedBox(height: 12),
            Text(
              'ANSWER POINTS',
              style: context.text.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: c.accent,
                letterSpacing: 0.48,
              ),
            ),
            const SizedBox(height: 8),
            if (q.answerPoints.isEmpty)
              Text(
                'No answer points in the sheet for this one.',
                style: context.text.bodyS,
              )
            else
              for (final p in q.answerPoints)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '•',
                        style: context.text.label.copyWith(color: c.accent),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          p,
                          style: context.text.label.copyWith(
                            fontWeight: FontWeight.w400,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String t, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(t, style: context.text.chip.copyWith(color: fg)),
  );
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.border,
    this.height = 56,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color? border;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: border == null ? BorderSide.none : BorderSide(color: border!),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: context.text.button.copyWith(
              color: foreground,
              fontSize: label.length > 12 ? 16 : 15,
            ),
          ),
        ),
      ),
    ),
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.state});
  final BusState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = state.ratings.length;
    Widget tile(String label, int v, Color? color) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.busCard,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: context.text.caption.copyWith(color: c.busTextMuted),
            ),
            Text(
              '$v',
              style: context.text.statM.copyWith(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          n == 1 ? '1 card done.' : '$n cards done.',
          style: context.text.h1.copyWith(fontSize: 30, height: 1.15),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            tile('Nailed', state.count(Rating.nailed), c.accent),
            const SizedBox(width: 8),
            tile('Shaky', state.count(Rating.shaky), null),
            const SizedBox(width: 8),
            tile('Blank', state.count(Rating.blank), c.warn),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Each card is saved as its own entry. Blank and Shaky come back tomorrow; Nailed comes back in 4 days.',
          style: context.text.label.copyWith(
            fontWeight: FontWeight.w400,
            color: c.busTextMuted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        _BigButton(
          label: 'Run it again',
          height: 52,
          background: c.busCard,
          foreground: c.text,
          border: c.busBorder,
          onTap: () => unawaited(context.read<BusModeCubit>().start()),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.bankEmpty});
  final bool bankEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          bankEmpty ? 'No cards on the phone yet.' : 'Nothing due right now.',
          style: context.text.h1.copyWith(fontSize: 28),
        ),
        const SizedBox(height: 12),
        Text(
          bankEmpty
              ? 'Open the Study tab once with signal to download the Study Bank. After that, Bus mode works offline.'
              : 'Every Tier-1 card is scheduled for later. Blank and Shaky return tomorrow.',
          style: context.text.label.copyWith(
            fontWeight: FontWeight.w400,
            color: c.busTextMuted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        _BigButton(
          label: 'Back',
          height: 52,
          background: c.busCard,
          foreground: c.text,
          border: c.busBorder,
          onTap: () => context.pop(),
        ),
      ],
    );
  }
}
