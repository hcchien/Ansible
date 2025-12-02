import 'dart:io';

import 'package:ansible_relay/ansible_relay.dart';

Future<void> main(List<String> args) async {
  final portEnv = Platform.environment['PORT'];
  final port = int.tryParse(portEnv ?? '') ?? 8080;

  final handler = createAnsibleRelayHandler();

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('Ansible Relay listening on port $port');

  await for (final request in server) {
    handler(request);
  }
}
