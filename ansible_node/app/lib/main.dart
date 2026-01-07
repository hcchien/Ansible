import 'package:flutter/material.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_domain/ansible_domain.dart';

import 'screens/login_screen.dart';
import 'screens/home_shell.dart';
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

  @override
  Widget build(BuildContext context) {
    const bgDeep = Color(0xFF050915);
    const bgLight = Color(0xFF0B1220);
    const accent = Color(0xFFFF9F43); // lively orange per latest UI
    const fontFamilyBase = 'PMingLiU'; // 新細明體
    const fontFallback = ['PMingLiU', 'MingLiU', 'PingFang TC'];
    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: accent,
      onPrimary: Colors.black,
      secondary: const Color(0xFFFFB76B),
      onSecondary: Colors.white,
      error: Colors.redAccent,
      onError: Colors.white,
      surface: const Color(0xFF0F182A),
      onSurface: Colors.white,
      surfaceContainerHighest: const Color(0xFF101728),
      onSurfaceVariant: const Color(0xFFA9B4C8),
      outline: const Color(0xFF1F2A3D),
      shadow: Colors.black,
      tertiary: accent.withOpacity(0.7),
      onTertiary: Colors.black,
    );

    return MaterialApp(
      title: 'Ansible Node',
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: bgDeep,
        cardColor: colorScheme.surface,
        fontFamily: fontFamilyBase,
        fontFamilyFallback: fontFallback,
        textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
              fontFamilyFallback: fontFallback,
            ),
        primaryTextTheme: ThemeData.dark().textTheme.apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
              fontFamilyFallback: fontFallback,
            ),
        appBarTheme: const AppBarTheme(
          backgroundColor: bgLight,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontFamily: fontFamilyBase),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF28334A)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            textStyle: const TextStyle(fontFamily: fontFamilyBase),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white70),
        useMaterial3: true,
      ),
      home: _isLoggedIn 
        ? HomeShell(
            db: widget.db,
            onLogout: () {
              widget.authService.logout();
              setState(() => _isLoggedIn = false);
            },
          )
        : LoginScreen(
            authService: widget.authService,
            onLoginSuccess: _handleLoginSuccess,
          ),
    );
  }
}
