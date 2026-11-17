import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/clock.dart';
import '../../data/repo/events_repository.dart';
import 'session_events.dart';

/// "Log it": record a session done away from the timer.
Future<void> showLogSessionDialog(BuildContext context, {String? questionId}) {
  final events = context.read<EventsRepository>();
  final clock = context.read<Clock>();
  final ctrl = TextEditingController(text: '25');
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        'Log a study session',
        style: ctx.text.h2.copyWith(fontSize: 20),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (questionId != null)
            Text('For $questionId, ending now.', style: ctx.text.caption),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: ctx.text.statS,
            decoration: const InputDecoration(
              labelText: 'Minutes',
              suffixText: 'min',
            ),
          ),
        ],
      ),
      actions: [
        OutlineButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx)),
        PrimaryButton(
          label: 'Log',
          height: 44,
          radius: 12,
          onPressed: () async {
            final mins = int.tryParse(ctrl.text);
            if (mins == null || mins <= 0) return;
            final end = clock.nowIst();
            await events.log([
              sessionEvent(
                startIst: end.subtract(Duration(minutes: mins)),
                endIst: end,
                questionId: questionId,
              ),
            ]);
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Logged $mins min session')),
              );
            }
          },
        ),
      ],
    ),
  ).whenComplete(ctrl.dispose);
}
