# VOICE LOGGING PLAN (Offline-First · Whisper `base` · Review Before Saving)

**Status:** Ready for Phase V0  
**Defaults locked in:**
1. **Offline-first by default:** Speech-to-text and initial parsing work with zero network (airplane mode / bus commute).
2. **First evaluation model:** `sherpa_onnx` with `Whisper base (int8)` + `Silero-VAD`, running in a background Dart `Isolate` for concurrent phrase-by-phrase live transcription.
3. **Review before saving:** Spoken logs ALWAYS build an editable Draft Card inside `QuickLogSheet`—nothing writes to Drift / Outbox until the user taps **Log** (or confirms).
4. **Sheet-as-source-of-truth:** Follow `"One event for each activity. One spend event for each payment."` (`Today` row 16) and tag voice-created rows with `source: 'voice'`.

---

## 0. Concurrency & Dependency Map

```text
          ┌─────────────────────────────────────────────────────┐
          │ Phase V0: Packages, Permissions & Shared Contracts  │
          │ (Sequential gate — run first, ~15 min)              │
          └──────────────────────────┬──────────────────────────┘
                                     │
       ┌─────────────────────────────┼─────────────────────────────┐
       ▼                             ▼                             ▼
┌──────────────────┐       ┌──────────────────┐       ┌──────────────────┐
│ Phase V1:        │       │ Phase V2:        │       │ Phase V3:        │
│ Model Manager &  │       │ Offline Speech   │       │ Mic PCM Stream + │
│ Settings UI      │       │ Normalizer &     │       │ Isolate Whisper  │
│                  │       │ Voice Draft      │       │ + Silero-VAD     │
└────────┬─────────┘       └────────┬─────────┘       └────────┬─────────┘
         │                          │                          │
         └──────────────────────────┼──────────────────────────┘
                                    ▼
          ┌─────────────────────────────────────────────────────┐
          │ Phase V4: Voice-Enabled QuickLog + Review UI + Gate │
          │ (Sequential integration — after V1, V2, V3 finish)  │
          └──────────────────────────┬──────────────────────────┘
                                     │ (Optional later)
                                     ▼
          ┌─────────────────────────────────────────────────────┐
          │ Phase V5: Optional Text-Only Online AI Refine       │
          │ (Opt-in Gemini Flash-Lite over text transcript)     │
          └─────────────────────────────────────────────────────┘
```

### Strict File Ownership Matrix (Zero Merge Conflicts for Concurrent Agents)

| Phase | Creates (exclusive) | Modifies (exclusive) | Must NOT touch |
|---|---|---|---|
| **V0** | `app/lib/domain/voice/voice_contracts.dart` | `app/pubspec.yaml`, `app/android/app/src/main/AndroidManifest.xml`, `app/android/app/build.gradle.kts`, `app/ios/Runner/Info.plist`, `app/lib/app/widgets/app_icon.dart` | `features/*`, `data/*`, `domain/quicklog/*` |
| **V1** | `app/lib/data/voice/voice_model_store.dart`, `app/lib/features/settings/voice_model_section.dart`, `app/test/data/voice_model_store_test.dart` | *(none)* | `pubspec.yaml`, `settings_screen.dart` (wired in V4), `domain/voice/voice_contracts.dart` |
| **V2** | `app/lib/domain/voice/speech_normalizer.dart`, `app/lib/domain/voice/voice_draft.dart`, `app/test/domain/voice_draft_test.dart` | *(none)* | `domain/voice/voice_contracts.dart`, `quicklog_sheet.dart`, `data/voice/*` |
| **V3** | `app/lib/data/voice/pcm_mic.dart`, `app/lib/data/voice/whisper_isolate.dart`, `app/lib/data/voice/sherpa_stt_engine.dart`, `app/test/data/sherpa_stt_engine_test.dart` | *(none)* | `domain/voice/*`, `voice_model_store.dart`, `features/*` |
| **V4** | `app/lib/features/quicklog/voice_session_cubit.dart`, `app/test/features/voice_quicklog_test.dart` | `app/lib/app/deps.dart`, `app/lib/features/settings/settings_screen.dart`, `app/lib/features/quicklog/quicklog_sheet.dart`, `app/lib/features/today/today_screen.dart`, `PROGRESS.md`, `DECISIONS.md` | `handoff/backend/Code.gs`, `domain/voice/voice_contracts.dart` (unless additive) |
| **V5** | `app/lib/data/voice/gemini_text_refiner.dart`, `app/test/data/gemini_text_refiner_test.dart` | `app/lib/features/quicklog/voice_session_cubit.dart`, `app/lib/features/quicklog/quicklog_sheet.dart`, `app/lib/features/settings/settings_screen.dart` | `Code.gs`, offline default path |

---

## Global Rules for Every Phase Agent

Before writing a single line, read `AGENTS.md` (and `PROGRESS.md` for toolchain paths). Key reminders:
1. **Toolchain:** Flutter binary is `/Users/nsesumit/fvm/default/bin/flutter`, Dart is `/Users/nsesumit/fvm/default/bin/dart` (always run from `app/`).
2. **Quality bar before finishing your phase:**
   ```bash
   cd app && /Users/nsesumit/fvm/default/bin/dart format . && /Users/nsesumit/fvm/default/bin/flutter analyze && /Users/nsesumit/fvm/default/bin/flutter test
   ```
   Zero analyzer issues, zero formatting diffs, 100% green tests.
3. **Never touch `handoff/backend/Code.gs` or run git commit/push/branch/reset.**
4. **Never log or print secrets.**
5. **Preserve all contracts in `voice_contracts.dart`** once V0 completes; V1/V2/V3 implement against those interfaces verbatim.

---

## Phase V0: Packages, Permissions & Shared Contracts (Sequential Gate)

**Goal:** Add required native dependencies, configure Android/iOS microphone permissions, add `AppIcons.mic`, and lock the shared Dart interfaces so V1, V2, and V3 can run in parallel.

### Steps
1. **Packages (run inside `app/`):**
   ```bash
   /Users/nsesumit/fvm/default/bin/flutter pub add sherpa_onnx record
   ```
   *(Verify both resolve cleanly with Dart `^3.13.7`; `http` and `path_provider` are already in `app/pubspec.yaml`.)*
2. **Android permissions & minSdk:**
   - Edit `app/android/app/src/main/AndroidManifest.xml`: add `<uses-permission android:name="android.permission.RECORD_AUDIO"/>` right below `INTERNET`.
   - Edit `app/android/app/build.gradle.kts`: verify `minSdk` compatibility with `sherpa_onnx` / `record` (if `flutter.minSdkVersion < 23`, set `minSdk = maxOf(flutter.minSdkVersion, 23)` or `24` per `sherpa_onnx` build requirements).
3. **iOS permission:**
   - Edit `app/ios/Runner/Info.plist`: add `NSMicrophoneUsageDescription` explaining offline voice logging.
4. **Mic stroke icon:**
   - Edit `app/lib/app/widgets/app_icon.dart`: add `mic` to `AppIcons` with a 24×24 stroke-1.8 path matching the existing icon set (no emoji).
5. **Create `app/lib/domain/voice/voice_contracts.dart`:**
   Define these exact immutable types and abstract interfaces:
   - `VoiceModelFiles` (`encoderPath`, `decoderPath`, `tokensPath`, `vadPath`)
   - `VoiceModelState` (`enum VoiceModelStatus { missing, downloading, ready, error }`, `double progress`, `int downloadedBytes`, `int totalBytes`, `String? error`, `VoiceModelFiles? files`)
   - `abstract interface class VoiceModelRepository`:
     - `Stream<VoiceModelState> watchState()`
     - `Future<VoiceModelState> currentState()`
     - `Future<void> download({bool force = false})`
     - `Future<void> delete()`
   - `SttSegment` (`String text`, `int durationMs`, `int decodeMs`, `bool isFinal`)
   - `enum SttStatus { idle, starting, listening, stopping, error }`
   - `abstract interface class SttEngine`:
     - `Stream<SttSegment> get segments`
     - `Stream<double> get rmsLevel` (`0.0`..`1.0` for waveform)
     - `Stream<SttStatus> get status`
     - `Future<void> start(VoiceModelFiles files)`
     - `Future<void> stop()`
     - `Future<void> dispose()`
   - `VoiceDraftItem` (`ParsedEntry entry`, `String? dateOverride`, `String? note`, `bool included`)
   - `VoiceDraftResult` (`String normalizedText`, `List<VoiceDraftItem> items`, `List<String> ignoredPlans`, `List<String> warnings`, `bool hasUnparsedFallback`)
   - `abstract interface class VoiceDraftParser`:
     - `VoiceDraftResult parse({required String transcript, required DateTime nowIst, required double cigPrice, required double teaPrice, List<Event> recentEvents = const []})`

### Gate Check (V0)
- Run `dart format . && flutter analyze && flutter test` in `app/` — all existing 81 tests pass, zero analyzer issues.
- Update `DECISIONS.md` with chosen `sherpa_onnx` + `record` versions and `minSdk` adjustment if any.

---

## Phase V1: Whisper `base` Model Manager & Settings UI (Parallelizable after V0)

**Goal:** Download, verify, cache, and manage `Whisper base (int8)` + `Silero-VAD` files on disk via `http` + `path_provider` (never bundled in APK), plus build the standalone `VoiceModelSection` widget for Settings.

### Model Artifacts (Hugging Face `csukuangfj/sherpa-onnx-whisper-base` + Silero VAD)
Download via `http` streaming into `<appDocsDir>/voice_models/whisper_base/`:
1. `base-encoder.int8.onnx` (~39 MB) — `https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/main/base-encoder.int8.onnx`
2. `base-decoder.int8.onnx` (~118 MB) — `https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/main/base-decoder.int8.onnx`
3. `base-tokens.txt` (~800 KB) — `https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/main/base-tokens.txt`
4. `silero_vad.onnx` (~2 MB) — `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx`

*(Write each file to `*.part` first, validate non-empty size / atomic rename on completion so interrupted downloads never leave corrupt `.onnx` files.)*

### Files to Create
1. `app/lib/data/voice/voice_model_store.dart`:
   - Implements `VoiceModelRepository` from `voice_contracts.dart`.
   - Constructor takes `{required Future<Directory> Function() dirProvider, http.Client? client, List<VoiceArtifactSpec>? artifacts}` for 100% deterministic unit testing in temp dirs with fake `http.Client`.
   - Emits smooth download progress (`downloadedBytes / totalBytes`) on `watchState()`.
   - `delete()` removes the directory and emits `VoiceModelStatus.missing`.
2. `app/lib/features/settings/voice_model_section.dart`:
   - Standalone `StatelessWidget` / `StatefulWidget` taking `VoiceModelRepository` (matching `AppCard`, `PrimaryButton`, `OutlineButton`, `AppColors`, `AppText` from `app/theme/app_theme.dart` and `app/widgets/common.dart`).
   - Shows model name (`Whisper base (int8) + Silero VAD`), status (`Not downloaded (~160 MB)` / `Downloading 42%` / `Ready offline`), Download / Cancel / Delete buttons with $\ge 44\text{ px}$ touch targets.
3. `app/test/data/voice_model_store_test.dart`:
   - Fake `http.Client` serving byte streams -> verifies `.part` atomic rename, progress stream updates, ready `VoiceModelFiles` paths, failed HTTP recovery (no corrupt final file), and `delete()`.

### Gate Check (V1)
- `dart format . && flutter analyze && flutter test` green.
- **Do NOT edit `settings_screen.dart`** (V4 mounts `VoiceModelSection`).

---

## Phase V2: Offline Speech Normalizer & Voice Draft Builder (Parallelizable after V0)

**Goal:** Turn raw messy English / Hinglish speech transcripts into clean, structured `VoiceDraftResult` entries **100% offline** before user confirmation, strictly respecting the sheet's rules and the Voice Logging Agent rules.

### Rules to Implement (Pure Dart, Zero External Dependencies)
1. **Plan / Hypothetical Filter (`ignoredPlans`):**
   - Sentences/clauses starting with or clearly marked as uncompleted intent (`"thinking of"`, `"planning to"`, `"might order"`, `"will have"`, `"going to"`, `"should i"`, `"haven't yet"`) are NOT converted into log entries—put them in `ignoredPlans` so the review UI can show `"Skipped plan: ..."` transparently.
2. **Self-Corrections:**
   - Patterns like `"two cigarettes, actually three"`, `"2 cig—no wait, 3"`, `"tea 20, sorry 15"`, `"make it 4"`: override the immediately preceding quantity or amount!
3. **Number Words & Currency Cleanup:**
   - Convert spoken numbers (`one`..`nineteen`, `twenty`..`ninety`, `hundred`, `half`) and `"rupees"` / `"rs"` / `"bucks"` / `"ka"` (`"50 rupees"`, `"fifty bucks"`, `"samosa pav 30 ka"` → `30`).
4. **Timing Phrases (No Invented Clocks):**
   - `"today"` (with no time) → `dateOverride = todayIst`, **do not inject a fake clock time** (unless `"just now"` → `nowIst` time).
   - `"yesterday"` (with no time) → `dateOverride = addDays(todayIst, -1)`.
   - `"around"` / `"about"` / `"roughly"` / `"~"` → `approx = true`.
   - `"just now"` → `approx = false`, current time.
5. **Activity vs. Spend Separation:**
   - `"I had tea and spent 50"` → `tea × 1` (no amount!) + separate `spend ₹50 (other)`!
   - `"I spent 50 on tea"` / `"tea 20 rupees"` → `tea × 1` (`amount: 20, category: tea`, which `toEvents()` emits as `tea` + paired `spend`).
   - `"I had 2 cigarettes"` (NO price stated!) → `cigarette × 2` with **`amount: null`** (matches `"From existing pack; no new spend"` in `Events`, unlike typed QuickLog default!).
   - `"I had a tea"` (NO price stated) → `tea × 1` with **`amount: null`** (or optional warning chip `"Price unstated"` in review UI so user can tap to add ₹ if paid!).
6. **Duplicate Hints against `recentEvents`:**
   - If `recentEvents` (today's effective events) already has a matching event within the day (e.g. same `type` + `label` or same `amountInr` within 15 min), add a short non-blocking string to `warnings` (`"You already logged Tea today"`).
7. **Source Tagging:**
   - Every `ParsedEntry` produced by `VoiceDraftParser` must have `source: 'voice'` (or `'lazypay'` if LazyPay mentioned).

### Files to Create
1. `app/lib/domain/voice/speech_normalizer.dart` (number-word normalization, filler stripping, clause splitting, self-correction resolution, plan detection, date/time/approx extraction).
2. `app/lib/domain/voice/voice_draft.dart` (implements `VoiceDraftParser` from `voice_contracts.dart`, wraps `parseQuickLog()` + custom voice rules, returns `VoiceDraftResult` + helper `toEvents(...)` honoring `"One event for each activity. One spend event for each payment."`).
3. `app/test/domain/voice_draft_test.dart` (≥ 35 unit tests covering: `"Today I had two cigarettes, one tea, and spent 50"`, `"I spent 50 on tea"`, `"Two cigarettes—actually, three"`, `"I'm thinking of ordering dinner"`, `"Yesterday 10000 steps"`, `"Slept around 12:30 am"`, `"Reached office at 10 40"`, `"Samosa pav 30 rupees and Lahori Jeera 10"`, `"Weight 87 point 5"`, duplicate warning, unparsed fallback to `note`).

### Gate Check (V2)
- `dart format . && flutter analyze && flutter test` green.

---

## Phase V3: Mic PCM Stream + Background Isolate `sherpa_onnx` (`Whisper base` + `Silero-VAD`) (Parallelizable after V0)

**Goal:** Implement `SttEngine` from `voice_contracts.dart` using `record` (16 kHz, 16-bit mono PCM stream) + `sherpa_onnx` `VoiceActivityDetector` (`Silero-VAD`) + `OfflineRecognizer` (`Whisper base int8`, `language: 'en'`, `numThreads: 2..4`) running inside a dedicated background Dart `Isolate`.

### Concurrency & Lifecycle Architecture
1. **`pcm_mic.dart` (`PcmMicSource` abstraction):**
   - Wraps `AudioRecorder` (`record` package) behind a tiny testable interface (`hasPermission()`, `startStream()`, `stop()`) yielding `Uint8List` PCM16 mono 16 kHz chunks.
2. **`whisper_isolate.dart` (Worker Isolate entrypoint):**
   - Spawns a long-lived `Isolate` on `start(VoiceModelFiles)` and keeps `VoiceActivityDetector` + `OfflineRecognizer` loaded while listening.
   - Configures:
     - `SileroVadModelConfig(model: files.vadPath, threshold: 0.5, minSpeechDuration: 0.25, minSilenceDuration: 0.6, windowSize: 512)`
     - `OfflineWhisperModelConfig(encoder: files.encoderPath, decoder: files.decoderPath, language: 'en', task: 'transcribe')`
     - `OfflineModelConfig(tokens: files.tokensPath, numThreads: 2, provider: 'cpu')`
   - Receives `Float32List` normalized PCM chunks (`sample / 32768.0`), feeds `vad.acceptWaveform()`, and whenever `!vad.isEmpty()`, pops `vad.front()`, runs `recognizer.decode(stream)` in the background Isolate, measures `decodeMs`, and sends `SttSegment(text: result.text.trim(), ...)` back to main Isolate!
   - On `stop`: calls `vad.flush()` so the final unfinished speech segment is NOT lost!
   - On `dispose`: `.free()`s `stream`, `recognizer`, and `vad` before killing the Isolate (zero native memory leaks).
3. **`sherpa_stt_engine.dart` (`SherpaSttEngine implements SttEngine`):**
   - Computes normalized RMS amplitude (`0.0..1.0`) from incoming PCM16 frames and emits on `rmsLevel` for live waveform animation.
   - Bridges `PcmMicSource` ↔ `whisper_isolate.dart`.
   - Handles missing mic permission with a clean error state on `status`.

### Files to Create
1. `app/lib/data/voice/pcm_mic.dart`
2. `app/lib/data/voice/whisper_isolate.dart`
3. `app/lib/data/voice/sherpa_stt_engine.dart`
4. `app/test/data/sherpa_stt_engine_test.dart` (tests PCM16 → Float32 normalization, RMS computation, permission-denied handling, and segment queuing/flush ordering using a fake `PcmMicSource` and injectable decoder hook so CI/unit tests run without native `.onnx` files on desktop).

### Gate Check (V3)
- `dart format . && flutter analyze && flutter test` green.

---

## Phase V4: Voice-Enabled QuickLog + Review-Before-Saving UI + Integration Gate (Sequential after V1, V2, V3)

**Goal:** Connect V1 + V2 + V3 into the app (`AppDeps`, `SettingsScreen`, `QuickLogSheet`, `TodayScreen`) with a live concurrent Draft Card where the user **always reviews/edits before saving**.

### Behavior & UI Requirements
1. **`VoiceSessionCubit` (`app/lib/features/quicklog/voice_session_cubit.dart`):**
   - Coordinates `VoiceModelRepository`, `SttEngine`, `VoiceDraftParser`, `Clock`, `AppSettings`, and recent `Events`.
   - When mic starts:
     - Checks `VoiceModelRepository.currentState()`: if not `ready`, emits a clear inline banner `"Download Whisper base (~160 MB) in Settings for offline voice"` + 1-tap button to jump to `/settings` (while still allowing typing!).
     - Starts `SttEngine` -> listens to `segments` & `rmsLevel` -> appends non-empty segments to transcript -> **concurrently re-runs `VoiceDraftParser.parse()`** on the full transcript -> emits updated `VoiceDraftResult` live!
   - Supports **Edit-in-place before saving**:
     - `toggleItem(index)` (include/exclude a drafted entry)
     - `removeItem(index)`
     - `updateItemAmount(index, double? amount)` / `updateItemTime(index, String? time)`
     - `onTranscriptEdited(String text)` (manual keyboard edits re-run draft parsing live!)
   - `commit()`: converts included `VoiceDraftItem`s into `Event`s (`source: 'voice'`, `"One event for each activity. One spend event for each payment."`) and returns `QuickLogOutcome` to `QuickLogSheet` -> `EventsRepository.log(...)` -> Drift + Outbox + 6s Undo bar!
2. **`QuickLogSheet` updates (`app/lib/features/quicklog/quicklog_sheet.dart`):**
   - Add a **Mic toggle button** (`AppIcons.mic`, $\ge 44\times44$, lime pulse / waveform bar while listening) inside the input field / header.
   - Show live transcript text + **Review Draft Card** (with included checkboxes/remove `×`, inline ₹ edit, `~approx` / `yesterday` / `unlinked spend` badges, skipped-plans chip if any, and duplicate warning banner if any).
   - Keep `Review before saving`: CTA button explicitly says `"Confirm & log N entries"` when voice items are drafted.
3. **`SettingsScreen` & `AppDeps` (`app/lib/app/deps.dart`, `app/lib/features/settings/settings_screen.dart`):**
   - Wire `VoiceModelStore` + `SherpaSttEngine` + `VoiceDraftBuilder` into `AppDeps` (with fake/overridable factory params for `AppHarness` tests!).
   - Mount `VoiceModelSection` inside `SettingsScreen`.
4. **`TodayScreen` shortcut (optional polish):**
   - Long-press FAB or a subtle mic action opens `QuickLogSheet(autoStartVoice: true)` when model is ready.
5. **Tests (`app/test/features/voice_quicklog_test.dart`):**
   - Fake `VoiceModelRepository` + fake `SttEngine` emitting incremental segments (`"Today I had two cigarettes"`, `"actually three and one tea"`, `"and spent 50"`):
     - Verifies live transcript updates concurrently and **nothing is written to Drift/Outbox during listening**.
     - Verifies Draft Card shows `Cigarette × 3`, `Tea × 1`, `Spend · ₹50` (`other`), and unchecking 1 item excludes it.
     - Verifies tapping `"Confirm & log"` writes exact `source: 'voice'` rows to Drift + Outbox (including airplane-mode -> reconnect gate!).
     - Verifies missing-model state shows prompt to download in Settings without crashing.

### Gate Check (V4)
- `dart format . && flutter analyze && flutter test` green.
- Update `PROGRESS.md` and `DECISIONS.md`.
- Manual phone check (owner): download `Whisper base` on Wi-Fi in Settings -> enable Airplane Mode -> dictate 3 real Hindi/English mixed phrases -> verify latency, accuracy, review card, and sync on reconnect.

---

## Phase V5: Optional Online Text-Only AI Refine (Opt-in, After V4)

**Goal:** Keep offline as the default, while offering an optional **"Refine with AI"** button inside `QuickLogSheet` when online + Gemini API key is saved in `flutter_secure_storage`. Sends **only the short text transcript** (never audio) + recent local events to Gemini Flash-Lite to handle ultra-messy speech, multi-clause corrections, or `void`-ing an already-synced event.

*(Specify & implement only after V4 is verified on device.)*

---

## Copy-Paste Prompts for Independent / Concurrent Agents

### Prompt for Phase V0 Agent
> Read `AGENTS.md`, `PROGRESS.md`, and `VOICE_LOGGING_PLAN.md`. Complete **Phase V0** strictly as specified in `VOICE_LOGGING_PLAN.md` (add `sherpa_onnx` and `record`, update Android/iOS mic permissions, add `AppIcons.mic`, create `app/lib/domain/voice/voice_contracts.dart`). Verify with `dart format . && flutter analyze && flutter test` in `app/`, update `DECISIONS.md`, and report results.

### Prompt for Phase V1 Agent *(run concurrently with V2 and V3 after V0)*
> Read `AGENTS.md`, `VOICE_LOGGING_PLAN.md`, and `app/lib/domain/voice/voice_contracts.dart`. Complete **Phase V1** strictly within V1's file ownership (`voice_model_store.dart`, `voice_model_section.dart`, `voice_model_store_test.dart`). Do not edit files owned by V2/V3/V4. Verify with `dart format . && flutter analyze && flutter test`.

### Prompt for Phase V2 Agent *(run concurrently with V1 and V3 after V0)*
> Read `AGENTS.md`, `VOICE_LOGGING_PLAN.md`, `app/lib/domain/voice/voice_contracts.dart`, and `app/lib/domain/quicklog/parser.dart`. Complete **Phase V2** strictly within V2's file ownership (`speech_normalizer.dart`, `voice_draft.dart`, `voice_draft_test.dart`). Do not edit files owned by V1/V3/V4. Verify with `dart format . && flutter analyze && flutter test`.

### Prompt for Phase V3 Agent *(run concurrently with V1 and V2 after V0)*
> Read `AGENTS.md`, `VOICE_LOGGING_PLAN.md`, and `app/lib/domain/voice/voice_contracts.dart`. Complete **Phase V3** strictly within V3's file ownership (`pcm_mic.dart`, `whisper_isolate.dart`, `sherpa_stt_engine.dart`, `sherpa_stt_engine_test.dart`). Do not edit files owned by V1/V2/V4. Verify with `dart format . && flutter analyze && flutter test`.

### Prompt for Phase V4 Agent *(run after V1, V2, V3 are green)*
> Read `AGENTS.md`, `PROGRESS.md`, `VOICE_LOGGING_PLAN.md`, and the outputs of Phases V1–V3 (`data/voice/`, `domain/voice/`, `features/settings/voice_model_section.dart`). Complete **Phase V4** (wire `AppDeps`, `SettingsScreen`, `VoiceSessionCubit`, `QuickLogSheet` review UI, and `voice_quicklog_test.dart`). Verify with `dart format . && flutter analyze && flutter test` and update `PROGRESS.md`.
