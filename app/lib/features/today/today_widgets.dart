import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/app_icon.dart';
import '../../app/widgets/common.dart';
import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../../domain/derivations/sleep.dart';
import '../../domain/quicklog/build_events.dart';
import 'today_cubit.dart';

/// 104-tall tile: icon + lime "+", big number, one-line caption.
/// Dashed border when the metric has never been logged.
class QuickTile extends StatelessWidget {
  const QuickTile({
    super.key,
    required this.icon,
    required this.value,
    required this.caption,
    required this.semanticLabel,
    this.onTap,
    this.onLongPress,
    this.showPlus = false,
    this.dashed = false,
  });

  final AppIcons icon;
  final Widget value;
  final String caption;
  final String semanticLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showPlus;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: SizedBox(
        height: context.dims.tileHeight,
        child: AppCard(
          padding: const EdgeInsets.all(12),
          dashed: dashed,
          color: dashed ? Colors.transparent : null,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppIcon(icon, color: c.textMuted),
                  const Spacer(),
                  if (showPlus)
                    AppIcon(
                      AppIcons.plus,
                      size: 18,
                      stroke: 2.2,
                      color: c.accent,
                    ),
                ],
              ),
              const Spacer(),
              ExcludeSemantics(child: value),
              const SizedBox(height: 2),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Big tile number with an optional dim suffix ("0/4", "—/50g").
class TileValue extends StatelessWidget {
  const TileValue(this.value, {super.key, this.unit, this.color});

  final String value;
  final String? unit;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = context.text.statL.copyWith(color: color);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: unit == null
          ? Text(value, maxLines: 1, style: style)
          : NumberWithUnit(value, unit!, style: style, unitSize: 14),
    );
  }
}

/// "Logged 1 cigarette · 18:02 · ₹25 · Undo" for 6 s, else the last entry.
class UndoLine extends StatelessWidget {
  const UndoLine({super.key, required this.state});
  final TodayState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final u = state.undo;
    final last = state.lastEvent;
    final String text;
    if (u != null) {
      text = u.text;
    } else if (last != null) {
      text = [
        'Last: ${logLine(last)}',
        if (last.time != null) 'at ${last.time}',
      ].join(' ');
    } else {
      text = '';
    }
    // 44 tall only while the Undo button is there (touch target);
    // otherwise just enough for one caption line, or a small gap.
    return SizedBox(
      height: u != null ? 44 : (text.isEmpty ? 12 : 32),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              key: const Key('undo-text'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.caption,
            ),
          ),
          if (u != null)
            TextButton(
              key: const Key('undo-button'),
              onPressed: () => context.read<TodayCubit>().undo(),
              style: TextButton.styleFrom(
                foregroundColor: c.accent,
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(
                'Undo',
                style: context.text.label.copyWith(color: c.accent),
              ),
            ),
        ],
      ),
    );
  }
}

/// One button cycling Board → Arrived → Board home → Arrived → Done.
class BusCard extends StatelessWidget {
  const BusCard({super.key, required this.state});
  final TodayState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cm = state.commute;
    final String title;
    final String sub;
    final String cta;
    switch (state.busAction) {
      case BusAction.arrive:
        title = cm.completedCount >= 1 ? 'On the bus home' : 'On the bus';
        sub = 'Boarded ${cm.legs.last.board ?? dash} · bus mode ready';
        cta = 'Arrived';
      case BusAction.done:
        final last = cm.lastCompleted!;
        title = 'Home ${last.arrive}';
        sub = 'Commute today ${duration(cm.totalMinutes)}';
        cta = 'Done';
      case BusAction.board:
        final last = cm.lastCompleted;
        if (last == null) {
          title = 'No bus yet today';
          sub = 'Tap Board when you get on';
          cta = 'Board';
        } else {
          title = 'Reached ${last.arrive}';
          sub = 'Boarded ${last.board} · ${duration(last.minutes)}';
          cta = 'Board home';
        }
    }
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.surface2,
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
                Text(
                  title,
                  key: const Key('bus-title'),
                  style: context.text.body,
                ),
                const SizedBox(height: 2),
                Text(sub, style: context.text.caption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlineButton(
            key: const Key('bus-button'),
            label: cta,
            fill: c.surface2,
            onPressed: state.busAction == BusAction.done
                ? null
                : () => context.read<TodayCubit>().busTap(),
          ),
        ],
      ),
    );
  }
}

/// Lime card: current focus and next action from Start Here.
class UpNextCard extends StatelessWidget {
  const UpNextCard({super.key, required this.state});
  final TodayState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = state.focus;
    final q = f.question;
    final target = parseDate(state.settings.targetDate);
    final left = state.daysLeft;
    final String countdown;
    if (left == null || target == null) {
      countdown = '';
    } else if (left > 0) {
      countdown =
          '$left ${left == 1 ? 'day' : 'days'} to ${DateFormat('d MMM').format(target)}';
    } else if (left == 0) {
      countdown = 'Target day';
    } else {
      countdown = 'Target passed';
    }
    final title = f.isEmpty
        ? 'Set a current focus'
        : (q != null && q.topic.isNotEmpty)
        ? q.topic
        : (f.focusText ?? dash);
    final body = f.isEmpty
        ? 'Add "Current focus" and "Next action" to the Start Here tab, then pull to refresh.'
        : f.nextAction;
    final overline = context.text.overline;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(context.dims.rHero),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  f.questionId == null
                      ? 'UP NEXT'
                      : 'UP NEXT · ${f.questionId}',
                  style: overline,
                ),
              ),
              Text(countdown.toUpperCase(), style: overline),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: context.text.cardTitle.copyWith(color: c.onAccent),
          ),
          if (body != null && body.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              body,
              style: context.text.bodyS.copyWith(
                color: c.onAccentMuted,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Start 25 min',
                  height: 44,
                  radius: 12,
                  background: c.bg,
                  foreground: c.accent,
                  onPressed: () => context.push(
                    f.questionId == null
                        ? '/session'
                        : '/session?q=${Uri.encodeComponent(f.questionId!)}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlineButton(
                label: 'Bus mode',
                color: c.onAccent,
                borderColor: c.onAccent,
                borderWidth: 1.5,
                onPressed: () => context.push('/bus'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Last night: "~7.5 h est." and "~22:30 → ~06:00". Orange after 02:00.
class SleepCard extends StatelessWidget {
  const SleepCard({super.key, required this.night});
  final SleepWindow? night;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = night;
    final h = n?.hours;
    final a = (n?.approx ?? false) ? '~' : '';
    final String caption;
    if (n == null) {
      caption = 'Not logged';
    } else if (n.wake == null) {
      caption = 'Bed $a${n.bed} · no wake yet';
    } else {
      caption = '$a${n.bed} → $a${n.wake}';
    }
    final style = context.text.statS.copyWith(
      color: (n?.late ?? false) ? c.warn : null,
    );
    return StatCard(
      label: 'Slept',
      caption: caption,
      value: Text.rich(
        TextSpan(
          text: h == null ? dash : '$a${trimNum(h)} h',
          style: style,
          children: [
            if (h != null && n!.approx)
              TextSpan(
                text: ' est.',
                style: context.text.caption.copyWith(
                  color: c.textDim,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SpendCard extends StatelessWidget {
  const SpendCard({super.key, required this.state});
  final TodayState state;

  @override
  Widget build(BuildContext context) {
    final s = state.summary;
    final n = s.spendEntries;
    final week = state.weekSpend;
    return StatCard(
      label: 'Spent today',
      onTap: () => context.go('/money'),
      value: Text(rupees(s.spend), style: context.text.statS),
      caption: [
        if (n > 0) '$n ${n == 1 ? 'entry' : 'entries'}' else 'Nothing yet',
        if (week != null) 'week ${rupeesCompact(week)}',
      ].join(' · '),
    );
  }
}

/// Today's supplements as a checklist. Ticking logs, unticking undoes.
Future<void> showSupplementsSheet(BuildContext context) {
  final cubit = context.read<TodayCubit>();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(context.dims.rSheet),
      ),
    ),
    builder: (_) =>
        BlocProvider.value(value: cubit, child: const _SupplementsSheet()),
  );
}

class _SupplementsSheet extends StatelessWidget {
  const _SupplementsSheet();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<TodayCubit>().state;
    final c = context.colors;
    final list = s.settings.supplements;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Supplements today', style: context.text.h2),
            const SizedBox(height: 8),
            if (list.isEmpty) ...[
              Text(
                'No supplements in your list yet. Add them in Settings.',
                style: context.text.bodyS,
              ),
              const SizedBox(height: 12),
              OutlineButton(
                label: 'Open Settings',
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/settings');
                },
              ),
            ] else
              for (final name in list)
                CheckboxListTile(
                  value: s.summary.hasSupplement(name),
                  onChanged: (_) =>
                      context.read<TodayCubit>().toggleSupplement(name),
                  title: Text(name, style: context.text.label),
                  activeColor: c.accent,
                  checkColor: c.onAccent,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
          ],
        ),
      ),
    );
  }
}
