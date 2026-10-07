import 'dart:isolate';

/// Runs [task] on a short-lived isolate.
Future<T> runInBackground<T>(T Function() task) => Isolate.run(task);
