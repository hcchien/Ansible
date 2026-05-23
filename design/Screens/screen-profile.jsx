// screen-profile.jsx — public-facing identity page (someone else's view)

function ScreenProfile() {
  return (
    <div className="ph" style={{ height: '100%', paddingTop: 56, paddingBottom: 40, display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 22px 14px' }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.16em' }}>← 討論串</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.16em' }}>···</span>
      </div>

      <div style={{ flex: 1, overflowY: 'auto' }}>
        {/* identity card */}
        <div style={{ padding: '0 22px 18px' }}>
          <div className="label-mono-sm" style={{ marginBottom: 10 }}>公開身分 · PUBLIC HANDLE</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 14 }}>
            <div style={{
              width: 60, height: 60, borderRadius: '50%',
              background: 'var(--bg-soft)', border: '0.5px solid var(--rule)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontFamily: 'var(--serif)', fontSize: 26, color: 'var(--fg-muted)', flexShrink: 0,
            }}>林</div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontFamily: 'var(--serif)', fontSize: 22, fontWeight: 500, color: 'var(--fg)' }}>林下</div>
              <div style={{ fontFamily: 'var(--serif-en)', fontStyle: 'italic', fontSize: 13, color: 'var(--fg-muted)', marginTop: 1 }}>under-the-canopy</div>
              <div style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)', letterSpacing: '0.14em', marginTop: 4, wordBreak: 'break-all' }}>pk · a3f1 … 2c9b</div>
            </div>
          </div>

          {/* bio */}
          <div style={{ fontFamily: 'var(--serif)', fontSize: 13.5, lineHeight: 1.7, color: 'var(--fg)' }}>
            在台北的某個老房子裡寫字。最近在想 patches、補丁、與不必修復的鬆動感。
          </div>

          {/* meta row */}
          <div style={{
            display: 'flex', gap: 14, marginTop: 14, flexWrap: 'wrap',
            fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-faint)', letterSpacing: '0.12em',
          }}>
            <span>加入 · 312 天</span>
            <span>·</span>
            <span>3 個共同的圈</span>
            <span>·</span>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
              <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--spore)' }}/>
              <span>14 分前在線</span>
            </span>
          </div>

          {/* actions */}
          <div style={{ display: 'flex', gap: 8, marginTop: 16 }}>
            <button style={{
              flex: 1, padding: '10px 14px', borderRadius: 999,
              background: 'var(--fg)', color: 'var(--bg)', border: 'none',
              fontFamily: 'var(--serif)', fontSize: 13, letterSpacing: '0.04em',
            }}>追蹤公開發布</button>
            <button style={{
              padding: '10px 14px', borderRadius: 999,
              background: 'transparent', color: 'var(--fg)',
              border: '0.5px solid var(--rule)',
              fontFamily: 'var(--serif)', fontSize: 13,
            }}>邀請進圈</button>
          </div>
        </div>

        {/* trust note */}
        <div style={{ padding: '0 22px 18px' }}>
          <div style={{
            padding: 12, borderRadius: 6, background: 'var(--bg-soft)',
            display: 'flex', gap: 10, alignItems: 'flex-start',
          }}>
            <svg width="14" height="14" viewBox="0 0 14 14" style={{ flexShrink: 0, marginTop: 2 }}>
              <circle cx="7" cy="7" r="5.5" fill="none" stroke="var(--fg-muted)" strokeWidth="0.8"/>
              <path d="M 7 4 v 4" stroke="var(--fg-muted)" strokeWidth="1"/>
              <circle cx="7" cy="10" r="0.7" fill="var(--fg-muted)"/>
            </svg>
            <div style={{ fontFamily: 'var(--serif)', fontSize: 11.5, lineHeight: 1.6, color: 'var(--fg-muted)' }}>
              你看到的是「公開 · 林下」這個身分。「圈內」與「本人」對你不可見。
            </div>
          </div>
        </div>

        {/* public posts */}
        <div className="label-mono-sm" style={{ padding: '0 22px 8px' }}>公開發布 · PUBLIC · 18</div>
        <div style={{ borderTop: '0.5px solid var(--rule)', borderBottom: '0.5px solid var(--rule)' }}>
          {[
            { title: '我們在「廢墟」裡到底在尋找什麼？', sub: '23 回 · 2 小時前', tag: 'PHIL' },
            { title: '一個老房子的牆角', sub: '7 回 · 昨日', tag: 'NOTE' },
            { title: '為什麼我們抗拒「重建」這個詞', sub: '4 回 · 5 天', tag: 'PHIL' },
            { title: '寫不下去的時候——一個方法', sub: '11 回 · 11 天', tag: 'TOOL' },
          ].map((p, i, a) => (
            <div key={i} style={{
              padding: '12px 22px',
              borderBottom: i === a.length - 1 ? 'none' : '0.5px solid var(--rule-soft)',
              display: 'flex', flexDirection: 'column', gap: 4,
            }}>
              <span style={{ fontFamily: 'var(--mono)', fontSize: 8.5, letterSpacing: '0.18em', color: 'var(--fg-faint)' }}>{p.tag}</span>
              <span style={{ fontFamily: 'var(--serif)', fontSize: 14.5, color: 'var(--fg)', fontWeight: 500 }}>{p.title}</span>
              <span style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)', letterSpacing: '0.12em' }}>{p.sub}</span>
            </div>
          ))}
        </div>

        <div style={{ height: 24 }}/>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenProfile });
