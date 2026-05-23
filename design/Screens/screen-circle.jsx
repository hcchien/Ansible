// screen-circle.jsx — passkey-based trusted circle detail

function ScreenCircle() {
  const members = [
    { glyph: 'T', name: 'Tris', sub: '你 · 發起人',           role: 'founder',  on: true },
    { glyph: 'k', name: 'kr.',  sub: 'passkey 已交換 · 18 天', role: 'writer',   on: true },
    { glyph: '林', name: '林下', sub: 'passkey 已交換 · 11 天', role: 'writer',   on: true },
    { glyph: '路', name: '路過的人', sub: '昨日加入',          role: 'observer', on: false },
  ];
  const roleLabel = { founder: '發起人', writer: '可發布', observer: '僅瀏覽' };
  const roleEn    = { founder: 'FOUNDER', writer: 'WRITER', observer: 'OBSERVER' };

  return (
    <div className="ph" style={{
      height: '100%', paddingTop: 56, paddingBottom: 40,
      display: 'flex', flexDirection: 'column',
    }}>
      {/* nav */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 22px 14px' }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.16em' }}>← 圈</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.16em' }}>···</span>
      </div>

      <div style={{ flex: 1, overflowY: 'auto' }}>
        {/* circle masthead */}
        <div style={{ padding: '0 22px 18px' }}>
          <div className="label-mono-sm" style={{ marginBottom: 6 }}>圈 · CIRCLE</div>
          <div style={{ fontFamily: 'var(--serif)', fontSize: 28, fontWeight: 500, lineHeight: 1.15, color: 'var(--fg)' }}>
            松茸圈
          </div>
          <div style={{ fontFamily: 'var(--serif-en)', fontStyle: 'italic', fontSize: 14, color: 'var(--fg-muted)', marginTop: 2 }}>
            matsutake circle
          </div>

          {/* circle meta */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginTop: 14, flexWrap: 'wrap' }}>
            <span style={{
              display: 'inline-flex', alignItems: 'center', gap: 6,
              fontFamily: 'var(--mono)', fontSize: 9.5, letterSpacing: '0.14em',
              color: 'var(--fg-muted)',
            }}>
              <svg width="10" height="10" viewBox="0 0 10 10">
                <circle cx="5" cy="5" r="3" fill="none" stroke="var(--spore)" strokeWidth="0.8"/>
                <circle cx="5" cy="5" r="1" fill="var(--spore)"/>
              </svg>
              本地 · LOCAL
            </span>
            <span style={{ fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-faint)', letterSpacing: '0.14em' }}>4 個成員</span>
            <span style={{ fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-faint)', letterSpacing: '0.14em' }}>無伺服器</span>
          </div>
        </div>

        {/* members */}
        <div className="label-mono-sm" style={{ padding: '4px 22px 8px' }}>成員 · MEMBERS</div>
        <div style={{ borderTop: '0.5px solid var(--rule)', borderBottom: '0.5px solid var(--rule)' }}>
          {members.map((m, i) => (
            <div key={i} style={{
              padding: '12px 22px', display: 'flex', alignItems: 'center', gap: 12,
              borderBottom: i === members.length - 1 ? 'none' : '0.5px solid var(--rule-soft)',
            }}>
              {/* glyph avatar */}
              <div style={{
                width: 34, height: 34, borderRadius: '50%',
                background: m.role === 'founder' ? 'var(--accent-soft)' : 'var(--bg-soft)',
                border: '0.5px solid ' + (m.role === 'founder' ? 'var(--accent)' : 'var(--rule)'),
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                fontFamily: 'var(--serif)', fontSize: 14,
                color: m.role === 'founder' ? 'var(--accent)' : 'var(--fg-muted)',
                flexShrink: 0,
              }}>{m.glyph}</div>

              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontFamily: 'var(--serif)', fontSize: 14.5, color: 'var(--fg)' }}>{m.name}</div>
                <div style={{ fontFamily: 'var(--serif)', fontSize: 11.5, color: 'var(--fg-faint)', marginTop: 2 }}>{m.sub}</div>
              </div>

              <div style={{ textAlign: 'right' }}>
                <div style={{ fontFamily: 'var(--serif)', fontSize: 11.5, color: 'var(--fg-muted)' }}>{roleLabel[m.role]}</div>
                <div style={{ fontFamily: 'var(--mono)', fontSize: 8, color: 'var(--fg-faint)', letterSpacing: '0.18em', marginTop: 1 }}>{roleEn[m.role]}</div>
              </div>
            </div>
          ))}
        </div>

        {/* invite */}
        <div style={{ padding: '14px 22px' }}>
          <div style={{
            padding: '14px 16px', borderRadius: 8,
            border: '0.5px dashed var(--rule)',
            display: 'flex', alignItems: 'center', gap: 12,
          }}>
            <svg width="22" height="22" viewBox="0 0 22 22" style={{ flexShrink: 0 }}>
              <circle cx="11" cy="9" r="3.5" fill="none" stroke="var(--fg-muted)" strokeWidth="1"/>
              <path d="M 11 12.5 v 5 M 8.5 15 h 5" stroke="var(--fg-muted)" strokeWidth="1" strokeLinecap="round"/>
            </svg>
            <div style={{ flex: 1 }}>
              <div style={{ fontFamily: 'var(--serif)', fontSize: 13.5, color: 'var(--fg)' }}>邀請新成員</div>
              <div style={{ fontFamily: 'var(--serif)', fontSize: 11.5, color: 'var(--fg-faint)', marginTop: 2 }}>
                透過 passkey 直接交換 · 無中介伺服器
              </div>
            </div>
            <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.14em' }}>＋</span>
          </div>
        </div>

        {/* boundaries / rules */}
        <div className="label-mono-sm" style={{ padding: '12px 22px 8px' }}>邊界 · RULES</div>
        <div style={{ padding: '0 22px', display: 'flex', flexDirection: 'column', gap: 10 }}>
          {[
            ['圈內成員都能寫', '回覆與筆記都共享在這個圈裡。'],
            ['同步靠 passkey', '每對成員之間直接交換，沒有中央伺服器。'],
            ['退出即不可見', '離開的人裝置上會保留副本，但同步停止。'],
          ].map(([t, sub], i) => (
            <div key={i} style={{ display: 'flex', gap: 12, alignItems: 'flex-start' }}>
              <span style={{
                width: 14, marginTop: 5, height: 1, background: 'var(--fg-faint)', flexShrink: 0,
              }}/>
              <div style={{ flex: 1 }}>
                <div style={{ fontFamily: 'var(--serif)', fontSize: 13, color: 'var(--fg)', fontWeight: 500 }}>{t}</div>
                <div style={{ fontFamily: 'var(--serif)', fontSize: 12, color: 'var(--fg-muted)', marginTop: 2, lineHeight: 1.55 }}>{sub}</div>
              </div>
            </div>
          ))}
        </div>

        {/* recent activity */}
        <div className="label-mono-sm" style={{ padding: '20px 22px 8px' }}>最近 · RECENT</div>
        <div style={{ borderTop: '0.5px solid var(--rule)' }}>
          {[
            { who: '林下',  what: '發了「廢墟中的協作」', when: '2小時' },
            { who: 'kr.',   what: '留下一個 murmur',       when: '今晨' },
            { who: '你',    what: '加入了路過的人',        when: '昨日' },
            { who: '林下',  what: '回覆了一段討論',        when: '3 天' },
          ].map((e, i, arr) => (
            <div key={i} style={{
              padding: '11px 22px', display: 'flex', gap: 10, alignItems: 'baseline',
              borderBottom: i === arr.length - 1 ? 'none' : '0.5px solid var(--rule-soft)',
            }}>
              <span style={{ fontFamily: 'var(--serif)', fontSize: 12.5, color: 'var(--fg)', minWidth: 56 }}>{e.who}</span>
              <span style={{ flex: 1, fontFamily: 'var(--serif)', fontSize: 12.5, color: 'var(--fg-muted)' }}>{e.what}</span>
              <span style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)', letterSpacing: '0.14em' }}>{e.when}</span>
            </div>
          ))}
        </div>

        <div style={{ height: 24 }}/>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenCircle });
