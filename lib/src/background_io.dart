import 'dart:isolate';

Future<R> runInBackground<R>(R Function() work) => Isolate.run(work);
