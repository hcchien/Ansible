// screen-onboarding-first.jsx — invite the first murmur

function ScreenOnboardingFirst() {
  return (
    <div className="ph" style={{
      height: '100%', paddingTop: 56,
      display: 'flex', flexDirection: 'column',
      background: 'var(--bg)',
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '8px 22px',
      }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-faint)', letterSpacing: '0.18em' }}>← 上一步</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-faint)', letterSpacing: '0.18em' }}>3 / 3</span>
      </div>

      <div style={{ flex: 1, padding: '20px 22px 0', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div style={{
          fontFamily: 'var(--mono)', fontSize: 9.5, letterSpacing: '0.2em',
          color: 'var(--fg-faint)', textTransform: 'uppercase',
        }}>第一個碎念 · FIRST MURMUR</div>

        <div style={{
          fontFamily: 'var(--serif)', fontSize: 22, lineHeight: 1.4,
          color: 'var(--fg)', fontWeight: 500,
        }}>
          現在腦子裡<br/>有什麼半成形的東西嗎？
        </div>

        <div style={{
          fontFamily: 'var(--serif)', fontStyle: 'italic',
          fontSize: 13, lineHeight: 1.65, color: 'var(--fg-muted)',
        }}>
          一句話、一個直覺、一個還沒理順的問題都可以。沒人會看到。
        </div>

        {/* compose surface */}
        <div style={{
          marginTop: 8, padding: '16px 16px 14px',
          border: '0.5px solid var(--rule)', borderRadius: 14,
          minHeight: 180,
          display: 'flex', flexDirection: 'column', gap: 10,
        }}>
          <div style={{
            fontFamily: 'var(--serif)', fontSize: 16, lineHeight: 1.65,
            color: 'var(--fg-faint)', fontStyle: 'italic',
          }}>
            這幾個月一直在想的事情是<span style={{
              borderRight: '1.5px solid var(--accent)', marginLeft: 1,
              animation: 'caret-ob 1s steps(2) infinite',
            }}>&nbsp;</span>
          </div>

          {/* prompt chips */}
          <div style={{ marginTop: 'auto', display: 'flex', flexWrap: 'wrap', gap: 6 }}>
            {['今天看到的一個畫面', '最近反覆想到的一句', '一個還沒答案的問題'].map(p => (
              <span key={p} style={{
                padding: '5px 10px', borderRadius: 999,
                border: '0.5px solid var(--rule)',
                fontFamily: 'var(--serif)', fontSize: 11, color: 'var(--fg-muted)',
              }}>{p}</span>
            ))}
          </div>
        </div>

        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          marginTop: 4,
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <PhVizChip kind="private"/>
            <span style={{ fontFamily: 'var(--serif)', fontStyle: 'italic', fontSize: 11, color: 'var(--fg-faint)' }}>預設只給自己</span>
          </div>
          <span style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)', letterSpacing: '0.14em' }}>0 / ∞</span>
        </div>
      </div>

      <div style={{ padding: '18px 22px 12px', display: 'flex', gap: 10 }}>
        <button style={{
          background: 'transparent', color: 'var(--fg-muted)',
          padding: '13px 18px', borderRadius: 999,
          border: '0.5px solid var(--rule)',
          fontFamily: 'var(--serif)', fontSize: 13,
        }}>晚點再說</button>
        <button style={{
          flex: 1, background: 'var(--fg)', color: 'var(--bg)',
          padding: '13px 18px', borderRadius: 999, border: 'none',
          fontFamily: 'var(--serif)', fontSize: 14, letterSpacing: '0.08em',
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
        }}>
          <span>放下 · 開始用</span>
          <span style={{ opacity: 0.55, fontFamily: 'var(--mono)', fontSize: 12 }}>↵</span>
        </button>
      </div>

      <IOSKeyboard/>

      <style>{`@keyframes caret-ob { 50% { border-color: transparent; } }`}</style>
    </div>
  );
}

Object.assign(window, { ScreenOnboardingFirst });
