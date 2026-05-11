import 'package:flutter/material.dart';

import '../l10n/subpage_l10n.dart';

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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _urlController = TextEditingController(text: widget.initialUrl);
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
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: text.t('serverUrl'),
                  hintText: text.t('serverUrlHint'),
                ),
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return text.t('urlRequired');
                  }
                  final uri = Uri.tryParse(value.trim());
                  if (uri == null || !uri.hasScheme) {
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
                'url': _urlController.text.trim(),
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
