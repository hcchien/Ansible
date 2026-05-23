// screen-onboarding-welcome.jsx — first launch, quiet manifesto

function ScreenOnboardingWelcome() {
  return (
    <div className="ph" style={{
      height: '100%', paddingTop: 56, paddingBottom: 44,
      display: 'flex', flexDirection: 'column',
      background: 'var(--bg)',
    }}>
      {/* Top: faint progress dots */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '8px 22px',
      }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-faint)', letterSpacing: '0.18em' }}>1 / 3</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-faint)', letterSpacing: '0.18em' }}>跳過</span>
      </div>

      {/* Centered hero — big mark + manifesto */}
      <div style={{
        flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center',
        padding: '0 32px', gap: 28,
      }}>
        {/* the signal mark, large */}
        <div style={{ display: 'flex', justifyContent: 'flex-start' }}>
          <svg width="120" height="80" viewBox="0 0 200 140">
            <g fill="none" stroke="var(--accent)" strokeLinecap="round">
              <path d="M 60 50 A 22 22 0 0 1 60 94" strokeWidth="2.75"/>
              <path d="M 60 36 A 36 36 0 0 1 60 108" strokeWidth="2" opacity="0.7"/>
              <path d="M 60 18 A 54 54 0 0 1 60 126" strokeWidth="1.4" opacity="0.4"/>
            </g>
            <circle cx="60" cy="72" r="11" fill="var(--fg)"/>
            <circle cx="152" cy="72" r="11" fill="none" stroke="var(--fg)" strokeWidth="2"/>
          </svg>
        </div>

        <div style={{
          fontFamily: 'var(--serif-en)', fontSize: 38, fontWeight: 300,
          letterSpacing: '-1px', color: 'var(--fg)', lineHeight: 1.1,
        }}>ansible</div>

        <div style={{
          fontFamily: 'var(--serif)', fontSize: 22, lineHeight: 1.55,
          color: 'var(--fg)', fontWeight: 400, letterSpacing: '0.005em',
        }}>
          在這裡，<br/>
          先慢一點。
        </div>

        <div style={{
          fontFamily: 'var(--serif)', fontStyle: 'italic',
          fontSize: 14, lineHeight: 1.7, color: 'var(--fg-muted)',
          maxWidth: 280,
        }}>
          一個給碎念、筆記、與不急著被聽見的話的地方。先寫給自己；如果哪天想讓人看見，你會知道的。
        </div>
      </div>

      {/* Bottom: enter button + trust footnote */}
      <div style={{ padding: '14px 22px 8px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <button style={{
          background: 'var(--fg)', color: 'var(--bg)',
          padding: '15px 22px', borderRadius: 999, border: 'none',
          fontFamily: 'var(--serif)', fontSize: 15, letterSpacing: '0.1em',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        }}>
          <span style={{ width: 18 }}/>
          <span>進入</span>
          <span style={{ opacity: 0.55, fontFamily: 'var(--mono)', fontSize: 12 }}>→</span>
        </button>
        <span style={{
          fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.18em',
          color: 'var(--fg-faint)', textAlign: 'center', textTransform: 'uppercase',
        }}>沒有帳號 · 沒有雲端 · 不會被收集</span>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenOnboardingWelcome });
