import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/busmode/busmode_screen.dart';
import '../features/money/money_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/study/session_screen.dart';
import '../features/study/study_screen.dart';
import '../features/today/today_screen.dart';
import '../features/week/week_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/app_icon.dart';

GoRouter buildRouter({String initialLocation = '/today'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/today', builder: (_, _) => const TodayScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/study', builder: (_, _) => const StudyScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/week', builder: (_, _) => const WeekScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/money', builder: (_, _) => const MoneyScreen()),
          ],
        ),
      ],
    ),
    GoRoute(path: '/bus', builder: (_, _) => const BusModeScreen()),
    GoRoute(
      path: '/session',
      builder: (_, state) =>
          SessionScreen(questionId: state.uri.queryParameters['q']),
    ),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
  ],
);

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: BottomNav(
        index: shell.currentIndex,
        onTap: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
      ),
    );
  }
}

class BottomNav extends StatelessWidget {
  const BottomNav({super.key, required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  static const _items = [
    (AppIcons.today, 'Today'),
    (AppIcons.study, 'Study'),
    (AppIcons.week, 'Week'),
    (AppIcons.money, 'Money'),
  ];

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
          height: context.dims.navHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: Semantics(
                      selected: i == index,
                      button: true,
                      label: _items[i].$2,
                      child: InkResponse(
                        onTap: () => onTap(i),
                        child: ExcludeSemantics(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AppIcon(
                                _items[i].$1,
                                size: 22,
                                color: i == index ? c.accent : c.textMuted,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _items[i].$2,
                                style: context.text.nav.copyWith(
                                  color: i == index ? c.accent : c.textMuted,
                                  fontWeight: i == index
                                      ? FontWeight.w600
                                      : FontWeight.w500,
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
