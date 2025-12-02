// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_node/main.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  testWidgets('renders login screen when user is logged out', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    final authService = _TestAuthService(initialLoggedIn: false);

    await tester.pumpWidget(MyApp(db: db, authService: authService));

    expect(find.text('Login to Ansible Relay'), findsOneWidget);
  });
}

class _TestAuthService extends AuthService {
  _TestAuthService({bool initialLoggedIn = false})
    : _isLoggedIn = initialLoggedIn,
      super(
        apiClient: RelayApiClient(
          baseUrl: 'http://localhost',
          client: _NoopHttpClient(),
        ),
        tokenStorage: _MemoryTokenStorage(),
      );

  bool _isLoggedIn;

  @override
  bool get isLoggedIn => _isLoggedIn;

  @override
  Future<void> login(String username, String password) async {
    _isLoggedIn = true;
  }

  @override
  Future<void> logout() async {
    _isLoggedIn = false;
  }
}

class _NoopHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError('Network calls should not run in widget tests.');
  }
}

class _MemoryTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<void> deleteToken() async {
    _token = null;
  }

  @override
  Future<String?> getToken() async => _token;

  @override
  Future<void> saveToken(String token) async {
    _token = token;
  }
}
