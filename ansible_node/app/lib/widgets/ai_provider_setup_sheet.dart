import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../theme/ansible_design.dart';

class AiProviderSetupResult {
  final String displayName;
  final AiProviderType providerType;
  final String? baseUrl;
  final String? modelName;
  final String? apiKey;

  const AiProviderSetupResult({
    required this.displayName,
    required this.providerType,
    this.baseUrl,
    this.modelName,
    this.apiKey,
  });
}

typedef AiProviderConnectionTester =
    Future<bool> Function(AiProviderSetupResult result);

class AiProviderSetupSheet extends StatefulWidget {
  const AiProviderSetupSheet({super.key, this.onTestConnection});

  final AiProviderConnectionTester? onTestConnection;

  @override
  State<AiProviderSetupSheet> createState() => _AiProviderSetupSheetState();
}

class _AiProviderSetupSheetState extends State<AiProviderSetupSheet> {
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController(text: 'manual');
  final _apiKeyController = TextEditingController();
  AiProviderType _providerType = AiProviderType.manual;
  bool _testing = false;
  bool _testPassed = false;

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  AiProviderSetupResult _result() {
    final label = switch (_providerType) {
      AiProviderType.manual => 'Manual',
      AiProviderType.openaiCompatible => 'OpenAI-compatible',
      AiProviderType.localHttp => 'Local HTTP',
      AiProviderType.system => 'System',
    };
    return AiProviderSetupResult(
      displayName: label,
      providerType: _providerType,
      baseUrl: _emptyToNull(_baseUrlController.text),
      modelName: _emptyToNull(_modelController.text),
      apiKey: _emptyToNull(_apiKeyController.text),
    );
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testPassed = false;
    });
    final ok =
        await (widget.onTestConnection?.call(_result()) ??
            Future<bool>.value(true));
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testPassed = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.uiCopy(zh: 'AI 提供者設定', en: 'AI Provider Settings'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<AiProviderType>(
              initialValue: _providerType,
              decoration: InputDecoration(
                labelText: context.uiCopy(zh: '提供者', en: 'Provider'),
              ),
              items: [
                DropdownMenuItem(
                  value: AiProviderType.manual,
                  child: Text(context.uiCopy(zh: '手動', en: 'Manual')),
                ),
                const DropdownMenuItem(
                  value: AiProviderType.openaiCompatible,
                  child: Text('OpenAI-compatible'),
                ),
                DropdownMenuItem(
                  value: AiProviderType.localHttp,
                  child: Text(context.uiCopy(zh: '本機 HTTP', en: 'Local HTTP')),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _providerType = value;
                  _testPassed = false;
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('ai_base_url_field'),
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://api.example/v1',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('ai_model_field'),
              controller: _modelController,
              decoration: const InputDecoration(labelText: 'Model'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('ai_api_key_field'),
              controller: _apiKeyController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'API key'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check),
                  label: Text(
                    context.uiCopy(zh: '測試連線', en: 'Test Connection'),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(_result()),
                  icon: const Icon(Icons.check),
                  label: Text(
                    context.uiCopy(zh: '儲存並繼續', en: 'Save and Continue'),
                  ),
                ),
              ],
            ),
            if (_testPassed) ...[
              const SizedBox(height: 12),
              Text(
                context.uiCopy(zh: '連線測試通過', en: 'Connection test passed'),
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AnsibleDesign.darkMoss
                      : AnsibleDesign.moss,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
