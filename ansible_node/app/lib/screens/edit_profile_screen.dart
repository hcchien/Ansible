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
  String _canonicalHandle = '';
  bool _loading = true;
  bool _saving = false;
  bool _publicationConsent = false;

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
      _canonicalHandle = canonicalHandle;
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
    if (!_publicationConsent || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.uiCopy(zh: '確認公開這份檔案', en: 'Confirm public profile'),
        ),
        content: Text(
          context.uiCopy(
            zh: '確認後會儲存這次設定，並在下次授權同步時與其他待同步內容一起送出。你可以在下一頁選擇同步節點並完成裝置驗證。',
            en: 'Confirm to save these settings for the next authorized sync, together with other pending content. Choose a sync node and verify on your device on the next screen.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.uiCopy(zh: '確認並繼續', en: 'Confirm and continue'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final displayName = _displayNameController.text.trim();
      // The handle is identity-anchor data, not an editable profile attribute.
      // Keep publishing the canonical value so a display-profile edit can never
      // silently fork the DID/Relay binding.
      final canonical = await const SecureCanonicalIdentityStore().load();
      final canonicalHandle = canonical?.did == widget.did
          ? canonical!.handle.trim()
          : '';
      // A missing/empty canonical handle is a legacy or incomplete identity,
      // not proof that a local profile value must be discarded. Keep that
      // onboarding path editable; once anchored, the canonical value wins.
      final handle = canonicalHandle.isNotEmpty
          ? canonicalHandle
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
          builder: (_) => SyncSettingsScreen(
            db: widget.db,
            localDid: widget.did,
            profilePublication: true,
          ),
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.uiCopy(
              zh: '無法儲存，請重試。尚未確認公開成功。',
              en: 'Could not save. Please try again. Publication has not been confirmed.',
            ),
          ),
        ),
      );
    }
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
                    zh: '選擇別人搜尋與追蹤你時看到的名稱。下一步會引導你發布，儲存不代表已公開成功。',
                    en: 'Choose the name people see when finding and following you. Next, review publication. Saving does not confirm that your profile is online.',
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
                  hint: context.uiCopy(
                    zh: '你想讓大家看到的暱稱',
                    en: 'Your public nickname',
                  ),
                ),
                const SizedBox(height: 16),
                _label(context, context.uiCopy(zh: 'HANDLE', en: 'HANDLE')),
                _field(
                  controller: _handleController,
                  hint: 'name.elix.cool',
                  readOnly: _canonicalHandle.isNotEmpty,
                ),
                if (_canonicalHandle.isNotEmpty) ...[
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
                ],
                const SizedBox(height: 24),
                AnimatedBuilder(
                  animation: Listenable.merge([
                    _displayNameController,
                    _handleController,
                  ]),
                  builder: (context, _) => Card(
                    key: const Key('public_profile_preview'),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.uiCopy(
                              zh: '公開檔案預覽',
                              en: 'Public profile preview',
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _displayNameController.text.trim().isEmpty
                                ? context.uiCopy(
                                    zh: '尚未填寫暱稱',
                                    en: 'No nickname yet',
                                  )
                                : _displayNameController.text.trim(),
                          ),
                          Text(_handleController.text.trim()),
                          const SizedBox(height: 12),
                          Text(
                            context.uiCopy(
                              zh: '將公開上方名稱、帳號與已設定的頭像。既有的公開徽章由錢包設定管理；這裡不會新增公開證件資料。',
                              en: 'Your name, handle and existing avatar will be public. Existing public badges are managed in Wallet; this does not add credential disclosures.',
                            ),
                            style: const TextStyle(fontSize: 12, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  key: const Key('public_profile_consent'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _publicationConsent,
                  onChanged: _saving
                      ? null
                      : (value) => setState(
                          () => _publicationConsent = value ?? false,
                        ),
                  title: Text(
                    context.uiCopy(
                      zh: '我同意公開預覽中的檔案，讓別人搜尋與追蹤我。',
                      en: 'I agree to publish the previewed profile so people can find and follow me.',
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: _saving || !_publicationConsent ? null : _save,
                  child: Text(
                    _saving
                        ? context.uiCopy(zh: '儲存中…', en: 'Saving…')
                        : context.uiCopy(
                            zh: '同意並前往發布',
                            en: 'Agree and continue to publication',
                          ),
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
