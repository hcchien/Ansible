// screen-ai-review.jsx — calm system message before sending content to remote AI

function ScreenAIReview() {
  return (
    <div className="ph" style={{
      height: '100%', position: 'relative',
      background: 'var(--bg)',
      display: 'flex', flexDirection: 'column',
    }}>
      {/* Background: a faded view of the note workspace, dimmed */}
      <div style={{
        position: 'absolute', inset: 0,
        background: 'var(--bg)',
        opacity: 0.45,
        pointerEvents: 'none',
      }}>
        <div style={{
          paddingTop: 70, padding: '70px 22px 0',
          fontFamily: 'var(--serif)', fontSize: 26, color: 'var(--fg-faint)',
          fontWeight: 500,
        }}>末日松茸採集</div>
        <div style={{
          padding: '8px 22px',
          fontFamily: 'var(--serif)', fontSize: 14, color: 'var(--fg-faint)',
          lineHeight: 1.7,
        }}>一朵一朵地撿，慢慢撿。林下不是空的──只是用看不見的方式生長著。</div>
      </div>

      {/* Spacer pushing sheet to bottom */}
      <div style={{ flex: 1 }}/>

      {/* The disclosure sheet — calm, paper, hairline */}
      <div style={{
        position: 'relative', zIndex: 2,
        background: 'var(--bg)',
        borderTop: '0.5px solid var(--rule)',
        borderTopLeftRadius: 22, borderTopRightRadius: 22,
        boxShadow: '0 -10px 30px rgba(60,40,20,0.08)',
        padding: '18px 22px 60px',
        display: 'flex', flexDirection: 'column', gap: 14,
      }}>
        {/* drag handle */}
        <div style={{
          width: 32, height: 3, borderRadius: 2,
          background: 'var(--rule)', alignSelf: 'center',
        }}/>

        {/* header — system-message tone */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 4 }}>
          <PhMark size={18}/>
          <span style={{
            fontFamily: 'var(--mono)', fontSize: 10, letterSpacing: '0.18em',
            color: 'var(--fg-muted)', textTransform: 'uppercase',
          }}>SYSTEM MESSAGE · 系統訊息</span>
        </div>

        {/* the actual statement, in serif, calm */}
        <div style={{
          fontFamily: 'var(--serif)', fontSize: 17, lineHeight: 1.65,
          color: 'var(--fg)', letterSpacing: '0.005em',
        }}>
          下面這些內容會離開你的裝置，傳送給遠端 AI 做整理。
        </div>
        <div style={{
          fontFamily: 'var(--serif)', fontStyle: 'italic',
          fontSize: 13, lineHeight: 1.65, color: 'var(--fg-muted)',
        }}>
          一旦傳出，就無法當作沒發生過。可以先把不想送的關掉。
        </div>

        {/* Manifest list — what gets sent */}
        <div style={{
          marginTop: 6, padding: '4px 0',
          borderTop: '0.5px solid var(--rule-soft)',
          borderBottom: '0.5px solid var(--rule-soft)',
        }}>
          {[
            { kind: '正文 · BODY', detail: '4 段 · ≈ 320 字', on: true, locked: true },
            { kind: '碎念 · MURMUR', detail: '6 則 · 04.21 → 04.27', on: true, locked: false },
            { kind: '標題 · TITLE', detail: '末日松茸採集', on: true, locked: false },
            { kind: '時間軸 · TIMELINE', detail: '寫作時序與停頓', on: false, locked: false },
            { kind: '引用 · QUOTES', detail: '2 則來自他人公開內容', on: false, locked: false },
          ].map((row, i, arr) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              padding: '11px 2px',
              borderBottom: i === arr.length - 1 ? 'none' : '0.5px solid var(--rule-soft)',
            }}>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                <span style={{ fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.16em', color: 'var(--fg-faint)' }}>{row.kind}</span>
                <span style={{ fontFamily: 'var(--serif)', fontSize: 13, color: row.on ? 'var(--fg)' : 'var(--fg-faint)' }}>{row.detail}</span>
              </div>
              {/* toggle */}
              <div style={{
                width: 36, height: 20, borderRadius: 999,
                background: row.on ? 'var(--fg)' : 'var(--bg-deep)',
                border: '0.5px solid var(--rule)',
                position: 'relative', opacity: row.locked ? 0.4 : 1,
              }}>
                <div style={{
                  position: 'absolute', top: 1.5, left: row.on ? 18 : 1.5,
                  width: 16, height: 16, borderRadius: '50%',
                  background: 'var(--bg)',
                  boxShadow: '0 1px 2px rgba(0,0,0,0.15)',
                  transition: 'left 0.18s',
                }}/>
              </div>
            </div>
          ))}
        </div>

        {/* destination */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <span style={{ fontFamily: 'var(--mono)', fontSize: 9.5, letterSpacing: '0.16em', color: 'var(--fg-faint)', textTransform: 'uppercase' }}>送往 · DESTINATION</span>
          <span style={{
            fontFamily: 'var(--serif)', fontSize: 12, color: 'var(--fg)',
            display: 'inline-flex', alignItems: 'center', gap: 8,
          }}>
            Claude Haiku 4.5
            <span style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)' }}>·</span>
            <span style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)' }}>US-EAST</span>
          </span>
        </div>

        {/* Actions */}
        <div style={{ display: 'flex', gap: 10, marginTop: 6 }}>
          <button style={{
            flex: 1, background: 'transparent', color: 'var(--fg)',
            padding: '12px 14px', borderRadius: 999,
            border: '0.5px solid var(--rule)',
            fontFamily: 'var(--serif)', fontSize: 14, letterSpacing: '0.05em',
          }}>留在本地</button>
          <button style={{
            flex: 2, background: 'var(--fg)', color: 'var(--bg)',
            padding: '12px 14px', borderRadius: 999, border: 'none',
            fontFamily: 'var(--serif)', fontSize: 14, letterSpacing: '0.08em',
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
          }}>
            <span>送出 · 約 320 字</span>
            <span style={{ opacity: 0.6, fontFamily: 'var(--mono)', fontSize: 11 }}>→</span>
          </button>
        </div>

        <span style={{
          fontFamily: 'var(--serif)', fontStyle: 'italic',
          fontSize: 11, color: 'var(--fg-faint)', textAlign: 'center', marginTop: 2,
        }}>
          按 ⌘⇧L 隨時打開這份清單。
        </span>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenAIReview });
