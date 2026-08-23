import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../theme/ansible_design.dart';
import '../services/canonical_identity_store.dart';
import '../widgets/ansible_screen_chrome.dart';
import 'sync_settings_screen.dart';

/// Edits the local user's **public** profile (display name + handle). Stored in
/// the contacts table keyed by the user's own DID, and published as a `profile`
/// op on the next sync so others can find them in discovery.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.db,
    required this.did,
    this.isOnboarding = false,
  });

  final AppDatabase db;
  final String did;
  final bool isOnboarding;

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
    var self = await _contacts.contactForDid(widget.did);
    final canonical = await const SecureCanonicalIdentityStore().load();
    final canonicalHandle = canonical?.did == widget.did
        ? canonical!.handle.trim()
        : '';
    if (self != null &&
        canonicalHandle.isNotEmpty &&
        self.handle?.trim() != canonicalHandle) {
      self = self.copyWith(handle: canonicalHandle, updatedAt: DateTime.now());
      await _contacts.upsertContact(self);
    }
    if (!mounted) return;
    setState(() {
      _existing = self;
      _displayNameController.text = self?.displayName ?? '';
      // Existing self-custody identities already own a public handle. Seed the
      // editor from that source of truth instead of showing an empty field and
      // inviting the person to create a conflicting second identity.
      // Repair installs where an older profile editor allowed the public
      // contact projection to drift away from the identity anchor. The
      // canonical store wins whenever it belongs to this DID.
      _handleController.text = canonicalHandle.isNotEmpty
          ? canonicalHandle
          : (self?.handle ?? '');
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final now = DateTime.now();
    final displayName = _displayNameController.text.trim();
    // The handle is identity-anchor data, not an editable profile attribute.
    // Keep publishing the canonical value so a display-profile edit can never
    // silently fork the DID/Relay binding.
    final canonical = await const SecureCanonicalIdentityStore().load();
    final handle = canonical?.did == widget.did
        ? canonical!.handle.trim()
        : _handleController.text.trim();

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
    // Publication needs a fresh, user-authorized signature. Go straight to
    // the sync surface rather than implying that a local save was published.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SyncSettingsScreen(db: widget.db, localDid: widget.did),
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: widget.isOnboarding
          ? context.uiCopy(zh: '讓大家找到你', en: 'LET PEOPLE FIND YOU')
          : context.uiCopy(zh: '編輯個人檔案', en: 'EDIT PROFILE'),
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
                if (widget.isOnboarding)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.uiCopy(zh: '暫時不要', en: 'Not now')),
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
                  hint: 'name.elix.cool',
                  readOnly: true,
                ),
                const SizedBox(height: 6),
                Text(
                  context.uiCopy(
                    zh: 'Handle 與你的 DID 身分綁定，不能在個人檔案中直接變更。你仍可自由修改上方的顯示名稱。',
                    en: 'Your handle is bound to your DID and cannot be changed from profile settings. You can still change your display name above.',
                  ),
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: AnsibleDesign.inkMuted,
                  ),
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
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
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
