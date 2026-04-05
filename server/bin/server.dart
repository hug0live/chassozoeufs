import 'dart:io';

import 'package:egg_hunt_server/src/app.dart';
import 'package:egg_hunt_server/src/game_store.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final port = int.tryParse(Platform.environment['APP_PORT'] ?? '8080') ?? 8080;
  final dataDir = Platform.environment['DATA_DIR'] ?? './data';
  final allowedOrigin = Platform.environment['ALLOWED_ORIGIN'] ?? '*';
  final publicDir = Platform.environment['PUBLIC_DIR'] ?? './public';

  final store = GameStore(dataDirectory: dataDir);
  await store.initialize();

  final app = EggHuntServerApp(
    store: store,
    allowedOrigin: allowedOrigin,
    publicDirectory: publicDir,
  );

  final server = await shelf_io.serve(
    app.handler,
    InternetAddress.anyIPv4,
    port,
  );

  server.autoCompress = true;

  stdout.writeln(
    'Chasse aux oeufs server listening on http://${server.address.address}:${server.port}',
  );
}
