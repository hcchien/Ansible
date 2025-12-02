import 'package:flutter/material.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_domain/ansible_domain.dart';
import 'screens/boards_list_screen.dart';
import 'screens/login_screen.dart';
import 'services/flutter_secure_token_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the database
  final db = AppDatabase();

  // Initialize Auth
  final tokenStorage = FlutterSecureTokenStorage();
  final apiClient = RelayApiClient(baseUrl: 'http://localhost:8080'); // Default local relay
  final authService = AuthService(
    apiClient: apiClient,
    tokenStorage: tokenStorage,
  );

  await authService.initialize();
  
  runApp(MyApp(db: db, authService: authService));
}

class MyApp extends StatefulWidget {
  final AppDatabase db;
  final AuthService authService;
  
  const MyApp({
    super.key, 
    required this.db,
    required this.authService,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late bool _isLoggedIn;

  @override
  void initState() {
    super.initState();
    _isLoggedIn = widget.authService.isLoggedIn;
  }

  void _handleLoginSuccess() {
    setState(() {
      _isLoggedIn = true;
    });
  }

  void _handleLogout() {
    widget.authService.logout();
    setState(() {
      _isLoggedIn = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ansible Node',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: _isLoggedIn 
        ? BoardsListScreen(
            db: widget.db,
            // We might want to pass authService to screens if they need to make API calls
            // For now, let's just pass logout callback or something if needed
            // Actually, BoardsListScreen currently only uses local DB.
            // But for Sync (P2), we will need background sync service.
          )
        : LoginScreen(
            authService: widget.authService,
            onLoginSuccess: _handleLoginSuccess,
          ),
    );
  }
}
