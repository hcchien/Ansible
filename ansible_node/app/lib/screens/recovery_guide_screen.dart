import 'package:flutter/material.dart';
import '../l10n/app_l10n.dart';
import 'recovery_approve_scanner_screen.dart';

class RecoveryGuideScreen extends StatelessWidget {
  const RecoveryGuideScreen({super.key, required this.did});
  final String did;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        context.uiCopy(
          zh: '換手機與帳號復原',
          en: 'Move phones and recover your account',
        ),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        _task(
          context,
          Icons.phone_android,
          '舊手機還在',
          'I still have my old phone',
          '先在新手機選擇「復原既有帳號」→「使用其他裝置核准」，輸入帳號並產生 QR。再用這台舊手機掃描，確認要復原的帳號。復原可能有等待期，完成前保留舊手機。',
          'On the new phone choose Recover existing account → Approve from another device, enter your account and generate a QR. Scan it with this old phone and confirm the account. Recovery may have a waiting period; keep the old phone until it finishes.',
        ),
        OutlinedButton.icon(
          key: const Key('recovery_guide_scan'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => RecoveryApproveScannerScreen(localDid: did),
            ),
          ),
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(
            context.uiCopy(
              zh: '用這台手機核准新手機',
              en: 'Approve the new phone from this device',
            ),
          ),
        ),
        _task(
          context,
          Icons.phonelink_erase,
          '舊手機遺失了',
          'My old phone is lost',
          '請在新手機選擇「復原既有帳號」，建立復原請求後選擇「使用一次性恢復碼」。你需要事先保存的恢復碼；它只能使用一次。請依畫面查看等待時間。沒有舊裝置、恢復碼或適用的既有備份時，平台無法替你取回自主管理的金鑰。',
          'On the new phone choose Recover existing account, create a recovery request, then choose Use recovery code. You need a previously saved one-time code. Check the displayed waiting period. Without an old device, recovery code or applicable existing backup, the platform cannot retrieve your self-custodied key.',
        ),
        _task(
          context,
          Icons.web,
          '只想在瀏覽器使用',
          'I only want to use a browser',
          '在 Elix 網頁選擇登入，再用 App 開啟該網頁的授權連結。確認網域、權限與期限後才核准。這是瀏覽器授權，不需要做手機復原。',
          'Choose sign in on Elix Web and open its approval link in the App. Check the domain, permissions and expiry before approving. Browser authorization does not require phone recovery.',
        ),
        _task(
          context,
          Icons.inventory_2_outlined,
          '貼文、草稿與私密資料會一起回來嗎？',
          'Will my posts, drafts and private data return?',
          '身分復原不等於資料備份。已同步的可存取內容可以重新拉取；只存在舊裝置的草稿、私人內容與部分私密看板金鑰不保證能復原。移除舊手機前請先確認新手機上的資料。目前不提供兩台原生 App 同時共用簽署身分的保證。',
          'Identity recovery is not a content backup. Accessible synced content can be fetched again; drafts, private content and some private-board keys stored only on the old device may not be recoverable. Check your data on the new phone before removing the old one. Concurrent signing with the same identity in two native Apps is not guaranteed.',
        ),
      ],
    ),
  );
  Widget _task(
    BuildContext context,
    IconData icon,
    String zh,
    String en,
    String bodyZh,
    String bodyEn,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.uiCopy(zh: zh, en: en),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(context.uiCopy(zh: bodyZh, en: bodyEn)),
      ],
    ),
  );
}
