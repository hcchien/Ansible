// screen-sync-settings.jsx — calm sync surface for local-first

function ScreenSyncSettings() {
  const Device = ({ glyph, name, sub, status, here }) => (
    <div style={{
      padding: '12px 22px', display: 'flex', alignItems: 'center', gap: 12,
      borderBottom: '0.5px solid var(--rule-soft)',
    }}>
      <div style={{
        width: 30, height: 30, borderRadius: 6,
        border: '0.5px solid var(--rule)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontFamily: 'var(--mono)', fontSize: 13, color: 'var(--fg-muted)',
        flexShrink: 0,
      }}>{glyph}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
          <span style={{ fontFamily: 'var(--serif)', fontSize: 14, color: 'var(--fg)' }}>{name}</span>
          {here && <span style={{
            fontFamily: 'var(--mono)', fontSize: 8, letterSpacing: '0.18em', color: 'var(--accent)',
            padding: '1px 5px', border: '0.5px solid var(--accent)', borderRadius: 2,
          }}>此裝置</span>}
        </div>
        <div style={{ fontFamily: 'var(--serif)', fontSize: 11.5, color: 'var(--fg-faint)', marginTop: 2 }}>{sub}</div>
      </div>
      <span style={{
        fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.14em',
        color: status === 'live' ? 'var(--spore)' : status === 'paused' ? 'var(--fg-faint)' : 'var(--fg-muted)',
        textTransform: 'uppercase',
      }}>{status === 'live' ? '已同步' : status === 'paused' ? '暫停' : '落後 3'}</span>
    </div>
  );

  const CircleRow = ({ name, members, when, status }) => (
    <div style={{
      padding: '12px 22px', display: 'flex', alignItems: 'center', gap: 12,
      borderBottom: '0.5px solid var(--rule-soft)',
    }}>
      <div style={{
        width: 26, height: 26, borderRadius: '50%',
        background: 'var(--bg-soft)', border: '0.5px solid var(--rule)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontFamily: 'var(--serif)', fontSize: 11, color: 'var(--fg-muted)', flexShrink: 0,
      }}>{name[0]}</div>
      <div style={{ flex: 1 }}>
        <div style={{ fontFamily: 'var(--serif)', fontSize: 14, color: 'var(--fg)' }}>{name}</div>
        <div style={{ fontFamily: 'var(--serif)', fontSize: 11.5, color: 'var(--fg-faint)', marginTop: 2 }}>{members} 人 · 上次 {when}</div>
      </div>
      <span style={{
        width: 8, height: 8, borderRadius: '50%',
        background: status === 'live' ? 'var(--spore)' : status === 'paused' ? 'var(--rule)' : 'var(--accent)',
      }}/>
    </div>
  );

  const Toggle = ({ on }) => (
    <div style={{
      width: 32, height: 18, borderRadius: 999,
      background: on ? 'var(--fg)' : 'var(--bg-deep)',
      border: '0.5px solid ' + (on ? 'var(--fg)' : 'var(--rule)'),
      position: 'relative', flexShrink: 0,
    }}>
      <div style={{
        position: 'absolute', top: 1.5, left: on ? 15 : 1.5,
        width: 13, height: 13, borderRadius: '50%',
        background: on ? 'var(--bg)' : 'var(--fg-faint)',
      }}/>
    </div>
  );

  const SwitchRow = ({ label, sub, on, last }) => (
    <div style={{
      padding: '12px 22px', display: 'flex', alignItems: 'center', gap: 12,
      borderBottom: last ? 'none' : '0.5px solid var(--rule-soft)',
    }}>
      <div style={{ flex: 1 }}>
        <div style={{ fontFamily: 'var(--serif)', fontSize: 14, color: 'var(--fg)' }}>{label}</div>
        {sub && <div style={{ fontFamily: 'var(--serif)', fontSize: 11.5, color: 'var(--fg-faint)', marginTop: 2, lineHeight: 1.5 }}>{sub}</div>}
      </div>
      <Toggle on={on}/>
    </div>
  );

  return (
    <div className="ph" style={{ height: '100%', paddingTop: 56, paddingBottom: 40, display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 22px 14px' }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.16em' }}>← 設定</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-faint)', letterSpacing: '0.16em' }}>SYNC</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-faint)', letterSpacing: '0.16em' }}>　</span>
      </div>

      <div style={{ flex: 1, overflowY: 'auto' }}>
        {/* hero */}
        <div style={{ padding: '0 22px 18px' }}>
          <div className="label-mono-sm" style={{ marginBottom: 6 }}>同步 · SYNC</div>
          <h1 style={{ fontFamily: 'var(--serif)', fontSize: 26, fontWeight: 500, margin: '0 0 12px', color: 'var(--fg)' }}>
            點對點 · 無雲
          </h1>
          <div style={{
            padding: 14, borderRadius: 6, background: 'var(--bg-soft)',
            display: 'flex', gap: 12, alignItems: 'flex-start',
          }}>
            <svg width="18" height="18" viewBox="0 0 18 18" style={{ flexShrink: 0, marginTop: 2 }}>
              <circle cx="4" cy="9" r="2" fill="var(--accent)"/>
              <circle cx="14" cy="9" r="2" fill="none" stroke="var(--accent)" strokeWidth="0.8"/>
              <path d="M 4 9 Q 9 3 14 9" stroke="var(--accent)" strokeWidth="0.8" fill="none" strokeDasharray="1.5 1.5"/>
            </svg>
            <div style={{ fontFamily: 'var(--serif)', fontSize: 12.5, lineHeight: 1.6, color: 'var(--fg-muted)' }}>
              你的內容只在你信任的裝置與圈裡流動。沒有伺服器在中間留副本。
            </div>
          </div>
        </div>

        {/* my devices */}
        <div className="label-mono-sm" style={{ padding: '0 22px 8px' }}>我的裝置 · DEVICES</div>
        <div style={{ borderTop: '0.5px solid var(--rule)', borderBottom: '0.5px solid var(--rule)' }}>
          <Device glyph="◐" name="iPhone (Tris)" sub="iOS 18 · 加入 312 天" status="live" here/>
          <Device glyph="□" name="MacBook Air"   sub="macOS · 加入 280 天"  status="live"/>
          <Device glyph="◇" name="iPad mini"    sub="iOS 18 · 加入 41 天"  status="behind"/>
          <Device glyph="○" name="舊手機"        sub="已暫停同步"          status="paused"/>
        </div>

        {/* circles */}
        <div className="label-mono-sm" style={{ padding: '20px 22px 8px' }}>同步的圈 · CIRCLES</div>
        <div style={{ borderTop: '0.5px solid var(--rule)', borderBottom: '0.5px solid var(--rule)' }}>
          <CircleRow name="週四讀書會" members={4} when="2 小時前" status="live"/>
          <CircleRow name="同居寫作組" members={2} when="今晨"     status="live"/>
          <CircleRow name="Tris ↔ kr." members={2} when="昨日"     status="paused"/>
        </div>

        {/* advanced */}
        <div className="label-mono-sm" style={{ padding: '20px 22px 8px' }}>進階 · ADVANCED</div>
        <div style={{ borderTop: '0.5px solid var(--rule)', borderBottom: '0.5px solid var(--rule)' }}>
          <SwitchRow label="只在 Wi-Fi 同步" sub="行動網路時暫停" on={true}/>
          <SwitchRow label="附件大檔同步" sub="預設只同步文字" on={false}/>
          <SwitchRow label="背景同步" sub="App 關閉時也保持" on={true} last/>
        </div>

        <div style={{ padding: '14px 22px 0' }}>
          <div style={{
            fontFamily: 'var(--serif)', fontStyle: 'italic',
            fontSize: 11.5, color: 'var(--fg-faint)', lineHeight: 1.6,
          }}>
            一切都是端到端加密的。連我們也讀不到。
          </div>
        </div>

        <div style={{ height: 24 }}/>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenSyncSettings });
