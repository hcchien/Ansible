import 'package:flutter/material.dart';

import '../l10n/subpage_l10n.dart';
import '../l10n/app_l10n.dart';

const productionRelayUrl = 'https://relay.elix.cool';

class RemoteNodeFormDialog extends StatefulWidget {
  final String? initialName;
  final String? initialUrl;
  final String? initialUsername;

  const RemoteNodeFormDialog({
    super.key,
    this.initialName,
    this.initialUrl,
    this.initialUsername,
  });

  @override
  State<RemoteNodeFormDialog> createState() => _RemoteNodeFormDialogState();
}

class _RemoteNodeFormDialogState extends State<RemoteNodeFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  String get _effectiveUrl => _urlController.text.trim().isEmpty
      ? productionRelayUrl
      : _urlController.text.trim().replaceFirst(RegExp(r'/+$'), '');
  String get _preset =>
      _effectiveUrl == productionRelayUrl ? 'production' : 'custom';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialName ?? 'Elix Relay',
    );
    _urlController = TextEditingController(
      text: widget.initialUrl?.trim().isNotEmpty == true
          ? widget.initialUrl
          : productionRelayUrl,
    );
    _usernameController = TextEditingController(text: widget.initialUsername);
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    final isEdit = widget.initialName != null;

    return AlertDialog(
      title: Text(isEdit ? text.t('editRemoteNode') : text.t('addRemoteNode')),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey('relay_preset_$_preset'),
                  initialValue: _preset,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.uiCopy(
                      zh: '選擇 Relay',
                      en: 'Choose a Relay',
                    ),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'production',
                      child: Text(
                        context.uiCopy(
                          zh: 'Elix 正式伺服器（預設）',
                          en: 'Elix production (default)',
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'custom',
                      child: Text(
                        context.uiCopy(zh: '自訂伺服器', en: 'Custom server'),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _urlController.text = value == 'production'
                        ? productionRelayUrl
                        : 'https://';
                    _usernameController.clear();
                    _passwordController.clear();
                  }),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: text.t('remoteNodeName'),
                    hintText: text.t('remoteNodeNameHint'),
                  ),
                  autofocus: true,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return text.t('nameRequired');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('relay_url_field'),
                  controller: _urlController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: text.t('serverUrl'),
                    hintText: productionRelayUrl,
                    helperText: context.uiCopy(
                      zh: '留空時使用 $productionRelayUrl；儲存後才套用。',
                      en: 'Blank uses $productionRelayUrl; applied only when saved.',
                    ),
                    helperMaxLines: 3,
                  ),
                  keyboardType: TextInputType.url,
                  validator: (value) {
                    final uri = Uri.tryParse(_effectiveUrl);
                    if (uri == null ||
                        uri.host.isEmpty ||
                        uri.userInfo.isNotEmpty ||
                        uri.hasQuery ||
                        uri.hasFragment ||
                        !(uri.scheme == 'https' ||
                            (uri.scheme == 'http' &&
                                [
                                  'localhost',
                                  '127.0.0.1',
                                  '::1',
                                ].contains(uri.host)))) {
                      return text.t('urlInvalid');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: text.t('usernameOptional'),
                    hintText: text.t('usernameHint'),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: isEdit
                        ? text.t('passwordKeep')
                        : text.t('passwordOptional'),
                    hintText: text.t('passwordHint'),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscurePassword,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'name': _nameController.text.trim(),
                'url': _effectiveUrl,
                'username': _usernameController.text.trim().isEmpty
                    ? null
                    : _usernameController.text.trim(),
                'password': _passwordController.text.isEmpty
                    ? null
                    : _passwordController.text,
              });
            }
          },
          child: Text(text.t('save')),
        ),
      ],
    );
  }
}
