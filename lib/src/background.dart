/// Web has no isolates, so the work runs inline.
Future<R> runInBackground<R>(R Function() work) async => work();
