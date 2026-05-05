import 'package:flutter/material.dart';

class TwProviderCredentialScreen extends StatelessWidget {
  const TwProviderCredentialScreen({super.key, required this.holderDid});

  final String holderDid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TW 身份驗證')),
      body: const Center(child: Text('TW 身份驗證')),
    );
  }
}
