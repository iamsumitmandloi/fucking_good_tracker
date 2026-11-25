import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/deps.dart';
import '../../app/sync_status.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/app_icon.dart';
import '../../app/widgets/common.dart';
import '../../core/clock.dart';
import '../../core/feature_flags.dart';
import '../../core/formatters.dart';
import '../../data/repo/settings_repository.dart';
import 'settings_cubit.dart';
import 'voice_model_section.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => SettingsCubit(c.read<AppDeps>()),
      child: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    final d = context.dims;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(d.screenH, 8, d.screenH, 32),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => context.pop(),
                  icon: Transform.flip(
                    flipX: true,
                    child: AppIcon(
                      AppIcons.chevron,
                      color: context.colors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text('Settings', style: context.text.h2),
              ],
            ),
            if (FeatureFlags.logging) ...[
              const SizedBox(height: 12),
              VoiceModelSection(
                repository: context.read<AppDeps>().voiceModels,
              ),
            ],
            const SizedBox(height: 12),
            const _ConnectionSection(),
            const SizedBox(height: 12),
            const _SyncSection(),
            const SizedBox(height: 12),
            const _PreferencesSection(),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: context.text.label),
  );
}

class _ConnectionSection extends StatefulWidget {
  const _ConnectionSection();

  @override
  State<_ConnectionSection> createState() => _ConnectionSectionState();
}

class _ConnectionSectionState extends State<_ConnectionSection> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  bool _urlLoaded = false;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return BlocConsumer<SettingsCubit, SettingsState>(
      listenWhen: (a, b) => a.url != b.url,
      listener: (_, s) {
        if (!_urlLoaded) {
          _url.text = s.url;
          _urlLoaded = true;
        }
      },
      builder: (context, s) {
        final c = context.colors;
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionTitle('Sheet connection'),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                style: context.text.bodyS.copyWith(color: c.text),
                decoration: const InputDecoration(
                  labelText: 'Web app URL (/exec)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _token,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                style: context.text.bodyS.copyWith(color: c.text),
                decoration: InputDecoration(
                  labelText: 'Token',
                  hintText: s.hasToken
                      ? '•••• saved · type to replace'
                      : 'Paste token',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: 'Save',
                      onPressed: () async {
                        await cubit.saveConnection(
                          url: _url.text,
                          token: _token.text,
                        );
                        _token.clear();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Saved')),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlineButton(
                    label: s.test == TestStatus.running
                        ? 'Testing…'
                        : 'Test connection',
                    height: 48,
                    radius: 14,
                    onPressed: s.test == TestStatus.running
                        ? null
                        : () => unawaited(cubit.testConnection()),
                  ),
                ],
              ),
              if (s.testMessage != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: s.test == TestStatus.ok ? c.accent : c.warn,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.test == TestStatus.ok
                            ? 'OK · ${s.testMessage}'
                            : s.testMessage!,
                        style: context.text.caption.copyWith(
                          color: s.test == TestStatus.ok ? c.accent : c.warn,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SyncSection extends StatelessWidget {
  const _SyncSection();

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncStatusCubit>().state;
    final log = context.select<SettingsCubit, List<String>>((c) => c.state.log);
    final c = context.colors;
    final last = sync.lastSyncAt == null
        ? dash
        : formatTime(sync.lastSyncAt!.toUtc().add(istOffset));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('Sync'),
          _Row(
            'Waiting to send',
            sync.pending == 0 ? 'Nothing' : '${sync.pending}',
            color: sync.pending == 0 ? null : c.warn,
          ),
          _Row('Last synced', last),
          _Row(
            'Connection',
            sync.online ? 'Online' : 'Offline',
            color: sync.online ? null : c.warn,
          ),
          if (sync.lastError != null)
            _Row('Last error', sync.lastError!, color: c.warn),
          const SizedBox(height: 10),
          OutlineButton(
            label: 'Sync now',
            onPressed: () => unawaited(context.read<SettingsCubit>().syncNow()),
          ),
          if (log.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Log', style: context.text.caption),
            const SizedBox(height: 4),
            for (final line in log.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  line.replaceFirst('T', ' '),
                  style: context.text.caption.copyWith(color: c.textDim),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: context.text.caption)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: context.text.caption.copyWith(
              color: color ?? context.colors.text,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PreferencesSection extends StatelessWidget {
  const _PreferencesSection();

  @override
  Widget build(BuildContext context) {
    final s = context.select<SettingsCubit, AppSettings>(
      (c) => c.state.settings,
    );
    final cubit = context.read<SettingsCubit>();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('Preferences'),
          _Tappable(
            label: 'Interview target date',
            value: s.targetDate,
            onTap: () async {
              final initial = parseDate(s.targetDate) ?? DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(2024),
                lastDate: DateTime(2030),
              );
              if (picked != null) {
                await cubit.update(
                  s.copyWith(
                    targetDate: formatDate(
                      DateTime.utc(picked.year, picked.month, picked.day),
                    ),
                  ),
                );
              }
            },
          ),
          _NumberField(
            label: 'Cigarette daily budget',
            value: s.cigBudget,
            onChanged: (v) => cubit.update(s.copyWith(cigBudget: v)),
          ),
          _NumberField(
            label: 'Cigarette price ₹',
            value: s.cigPrice.round(),
            onChanged: (v) => cubit.update(s.copyWith(cigPrice: v.toDouble())),
          ),
          _NumberField(
            label: 'Tea price ₹',
            value: s.teaPrice.round(),
            onChanged: (v) => cubit.update(s.copyWith(teaPrice: v.toDouble())),
          ),
          _NumberField(
            label: 'Breakfast protein target g',
            value: s.proteinTargetG,
            onChanged: (v) => cubit.update(s.copyWith(proteinTargetG: v)),
          ),
          _NumberField(
            label: 'Bus mode cards per run',
            value: s.busRunSize,
            onChanged: (v) =>
                cubit.update(s.copyWith(busRunSize: v.clamp(1, 50))),
          ),
          const SizedBox(height: 8),
          _SupplementsEditor(
            items: s.supplements,
            onChanged: (list) => cubit.update(s.copyWith(supplements: list)),
          ),
        ],
      ),
    );
  }
}

class _Tappable extends StatelessWidget {
  const _Tappable({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.text.bodyS)),
          Text(value, style: context.text.label),
        ],
      ),
    ),
  );
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: Row(
      children: [
        Expanded(child: Text(label, style: context.text.bodyS)),
        SizedBox(
          width: 88,
          child: TextFormField(
            key: ValueKey('$label-$value'),
            initialValue: '$value',
            textAlign: TextAlign.right,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: context.text.label,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
            ),
            onFieldSubmitted: (t) {
              final v = int.tryParse(t);
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    ),
  );
}

class _SupplementsEditor extends StatefulWidget {
  const _SupplementsEditor({required this.items, required this.onChanged});
  final List<String> items;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_SupplementsEditor> createState() => _SupplementsEditorState();
}

class _SupplementsEditorState extends State<_SupplementsEditor> {
  final _add = TextEditingController();

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _add.text.trim();
    if (t.isEmpty || widget.items.contains(t)) return;
    widget.onChanged([...widget.items, t]);
    _add.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Supplements checklist', style: context.text.bodyS),
        const SizedBox(height: 8),
        if (widget.items.isEmpty)
          Text(
            'None yet. The Today tile shows "—" until you add some.',
            style: context.text.caption,
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in widget.items)
              InputChip(
                label: Text(
                  s,
                  style: context.text.caption.copyWith(color: c.text),
                ),
                backgroundColor: c.surface2,
                side: BorderSide(color: c.border),
                onDeleted: () => widget.onChanged([...widget.items]..remove(s)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _add,
                style: context.text.bodyS.copyWith(color: c.text),
                decoration: const InputDecoration(
                  hintText: 'Add a supplement',
                  isDense: true,
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 8),
            OutlineButton(label: 'Add', onPressed: _submit),
          ],
        ),
      ],
    );
  }
}
