// screen-murmur-detail.jsx — single murmur with forward lineage (which notes it lives in)

function ScreenMurmurDetail() {
  return (
    <div className="ph" style={{ height: '100%', paddingTop: 56, paddingBottom: 40, display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 22px 14px' }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.16em' }}>← 草地</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-faint)', letterSpacing: '0.16em' }}>MURMUR</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.16em' }}>···</span>
      </div>

      <div style={{ flex: 1, overflowY: 'auto' }}>
        {/* origin marker */}
        <div style={{ padding: '0 22px 8px', display: 'flex', alignItems: 'center', gap: 10 }}>
          <span style={{ fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.18em', color: 'var(--fg-faint)' }}>2025·11·14 · 14:22</span>
          <span style={{ flex: 1, height: 0.5, background: 'var(--rule)' }}/>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.14em', color: 'var(--fg-muted)' }}>
            <span style={{ width: 5, height: 5, borderRadius: '50%', background: 'var(--fg-muted)' }}/>
            私人
          </span>
        </div>

        {/* murmur body */}
        <div style={{ padding: '12px 22px 22px' }}>
          <div style={{
            fontFamily: 'var(--serif)', fontSize: 22, lineHeight: 1.55,
            color: 'var(--fg)', fontWeight: 400,
            borderLeft: '2px solid var(--accent)', paddingLeft: 16,
            fontStyle: 'italic',
          }}>
            如果信任是一種地形而非通道，那我們就不需要建橋。我們需要學會在凹陷處停留。
          </div>
          <div style={{
            display: 'flex', gap: 16, marginTop: 14,
            fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-faint)', letterSpacing: '0.12em',
          }}>
            <span>34 字</span>
            <span>·</span>
            <span>3 個 note 引用了它</span>
            <span>·</span>
            <span>1 次被討論</span>
          </div>
        </div>

        {/* lineage forward — where it grew into */}
        <div className="label-mono-sm" style={{ padding: '6px 22px 10px' }}>長進了 · GREW INTO</div>
        <div style={{ padding: '0 22px', display: 'flex', flexDirection: 'column', gap: 0 }}>
          {[
            { title: '廢墟中的協作', when: '2 天後',  count: 6, viz: 'circle', mine: true },
            { title: '荒涼感作為一種介面語言', when: '5 天後', count: 4, viz: 'public', mine: true },
            { title: '為什麼我們抗拒重建', when: '11 天後', count: 8, viz: 'private', mine: true },
          ].map((n, i, a) => (
            <div key={i} style={{ display: 'flex', gap: 14 }}>
              {/* timeline rail */}
              <div style={{ width: 14, position: 'relative', flexShrink: 0 }}>
                <div style={{
                  position: 'absolute', left: 6, top: 0, bottom: i === a.length - 1 ? '50%' : 0,
                  width: 0.5, background: 'var(--rule)',
                }}/>
                <div style={{
                  position: 'absolute', left: 3, top: 18,
                  width: 7, height: 7, borderRadius: '50%',
                  background: 'var(--bg)', border: '0.5px solid var(--fg)',
                }}/>
              </div>
              <div style={{
                flex: 1, padding: '14px 0',
                borderBottom: i === a.length - 1 ? 'none' : '0.5px solid var(--rule-soft)',
              }}>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
                  <span style={{ fontFamily: 'var(--mono)', fontSize: 8.5, letterSpacing: '0.18em', color: 'var(--fg-faint)' }}>NOTE</span>
                  <span style={{ width: 4, height: 4, borderRadius: '50%',
                    background: n.viz === 'private' ? 'var(--fg-muted)' : n.viz === 'circle' ? 'var(--accent)' : 'var(--spore)' }}/>
                  <span style={{ flex: 1 }}/>
                  <span style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)', letterSpacing: '0.1em' }}>{n.when}</span>
                </div>
                <div style={{ fontFamily: 'var(--serif)', fontSize: 14.5, fontWeight: 500, color: 'var(--fg)', marginTop: 5 }}>{n.title}</div>
                <div style={{ fontFamily: 'var(--serif)', fontStyle: 'italic', fontSize: 11.5, color: 'var(--fg-muted)', marginTop: 3 }}>
                  與另外 {n.count - 1} 個 murmur 一起構成
                </div>
              </div>
            </div>
          ))}

          {/* growth edge */}
          <div style={{ display: 'flex', gap: 14, marginTop: 4 }}>
            <div style={{ width: 14, position: 'relative', flexShrink: 0 }}>
              <div style={{
                position: 'absolute', left: 3, top: 14, width: 7, height: 7,
                borderRadius: '50%', border: '0.5px dashed var(--rule)', background: 'var(--bg)',
              }}/>
            </div>
            <div style={{ flex: 1, padding: '12px 0' }}>
              <span style={{ fontFamily: 'var(--serif)', fontStyle: 'italic', fontSize: 12.5, color: 'var(--fg-faint)' }}>
                還可以再長下去——把它放進新的筆記
              </span>
            </div>
          </div>
        </div>

        {/* discussion ref */}
        <div className="label-mono-sm" style={{ padding: '20px 22px 8px' }}>被引用 · QUOTED · 1</div>
        <div style={{ borderTop: '0.5px solid var(--rule)', borderBottom: '0.5px solid var(--rule)' }}>
          <div style={{ padding: '12px 22px' }}>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 4 }}>
              <span style={{ fontFamily: 'var(--mono)', fontSize: 8.5, letterSpacing: '0.18em', color: 'var(--fg-faint)' }}>THRD · PHIL</span>
              <span style={{ flex: 1 }}/>
              <span style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)', letterSpacing: '0.1em' }}>1 小時前</span>
            </div>
            <div style={{ fontFamily: 'var(--serif)', fontSize: 13.5, color: 'var(--fg)', fontWeight: 500 }}>
              我們在「廢墟」裡到底在尋找什麼？
            </div>
            <div style={{ fontFamily: 'var(--serif)', fontStyle: 'italic', fontSize: 12, color: 'var(--fg-muted)', marginTop: 4 }}>
              kr.：「凹陷處停留」這個說法很準。
            </div>
          </div>
        </div>

        <div style={{ height: 24 }}/>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenMurmurDetail });
