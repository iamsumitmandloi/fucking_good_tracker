import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../features/viewer/viewer_cubit.dart';
import 'deps.dart';
import 'router.dart';
import 'sync_status.dart';
import 'theme/app_theme.dart';

class StartingAgainApp extends StatefulWidget {
  const StartingAgainApp({
    super.key,
    required this.deps,
    this.theme,
    this.initialLocation,
    this.extraRoutes = const [],
  });

  final AppDeps deps;

  /// Tests pass a theme without google_fonts.
  final ThemeData? theme;

  /// Null opens the default tab ([defaultLocation]).
  final String? initialLocation;

  /// Tests mount screens that are not in the shell (e.g. the v1 Week).
  final List<RouteBase> extraRoutes;

  @override
  State<StartingAgainApp> createState() => _StartingAgainAppState();
}

class _StartingAgainAppState extends State<StartingAgainApp> {
  late final GoRouter _router = buildRouter(
    initialLocation: widget.initialLocation,
    extraRoutes: widget.extraRoutes,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.deps;
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: d),
        RepositoryProvider.value(value: d.clock),
        RepositoryProvider.value(value: d.events),
        RepositoryProvider.value(value: d.study),
        RepositoryProvider.value(value: d.legacy),
        RepositoryProvider.value(value: d.settings),
        RepositoryProvider.value(value: d.appSync),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => SyncStatusCubit(db: d.db, appSync: d.appSync),
          ),
          BlocProvider(
            create: (_) => ViewerCubit(
              events: d.events,
              settings: d.settings,
              db: d.db,
              clock: d.clock,
            ),
          ),
        ],
        child: MaterialApp.router(
          title: 'Starting Again',
          debugShowCheckedModeBanner: false,
          theme: widget.theme ?? buildTheme(),
          darkTheme: widget.theme ?? buildTheme(),
          themeMode: ThemeMode.dark,
          routerConfig: _router,
        ),
      ),
    );
  }
}
