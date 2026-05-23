// screen-credential-admin.jsx — who has access to what; audit + revoke

function ScreenCredentialAdmin() {
  const grants = [
    { who: '週四讀書會',   whoEn: 'CIRCLE',   what: '讀書會 · Tris',  scope: '寫入 · 讀取', when: '92 天' },
    { who: '公開討論',     whoEn: 'PUBLIC',   what: '公開 · Tris',     scope: '只發布',     when: '278 天' },
    { who: 'Tris ↔ kr.',  whoEn: 'PEER',     what: '本人',            scope: '完全互信',   when: '180 天' },
    { who: '同居寫作組',   whoEn: 'CIRCLE',   what: '本人',            scope: '寫入 · 讀取', when: '11 天' },
  ];
  const events = [
    { who: 'kr.',     act: '讀取了「廢墟中的協作」', via: 'circle handle', when: '14:22' },
    { who: '林下',    act: '回覆了一段',            via: 'public handle', when: '13:08' },
    { who: 'iPad',    act: '同步了 6 個 murmur',     via: '本人',          when: '11:40' },
    { who: '路過的人', act: '讀取了公開討論串',      via: 'observer',      when: '昨 22:14' },
    { who: 'kr.',     act: 'passkey 交換',           via: '本人',          when: '180 天前' },
  ];

  return (
    <div className="ph" style={{ height: '100%', paddingTop: 56, paddingBottom: 40, display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 22px 14px' }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.16em' }}>← 設定</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-faint)', letterSpacing: '0.16em' }}>ADMIN</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-faint)', letterSpacing: '0.16em' }}>　</span>
      </div>

      <div style={{ flex: 1, overflowY: 'auto' }}>
        {/* hero */}
        <div style={{ padding: '0 22px 18px' }}>
          <div className="label-mono-sm" style={{ marginBottom: 6 }}>管理 · ADMIN</div>
          <h1 style={{ fontFamily: 'var(--serif)', fontSize: 26, fontWeight: 500, margin: '0 0 6px', color: 'var(--fg)' }}>
            誰看見了哪一個我
          </h1>
          <div style={{ fontFamily: 'var(--serif-en)', fontStyle: 'italic', fontSize: 13, color: 'var(--fg-muted)', marginBottom: 14 }}>
            access &amp; audit
          </div>

          {/* summary numbers */}
          <div style={{
            display: 'grid', gridTemplateColumns: '1fr 1fr 1fr',
            border: '0.5px solid var(--rule)', borderRadius: 6,
          }}>
            {[
              ['4', '正在使用的圈'],
              ['7', '授權中的對接'],
              ['0', '可疑的存取'],
            ].map(([n, l], i) => (
              <div key={i} style={{
                padding: '12px 6px', textAlign: 'center',
                borderRight: i < 2 ? '0.5px solid var(--rule-soft)' : 'none',
              }}>
                <div style={{ fontFamily: 'var(--serif)', fontSize: 22, fontWeight: 500, color: 'var(--fg)' }}>{n}</div>
                <div style={{ fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.14em', color: 'var(--fg-faint)', marginTop: 2 }}>{l}</div>
              </div>
            ))}
          </div>
        </div>

        {/* grants matrix */}
        <div className="label-mono-sm" style={{ padding: '0 22px 8px' }}>授權中 · GRANTS</div>
        <div style={{ borderTop: '0.5px solid var(--rule)', borderBottom: '0.5px solid var(--rule)' }}>
          {grants.map((g, i) => (
            <div key={i} style={{
              padding: '12px 22px',
              borderBottom: i === grants.length - 1 ? 'none' : '0.5px solid var(--rule-soft)',
              display: 'flex', flexDirection: 'column', gap: 6,
            }}>
              <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
                  <span style={{ fontFamily: 'var(--serif)', fontSize: 14, color: 'var(--fg)' }}>{g.who}</span>
                  <span style={{ fontFamily: 'var(--mono)', fontSize: 8.5, letterSpacing: '0.18em', color: 'var(--fg-faint)' }}>{g.whoEn}</span>
                </div>
                <span style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)', letterSpacing: '0.12em' }}>{g.when}</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, fontFamily: 'var(--serif)', fontSize: 12 }}>
                <span style={{ color: 'var(--fg-muted)' }}>用</span>
                <span style={{ color: 'var(--fg)', fontStyle: 'italic' }}>{g.what}</span>
                <span style={{ color: 'var(--fg-faint)' }}>·</span>
                <span style={{ color: 'var(--fg-muted)' }}>{g.scope}</span>
                <span style={{ flex: 1 }}/>
                <span style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--danger)', letterSpacing: '0.12em' }}>撤銷</span>
              </div>
            </div>
          ))}
        </div>

        {/* audit log */}
        <div className="label-mono-sm" style={{ padding: '20px 22px 8px' }}>近期存取 · LOG</div>
        <div style={{ borderTop: '0.5px solid var(--rule)' }}>
          {events.map((e, i, arr) => (
            <div key={i} style={{
              padding: '10px 22px', display: 'flex', gap: 10, alignItems: 'baseline',
              borderBottom: i === arr.length - 1 ? 'none' : '0.5px solid var(--rule-soft)',
              fontFamily: 'var(--serif)', fontSize: 12,
            }}>
              <span style={{ color: 'var(--fg)', minWidth: 56 }}>{e.who}</span>
              <span style={{ flex: 1, color: 'var(--fg-muted)' }}>{e.act}</span>
              <span style={{ fontFamily: 'var(--mono)', fontSize: 8.5, letterSpacing: '0.16em', color: 'var(--fg-faint)' }}>{e.via}</span>
              <span style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)', letterSpacing: '0.1em', minWidth: 52, textAlign: 'right' }}>{e.when}</span>
            </div>
          ))}
        </div>

        {/* danger zone */}
        <div className="label-mono-sm" style={{ padding: '24px 22px 8px', color: 'var(--danger)' }}>不可逆 · IRREVERSIBLE</div>
        <div style={{
          margin: '0 22px',
          border: '0.5px solid var(--danger)', borderRadius: 6,
          padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 12,
        }}>
          {[
            ['撤銷所有非此裝置', '其他裝置與圈會被踢出。可重新授權。'],
            ['焚燒此身分', '所有衍生身分一併消失。其他人裝置上的副本仍存在，但無法再驗證。'],
          ].map(([t, sub], i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'flex-start', gap: 10 }}>
              <div style={{ flex: 1 }}>
                <div style={{ fontFamily: 'var(--serif)', fontSize: 13, color: 'var(--fg)', fontWeight: 500 }}>{t}</div>
                <div style={{ fontFamily: 'var(--serif)', fontSize: 11.5, color: 'var(--fg-muted)', marginTop: 2, lineHeight: 1.55 }}>{sub}</div>
              </div>
              <span style={{
                fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.14em',
                color: 'var(--danger)', padding: '4px 10px',
                border: '0.5px solid var(--danger)', borderRadius: 999,
                whiteSpace: 'nowrap', alignSelf: 'center',
              }}>執行</span>
            </div>
          ))}
        </div>

        <div style={{ height: 24 }}/>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenCredentialAdmin });
