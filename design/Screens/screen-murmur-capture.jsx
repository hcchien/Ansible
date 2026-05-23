// screen-murmur-capture.jsx — quick local capture, keyboard up

function ScreenMurmurCapture() {
  return (
    <div className="ph" style={{
      height: '100%', display: 'flex', flexDirection: 'column',
      paddingTop: 56,
    }}>
      {/* tight header — capture is a focus mode */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '8px 22px 14px', borderBottom: '0.5px solid var(--rule-soft)',
      }}>
        <span style={{
          fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)',
          letterSpacing: '0.18em', textTransform: 'uppercase',
        }}>← 收起</span>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{
            width: 5, height: 5, borderRadius: '50%', background: 'var(--spore)',
          }}/>
          <span style={{
            fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)',
            letterSpacing: '0.16em',
          }}>本地 · 14:36</span>
        </div>
        <span style={{
          fontFamily: 'var(--serif)', fontSize: 13, color: 'var(--fg)',
        }}>記下</span>
      </div>

      {/* Compose surface — pure paper */}
      <div style={{
        flex: 1, padding: '24px 22px 12px',
        display: 'flex', flexDirection: 'column', gap: 14,
        overflow: 'hidden',
      }}>
        <span style={{
          fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.2em',
          color: 'var(--fg-faint)', textTransform: 'uppercase',
        }}>MURMUR · 碎念</span>

        <div style={{
          fontFamily: 'var(--serif)', fontSize: 19, lineHeight: 1.65,
          color: 'var(--fg)',
        }}>
          松茸喜歡的是被擾動過、卻沒被毀掉的林子。
          完全的廢墟長不出來，太完整的森林也不會。
          <span style={{ borderRight: '1.5px solid var(--accent)', marginLeft: 1, animation: 'caret 1s steps(2) infinite' }}>&nbsp;</span>
        </div>

        {/* meta footer of the murmur — quiet */}
        <div style={{
          marginTop: 'auto', paddingTop: 14,
          borderTop: '0.5px solid var(--rule-soft)',
          display: 'flex', flexDirection: 'column', gap: 12,
        }}>
          {/* visibility row */}
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <span style={{ fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.16em', color: 'var(--fg-faint)', textTransform: 'uppercase' }}>誰能看 · VISIBILITY</span>
            <PhVizChip kind="private" size="md"/>
          </div>
          {/* link row — what is this murmur attached to? */}
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <span style={{ fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.16em', color: 'var(--fg-faint)', textTransform: 'uppercase' }}>連到 · ATTACH TO</span>
            <span style={{
              display: 'inline-flex', alignItems: 'center', gap: 6,
              padding: '4px 10px', borderRadius: 999,
              border: '0.5px solid var(--rule)',
              fontFamily: 'var(--serif)', fontSize: 12, color: 'var(--fg)',
            }}>
              <span style={{ width: 5, height: 5, borderRadius: '50%', background: 'var(--accent)' }}/>
              末日松茸採集
              <span style={{ color: 'var(--fg-faint)', marginLeft: 4, fontFamily: 'var(--mono)', fontSize: 9 }}>+1</span>
            </span>
          </div>
        </div>
      </div>

      {/* compose toolbar — directly above keyboard */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '10px 22px',
        borderTop: '0.5px solid var(--rule-soft)',
        background: 'var(--bg-soft)',
      }}>
        <div style={{ display: 'flex', gap: 18 }}>
          {['Aa','#','◷','📎'].map((g, i) => (
            <span key={i} style={{
              fontFamily: 'var(--mono)', fontSize: 14, color: 'var(--fg-muted)',
              opacity: 0.85,
            }}>{g}</span>
          ))}
        </div>
        <button style={{
          background: 'var(--fg)', color: 'var(--bg)',
          padding: '8px 18px', borderRadius: 999,
          fontFamily: 'var(--serif)', fontSize: 13, letterSpacing: '0.08em',
          border: 'none',
        }}>放下 ↵</button>
      </div>

      {/* iOS keyboard */}
      <IOSKeyboard/>

      <style>{`
        @keyframes caret { 50% { border-color: transparent; } }
      `}</style>
    </div>
  );
}

Object.assign(window, { ScreenMurmurCapture });
