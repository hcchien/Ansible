import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Platform stores are device services. Give each widget/unit test an isolated
/// local store; individual tests can still override errors or seed fixtures.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  await testMain();
}
