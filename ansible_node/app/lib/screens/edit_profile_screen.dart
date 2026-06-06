import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

/// Edits the local user's **public** profile (display name + handle). Stored in
/// the contacts table keyed by the user's own DID, and published as a `profile`
/// op on the next sync so others can find them in discovery.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.db, required this.did});

  final AppDatabase db;
  final String did;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final ContactRepository _contacts = DriftContactRepository(widget.db);
  final _displayNameController = TextEditingController();
  final _handleController = TextEditingController();

  ContactRecord? _existing;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _handleController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final self = await _contacts.contactForDid(widget.did);
    if (!mounted) return;
    setState(() {
      _existing = self;
      _displayNameController.text = self?.displayName ?? '';
      _handleController.text = self?.handle ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final now = DateTime.now();
    final displayName = _displayNameController.text.trim();
    final handle = _handleController.text.trim();

    await _contacts.upsertContact(
      ContactRecord(
        subjectDid: widget.did,
        handle: handle.isEmpty ? null : handle,
        displayName: displayName.isEmpty ? null : displayName,
        avatarUrl: _existing?.avatarUrl,
        relationship: _existing?.relationship ?? ContactRelationship.manual,
        source: 'self',
        trustState: _existing?.trustState ?? ContactTrustState.known,
        createdAt: _existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.uiCopy(
            zh: '已儲存，下次同步將公開發布',
            en: 'Saved — will be published on next sync',
          ),
        ),
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: context.uiCopy(zh: '編輯個人檔案', en: 'EDIT PROFILE'),
      leadingLabel: context.uiCopy(zh: '← 返回', en: '← Back'),
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
              children: [
                Text(
                  context.uiCopy(
                    zh: '這些是公開資訊，會發布到網路讓他人搜尋與追蹤。',
                    en: 'This is public — it is published so others can find and follow you.',
                  ),
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: AnsibleDesign.inkMuted,
                  ),
                ),
                const SizedBox(height: 18),
                _label(context, context.uiCopy(zh: '顯示名稱', en: 'DISPLAY NAME')),
                _field(
                  controller: _displayNameController,
                  hint: context.uiCopy(zh: '你的名字', en: 'Your name'),
                ),
                const SizedBox(height: 16),
                _label(context, context.uiCopy(zh: 'HANDLE', en: 'HANDLE')),
                _field(
                  controller: _handleController,
                  hint: 'name.example',
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(
                    _saving
                        ? context.uiCopy(zh: '儲存中…', en: 'Saving…')
                        : context.uiCopy(zh: '儲存', en: 'Save'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: AnsibleMonoLabel(text, padding: EdgeInsets.zero),
      );

  Widget _field({
    required TextEditingController controller,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 14, color: AnsibleDesign.ink),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AnsibleDesign.paperDeep.withValues(alpha: 0.45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AnsibleDesign.ink),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AnsibleDesign.ink),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AnsibleDesign.ink),
        ),
      ),
    );
  }
}
