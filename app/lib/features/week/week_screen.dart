import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';

class WeekScreen extends StatelessWidget {
  const WeekScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final d = context.dims;
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(d.screenH, d.screenTop, d.screenH, 24),
        children: const [
          ScreenHeader(caption: '', title: 'Week'),
          SizedBox(height: 12),
          EmptyState(
            title: 'Nothing here yet',
            message: 'Data appears after the first sync.',
          ),
        ],
      ),
    );
  }
}
