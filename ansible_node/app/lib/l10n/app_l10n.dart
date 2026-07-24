import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

extension AppL10nContext on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      lookupAppLocalizations(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );

  bool get usesChineseUi {
    final appLocalizations = Localizations.of<AppLocalizations>(
      this,
      AppLocalizations,
    );
    if (appLocalizations == null) return true;
    return Localizations.localeOf(this).languageCode == 'zh';
  }

  String uiCopy({required String zh, required String en}) {
    if (usesChineseUi) return zh;
    final languageCode = Localizations.localeOf(this).languageCode;
    return localizeUiCopy(languageCode, en);
  }
}

String localizeUiCopy(String localeName, String english) {
  final languageCode = localeName.split(RegExp('[-_]')).first;
  return _uiCopyTranslations[languageCode]?[english] ?? english;
}

/// Localizes legacy two-language call sites while they are migrated into ARB.
///
/// Keeping this catalog keyed by the English source makes older screens useful
/// in every supported locale without silently machine-translating security or
/// identity terminology at runtime.
const _uiCopyTranslations = <String, Map<String, String>>{
  'ja': {
    'DISCOVER': '探索',
    '← Back': '← 戻る',
    'PEOPLE': 'ユーザー',
    'BOARDS': 'ボード',
    'POSTS': '投稿',
    'Search people, boards, posts': 'ユーザー、ボード、投稿を検索',
    'Clear': 'クリア',
    'No people found': 'ユーザーが見つかりません',
    'No suggestions yet': 'おすすめはまだありません',
    'No boards found': 'ボードが見つかりません',
    'No boards yet': 'ボードはまだありません',
    'No posts found': '投稿が見つかりません',
    'Nothing here yet': 'まだ何もありません',
    'Try again': '再試行',
    'Follow': 'フォロー',
    'Following': 'フォロー中',
    'MY CONTENT': '自分のコンテンツ',
    'My board': 'マイボード',
    'Your own posts and notes': '自分の投稿とノート',
    'Credential issuer tools': '認証情報発行ツール',
    'Set up only if you need to issue membership credentials':
        '会員認証情報を発行する場合のみ設定します',
    'Hide': '閉じる',
    'Show': '表示',
    'Hosted Issuer': 'ホスト型発行者',
    'Organization credentials and signing governance': '組織認証情報と署名ガバナンス',
    'Issuer administrators': '発行者管理者',
    'Enrollment, passkeys, and multi-admin approval': '登録、パスキー、複数管理者の承認',
    'Identity key custody': 'ID鍵の保管',
    'Hardware-backed': 'ハードウェア保護',
    'Upgrade available': 'アップグレード可能',
    'Reduced trust': '信頼度低',
    'Non-exportable; signing requires device authorization':
        'エクスポート不可。署名にはデバイス認証が必要です',
    'Devices and account recovery': 'デバイスとアカウント復旧',
    'Approve, revoke, recovery codes, and audit': '承認、失効、復旧コード、監査',
    'Recoverable: backed up': '復旧可能：バックアップ済み',
    '⚠ No backup': '⚠ バックアップなし',
    'Recover account': 'アカウントを復旧',
    'Restore identity from an encrypted backup': '暗号化バックアップからIDを復元',
    'From backup': 'バックアップから',
    'External content': '外部コンテンツ',
    'Show unverified fediverse content on boards that opt in; off by default':
        '許可したボードに未検証のFediverseコンテンツを表示します（初期設定はオフ）',
    'Interface & Language': 'インターフェースと言語',
    'Board Theme': 'ボードのテーマ',
    'Personal and Forum boards can each use Paper, Ink, or Auto.':
        '個人ボードとフォーラムで Paper、Ink、Auto を個別に選べます。',
    'Board Motion': 'ボード切り替え',
    'Personal': '個人',
    'Forum': 'フォーラム',
    'Apply for a membership credential': '会員認証情報を申請または受信',
    'CREDENTIAL': '認証情報',
    '← Wallet': '← ウォレット',
    'Credential details': '認証情報の詳細',
    'Credential': '認証情報',
    'Type': '種類',
    'Issuer': '発行者',
    'Holder': '保有者',
    'Validity': '有効期間',
    'Credential ID': '認証情報 ID',
    'Disclosable claims': '開示可能なクレーム',
    'Verification': '検証情報',
    'Local checks': 'ローカル検査',
    'Presentations': '提示履歴',
    'Minimum disclosure': '最小限の開示',
    'Active': '有効',
    'Nationality': '国籍',
    'Age 18 or older': '18歳以上',
    'Verified human': '本人確認済み',
    'Taiwan Citizenship': '台湾市民',
    'Age 18 or Older': '18歳以上',
    'Not provided': '未提供',
    'Claims': 'クレーム',
    'This credential has no additional public claims': '追加の公開クレームはありません',
    'Proof': '署名証明',
    'Structure, validity, and privacy-field checks passed':
        '構造、有効期間、プライバシー項目の検査に合格しました',
    'Only Wallet metadata and validity were checked': 'ウォレットの概要と有効期間のみを確認しました',
    'Full payload is unavailable in secure storage': '完全な内容は安全なストレージにありません',
    'Credential summary only': '認証情報の概要のみ',
    'This credential belongs to an earlier installation and its complete payload is no longer in secure storage. You can still inspect the summary; verify again before presenting the full credential.':
        'この認証情報は以前のインストールで作成され、完全な内容は安全なストレージに残っていません。概要は確認できます。完全な認証情報を提示する前に、もう一度本人確認を行ってください。',
    'Credential unavailable': '認証情報を読み取れません',
    'The local encrypted payload could not be unlocked. Nothing was sent to another service.':
        'ローカルの暗号化内容を解除できませんでした。データは他のサービスへ送信されていません。',
    'This screen reads only the local Wallet. Passport numbers, national IDs, legal names, and birth dates are neither shown nor included in presentable credentials.':
        'この画面はローカルのウォレットだけを読み取ります。旅券番号、身分証番号、氏名、生年月日は表示されず、提示可能な認証情報にも含まれません。',
  },
  'ko': {
    'MY CONTENT': '내 콘텐츠',
    'My board': '내 보드',
    'Your own posts and notes': '내 게시물과 노트',
    'Credential issuer tools': '자격 증명 발급 도구',
    'Set up only if you need to issue membership credentials':
        '회원 자격 증명을 발급할 때만 설정하세요',
    'Hide': '접기',
    'Show': '펼치기',
    'Hosted Issuer': '호스팅 발급자',
    'Organization credentials and signing governance': '조직 자격 증명과 서명 거버넌스',
    'Issuer administrators': '발급자 관리자',
    'Enrollment, passkeys, and multi-admin approval': '등록, 패스키, 다중 관리자 승인',
    'Identity key custody': '신원 키 보관',
    'Hardware-backed': '하드웨어 보호',
    'Upgrade available': '업그레이드 가능',
    'Reduced trust': '신뢰 수준 낮음',
    'Non-exportable; signing requires device authorization':
        '내보낼 수 없으며 서명에는 기기 승인이 필요합니다',
    'Devices and account recovery': '기기 및 계정 복구',
    'Approve, revoke, recovery codes, and audit': '승인, 폐기, 복구 코드 및 감사',
    'Interface & Language': '인터페이스 및 언어',
    'Board Theme': '보드 테마',
    'Personal and Forum boards can each use Paper, Ink, or Auto.':
        '개인 보드와 포럼 보드에서 Paper, Ink 또는 Auto를 각각 선택할 수 있습니다.',
    'Board Motion': '보드 전환 효과',
    'Personal': '개인',
    'Forum': '포럼',
    'Apply for a membership credential': '회원 자격 증명 신청 또는 받기',
    'Credential details': '자격 증명 세부 정보',
    'Credential': '자격 증명',
    'Type': '유형',
    'Issuer': '발급자',
    'Holder': '소유자',
    'Validity': '유효 기간',
    'Credential ID': '자격 증명 ID',
    'Disclosable claims': '공개 가능한 클레임',
    'Verification': '검증 정보',
    'Local checks': '로컬 검사',
    'Presentations': '제시 기록',
    'Minimum disclosure': '최소 공개',
    'Active': '유효',
    'Nationality': '국적',
    'Age 18 or older': '만 18세 이상',
    'Verified human': '실명 확인됨',
    'Taiwan Citizenship': '대만 시민',
    'Age 18 or Older': '만 18세 이상',
    'Not provided': '제공되지 않음',
  },
  'fr': {
    'MY CONTENT': 'MON CONTENU',
    'My board': 'Mon tableau',
    'Your own posts and notes': 'Vos publications et notes',
    'Credential issuer tools': 'Outils d’émission de justificatifs',
    'Set up only if you need to issue membership credentials':
        'À configurer uniquement pour émettre des justificatifs de membre',
    'Hide': 'Masquer',
    'Show': 'Afficher',
    'Hosted Issuer': 'Émetteur hébergé',
    'Organization credentials and signing governance':
        'Justificatifs d’organisation et gouvernance des signatures',
    'Issuer administrators': 'Administrateurs de l’émetteur',
    'Enrollment, passkeys, and multi-admin approval':
        'Inscription, passkeys et approbation multi-administrateurs',
    'Identity key custody': 'Conservation de la clé d’identité',
    'Hardware-backed': 'Protégée par le matériel',
    'Upgrade available': 'Mise à niveau disponible',
    'Reduced trust': 'Confiance réduite',
    'Non-exportable; signing requires device authorization':
        'Non exportable ; la signature exige l’autorisation de l’appareil',
    'Devices and account recovery': 'Appareils et récupération du compte',
    'Approve, revoke, recovery codes, and audit':
        'Approbation, révocation, codes de récupération et audit',
    'Interface & Language': 'Interface et langue',
    'Board Theme': 'Thème des tableaux',
    'Personal and Forum boards can each use Paper, Ink, or Auto.':
        'Les tableaux personnels et les forums peuvent utiliser Paper, Ink ou Auto séparément.',
    'Board Motion': 'Animation des tableaux',
    'Personal': 'Personnel',
    'Forum': 'Forum',
    'Apply for a membership credential':
        'Demander ou recevoir un justificatif de membre',
    'Credential details': 'Détails du justificatif',
    'Credential': 'Justificatif',
    'Type': 'Type',
    'Issuer': 'Émetteur',
    'Holder': 'Titulaire',
    'Validity': 'Validité',
    'Credential ID': 'ID du justificatif',
    'Disclosable claims': 'Attributs divulgables',
    'Verification': 'Vérification',
    'Local checks': 'Contrôles locaux',
    'Presentations': 'Présentations',
    'Minimum disclosure': 'Divulgation minimale',
    'Active': 'Valide',
    'Nationality': 'Nationalité',
    'Age 18 or older': '18 ans ou plus',
    'Verified human': 'Personne vérifiée',
    'Taiwan Citizenship': 'Citoyenneté taïwanaise',
    'Age 18 or Older': '18 ans ou plus',
    'Not provided': 'Non fourni',
  },
  'es': {
    'MY CONTENT': 'MI CONTENIDO',
    'My board': 'Mi tablero',
    'Your own posts and notes': 'Tus publicaciones y notas',
    'Credential issuer tools': 'Herramientas de emisión de credenciales',
    'Set up only if you need to issue membership credentials':
        'Configúralo solo si necesitas emitir credenciales de membresía',
    'Hide': 'Ocultar',
    'Show': 'Mostrar',
    'Hosted Issuer': 'Emisor alojado',
    'Organization credentials and signing governance':
        'Credenciales de organización y gobernanza de firmas',
    'Issuer administrators': 'Administradores del emisor',
    'Enrollment, passkeys, and multi-admin approval':
        'Registro, passkeys y aprobación de varios administradores',
    'Identity key custody': 'Custodia de la clave de identidad',
    'Hardware-backed': 'Protegida por hardware',
    'Upgrade available': 'Actualización disponible',
    'Reduced trust': 'Confianza reducida',
    'Non-exportable; signing requires device authorization':
        'No exportable; firmar requiere autorización del dispositivo',
    'Devices and account recovery': 'Dispositivos y recuperación de cuenta',
    'Approve, revoke, recovery codes, and audit':
        'Aprobar, revocar, códigos de recuperación y auditoría',
    'Interface & Language': 'Interfaz e idioma',
    'Board Theme': 'Tema de los tableros',
    'Personal and Forum boards can each use Paper, Ink, or Auto.':
        'Los tableros personales y de foro pueden usar Paper, Ink o Auto por separado.',
    'Board Motion': 'Animación de tableros',
    'Personal': 'Personal',
    'Forum': 'Foro',
    'Apply for a membership credential':
        'Solicitar o recibir una credencial de membresía',
    'Credential details': 'Detalles de la credencial',
    'Credential': 'Credencial',
    'Type': 'Tipo',
    'Issuer': 'Emisor',
    'Holder': 'Titular',
    'Validity': 'Validez',
    'Credential ID': 'ID de credencial',
    'Disclosable claims': 'Atributos divulgables',
    'Verification': 'Verificación',
    'Local checks': 'Comprobaciones locales',
    'Presentations': 'Presentaciones',
    'Minimum disclosure': 'Divulgación mínima',
    'Active': 'Válida',
    'Nationality': 'Nacionalidad',
    'Age 18 or older': '18 años o más',
    'Verified human': 'Persona verificada',
    'Taiwan Citizenship': 'Ciudadanía taiwanesa',
    'Age 18 or Older': '18 años o más',
    'Not provided': 'No proporcionado',
  },
  'de': {
    'MY CONTENT': 'MEINE INHALTE',
    'My board': 'Mein Board',
    'Your own posts and notes': 'Deine Beiträge und Notizen',
    'Credential issuer tools': 'Werkzeuge für Nachweis-Aussteller',
    'Set up only if you need to issue membership credentials':
        'Nur einrichten, wenn du Mitgliedsnachweise ausstellen möchtest',
    'Hide': 'Ausblenden',
    'Show': 'Anzeigen',
    'Hosted Issuer': 'Gehosteter Aussteller',
    'Organization credentials and signing governance':
        'Organisationsnachweise und Signaturverwaltung',
    'Issuer administrators': 'Aussteller-Administratoren',
    'Enrollment, passkeys, and multi-admin approval':
        'Registrierung, Passkeys und Mehrfachfreigabe',
    'Identity key custody': 'Verwahrung des Identitätsschlüssels',
    'Hardware-backed': 'Hardwaregeschützt',
    'Upgrade available': 'Upgrade verfügbar',
    'Reduced trust': 'Reduziertes Vertrauen',
    'Non-exportable; signing requires device authorization':
        'Nicht exportierbar; Signieren erfordert Gerätefreigabe',
    'Devices and account recovery': 'Geräte und Kontowiederherstellung',
    'Approve, revoke, recovery codes, and audit':
        'Freigeben, widerrufen, Wiederherstellungscodes und Audit',
    'Interface & Language': 'Oberfläche und Sprache',
    'Board Theme': 'Board-Design',
    'Personal and Forum boards can each use Paper, Ink, or Auto.':
        'Persönliche und Forum-Boards können getrennt Paper, Ink oder Auto verwenden.',
    'Board Motion': 'Board-Animation',
    'Personal': 'Persönlich',
    'Forum': 'Forum',
    'Apply for a membership credential':
        'Mitgliedsnachweis beantragen oder empfangen',
    'Credential details': 'Nachweisdetails',
    'Credential': 'Nachweis',
    'Type': 'Typ',
    'Issuer': 'Aussteller',
    'Holder': 'Inhaber',
    'Validity': 'Gültigkeit',
    'Credential ID': 'Nachweis-ID',
    'Disclosable claims': 'Offenlegbare Angaben',
    'Verification': 'Verifizierung',
    'Local checks': 'Lokale Prüfungen',
    'Presentations': 'Vorlagen',
    'Minimum disclosure': 'Minimale Offenlegung',
    'Active': 'Gültig',
    'Nationality': 'Staatsangehörigkeit',
    'Age 18 or older': '18 Jahre oder älter',
    'Verified human': 'Verifizierte Person',
    'Taiwan Citizenship': 'Taiwanische Staatsangehörigkeit',
    'Age 18 or Older': '18 Jahre oder älter',
    'Not provided': 'Nicht angegeben',
  },
  'it': {
    'MY CONTENT': 'I MIEI CONTENUTI',
    'My board': 'La mia bacheca',
    'Your own posts and notes': 'I tuoi post e le tue note',
    'Credential issuer tools': 'Strumenti per emettere credenziali',
    'Set up only if you need to issue membership credentials':
        'Configura solo se devi emettere credenziali associative',
    'Hide': 'Nascondi',
    'Show': 'Mostra',
    'Hosted Issuer': 'Emittente ospitato',
    'Organization credentials and signing governance':
        'Credenziali organizzative e governance delle firme',
    'Issuer administrators': 'Amministratori dell’emittente',
    'Enrollment, passkeys, and multi-admin approval':
        'Registrazione, passkey e approvazione multi-amministratore',
    'Identity key custody': 'Custodia della chiave d’identità',
    'Hardware-backed': 'Protetta dall’hardware',
    'Upgrade available': 'Aggiornamento disponibile',
    'Reduced trust': 'Attendibilità ridotta',
    'Non-exportable; signing requires device authorization':
        'Non esportabile; la firma richiede l’autorizzazione del dispositivo',
    'Devices and account recovery': 'Dispositivi e recupero account',
    'Approve, revoke, recovery codes, and audit':
        'Approva, revoca, codici di recupero e audit',
    'Interface & Language': 'Interfaccia e lingua',
    'Board Theme': 'Tema delle bacheche',
    'Personal and Forum boards can each use Paper, Ink, or Auto.':
        'Le bacheche personali e dei forum possono usare separatamente Paper, Ink o Auto.',
    'Board Motion': 'Animazione delle bacheche',
    'Personal': 'Personale',
    'Forum': 'Forum',
    'Apply for a membership credential':
        'Richiedi o ricevi una credenziale associativa',
    'Credential details': 'Dettagli della credenziale',
    'Credential': 'Credenziale',
    'Type': 'Tipo',
    'Issuer': 'Emittente',
    'Holder': 'Titolare',
    'Validity': 'Validità',
    'Credential ID': 'ID credenziale',
    'Disclosable claims': 'Attributi divulgabili',
    'Verification': 'Verifica',
    'Local checks': 'Controlli locali',
    'Presentations': 'Presentazioni',
    'Minimum disclosure': 'Divulgazione minima',
    'Active': 'Valida',
    'Nationality': 'Nazionalità',
    'Age 18 or older': '18 anni o più',
    'Verified human': 'Persona verificata',
    'Taiwan Citizenship': 'Cittadinanza taiwanese',
    'Age 18 or Older': '18 anni o più',
    'Not provided': 'Non fornito',
  },
};
