import 'dart:async';

/// Emits a map of the latest value from every source, once all of them have
/// produced at least one value and on every change after that.
Stream<Map<K, T>> combineLatestMap<K, T>(Map<K, Stream<T>> sources) {
  if (sources.isEmpty) return Stream<Map<K, T>>.value(<K, T>{});
  late StreamController<Map<K, T>> controller;
  final subscriptions = <StreamSubscription<T>>[];
  final latest = <K, T>{};
  controller = StreamController<Map<K, T>>(
    onListen: () {
      sources.forEach((key, source) {
        subscriptions.add(source.listen((value) {
          latest[key] = value;
          if (latest.length == sources.length) controller.add(Map<K, T>.of(latest));
        }, onError: controller.addError));
      });
    },
    onPause: () {
      for (final s in subscriptions) {
        s.pause();
      }
    },
    onResume: () {
      for (final s in subscriptions) {
        s.resume();
      }
    },
    onCancel: () => Future.wait(subscriptions.map((s) => s.cancel())),
  );
  return controller.stream;
}
