import 'package:flutter/widgets.dart';

import 'runtime/ibex_runtime_session.dart';
import 'ui/ibex_runtime_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final session = await IbexRuntimeSession.open();
    runApp(IbexRuntimeApp(controller: session.controller));
  } catch (error) {
    runApp(IbexRuntimeFailureApp(errorCode: error.runtimeType.toString()));
  }
}
