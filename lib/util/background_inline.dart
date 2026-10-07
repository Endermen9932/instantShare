/// No isolates on the web: run inline after yielding to the event loop so a
/// progress indicator can paint first.
Future<T> runInBackground<T>(T Function() task) async {
  await Future<void>.delayed(const Duration(milliseconds: 50));
  return task();
}
