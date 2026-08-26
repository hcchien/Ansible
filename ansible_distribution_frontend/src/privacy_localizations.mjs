// Reviewed privacy-policy editions beyond the original Traditional Chinese
// and English documents. Keep every edition structurally aligned so changes
// to a data-flow promise are made across all eight languages together.

export function createPrivacyLocalizations({ privacyEmail }) {
  return Object.freeze({
    fr: {
      title: 'Politique de confidentialité',
      body: `
        <h1>Politique de confidentialité</h1>
        <p class="legal-effective">Date d’entrée en vigueur : 7 juillet 2026</p>

        <p>Elix (domaine elix.cool, ci-après « le Service ») est une communauté de discussion décentralisée fondée sur l’identité auto-souveraine. Notre principe de conception est le suivant : les données restent autant que possible sur votre appareil ; celles qui le quittent sont réduites au minimum, signées par vous, vérifiables et portables. La présente politique explique quelles données sont traitées, dans quels systèmes, pendant combien de temps et quels sont vos droits.</p>

        <h2>Ce que nous ne faisons pas</h2>
        <ul>
          <li>Aucun SDK d’analyse, de suivi ou de publicité, et aucun code de suivi tiers.</li>
          <li>Aucune télémétrie individuelle ; les indicateurs opérationnels sont uniquement agrégés et ne peuvent pas être rattachés à une personne.</li>
          <li>Nous ne collectons ni ne conservons votre localisation.</li>
          <li>Les adresses IP ne sont inscrites dans aucun registre permanent.</li>
          <li>Nous ne vendons, ne louons ni ne partageons de données personnelles avec des tiers à des fins de marketing.</li>
        </ul>

        <h2>Où les données sont conservées</h2>

        <h3>Votre appareil</h3>
        <ul>
          <li><strong>Clés privées d’identité (Ed25519)</strong> : générées et conservées sur votre appareil (conservation logicielle, indiquée par le niveau custody_class) et exclues de la sauvegarde dans le cloud (noBackupFilesDir sous Android, protection des fichiers sous iOS). Les clés privées ne quittent jamais votre appareil.</li>
          <li>Votre base de données locale, vos brouillons et les justificatifs vérifiables (Verifiable Credentials, VC) de votre portefeuille.</li>
        </ul>

        <h3>Relay (service de relais)</h3>
        <p>Le Relay ne conserve que ce que vous choisissez de rendre public :</p>
        <ul>
          <li>Votre DID public et votre handle (identifiant de compte).</li>
          <li>Vos publications et opérations publiques signées — un journal signé, à ajout uniquement (append-only) et infalsifiable.</li>
          <li>Les dossiers de modération.</li>
          <li>Les jetons de notification push de l’appareil (utilisés uniquement comme signaux de synchronisation sans contenu).</li>
        </ul>
        <p>Le Relay ne conserve <strong>aucun</strong> e-mail, nom légal, numéro de téléphone, numéro d’identité nationale ni donnée de localisation ; les adresses IP ne sont pas conservées.</p>

        <h3>Issuer (service de vérification d’identité)</h3>
        <ul>
          <li>Pendant la vérification, votre e-mail et le code à usage unique (OTP) ne restent en mémoire que quelques minutes, puis sont supprimés.</li>
          <li>Pour empêcher les inscriptions multiples par une même personne (résistance aux attaques Sybil), seul un engagement haché, irréversible et protégé par une clé est conservé ; il ne peut pas être reconverti en votre e-mail ou en données d’identité.</li>
          <li>Les données de la puce NFC du passeport et celles de MobileMoica à Taïwan (certificat citoyen mobile) sont traitées temporairement pendant la vérification et ne sont <strong>jamais conservées</strong>.</li>
          <li>Les justificatifs vérifiables émis ne sont conservés que dans le portefeuille de votre appareil ; leur révocation est prise en charge.</li>
        </ul>

        <h3>AppView (service de projection pour la lecture)</h3>
        <p>AppView est une projection en lecture seule des contenus déjà publics sur le Relay, utilisée pour la consultation et la recherche. Il ne contient aucune donnée personnelle supplémentaire.</p>

        <h2>Quand les données quittent votre appareil</h2>
        <p>Uniquement lorsque vous le choisissez : pour publier un contenu public, effectuer une vérification d’identité ou activer les notifications push. Les clés privées et les données privées non publiées ne quittent pas l’appareil.</p>

        <h2>Durée de conservation</h2>
        <div class="legal-table-wrap">
          <table>
            <thead><tr><th>Données</th><th>Emplacement</th><th>Durée de conservation</th></tr></thead>
            <tbody>
              <tr><td>Clés privées d’identité (Ed25519)</td><td>Votre appareil uniquement</td><td>Jusqu’à la suppression de l’identité locale ou la désinstallation</td></tr>
              <tr><td>DID public, handle</td><td>Relay</td><td>Pendant la durée de vie du compte (registre public)</td></tr>
              <tr><td>Publications et opérations publiques signées</td><td>Relay</td><td>Ne sont plus diffusées après leur suppression ; le journal signé sous-jacent à ajout uniquement est conservé (voir « Vos droits »)</td></tr>
              <tr><td>Dossiers de modération</td><td>Relay</td><td>Conservés pour la gouvernance et les recours</td></tr>
              <tr><td>Jetons de notification push</td><td>Relay</td><td>Jusqu’à la déconnexion de l’appareil ou l’expiration du jeton</td></tr>
              <tr><td>E-mail et OTP (pendant la vérification)</td><td>Issuer (mémoire uniquement)</td><td>Quelques minutes ; supprimés à la fin de la vérification</td></tr>
              <tr><td>Engagement haché anti-duplication</td><td>Issuer</td><td>Conservé (irréversible ; ne peut révéler aucune donnée personnelle)</td></tr>
              <tr><td>Données NFC du passeport / MobileMoica</td><td>Issuer (temporaire)</td><td>Traitées uniquement pendant la vérification ; jamais conservées</td></tr>
              <tr><td>Justificatifs vérifiables (VC)</td><td>Portefeuille de votre appareil</td><td>Conservés par vous ; révocables</td></tr>
              <tr><td>Adresses IP</td><td>—</td><td>Non conservées</td></tr>
              <tr><td>Projection AppView</td><td>AppView</td><td>Suit le contenu public du Relay ; les suppressions sont propagées</td></tr>
            </tbody>
          </table>
        </div>

        <h2>Vos droits</h2>
        <ul>
          <li><strong>Accès et portabilité</strong> : votre contenu public est dans un format signé et portable ; vous pouvez y accéder à tout moment ou l’emporter vers un autre service compatible.</li>
          <li><strong>Suppression</strong> :
            <ul>
              <li>Vous pouvez effacer votre identité locale dans l’application (Réglages → Se déconnecter de cet appareil), ce qui empêche cet appareil d’utiliser cette identité.</li>
              <li>Le contenu que vous supprimez est retiré d’AppView et des autres interfaces de lecture ; la suppression est propagée en aval.</li>
              <li><strong>Déclaration transparente</strong> : les publications publiques du Relay font partie d’un journal signé à ajout uniquement. La suppression retire le contenu de toutes les interfaces de diffusion, mais les entrées signées sous-jacentes sont conservées afin de préserver l’intégrité et la vérifiabilité du registre.</li>
              <li>Pour demander la suppression complète du compte et des données, écrivez à <a href="mailto:${privacyEmail}">${privacyEmail}</a> ; nous traiterons votre demande et y répondrons dans un délai raisonnable. Consultez aussi <a href="/account-deletion">Suppression du compte et des données</a>.</li>
            </ul>
          </li>
          <li><strong>Révocation des justificatifs</strong> : les justificatifs vérifiables émis peuvent être révoqués.</li>
        </ul>

        <h2>Droit applicable</h2>
        <p>Nous traitons les données personnelles conformément à la <strong>loi taïwanaise sur la protection des données personnelles</strong> ; les personnes concernées peuvent exercer les droits prévus à l’article 3 (demande d’information, consultation, copies, ajout, rectification, cessation du traitement ou de l’utilisation et suppression). Pour les utilisateurs situés dans l’UE/EEE, le <strong>RGPD</strong> s’applique (bases juridiques : exécution du contrat et votre consentement explicite — par exemple pour la vérification d’identité). Pour les utilisateurs de Californie, le <strong>CCPA/CPRA</strong> s’applique : nous ne vendons ni ne partageons les informations personnelles. Pour exercer l’un de ces droits, contactez <a href="mailto:${privacyEmail}">${privacyEmail}</a>.</p>

        <h2>Enfants</h2>
        <p>Le Service ne s’adresse pas aux enfants de moins de 13 ans. Si nous apprenons que nous avons traité les données personnelles d’un enfant de moins de 13 ans sans le consentement d’un représentant légal, nous les supprimerons rapidement.</p>

        <h2>Modifications de la présente politique</h2>
        <p>Lorsque nous modifions la présente politique, nous mettons à jour la date d’entrée en vigueur sur cette page ; toute modification importante sera annoncée de manière visible dans le Service. La poursuite de l’utilisation du Service signifie que vous avez pris connaissance de la politique mise à jour.</p>

        <h2>Nous contacter</h2>
        <p>Questions et demandes relatives à la confidentialité : <a href="mailto:${privacyEmail}">${privacyEmail}</a></p>
      `,
    },
    es: {
      title: 'Política de privacidad',
      body: `
        <h1>Política de privacidad</h1>
        <p class="legal-effective">Fecha de entrada en vigor: 7 de julio de 2026</p>

        <p>Elix (dominio elix.cool, «el Servicio») es una comunidad de debate descentralizada basada en la identidad autosoberana. Nuestro principio de diseño es que los datos permanezcan en tu dispositivo siempre que sea posible; lo que sale del dispositivo se reduce al mínimo, está firmado por ti, es verificable y portátil. Esta política explica qué datos se tratan en cada sistema, durante cuánto tiempo y qué derechos tienes.</p>

        <h2>Lo que no hacemos</h2>
        <ul>
          <li>No usamos SDK de analítica, seguimiento ni publicidad, ni incorporamos código de seguimiento de terceros.</li>
          <li>No generamos telemetría individual; las métricas operativas solo se recopilan de forma agregada y no pueden vincularse con una persona.</li>
          <li>No recopilamos ni almacenamos tu ubicación.</li>
          <li>Las direcciones IP no se escriben en ningún registro permanente.</li>
          <li>No vendemos, alquilamos ni compartimos datos personales con terceros para fines de marketing.</li>
        </ul>

        <h2>Dónde se almacenan los datos</h2>

        <h3>Tu dispositivo</h3>
        <ul>
          <li><strong>Claves privadas de identidad (Ed25519)</strong>: se generan y almacenan en tu dispositivo (custodia por software, indicada mediante el nivel custody_class) y se excluyen de las copias de seguridad en la nube (noBackupFilesDir en Android y protección de archivos en iOS). Las claves privadas nunca salen de tu dispositivo.</li>
          <li>Tu base de datos local, tus borradores y las credenciales verificables (Verifiable Credentials, VC) de tu Wallet.</li>
        </ul>

        <h3>Relay (servicio de retransmisión)</h3>
        <p>El Relay solo almacena lo que eliges hacer público:</p>
        <ul>
          <li>Tu DID público y tu handle (identificador de cuenta).</li>
          <li>Tus publicaciones y operaciones públicas firmadas: un registro firmado, de solo anexado (append-only) y resistente a manipulaciones.</li>
          <li>Registros de moderación.</li>
          <li>Tokens de notificaciones push del dispositivo (usados únicamente como avisos de sincronización sin contenido).</li>
        </ul>
        <p>El Relay <strong>no almacena</strong> tu correo electrónico, nombre legal, número de teléfono, número de identidad nacional ni ubicación; las direcciones IP no se conservan.</p>

        <h3>Issuer (servicio de verificación de identidad)</h3>
        <ul>
          <li>Durante la verificación, tu correo electrónico y el código de un solo uso (OTP) permanecen en memoria solo unos minutos y luego se descartan.</li>
          <li>Para impedir registros duplicados de una misma persona (resistencia a ataques Sybil), solo se conserva un compromiso hash irreversible protegido por clave; no puede revertirse para obtener tu correo electrónico ni otros datos de identidad.</li>
          <li>Los datos del chip NFC del pasaporte y los de MobileMoica de Taiwán (certificado ciudadano móvil) se tratan de forma transitoria durante la verificación y <strong>nunca se almacenan</strong>.</li>
          <li>Las credenciales verificables emitidas solo se guardan en la Wallet de tu dispositivo; se admite la revocación de credenciales.</li>
        </ul>

        <h3>AppView (servicio de proyección de lectura)</h3>
        <p>AppView es una proyección de solo lectura del contenido que ya es público en el Relay, utilizada para navegar y buscar. No contiene datos personales adicionales.</p>

        <h2>Cuándo salen los datos de tu dispositivo</h2>
        <p>Solo cuando tú lo eliges: al publicar contenido público, realizar una verificación de identidad o activar las notificaciones push. Las claves privadas y los datos privados sin publicar no salen del dispositivo.</p>

        <h2>Conservación</h2>
        <div class="legal-table-wrap">
          <table>
            <thead><tr><th>Datos</th><th>Ubicación</th><th>Periodo de conservación</th></tr></thead>
            <tbody>
              <tr><td>Claves privadas de identidad (Ed25519)</td><td>Solo tu dispositivo</td><td>Hasta que borres la identidad local o desinstales la aplicación</td></tr>
              <tr><td>DID público, handle</td><td>Relay</td><td>Durante la existencia de la cuenta (registro público)</td></tr>
              <tr><td>Publicaciones y operaciones públicas firmadas</td><td>Relay</td><td>Dejan de mostrarse al eliminarlas; se conserva el registro firmado subyacente de solo anexado (consulta «Tus derechos»)</td></tr>
              <tr><td>Registros de moderación</td><td>Relay</td><td>Se conservan para gobernanza y apelaciones</td></tr>
              <tr><td>Tokens de notificaciones push</td><td>Relay</td><td>Hasta que cierres sesión en el dispositivo o caduque el token</td></tr>
              <tr><td>Correo electrónico y OTP (durante la verificación)</td><td>Issuer (solo en memoria)</td><td>Unos minutos; se descartan al finalizar la verificación</td></tr>
              <tr><td>Compromiso hash para evitar duplicados</td><td>Issuer</td><td>Se conserva (irreversible; no puede revelar datos personales)</td></tr>
              <tr><td>Datos NFC del pasaporte / MobileMoica</td><td>Issuer (transitorio)</td><td>Solo se tratan durante la verificación; nunca se almacenan</td></tr>
              <tr><td>Credenciales verificables (VC)</td><td>Wallet de tu dispositivo</td><td>Las conservas tú; son revocables</td></tr>
              <tr><td>Direcciones IP</td><td>—</td><td>No se conservan</td></tr>
              <tr><td>Proyección de AppView</td><td>AppView</td><td>Refleja el contenido público del Relay; las eliminaciones se propagan</td></tr>
            </tbody>
          </table>
        </div>

        <h2>Tus derechos</h2>
        <ul>
          <li><strong>Acceso y portabilidad</strong>: tu contenido público tiene un formato firmado y portátil; puedes acceder a él en cualquier momento o trasladarlo a otro servicio compatible.</li>
          <li><strong>Eliminación</strong>:
            <ul>
              <li>Puedes borrar tu identidad local desde la aplicación (Ajustes → Cerrar sesión en este dispositivo), lo que impide que este dispositivo siga usando esa identidad.</li>
              <li>El contenido que eliminas se retira de AppView y de otras interfaces de lectura; las eliminaciones se propagan a los servicios posteriores.</li>
              <li><strong>Declaración transparente</strong>: las publicaciones públicas del Relay forman parte de un registro firmado de solo anexado. Al eliminar contenido, deja de mostrarse en todas las interfaces públicas, pero las entradas firmadas subyacentes se conservan para mantener la integridad y verificabilidad del registro.</li>
              <li>Para solicitar la eliminación completa de la cuenta y los datos, escribe a <a href="mailto:${privacyEmail}">${privacyEmail}</a>; tramitaremos y responderemos tu solicitud en un plazo razonable. Consulta también <a href="/account-deletion">Eliminación de la cuenta y los datos</a>.</li>
            </ul>
          </li>
          <li><strong>Revocación de credenciales</strong>: las credenciales verificables emitidas pueden revocarse.</li>
        </ul>

        <h2>Legislación aplicable</h2>
        <p>Tratamos los datos personales conforme a la <strong>Ley de Protección de Datos Personales de Taiwán</strong>; las personas interesadas pueden ejercer los derechos del artículo 3 (consulta, revisión, copias, complementación, corrección, cese del tratamiento o uso y eliminación). Para usuarios de la UE/EEE se aplica el <strong>RGPD</strong> (bases jurídicas: ejecución del contrato y tu consentimiento explícito, por ejemplo, para la verificación de identidad). Para usuarios de California se aplica la <strong>CCPA/CPRA</strong>: no vendemos ni compartimos información personal. Para ejercer cualquiera de estos derechos, escribe a <a href="mailto:${privacyEmail}">${privacyEmail}</a>.</p>

        <h2>Menores</h2>
        <p>El Servicio no está dirigido a menores de 13 años. Si sabemos que hemos tratado datos personales de un menor de 13 años sin el consentimiento de su representante legal, los eliminaremos de inmediato.</p>

        <h2>Cambios en esta política</h2>
        <p>Cuando modifiquemos esta política, actualizaremos la fecha de entrada en vigor de esta página; los cambios importantes se anunciarán de forma destacada en el Servicio. El uso continuado del Servicio significa que has leído la política actualizada.</p>

        <h2>Contacto</h2>
        <p>Preguntas y solicitudes sobre privacidad: <a href="mailto:${privacyEmail}">${privacyEmail}</a></p>
      `,
    },
    ja: {
      title: 'プライバシーポリシー',
      body: `
        <h1>プライバシーポリシー</h1>
        <p class="legal-effective">施行日：2026年7月7日</p>

        <p>Elix（ドメイン：elix.cool、以下「本サービス」）は、自己主権型アイデンティティを基盤とする分散型のディスカッションコミュニティです。設計原則は、可能な限りデータを利用者の端末に保持し、端末外へ出るデータを最小限に抑え、利用者自身が署名し、検証可能かつ移行可能なものにすることです。本ポリシーでは、どのシステムでどのデータを処理するか、保存期間、および利用者の権利について説明します。</p>

        <h2>当サービスが行わないこと</h2>
        <ul>
          <li>分析、トラッキング、広告用のSDKを使用せず、第三者のトラッキングコードも組み込みません。</li>
          <li>利用者単位のテレメトリを作成しません。運用指標は集計値のみで、個人に結び付けることはできません。</li>
          <li>位置情報を収集・保存しません。</li>
          <li>IPアドレスを永続的な記録に書き込みません。</li>
          <li>マーケティング目的で個人データを第三者に販売、貸与、共有しません。</li>
        </ul>

        <h2>データの保存場所</h2>

        <h3>利用者の端末</h3>
        <ul>
          <li><strong>アイデンティティ秘密鍵（Ed25519）</strong>：端末上で生成・保存され（ソフトウェア保管で、保管レベルは custody_class として表示）、クラウドバックアップから除外されます（Android は noBackupFilesDir、iOS はファイル保護機能を使用）。秘密鍵が端末外へ出ることはありません。</li>
          <li>ローカルデータベース、下書き、およびWallet内の検証可能なクレデンシャル（Verifiable Credentials、VC）。</li>
        </ul>

        <h3>Relay（メッセージ中継サービス）</h3>
        <p>Relayが保存するのは、利用者が公開を選択したものだけです。</p>
        <ul>
          <li>公開DIDとhandle（アカウント識別名）。</li>
          <li>署名して公開した投稿と操作記録。これは追記専用（append-only）で改ざん検知可能な署名ログです。</li>
          <li>モデレーション記録。</li>
          <li>端末のプッシュ通知トークン（内容を含まない同期通知にのみ使用）。</li>
        </ul>
        <p>Relayは、メールアドレス、法的氏名、電話番号、国民識別番号、位置情報を<strong>保存しません</strong>。IPアドレスも保持しません。</p>

        <h3>Issuer（本人確認サービス）</h3>
        <ul>
          <li>確認中のメールアドレスとワンタイムパスコード（OTP）は、数分間だけメモリに保持され、確認完了後に破棄されます。</li>
          <li>同一人物による重複登録を防ぐため（Sybil攻撃への対策）、鍵付きで不可逆なハッシュコミットメントだけを保存します。これをメールアドレスやその他の身元データに戻すことはできません。</li>
          <li>パスポートのNFCチップデータと台湾のMobileMoica（モバイル自然人証明書）のデータは、確認中に一時的に処理されるだけで、<strong>保存されることはありません</strong>。</li>
          <li>発行された検証可能なクレデンシャルは利用者の端末のWalletにだけ保存され、クレデンシャルの失効にも対応します。</li>
        </ul>

        <h3>AppView（閲覧用投影サービス）</h3>
        <p>AppViewは、Relayですでに公開されているコンテンツを閲覧・検索するための読み取り専用の投影です。追加の個人データは保持しません。</p>

        <h2>データが端末外へ出る場合</h2>
        <p>公開コンテンツを投稿するとき、本人確認を行うとき、またはプッシュ通知を有効にするときなど、利用者が選択した場合に限ります。秘密鍵と未公開の非公開データは端末外へ出ません。</p>

        <h2>保存期間</h2>
        <div class="legal-table-wrap">
          <table>
            <thead><tr><th>データ</th><th>保存場所</th><th>保存期間</th></tr></thead>
            <tbody>
              <tr><td>アイデンティティ秘密鍵（Ed25519）</td><td>利用者の端末のみ</td><td>ローカルのアイデンティティを消去するか、アプリをアンインストールするまで</td></tr>
              <tr><td>公開DID、handle</td><td>Relay</td><td>アカウントの存続期間（公開記録）</td></tr>
              <tr><td>署名済みの公開投稿／操作</td><td>Relay</td><td>削除後は外部への提供を停止。基礎となる追記専用署名ログは保持（「利用者の権利」を参照）</td></tr>
              <tr><td>モデレーション記録</td><td>Relay</td><td>ガバナンスと異議申立てのために保持</td></tr>
              <tr><td>端末のプッシュ通知トークン</td><td>Relay</td><td>端末からログアウトするか、トークンが失効するまで</td></tr>
              <tr><td>メールアドレスとOTP（確認中）</td><td>Issuer（メモリのみ）</td><td>数分間。確認完了後に破棄</td></tr>
              <tr><td>重複防止用ハッシュコミットメント</td><td>Issuer</td><td>保持（不可逆で、個人データを復元できない）</td></tr>
              <tr><td>パスポートNFC／MobileMoicaデータ</td><td>Issuer（一時処理）</td><td>確認中のみ処理し、保存しない</td></tr>
              <tr><td>検証可能なクレデンシャル（VC）</td><td>利用者の端末のWallet</td><td>利用者が保管。失効可能</td></tr>
              <tr><td>IPアドレス</td><td>—</td><td>保持しない</td></tr>
              <tr><td>AppViewの投影コンテンツ</td><td>AppView</td><td>Relayの公開コンテンツに追随し、削除も伝播</td></tr>
            </tbody>
          </table>
        </div>

        <h2>利用者の権利</h2>
        <ul>
          <li><strong>アクセスと移行</strong>：公開コンテンツは署名付きの移行可能な形式です。いつでもアクセスでき、他の互換サービスへ持ち出すこともできます。</li>
          <li><strong>削除</strong>：
            <ul>
              <li>アプリ内でローカルのアイデンティティを消去できます（設定 → この端末からログアウト）。これにより、この端末ではそのアイデンティティを使用できなくなります。</li>
              <li>削除したコンテンツはAppViewなどの閲覧画面から取り除かれ、削除は下流にも伝播します。</li>
              <li><strong>正確な説明</strong>：Relay上の公開投稿は追記専用の署名ログの一部です。削除するとすべての公開画面でコンテンツの提供を停止しますが、記録の完全性と検証可能性を維持するため、基礎となる署名ログのエントリ自体は保持されます。</li>
              <li>アカウントとデータの完全な削除を希望する場合は、<a href="mailto:${privacyEmail}">${privacyEmail}</a> へご連絡ください。合理的な期間内に処理し、回答します。<a href="/account-deletion">アカウントとデータの削除</a>もご覧ください。</li>
            </ul>
          </li>
          <li><strong>クレデンシャルの失効</strong>：発行済みの検証可能なクレデンシャルは失効させることができます。</li>
        </ul>

        <h2>適用法令</h2>
        <p>本サービスは、<strong>台湾の個人データ保護法</strong>に基づいて個人データを処理します。データ主体は同法第3条に定める権利（照会、閲覧、複製、補充、訂正、処理・利用の停止、削除）を行使できます。EU／EEAの利用者には<strong>GDPR</strong>が適用されます（法的根拠：契約の履行、および本人確認などにおける利用者の明示的な同意）。米国カリフォルニア州の利用者には<strong>CCPA/CPRA</strong>が適用され、当サービスは個人情報を販売も共有もしません。これらの権利を行使するには、<a href="mailto:${privacyEmail}">${privacyEmail}</a> へご連絡ください。</p>

        <h2>子ども</h2>
        <p>本サービスは13歳未満の子どもを対象としていません。法定代理人の同意なく13歳未満の子どもの個人データを処理したことが判明した場合は、速やかに削除します。</p>

        <h2>本ポリシーの変更</h2>
        <p>本ポリシーを変更する場合、このページの施行日を更新します。重要な変更は本サービス内で目立つ形でお知らせします。本サービスを継続して利用することにより、更新後のポリシーを確認したものとみなされます。</p>

        <h2>お問い合わせ</h2>
        <p>プライバシーに関する質問・請求：<a href="mailto:${privacyEmail}">${privacyEmail}</a></p>
      `,
    },
    ko: {
      title: '개인정보 처리방침',
      body: `
        <h1>개인정보 처리방침</h1>
        <p class="legal-effective">시행일: 2026년 7월 7일</p>

        <p>Elix(도메인 elix.cool, 이하 ‘서비스’)는 자기주권 신원을 기반으로 하는 탈중앙화 토론 커뮤니티입니다. 설계 원칙은 가능한 한 데이터를 사용자의 기기에 보관하고, 기기를 벗어나는 데이터는 최소화하며, 사용자가 서명하고 검증 및 이동할 수 있게 하는 것입니다. 본 방침은 어떤 시스템에서 어떤 데이터를 처리하는지, 얼마나 오래 보관하는지, 사용자가 어떤 권리를 갖는지 설명합니다.</p>

        <h2>서비스가 하지 않는 일</h2>
        <ul>
          <li>분석, 추적 또는 광고 SDK를 사용하지 않으며 제3자 추적 코드도 삽입하지 않습니다.</li>
          <li>사용자별 원격 측정 정보를 만들지 않습니다. 운영 지표는 집계된 형태로만 수집되며 개인과 연결할 수 없습니다.</li>
          <li>위치 정보를 수집하거나 저장하지 않습니다.</li>
          <li>IP 주소를 영구 기록에 저장하지 않습니다.</li>
          <li>마케팅 목적으로 개인정보를 제3자에게 판매, 대여 또는 공유하지 않습니다.</li>
        </ul>

        <h2>데이터 저장 위치</h2>

        <h3>사용자의 기기</h3>
        <ul>
          <li><strong>신원 개인 키(Ed25519)</strong>: 기기에서 생성되고 저장되며(소프트웨어 보관, custody_class 보관 등급 표시), 클라우드 백업에서는 제외됩니다(Android의 noBackupFilesDir, iOS의 파일 보호 기능 사용). 개인 키는 절대로 기기를 벗어나지 않습니다.</li>
          <li>로컬 데이터베이스, 초안, Wallet에 있는 검증 가능한 자격 증명(Verifiable Credentials, VC).</li>
        </ul>

        <h3>Relay(메시지 중계 서비스)</h3>
        <p>Relay는 사용자가 공개하기로 선택한 데이터만 저장합니다.</p>
        <ul>
          <li>공개 DID와 handle(계정 식별자).</li>
          <li>서명하여 게시한 공개 게시물과 작업 기록. 이는 추가 전용(append-only)이며 변조를 확인할 수 있는 서명 로그입니다.</li>
          <li>운영 및 조정 기록.</li>
          <li>기기 푸시 토큰(내용이 없는 동기화 알림에만 사용).</li>
        </ul>
        <p>Relay는 이메일, 법적 이름, 전화번호, 주민등록번호 등의 국가 식별번호 또는 위치 정보를 <strong>저장하지 않으며</strong>, IP 주소도 보관하지 않습니다.</p>

        <h3>Issuer(신원 확인 서비스)</h3>
        <ul>
          <li>확인 과정에서 이메일과 일회용 인증 코드(OTP)는 메모리에 몇 분 동안만 유지된 뒤 폐기됩니다.</li>
          <li>동일인의 중복 가입을 방지하기 위해(Sybil 공격 방지) 키로 보호된 비가역 해시 커밋먼트만 보관합니다. 이 값으로 이메일이나 신원 데이터를 복원할 수 없습니다.</li>
          <li>여권 NFC 칩 데이터와 대만 MobileMoica(모바일 자연인 인증서) 데이터는 확인 과정에서 일시적으로만 처리되며 <strong>절대로 저장되지 않습니다</strong>.</li>
          <li>발급된 검증 가능한 자격 증명은 사용자 기기의 Wallet에만 저장되며, 자격 증명 철회를 지원합니다.</li>
        </ul>

        <h3>AppView(읽기용 투영 서비스)</h3>
        <p>AppView는 Relay에 이미 공개된 콘텐츠를 탐색하고 검색하기 위한 읽기 전용 투영입니다. 추가 개인정보를 보유하지 않습니다.</p>

        <h2>데이터가 기기를 벗어나는 경우</h2>
        <p>사용자가 선택한 경우에만 해당합니다. 공개 콘텐츠 게시, 신원 확인 또는 푸시 알림 활성화 시 필요한 데이터가 기기를 벗어납니다. 개인 키와 게시되지 않은 비공개 데이터는 기기를 벗어나지 않습니다.</p>

        <h2>보관 기간</h2>
        <div class="legal-table-wrap">
          <table>
            <thead><tr><th>데이터</th><th>저장 위치</th><th>보관 기간</th></tr></thead>
            <tbody>
              <tr><td>신원 개인 키(Ed25519)</td><td>사용자 기기에만 저장</td><td>로컬 신원을 삭제하거나 앱을 제거할 때까지</td></tr>
              <tr><td>공개 DID, handle</td><td>Relay</td><td>계정이 유지되는 동안(공개 기록)</td></tr>
              <tr><td>서명된 공개 게시물/작업</td><td>Relay</td><td>삭제 시 외부 제공 중단. 기반이 되는 추가 전용 서명 로그는 보존(‘사용자의 권리’ 참조)</td></tr>
              <tr><td>운영 및 조정 기록</td><td>Relay</td><td>거버넌스 및 이의 제기를 위해 보관</td></tr>
              <tr><td>기기 푸시 토큰</td><td>Relay</td><td>기기에서 로그아웃하거나 토큰이 만료될 때까지</td></tr>
              <tr><td>이메일 및 OTP(확인 중)</td><td>Issuer(메모리에만 저장)</td><td>몇 분간 보관 후 확인 완료 시 폐기</td></tr>
              <tr><td>중복 방지 해시 커밋먼트</td><td>Issuer</td><td>보관(비가역적이며 개인정보를 드러낼 수 없음)</td></tr>
              <tr><td>여권 NFC/MobileMoica 데이터</td><td>Issuer(일시 처리)</td><td>확인 과정에서만 처리하며 저장하지 않음</td></tr>
              <tr><td>검증 가능한 자격 증명(VC)</td><td>사용자 기기의 Wallet</td><td>사용자가 보관하며 철회 가능</td></tr>
              <tr><td>IP 주소</td><td>—</td><td>보관하지 않음</td></tr>
              <tr><td>AppView 투영 콘텐츠</td><td>AppView</td><td>Relay의 공개 콘텐츠를 반영하며 삭제도 전파</td></tr>
            </tbody>
          </table>
        </div>

        <h2>사용자의 권리</h2>
        <ul>
          <li><strong>접근 및 이동</strong>: 공개 콘텐츠는 서명되고 이동 가능한 형식이므로 언제든지 접근하거나 다른 호환 서비스로 옮길 수 있습니다.</li>
          <li><strong>삭제</strong>:
            <ul>
              <li>앱에서 로컬 신원을 삭제할 수 있습니다(설정 → 이 기기에서 로그아웃). 그러면 이 기기에서는 해당 신원을 더 이상 사용할 수 없습니다.</li>
              <li>삭제한 콘텐츠는 AppView 및 기타 읽기 화면에서 제거되며, 삭제 내용은 하위 서비스로 전파됩니다.</li>
              <li><strong>정확한 안내</strong>: Relay의 공개 게시물은 추가 전용 서명 로그의 일부입니다. 삭제하면 모든 외부 제공 화면에서 콘텐츠가 제거되지만, 기록의 무결성과 검증 가능성을 유지하기 위해 기반 서명 로그 항목 자체는 보관됩니다.</li>
              <li>계정과 데이터의 전체 삭제를 요청하려면 <a href="mailto:${privacyEmail}">${privacyEmail}</a>로 이메일을 보내 주세요. 합리적인 기간 안에 처리하고 답변하겠습니다. <a href="/account-deletion">계정 및 데이터 삭제</a>도 참조하세요.</li>
            </ul>
          </li>
          <li><strong>자격 증명 철회</strong>: 발급된 검증 가능한 자격 증명은 철회할 수 있습니다.</li>
        </ul>

        <h2>적용 법률</h2>
        <p>서비스는 <strong>대만 개인정보 보호법</strong>에 따라 개인정보를 처리합니다. 정보 주체는 동법 제3조에 규정된 권리(조회, 열람, 사본 제공, 보충, 정정, 처리·이용 중지 및 삭제)를 행사할 수 있습니다. EU/EEA 사용자는 <strong>GDPR</strong>의 적용을 받습니다(법적 근거: 계약 이행 및 신원 확인 등에 대한 명시적 동의). 미국 캘리포니아 사용자는 <strong>CCPA/CPRA</strong>의 적용을 받으며, 서비스는 개인정보를 판매하거나 공유하지 않습니다. 이러한 권리를 행사하려면 <a href="mailto:${privacyEmail}">${privacyEmail}</a>로 연락해 주세요.</p>

        <h2>아동</h2>
        <p>서비스는 만 13세 미만 아동을 대상으로 하지 않습니다. 법정대리인의 동의 없이 만 13세 미만 아동의 개인정보를 처리한 사실을 알게 되면 신속히 삭제합니다.</p>

        <h2>본 방침의 변경</h2>
        <p>본 방침을 변경할 때에는 이 페이지의 시행일을 갱신하며, 중요한 변경 사항은 서비스 내에서 눈에 띄게 알립니다. 서비스를 계속 이용하면 갱신된 방침을 읽은 것으로 간주됩니다.</p>

        <h2>문의</h2>
        <p>개인정보 관련 질문 및 요청: <a href="mailto:${privacyEmail}">${privacyEmail}</a></p>
      `,
    },
    de: {
      title: 'Datenschutzerklärung',
      body: `
        <h1>Datenschutzerklärung</h1>
        <p class="legal-effective">Gültig ab: 7. Juli 2026</p>

        <p>Elix (Domain elix.cool, im Folgenden „der Dienst“) ist eine dezentrale Diskussionsgemeinschaft auf Grundlage selbstbestimmter Identität. Unser Gestaltungsprinzip lautet: Daten verbleiben nach Möglichkeit auf deinem Gerät; Daten, die das Gerät verlassen, werden minimiert, von dir signiert, sind überprüfbar und übertragbar. Diese Erklärung erläutert, welche Daten in welchen Systemen verarbeitet werden, wie lange sie gespeichert werden und welche Rechte du hast.</p>

        <h2>Was wir nicht tun</h2>
        <ul>
          <li>Keine Analyse-, Tracking- oder Werbe-SDKs und kein Tracking-Code von Drittanbietern.</li>
          <li>Keine personenbezogene Telemetrie; Betriebskennzahlen werden ausschließlich zusammengefasst und lassen sich keiner Person zuordnen.</li>
          <li>Wir erfassen oder speichern deinen Standort nicht.</li>
          <li>IP-Adressen werden in keinem dauerhaften Protokoll gespeichert.</li>
          <li>Wir verkaufen, vermieten oder teilen personenbezogene Daten nicht zu Marketingzwecken mit Dritten.</li>
        </ul>

        <h2>Wo Daten gespeichert werden</h2>

        <h3>Dein Gerät</h3>
        <ul>
          <li><strong>Private Identitätsschlüssel (Ed25519)</strong>: werden auf deinem Gerät erzeugt und gespeichert (Softwareverwahrung, gekennzeichnet durch die Verwahrungsklasse custody_class) und von Cloud-Sicherungen ausgeschlossen (noBackupFilesDir unter Android, Dateischutz unter iOS). Private Schlüssel verlassen dein Gerät niemals.</li>
          <li>Deine lokale Datenbank, Entwürfe und die überprüfbaren Nachweise (Verifiable Credentials, VC) in deiner Wallet.</li>
        </ul>

        <h3>Relay (Nachrichtenweiterleitung)</h3>
        <p>Das Relay speichert nur, was du ausdrücklich veröffentlichst:</p>
        <ul>
          <li>Deine öffentliche DID und deinen Handle (Kontobezeichnung).</li>
          <li>Deine signierten öffentlichen Beiträge und Vorgänge — ein manipulationssicheres, nur ergänzbares (append-only) signiertes Protokoll.</li>
          <li>Moderationsaufzeichnungen.</li>
          <li>Push-Token des Geräts (nur als inhaltslose Synchronisierungshinweise).</li>
        </ul>
        <p>Das Relay speichert <strong>keine</strong> E-Mail-Adresse, keinen amtlichen Namen, keine Telefonnummer, nationale Identifikationsnummer oder Standortdaten; IP-Adressen werden nicht dauerhaft gespeichert.</p>

        <h3>Issuer (Identitätsprüfung)</h3>
        <ul>
          <li>Während der Prüfung werden deine E-Mail-Adresse und der Einmalcode (OTP) nur wenige Minuten im Arbeitsspeicher gehalten und anschließend verworfen.</li>
          <li>Um Mehrfachanmeldungen derselben Person zu verhindern (Sybil-Resistenz), wird nur eine schlüsselgebundene, unumkehrbare Hash-Zusage gespeichert; daraus lassen sich weder deine E-Mail-Adresse noch Identitätsdaten wiederherstellen.</li>
          <li>Daten aus dem NFC-Chip des Reisepasses und Daten des taiwanischen MobileMoica (mobiles Bürgerzertifikat) werden während der Prüfung nur vorübergehend verarbeitet und <strong>niemals gespeichert</strong>.</li>
          <li>Ausgestellte überprüfbare Nachweise werden ausschließlich in der Wallet auf deinem Gerät gespeichert; ein Widerruf der Nachweise wird unterstützt.</li>
        </ul>

        <h3>AppView (Leseprojektion)</h3>
        <p>AppView ist eine schreibgeschützte Projektion der bereits öffentlichen Inhalte des Relay für Navigation und Suche. Es werden keine zusätzlichen personenbezogenen Daten gespeichert.</p>

        <h2>Wann Daten dein Gerät verlassen</h2>
        <p>Nur wenn du dich dafür entscheidest: beim Veröffentlichen öffentlicher Inhalte, bei einer Identitätsprüfung oder beim Aktivieren von Push-Benachrichtigungen. Private Schlüssel und unveröffentlichte private Daten verlassen das Gerät nicht.</p>

        <h2>Speicherdauer</h2>
        <div class="legal-table-wrap">
          <table>
            <thead><tr><th>Daten</th><th>Speicherort</th><th>Speicherdauer</th></tr></thead>
            <tbody>
              <tr><td>Private Identitätsschlüssel (Ed25519)</td><td>Nur dein Gerät</td><td>Bis du die lokale Identität löschst oder die App deinstallierst</td></tr>
              <tr><td>Öffentliche DID, Handle</td><td>Relay</td><td>Lebensdauer des Kontos (öffentlicher Datensatz)</td></tr>
              <tr><td>Signierte öffentliche Beiträge/Vorgänge</td><td>Relay</td><td>Nach dem Löschen nicht mehr öffentlich bereitgestellt; das zugrunde liegende nur ergänzbare signierte Protokoll bleibt erhalten (siehe „Deine Rechte“)</td></tr>
              <tr><td>Moderationsaufzeichnungen</td><td>Relay</td><td>Für Governance und Einsprüche gespeichert</td></tr>
              <tr><td>Push-Token des Geräts</td><td>Relay</td><td>Bis zur Abmeldung des Geräts oder zum Ablauf des Tokens</td></tr>
              <tr><td>E-Mail und OTP (während der Prüfung)</td><td>Issuer (nur Arbeitsspeicher)</td><td>Wenige Minuten; nach Abschluss der Prüfung verworfen</td></tr>
              <tr><td>Hash-Zusage zur Verhinderung von Duplikaten</td><td>Issuer</td><td>Gespeichert (unumkehrbar; legt keine personenbezogenen Daten offen)</td></tr>
              <tr><td>Reisepass-NFC-/MobileMoica-Daten</td><td>Issuer (vorübergehend)</td><td>Nur während der Prüfung verarbeitet; nie gespeichert</td></tr>
              <tr><td>Überprüfbare Nachweise (VC)</td><td>Wallet auf deinem Gerät</td><td>Von dir verwahrt; widerrufbar</td></tr>
              <tr><td>IP-Adressen</td><td>—</td><td>Nicht gespeichert</td></tr>
              <tr><td>AppView-Projektion</td><td>AppView</td><td>Spiegelt öffentliche Relay-Inhalte; Löschungen werden übernommen</td></tr>
            </tbody>
          </table>
        </div>

        <h2>Deine Rechte</h2>
        <ul>
          <li><strong>Zugriff und Übertragbarkeit</strong>: Deine öffentlichen Inhalte liegen in einem signierten, übertragbaren Format vor. Du kannst jederzeit darauf zugreifen oder sie zu einem anderen kompatiblen Dienst mitnehmen.</li>
          <li><strong>Löschung</strong>:
            <ul>
              <li>Du kannst deine lokale Identität in der App löschen (Einstellungen → Von diesem Gerät abmelden). Danach kann dieses Gerät die Identität nicht mehr verwenden.</li>
              <li>Von dir gelöschte Inhalte werden aus AppView und anderen Leseoberflächen entfernt; Löschungen werden an nachgelagerte Dienste weitergegeben.</li>
              <li><strong>Transparenter Hinweis</strong>: Öffentliche Beiträge im Relay sind Teil eines nur ergänzbaren signierten Protokolls. Durch das Löschen werden die Inhalte von allen öffentlichen Oberflächen entfernt; die zugrunde liegenden signierten Protokolleinträge bleiben jedoch erhalten, um Integrität und Überprüfbarkeit des Datensatzes zu gewährleisten.</li>
              <li>Für die vollständige Löschung deines Kontos und deiner Daten schreibe an <a href="mailto:${privacyEmail}">${privacyEmail}</a>. Wir bearbeiten und beantworten deine Anfrage innerhalb eines angemessenen Zeitraums. Siehe auch <a href="/account-deletion">Konto- und Datenlöschung</a>.</li>
            </ul>
          </li>
          <li><strong>Widerruf von Nachweisen</strong>: Ausgestellte überprüfbare Nachweise können widerrufen werden.</li>
        </ul>

        <h2>Anwendbares Recht</h2>
        <p>Wir verarbeiten personenbezogene Daten nach dem <strong>taiwanischen Gesetz zum Schutz personenbezogener Daten</strong>. Betroffene können die Rechte nach Artikel 3 ausüben (Auskunft, Einsicht, Kopien, Ergänzung, Berichtigung, Einstellung der Verarbeitung oder Nutzung und Löschung). Für Nutzerinnen und Nutzer in der EU/im EWR gilt die <strong>DSGVO</strong> (Rechtsgrundlagen: Vertragserfüllung und deine ausdrückliche Einwilligung, etwa bei der Identitätsprüfung). Für Personen in Kalifornien gilt der <strong>CCPA/CPRA</strong> — wir verkaufen oder teilen keine personenbezogenen Informationen. Um eines dieser Rechte auszuüben, kontaktiere <a href="mailto:${privacyEmail}">${privacyEmail}</a>.</p>

        <h2>Kinder</h2>
        <p>Der Dienst richtet sich nicht an Kinder unter 13 Jahren. Wenn wir erfahren, dass wir personenbezogene Daten eines Kindes unter 13 Jahren ohne Zustimmung einer gesetzlichen Vertretung verarbeitet haben, löschen wir diese unverzüglich.</p>

        <h2>Änderungen dieser Erklärung</h2>
        <p>Wenn wir diese Erklärung ändern, aktualisieren wir das Datum des Inkrafttretens auf dieser Seite. Wesentliche Änderungen werden im Dienst deutlich angekündigt. Wenn du den Dienst weiter nutzt, bedeutet dies, dass du die aktualisierte Erklärung gelesen hast.</p>

        <h2>Kontakt</h2>
        <p>Fragen und Anfragen zum Datenschutz: <a href="mailto:${privacyEmail}">${privacyEmail}</a></p>
      `,
    },
    it: {
      title: 'Informativa sulla privacy',
      body: `
        <h1>Informativa sulla privacy</h1>
        <p class="legal-effective">Data di entrata in vigore: 7 luglio 2026</p>

        <p>Elix (dominio elix.cool, di seguito «il Servizio») è una comunità di discussione decentralizzata basata sull’identità auto-sovrana. Il nostro principio di progettazione è il seguente: i dati restano sul tuo dispositivo ogni volta che è possibile; ciò che lascia il dispositivo è ridotto al minimo, firmato da te, verificabile e portabile. Questa informativa spiega quali dati vengono trattati nei diversi sistemi, per quanto tempo e quali sono i tuoi diritti.</p>

        <h2>Cosa non facciamo</h2>
        <ul>
          <li>Nessun SDK di analisi, tracciamento o pubblicità e nessun codice di tracciamento di terze parti.</li>
          <li>Nessuna telemetria per singolo utente; le metriche operative sono solo aggregate e non possono essere ricondotte a una persona.</li>
          <li>Non raccogliamo né conserviamo la tua posizione.</li>
          <li>Gli indirizzi IP non vengono registrati in alcun archivio permanente.</li>
          <li>Non vendiamo, affittiamo o condividiamo dati personali con terzi per finalità di marketing.</li>
        </ul>

        <h2>Dove si trovano i dati</h2>

        <h3>Il tuo dispositivo</h3>
        <ul>
          <li><strong>Chiavi private dell’identità (Ed25519)</strong>: generate e conservate sul tuo dispositivo (custodia software, indicata dal livello custody_class) ed escluse dal backup nel cloud (noBackupFilesDir su Android, protezione dei file su iOS). Le chiavi private non lasciano mai il dispositivo.</li>
          <li>Il database locale, le bozze e le credenziali verificabili (Verifiable Credentials, VC) contenute nel tuo Wallet.</li>
        </ul>

        <h3>Relay (servizio di inoltro)</h3>
        <p>Il Relay conserva solo ciò che scegli di rendere pubblico:</p>
        <ul>
          <li>Il tuo DID pubblico e il tuo handle (identificativo dell’account).</li>
          <li>I tuoi post e le tue operazioni pubbliche firmate: un registro firmato, append-only e resistente alle manomissioni.</li>
          <li>I registri di moderazione.</li>
          <li>I token push del dispositivo (usati soltanto come segnali di sincronizzazione senza contenuto).</li>
        </ul>
        <p>Il Relay <strong>non conserva</strong> e-mail, nome legale, numero di telefono, numero di identità nazionale o posizione; gli indirizzi IP non vengono conservati.</p>

        <h3>Issuer (servizio di verifica dell’identità)</h3>
        <ul>
          <li>Durante la verifica, l’indirizzo e-mail e il codice monouso (OTP) restano in memoria soltanto per alcuni minuti e vengono poi eliminati.</li>
          <li>Per impedire registrazioni duplicate della stessa persona (resistenza agli attacchi Sybil), viene conservato solo un commitment hash irreversibile protetto da chiave; non può essere riconvertito nell’indirizzo e-mail o in dati di identità.</li>
          <li>I dati del chip NFC del passaporto e quelli di MobileMoica di Taiwan (certificato cittadino mobile) vengono trattati temporaneamente durante la verifica e <strong>non vengono mai conservati</strong>.</li>
          <li>Le credenziali verificabili emesse sono conservate esclusivamente nel Wallet del tuo dispositivo; è supportata la revoca delle credenziali.</li>
        </ul>

        <h3>AppView (servizio di proiezione per la lettura)</h3>
        <p>AppView è una proiezione in sola lettura dei contenuti già pubblici sul Relay, usata per la consultazione e la ricerca. Non contiene dati personali aggiuntivi.</p>

        <h2>Quando i dati lasciano il dispositivo</h2>
        <p>Solo quando lo scegli: pubblicando contenuti pubblici, effettuando una verifica dell’identità o attivando le notifiche push. Le chiavi private e i dati privati non pubblicati non lasciano il dispositivo.</p>

        <h2>Periodo di conservazione</h2>
        <div class="legal-table-wrap">
          <table>
            <thead><tr><th>Dati</th><th>Dove</th><th>Periodo di conservazione</th></tr></thead>
            <tbody>
              <tr><td>Chiavi private dell’identità (Ed25519)</td><td>Solo sul tuo dispositivo</td><td>Fino alla cancellazione dell’identità locale o alla disinstallazione</td></tr>
              <tr><td>DID pubblico, handle</td><td>Relay</td><td>Per la durata dell’account (registro pubblico)</td></tr>
              <tr><td>Post e operazioni pubbliche firmate</td><td>Relay</td><td>Non più mostrati dopo l’eliminazione; il registro firmato append-only sottostante viene conservato (vedi «I tuoi diritti»)</td></tr>
              <tr><td>Registri di moderazione</td><td>Relay</td><td>Conservati per la governance e i ricorsi</td></tr>
              <tr><td>Token push del dispositivo</td><td>Relay</td><td>Fino alla disconnessione del dispositivo o alla scadenza del token</td></tr>
              <tr><td>E-mail e OTP (durante la verifica)</td><td>Issuer (solo in memoria)</td><td>Alcuni minuti; eliminati al termine della verifica</td></tr>
              <tr><td>Commitment hash per impedire duplicati</td><td>Issuer</td><td>Conservato (irreversibile; non può rivelare dati personali)</td></tr>
              <tr><td>Dati NFC del passaporto / MobileMoica</td><td>Issuer (temporanei)</td><td>Trattati solo durante la verifica; mai conservati</td></tr>
              <tr><td>Credenziali verificabili (VC)</td><td>Wallet del tuo dispositivo</td><td>Conservate da te; revocabili</td></tr>
              <tr><td>Indirizzi IP</td><td>—</td><td>Non conservati</td></tr>
              <tr><td>Proiezione AppView</td><td>AppView</td><td>Rispecchia i contenuti pubblici del Relay; le eliminazioni si propagano</td></tr>
            </tbody>
          </table>
        </div>

        <h2>I tuoi diritti</h2>
        <ul>
          <li><strong>Accesso e portabilità</strong>: i tuoi contenuti pubblici sono in un formato firmato e portabile; puoi accedervi in qualsiasi momento o trasferirli a un altro servizio compatibile.</li>
          <li><strong>Eliminazione</strong>:
            <ul>
              <li>Puoi cancellare l’identità locale dall’app (Impostazioni → Esci da questo dispositivo); il dispositivo non potrà più usare quell’identità.</li>
              <li>I contenuti che elimini vengono rimossi da AppView e dalle altre interfacce di lettura; le eliminazioni vengono propagate ai servizi a valle.</li>
              <li><strong>Nota trasparente</strong>: i post pubblici sul Relay fanno parte di un registro firmato append-only. L’eliminazione rimuove il contenuto da tutte le interfacce di pubblicazione, ma le voci firmate sottostanti vengono conservate per preservare l’integrità e la verificabilità del registro.</li>
              <li>Per richiedere l’eliminazione completa dell’account e dei dati, scrivi a <a href="mailto:${privacyEmail}">${privacyEmail}</a>; elaboreremo la richiesta e risponderemo entro un periodo ragionevole. Vedi anche <a href="/account-deletion">Eliminazione dell’account e dei dati</a>.</li>
            </ul>
          </li>
          <li><strong>Revoca delle credenziali</strong>: le credenziali verificabili emesse possono essere revocate.</li>
        </ul>

        <h2>Legge applicabile</h2>
        <p>Trattiamo i dati personali ai sensi della <strong>Legge taiwanese sulla protezione dei dati personali</strong>; gli interessati possono esercitare i diritti previsti dall’articolo 3 (richiesta di informazioni, consultazione, copie, integrazione, rettifica, cessazione del trattamento o dell’uso e cancellazione). Per gli utenti nell’UE/SEE si applica il <strong>GDPR</strong> (basi giuridiche: esecuzione del contratto e consenso esplicito, ad esempio per la verifica dell’identità). Per gli utenti della California si applica il <strong>CCPA/CPRA</strong>: non vendiamo né condividiamo informazioni personali. Per esercitare uno di questi diritti, contatta <a href="mailto:${privacyEmail}">${privacyEmail}</a>.</p>

        <h2>Minori</h2>
        <p>Il Servizio non è rivolto a minori di 13 anni. Se veniamo a conoscenza di aver trattato dati personali di un minore di 13 anni senza il consenso del rappresentante legale, li elimineremo tempestivamente.</p>

        <h2>Modifiche alla presente informativa</h2>
        <p>Quando modifichiamo questa informativa, aggiorniamo la data di entrata in vigore su questa pagina; le modifiche sostanziali saranno annunciate in modo evidente nel Servizio. Continuando a usare il Servizio dichiari di aver letto l’informativa aggiornata.</p>

        <h2>Contatti</h2>
        <p>Domande e richieste sulla privacy: <a href="mailto:${privacyEmail}">${privacyEmail}</a></p>
      `,
    },
  });
}
