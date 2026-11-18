import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../core/feature_flags.dart';
import '../features/busmode/busmode_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/study/session_screen.dart';
import '../features/study/study_screen.dart';
import '../features/today/today_screen.dart';
import '../features/viewer/day/day_screen.dart';
import '../features/viewer/insights/insights_screen.dart';
import '../features/viewer/money/money_view_screen.dart';
import '../features/viewer/trends/trends_screen.dart';
import '../features/viewer/week/week_view_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/app_icon.dart';

/// Where the app opens.
String get defaultLocation => FeatureFlags.logging ? '/today' : '/day';

typedef NavItem = (AppIcons icon, String label);

/// Tabs in shell order. Today and Study (both write events) exist only
/// when [FeatureFlags.logging] is on.
List<(String path, NavItem item, Widget Function(GoRouterState) screen)>
shellTabs() => [
  if (FeatureFlags.logging)
    ('/today', (AppIcons.today, 'Today'), (_) => const TodayScreen()),
  ('/day', (AppIcons.day, 'Day'), (_) => const DayScreen()),
  ('/week', (AppIcons.rows, 'Week'), (_) => const WeekViewScreen()),
  (
    '/trends',
    (AppIcons.trends, 'Trends'),
    (s) => TrendsScreen(sleep: s.uri.queryParameters['seg'] == 'sleep'),
  ),
  ('/money', (AppIcons.money, 'Money'), (_) => const MoneyViewScreen()),
  ('/insights', (AppIcons.insights, 'Insights'), (_) => const InsightsScreen()),
  if (FeatureFlags.logging)
    ('/study', (AppIcons.study, 'Study'), (_) => const StudyScreen()),
];

GoRouter buildRouter({
  String? initialLocation,
  List<RouteBase> extraRoutes = const [],
}) {
  final tabs = shellTabs();
  return GoRouter(
    initialLocation: initialLocation ?? defaultLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            AppShell(shell: shell, items: [for (final t in tabs) t.$2]),
        branches: [
          for (final t in tabs)
            StatefulShellBranch(
              routes: [GoRoute(path: t.$1, builder: (_, s) => t.$3(s))],
            ),
        ],
      ),
      if (FeatureFlags.logging) ...[
        GoRoute(path: '/bus', builder: (_, _) => const BusModeScreen()),
        GoRoute(
          path: '/session',
          builder: (_, state) =>
              SessionScreen(questionId: state.uri.queryParameters['q']),
        ),
      ],
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      ...extraRoutes,
    ],
  );
}

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell, required this.items});

  final StatefulNavigationShell shell;
  final List<NavItem> items;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: BottomNav(
        items: items,
        index: shell.currentIndex,
        onTap: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
      ),
    );
  }
}

class BottomNav extends StatelessWidget {
  const BottomNav({
    super.key,
    required this.items,
    required this.index,
    required this.onTap,
  });

  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.divider)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: Semantics(
                      selected: i == index,
                      button: true,
                      label: items[i].$2,
                      child: InkResponse(
                        onTap: () => onTap(i),
                        child: ExcludeSemantics(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AppIcon(
                                items[i].$1,
                                size: 22,
                                color: i == index ? c.accent : c.textMuted,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                items[i].$2,
                                style: context.text.nav.copyWith(
                                  color: i == index ? c.accent : c.textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
