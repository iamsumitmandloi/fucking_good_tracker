import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/deps.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/app_icon.dart';
import '../../app/widgets/common.dart';
import '../../core/clock.dart';
import 'session_events.dart';

const sessionLength = Duration(minutes: 25);
const _metaKey = 'session_running';

/// 25-minute focus timer. The start time is persisted, so killing or
/// backgrounding the app doesn't lose the session.
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, this.questionId});

  final String? questionId;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  DateTime? _startUtc;
  String? _questionId;
  Timer? _tick;
  bool _logged = false;
  int _loggedMinutes = 0;

  AppDeps get _deps => context.read<AppDeps>();

  @override
  void initState() {
    super.initState();
    unawaited(_restoreOrStart());
  }

  Future<void> _restoreOrStart() async {
    final raw = await _deps.db.readMeta(_metaKey);
    DateTime? start;
    String? q = widget.questionId;
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        start = DateTime.tryParse(j['start'] as String? ?? '');
        q = (j['q'] as String?) ?? q;
      } on Object {
        start = null;
      }
    }
    if (start == null) {
      start = _deps.clock.nowUtc();
      await _deps.db.writeMeta(
        _metaKey,
        jsonEncode({'start': start.toIso8601String(), 'q': q}),
      );
    }
    if (!mounted) return;
    setState(() {
      _startUtc = start;
      _questionId = q;
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _onTick();
  }

  void _onTick() {
    if (!mounted || _startUtc == null || _logged) return;
    if (_elapsed >= sessionLength) {
      unawaited(_finish());
    } else {
      setState(() {});
    }
  }

  Duration get _elapsed => _startUtc == null
      ? Duration.zero
      : _deps.clock.nowUtc().difference(_startUtc!);

  Future<void> _finish() async {
    if (_logged || _startUtc == null) return;
    _logged = true;
    _tick?.cancel();
    final startIst = _startUtc!.add(istOffset);
    final elapsed = _elapsed > sessionLength ? sessionLength : _elapsed;
    final e = sessionEvent(
      startIst: DateTime.utc(
        startIst.year,
        startIst.month,
        startIst.day,
        startIst.hour,
        startIst.minute,
      ),
      endIst: DateTime.utc(
        startIst.year,
        startIst.month,
        startIst.day,
        startIst.hour,
        startIst.minute,
      ).add(elapsed),
      questionId: _questionId,
    );
    await _deps.events.log([e]);
    await _deps.db.writeMeta(_metaKey, null);
    if (mounted) setState(() => _loggedMinutes = e.qty!.round());
  }

  Future<void> _cancel() async {
    _tick?.cancel();
    await _deps.db.writeMeta(_metaKey, null);
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final remaining = sessionLength - _elapsed;
    final r = remaining.isNegative ? Duration.zero : remaining;
    final mm = r.inMinutes.toString().padLeft(2, '0');
    final ss = (r.inSeconds % 60).toString().padLeft(2, '0');
    final progress = _elapsed.inSeconds / sessionLength.inSeconds;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => context.pop(),
                    icon: AppIcon(
                      AppIcons.close,
                      size: 18,
                      stroke: 2,
                      color: c.textMuted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _questionId == null
                        ? 'Study session'
                        : 'Session · $_questionId',
                    style: context.text.label.copyWith(color: c.accent),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
              const Spacer(),
              if (_logged)
                Column(
                  children: [
                    Text('$_loggedMinutes min logged.', style: context.text.h1),
                    const SizedBox(height: 8),
                    Text(
                      'Saved on the phone; it syncs when there is signal.',
                      style: context.text.caption,
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    Semantics(
                      label: '$mm minutes $ss seconds left',
                      child: Text(
                        '$mm:$ss',
                        style: context.text.statXl.copyWith(
                          fontSize: 72,
                          letterSpacing: -2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0, 1),
                        minHeight: 8,
                        backgroundColor: c.track,
                        color: c.accent,
                      ),
                    ),
                  ],
                ),
              const Spacer(),
              if (_logged)
                PrimaryButton(
                  label: 'Done',
                  height: 54,
                  radius: 16,
                  onPressed: () => context.pop(),
                )
              else ...[
                PrimaryButton(
                  label: 'Finish and log',
                  height: 54,
                  radius: 16,
                  onPressed: _startUtc == null
                      ? null
                      : () => unawaited(_finish()),
                ),
                const SizedBox(height: 8),
                OutlineButton(
                  label: 'Discard session',
                  height: 48,
                  radius: 14,
                  onPressed: _cancel,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
