import 'package:flutter/material.dart';

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
    final isEdit = widget.initialName != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Remote Node' : 'Add Remote Node'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g., Main Server',
                ),
                autofocus: true,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'e.g., https://relay.example.com',
                ),
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'URL is required';
                  }
                  final uri = Uri.tryParse(value.trim());
                  if (uri == null || !uri.hasScheme) {
                    return 'Please enter a valid URL';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username (optional)',
                  hintText: 'Enter username for authentication',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: isEdit ? 'Password (leave blank to keep)' : 'Password (optional)',
                  hintText: 'Enter password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
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
          child: const Text('Cancel'),
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
          child: const Text('Save'),
        ),
      ],
    );
  }
}
