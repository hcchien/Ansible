// screen-onboarding-promise.jsx — local-first commitment, calm system message

function ScreenOnboardingPromise() {
  return (
    <div className="ph" style={{
      height: '100%', paddingTop: 56, paddingBottom: 44,
      display: 'flex', flexDirection: 'column',
      background: 'var(--bg)',
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '8px 22px',
      }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-faint)', letterSpacing: '0.18em' }}>← 上一步</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-faint)', letterSpacing: '0.18em' }}>2 / 3</span>
      </div>

      <div style={{ flex: 1, padding: '24px 22px 0', display: 'flex', flexDirection: 'column', gap: 20 }}>
        <div style={{
          fontFamily: 'var(--mono)', fontSize: 9.5, letterSpacing: '0.2em',
          color: 'var(--fg-faint)', textTransform: 'uppercase',
        }}>本地優先 · LOCAL FIRST</div>

        <div style={{
          fontFamily: 'var(--serif)', fontSize: 24, lineHeight: 1.45,
          color: 'var(--fg)', fontWeight: 500,
        }}>
          這是一個會跟你<br/>
          一起變舊的地方。
        </div>

        <div style={{
          fontFamily: 'var(--serif)', fontSize: 13.5, lineHeight: 1.75,
          color: 'var(--fg-muted)',
        }}>
          所有寫下來的東西，預設只在你的裝置裡；不上雲，不索引，不分析。要送出去之前，會先問你。
        </div>

        {/* What stays / what leaves */}
        <div style={{
          marginTop: 8,
          border: '0.5px solid var(--rule)', borderRadius: 14,
          overflow: 'hidden',
        }}>
          <div style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            padding: '12px 16px',
            borderBottom: '0.5px solid var(--rule-soft)',
            background: 'var(--bg-soft)',
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--spore)' }}/>
              <span style={{ fontFamily: 'var(--serif)', fontSize: 13, color: 'var(--fg)' }}>留在你這裡</span>
            </div>
            <span style={{ fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.14em', color: 'var(--fg-faint)' }}>STAYS LOCAL</span>
          </div>
          {['碎念與筆記的內容', '寫作的時序與停頓', '草稿與沒寄出的句子'].map((t, i) => (
            <div key={i} style={{
              padding: '10px 16px',
              borderBottom: '0.5px solid var(--rule-soft)',
              fontFamily: 'var(--serif)', fontSize: 13, color: 'var(--fg)',
            }}>· {t}</div>
          ))}

          <div style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            padding: '12px 16px',
            borderTop: '0.5px solid var(--rule)',
            borderBottom: '0.5px solid var(--rule-soft)',
            background: 'var(--bg-soft)',
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--accent)' }}/>
              <span style={{ fontFamily: 'var(--serif)', fontSize: 13, color: 'var(--fg)' }}>送出前會先問你</span>
            </div>
            <span style={{ fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.14em', color: 'var(--fg-faint)' }}>ASKS FIRST</span>
          </div>
          {['請 AI 整理一段內容', '把筆記分享到圈子或公開', '把 murmur 編入別人的討論'].map((t, i, arr) => (
            <div key={i} style={{
              padding: '10px 16px',
              borderBottom: i === arr.length - 1 ? 'none' : '0.5px solid var(--rule-soft)',
              fontFamily: 'var(--serif)', fontSize: 13, color: 'var(--fg)',
            }}>· {t}</div>
          ))}
        </div>
      </div>

      <div style={{ padding: '18px 22px 8px' }}>
        <button style={{
          width: '100%', background: 'var(--fg)', color: 'var(--bg)',
          padding: '15px 22px', borderRadius: 999, border: 'none',
          fontFamily: 'var(--serif)', fontSize: 15, letterSpacing: '0.08em',
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
        }}>
          <span>明白了 · 繼續</span>
          <span style={{ opacity: 0.55, fontFamily: 'var(--mono)', fontSize: 12 }}>→</span>
        </button>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenOnboardingPromise });
