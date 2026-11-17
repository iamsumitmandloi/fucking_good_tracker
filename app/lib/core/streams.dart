import 'dart:async';

/// Emits the latest value of every stream once each has emitted at least once.
Stream<List<Object?>> combineLatest(List<Stream<Object?>> streams) {
  late StreamController<List<Object?>> controller;
  final subs = <StreamSubscription<Object?>>[];
  final values = List<Object?>.filled(streams.length, null);
  final seen = List<bool>.filled(streams.length, false);

  controller = StreamController<List<Object?>>(
    onListen: () {
      for (var i = 0; i < streams.length; i++) {
        subs.add(
          streams[i].listen((v) {
            values[i] = v;
            seen[i] = true;
            if (seen.every((s) => s)) controller.add(List.of(values));
          }, onError: controller.addError),
        );
      }
    },
    onCancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
    },
  );
  return controller.stream;
}
