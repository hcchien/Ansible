// screen-settings-home.jsx — root settings screen

function ScreenSettingsHome() {
  const Row = ({ glyph, label, en, sub, value, last, danger }) => (
    <div style={{
      padding: '13px 22px', display: 'flex', alignItems: 'center', gap: 12,
      borderBottom: last ? 'none' : '0.5px solid var(--rule-soft)',
    }}>
      <div style={{
        width: 26, height: 26, borderRadius: 4,
        border: '0.5px solid var(--rule)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontFamily: 'var(--mono)', fontSize: 12, color: danger ? 'var(--danger)' : 'var(--fg-muted)',
        flexShrink: 0,
      }}>{glyph}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
          <span style={{ fontFamily: 'var(--serif)', fontSize: 14.5, color: danger ? 'var(--danger)' : 'var(--fg)' }}>{label}</span>
          <span style={{ fontFamily: 'var(--mono)', fontSize: 8.5, letterSpacing: '0.18em', color: 'var(--fg-faint)' }}>{en}</span>
        </div>
        {sub && <div style={{ fontFamily: 'var(--serif)', fontSize: 11.5, color: 'var(--fg-faint)', marginTop: 2 }}>{sub}</div>}
      </div>
      {value && <span style={{ fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-muted)', letterSpacing: '0.14em' }}>{value}</span>}
      <span style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--fg-faint)' }}>›</span>
    </div>
  );

  const Section = ({ label, children }) => (
    <>
      <div className="label-mono-sm" style={{ padding: '18px 22px 8px' }}>{label}</div>
      <div style={{ borderTop: '0.5px solid var(--rule)', borderBottom: '0.5px solid var(--rule)' }}>
        {children}
      </div>
    </>
  );

  return (
    <div className="ph" style={{ height: '100%', paddingTop: 56, paddingBottom: 40, display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 22px 14px' }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-faint)', letterSpacing: '0.16em' }}>　</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-faint)', letterSpacing: '0.16em' }}>SETTINGS</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.16em' }}>完成</span>
      </div>

      <div style={{ flex: 1, overflowY: 'auto' }}>
        {/* you */}
        <div style={{ padding: '0 22px 18px', display: 'flex', alignItems: 'center', gap: 14 }}>
          <div style={{
            width: 52, height: 52, borderRadius: '50%',
            background: 'var(--accent-soft)', border: '0.5px solid var(--accent)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontFamily: 'var(--serif)', fontSize: 22, color: 'var(--accent)',
          }}>T</div>
          <div style={{ flex: 1 }}>
            <div style={{ fontFamily: 'var(--serif)', fontSize: 18, fontWeight: 500, color: 'var(--fg)' }}>Tris</div>
            <div style={{ fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-faint)', letterSpacing: '0.12em', marginTop: 3 }}>4 個身分 · 3 台裝置 · 3 個圈</div>
          </div>
          <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.14em' }}>編輯</span>
        </div>

        <Section label="身分與裝置 · IDENTITY">
          <Row glyph="◎" label="錢包" en="WALLET" sub="4 個身分 · 公開 / 圈內 / 本人" value="4"/>
          <Row glyph="↔" label="同步" en="SYNC" sub="3 台裝置 · 點對點" value="已同步"/>
          <Row glyph="□" label="存取與審計" en="ADMIN" sub="誰看見了哪一個我" value="0 可疑" last/>
        </Section>

        <Section label="日常 · DAILY">
          <Row glyph="◐" label="收信" en="INBOX" sub="圈內回覆、新成員、同步" value="3"/>
          <Row glyph="◇" label="通知" en="NOTIFICATIONS" sub="決定哪些事會打擾你" value="輕"/>
          <Row glyph="A" label="閱讀偏好" en="READING" sub="字級、行距、主題" value="松茸 · 大" last/>
        </Section>

        <Section label="邊界 · BOUNDARIES">
          <Row glyph="●" label="鎖定" en="LOCK" sub="把 app 變成空白封面" value="關閉"/>
          <Row glyph="⌷" label="備份與還原" en="RECOVERY" sub="passphrase、新裝置遷移" value="未設"/>
          <Row glyph="⊘" label="封鎖名單" en="BLOCKED" sub="你看不到，他們也看不到你" value="0" last/>
        </Section>

        <Section label="關於 · ABOUT">
          <Row glyph="i" label="關於 Ansible" en="ABOUT" sub="信號越過星際的距離"/>
          <Row glyph="?" label="使用手冊" en="MANUAL"/>
          <Row glyph="!" label="登出此裝置" en="SIGN OUT" sub="保留資料；下次需要 passkey" danger last/>
        </Section>

        <div style={{
          padding: '20px 22px 8px', textAlign: 'center',
          fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-faint)', letterSpacing: '0.14em',
        }}>
          ANSIBLE · v0.7.2 · LOCAL-FIRST
        </div>
        <div style={{ height: 24 }}/>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenSettingsHome });
