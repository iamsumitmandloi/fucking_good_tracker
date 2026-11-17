import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_sync.dart';
import '../../app/deps.dart';
import '../../app/sync_status.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/app_icon.dart';
import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../../core/ids.dart';
import '../../domain/event_type.dart';
import '../quicklog/quicklog_sheet.dart';
import 'today_cubit.dart';
import 'today_widgets.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, this.idFactory = newEventId});

  /// Tests pass a `dev-` id factory.
  final String Function() idFactory;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => TodayCubit(
        events: c.read(),
        settings: c.read(),
        study: c.read(),
        clock: c.read(),
        db: c.read<AppDeps>().db,
        idFactory: idFactory,
      ),
      child: const _TodayView(),
    );
  }
}

/// Opens Quick log and logs whatever it returns (with the undo line).
Future<void> openQuickLog(BuildContext context, {String prefill = ''}) async {
  final cubit = context.read<TodayCubit>();
  final events = await showQuickLog(
    context,
    prefill: prefill,
    idFactory: cubit.idFactory,
  );
  if (events != null && events.isNotEmpty) await cubit.logAll(events);
}

String _mealPrefill(DateTime nowIst) {
  final h = nowIst.hour;
  if (h < 11) return 'breakfast ';
  if (h < 16) return 'lunch ';
  if (h < 19) return 'snack ';
  return 'dinner ';
}

class _TodayView extends StatelessWidget {
  const _TodayView();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<TodayCubit>().state;
    final d = context.dims;
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      floatingActionButton: Semantics(
        label: 'Quick log',
        button: true,
        child: FloatingActionButton(
          key: const Key('quicklog-fab'),
          onPressed: () => openQuickLog(context),
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          shape: const CircleBorder(),
          child: AppIcon(
            AppIcons.plus,
            size: 24,
            stroke: 2.2,
            color: c.onAccent,
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => context.read<AppSync>().syncNow(),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              d.screenH,
              d.screenTop - 8,
              d.screenH,
              96,
            ),
            children: [
              const SyncBanner(),
              _Header(state: s),
              SizedBox(height: d.gapL),
              if (s.loaded) ...[
                _Tiles(state: s),
                UndoLine(state: s),
                BusCard(state: s),
                SizedBox(height: d.gapL),
                UpNextCard(state: s),
                SizedBox(height: d.gapL),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: SleepCard(night: s.night)),
                    SizedBox(width: d.gap),
                    Expanded(child: SpendCard(state: s)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});
  final TodayState state;

  @override
  Widget build(BuildContext context) {
    final date = parseDate(state.today);
    final caption = [
      if (date != null) dayHeader(date),
      if (state.dayN != null) 'Day ${state.dayN}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  caption,
                  style: context.text.caption.copyWith(
                    fontSize: 13,
                    letterSpacing: 0.26,
                  ),
                ),
                const SizedBox(height: 2),
                Text('Today', style: context.text.h1),
              ],
            ),
          ),
          const SyncDot(),
        ],
      ),
    );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.state});
  final TodayState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final sum = s.summary;
    final c = context.colors;
    final cubit = context.read<TodayCubit>();
    final d = context.dims;

    final yDate = parseDate(s.yesterday.date);
    final cigCaption = s.yesterday.cigs != null && yDate != null
        ? 'Cigs · ${DateFormat('EEE').format(yDate)} was ${trimNum(s.yesterday.cigs)}'
        : 'Cigs · budget ${s.settings.cigBudget}';

    final meal = sum.lastMeal;
    final supps = s.settings.supplements;

    final tiles = <Widget>[
      QuickTile(
        key: const Key('tile-cig'),
        icon: AppIcons.cigarette,
        semanticLabel: 'Log one cigarette',
        showPlus: true,
        dashed: !s.everLogged.contains(EventType.cigarette),
        value: TileValue(
          sum.cigs == null ? dash : trimNum(sum.cigs),
          color: s.overCigBudget ? c.warn : null,
        ),
        caption: cigCaption,
        onTap: cubit.addCig,
        onLongPress: () => openQuickLog(context, prefill: 'cig '),
      ),
      QuickTile(
        key: const Key('tile-tea'),
        icon: AppIcons.tea,
        semanticLabel: 'Log one tea',
        showPlus: true,
        dashed: !s.everLogged.contains(EventType.tea),
        value: TileValue(sum.teas == null ? dash : trimNum(sum.teas)),
        caption: 'Tea · ${rupees(s.settings.teaPrice)} each',
        onTap: cubit.addTea,
        onLongPress: () => openQuickLog(context, prefill: 'tea '),
      ),
      QuickTile(
        key: const Key('tile-water'),
        icon: AppIcons.water,
        semanticLabel: 'Log 250 millilitres of water',
        showPlus: true,
        dashed: !s.everLogged.contains(EventType.waterMl),
        value: TileValue(
          sum.waterMl == null
              ? dash
              : '${trimNum(sum.waterMl! / 1000, digits: 2)} L',
        ),
        caption: 'Water · tap +250 ml',
        onTap: cubit.addWater,
        onLongPress: () => openQuickLog(context, prefill: 'water '),
      ),
      QuickTile(
        key: const Key('tile-meal'),
        icon: AppIcons.meal,
        semanticLabel: 'Log a meal',
        dashed:
            !s.everLogged.contains(EventType.meal) &&
            !s.everLogged.contains(EventType.snack),
        value: meal == null
            ? const TileValue(dash)
            : Text(
                meal.label ?? meal.note ?? 'Meal',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.statM,
              ),
        caption: meal == null
            ? 'Meal · not logged'
            : [
                ?meal.time,
                if (meal.amountInr != null) rupees(meal.amountInr),
              ].join(' · '),
        onTap: () => openQuickLog(
          context,
          prefill: _mealPrefill(context.read<Clock>().nowIst()),
        ),
        onLongPress: () => openQuickLog(context),
      ),
      QuickTile(
        key: const Key('tile-supps'),
        icon: AppIcons.pill,
        semanticLabel: 'Open supplement checklist',
        dashed: !s.everLogged.contains(EventType.supplement),
        value: supps.isEmpty
            ? const TileValue(dash)
            : TileValue('${s.suppsTaken}', unit: '/${supps.length}'),
        caption: supps.isEmpty ? 'Supps · set list' : 'Supplements',
        onTap: () => showSupplementsSheet(context),
        onLongPress: () => openQuickLog(context, prefill: 'supp '),
      ),
      QuickTile(
        key: const Key('tile-protein'),
        icon: AppIcons.protein,
        semanticLabel: 'Log breakfast protein',
        dashed: !s.everProtein,
        value: TileValue(
          sum.proteinG == null ? dash : trimNum(sum.proteinG),
          unit: '/${s.settings.proteinTargetG}g',
        ),
        caption: 'Bkfst protein',
        onTap: () => openQuickLog(context, prefill: 'protein '),
        onLongPress: () => openQuickLog(context, prefill: 'protein '),
      ),
    ];

    return Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) SizedBox(height: d.gap),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) SizedBox(width: d.gap),
                Expanded(child: tiles[row * 3 + i]),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
