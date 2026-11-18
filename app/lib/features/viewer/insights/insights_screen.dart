import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../money/money_view_screen.dart';
import '../viewer_cubit.dart';

/// Insights tab. The body lives next to Money's widgets it shares.
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ViewerCubit>().state;
    if (!s.loaded) return const SizedBox.shrink();
    return InsightsBody(m: s.week!, daysWithData: s.dates.length);
  }
}
