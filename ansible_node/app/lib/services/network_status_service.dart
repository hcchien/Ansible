import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum NetworkStatus {
  online,      // Connected and can reach internet
  offline,     // No network connection
  checking,    // Currently checking status
}

class NetworkStatusService extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  NetworkStatus _status = NetworkStatus.checking;
  List<ConnectivityResult> _connectivityResults = [];
  DateTime? _lastChecked;

  NetworkStatus get status => _status;
  List<ConnectivityResult> get connectivityResults => _connectivityResults;
  DateTime? get lastChecked => _lastChecked;

  bool get isOnline => _status == NetworkStatus.online;
  bool get isOffline => _status == NetworkStatus.offline;
  bool get isChecking => _status == NetworkStatus.checking;

  String get connectionType {
    if (_connectivityResults.isEmpty) return 'Unknown';
    final types = _connectivityResults.map((r) {
      switch (r) {
        case ConnectivityResult.wifi:
          return 'WiFi';
        case ConnectivityResult.mobile:
          return 'Mobile';
        case ConnectivityResult.ethernet:
          return 'Ethernet';
        case ConnectivityResult.vpn:
          return 'VPN';
        case ConnectivityResult.bluetooth:
          return 'Bluetooth';
        case ConnectivityResult.other:
          return 'Other';
        case ConnectivityResult.none:
          return 'None';
      }
    }).toSet();
    return types.join(', ');
  }

  NetworkStatusService() {
    _init();
  }

  void _init() {
    // Check initial status
    checkStatus();

    // Listen for connectivity changes
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _connectivityResults = results;
      _updateStatus(results);
    });
  }

  Future<void> checkStatus() async {
    _status = NetworkStatus.checking;
    notifyListeners();

    try {
      _connectivityResults = await _connectivity.checkConnectivity();
      await _updateStatus(_connectivityResults);
    } catch (e) {
      _status = NetworkStatus.offline;
      notifyListeners();
    }
  }

  Future<void> _updateStatus(List<ConnectivityResult> results) async {
    _lastChecked = DateTime.now();

    // Check if we have any connection
    final hasConnection = results.any((r) => r != ConnectivityResult.none);

    if (!hasConnection) {
      _status = NetworkStatus.offline;
      notifyListeners();
      return;
    }

    // We have a connection, verify internet access by pinging a reliable endpoint
    try {
      final response = await http.get(
        Uri.parse('https://www.google.com/generate_204'),
      ).timeout(const Duration(seconds: 5));

      _status = response.statusCode == 204 ? NetworkStatus.online : NetworkStatus.offline;
    } catch (e) {
      // If Google fails, try another endpoint
      try {
        final response = await http.get(
          Uri.parse('https://www.cloudflare.com/cdn-cgi/trace'),
        ).timeout(const Duration(seconds: 5));

        _status = response.statusCode == 200 ? NetworkStatus.online : NetworkStatus.offline;
      } catch (e) {
        // Consider online if we have connectivity but can't verify
        // (could be behind a captive portal or firewall)
        _status = NetworkStatus.online;
      }
    }

    notifyListeners();
  }

  /// Check if a specific URL is reachable
  Future<bool> isUrlReachable(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (e) {
      return false;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
