import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../data/voice/voice_model_store.dart';
import '../../domain/voice/voice_contracts.dart';

class VoiceModelSection extends StatefulWidget {
  const VoiceModelSection({super.key, required this.repository});

  final VoiceModelRepository repository;

  @override
  State<VoiceModelSection> createState() => _VoiceModelSectionState();
}

class _VoiceModelSectionState extends State<VoiceModelSection> {
  late Stream<VoiceModelState> _states;

  @override
  void initState() {
    super.initState();
    _states = widget.repository.watchState();
  }

  @override
  void didUpdateWidget(VoiceModelSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.repository != oldWidget.repository) {
      _states = widget.repository.watchState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    return StreamBuilder<VoiceModelState>(
      stream: _states,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final status = state?.status;
        final percent = ((state?.progress ?? 0) * 100).floor();
        final description = switch (status) {
          null => 'Checking model…',
          VoiceModelStatus.missing => 'Not downloaded (~160 MB)',
          VoiceModelStatus.downloading => 'Downloading $percent%',
          VoiceModelStatus.ready => 'Ready offline',
          VoiceModelStatus.error => state?.error ?? 'Model unavailable',
        };
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Whisper base (int8) + Silero VAD',
                style: context.text.label,
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: context.text.caption.copyWith(
                  color: status == VoiceModelStatus.error
                      ? context.colors.warn
                      : context.colors.textMuted,
                ),
              ),
              if (status == VoiceModelStatus.downloading) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: state!.totalBytes > 0 ? state.progress : null,
                  semanticsLabel: 'Model download progress',
                ),
              ],
              if (status != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (status == VoiceModelStatus.missing ||
                        status == VoiceModelStatus.error)
                      PrimaryButton(
                        label: status == VoiceModelStatus.error
                            ? 'Retry download'
                            : 'Download',
                        onPressed: () => repository.download(),
                      ),
                    if (status == VoiceModelStatus.downloading &&
                        repository is CancellableVoiceModelRepository)
                      OutlineButton(
                        label: 'Cancel',
                        onPressed: repository.cancelDownload,
                      ),
                    if (status == VoiceModelStatus.ready ||
                        status == VoiceModelStatus.error)
                      OutlineButton(
                        label: 'Delete',
                        onPressed: repository.delete,
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
