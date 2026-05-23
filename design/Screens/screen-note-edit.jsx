// screen-note-edit.jsx — note in edit mode: writing surface + murmur drawer + autosave

function ScreenNoteEdit() {
  const [drawer, setDrawer] = React.useState(true);

  return (
    <div className="ph" style={{
      height: '100%', paddingTop: 56,
      display: 'flex', flexDirection: 'column',
      background: 'var(--bg)',
    }}>
      {/* nav — edit mode */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '8px 22px',
      }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.16em' }}>← 取消</span>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ width: 5, height: 5, borderRadius: '50%', background: 'var(--spore)' }}/>
          <span style={{ fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-faint)', letterSpacing: '0.16em' }}>自動保留 · 12 秒前</span>
        </div>
        <span style={{
          fontFamily: 'var(--serif)', fontSize: 13, color: 'var(--fg)',
          padding: '4px 12px', borderRadius: 999, background: 'var(--bg-soft)',
          border: '0.5px solid var(--rule)',
        }}>完成</span>
      </div>

      {/* meta */}
      <div style={{ padding: '8px 22px 0' }}>
        <div className="label-mono-sm" style={{ marginBottom: 8 }}>編輯中 · EDITING</div>
      </div>

      {/* writing surface */}
      <div style={{ flex: 1, overflowY: 'auto', padding: '0 22px 12px' }}>
        {/* title input */}
        <div style={{
          fontFamily: 'var(--serif)', fontWeight: 500,
          fontSize: 28, lineHeight: 1.2, color: 'var(--fg)',
          padding: '4px 0 6px', borderBottom: '0.5px solid var(--rule-soft)',
          letterSpacing: '0.005em', position: 'relative',
        }}>
          末日松茸採集
          <span style={{
            display: 'inline-block', width: 1.5, height: 22,
            background: 'var(--accent)', marginLeft: 2, verticalAlign: 'text-bottom',
            animation: 'caret-edit 1s steps(2) infinite',
          }}/>
        </div>

        {/* visibility row */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '10px 0 14px' }}>
          <PhVizChip kind="private" size="sm"/>
          <span style={{ fontFamily: 'var(--serif)', fontStyle: 'italic', fontSize: 11.5, color: 'var(--fg-faint)' }}>
            還沒讓任何人看見
          </span>
        </div>

        {/* body — editable paragraphs */}
        <p style={{ fontFamily: 'var(--serif)', fontSize: 15.5, lineHeight: 1.8, margin: '0 0 14px', color: 'var(--fg)' }}>
          一朵一朵地撿，慢慢撿。林下不是空的——只是用看不見的方式生長著。
        </p>

        {/* selected paragraph — with selection highlight */}
        <p style={{
          fontFamily: 'var(--serif)', fontSize: 15.5, lineHeight: 1.8, margin: '0 0 14px',
          color: 'var(--fg)',
        }}>
          Anna Tsing 把廢墟當成<span style={{
            background: 'oklch(0.86 0.06 70)', padding: '0 2px',
          }}>可棲居的地方</span>；不是要修復，而是要學會在裡面活下去。
        </p>

        {/* embedded murmur (already pulled in) */}
        <div style={{
          margin: '6px 0 14px', padding: '10px 14px',
          background: 'var(--bg-soft)', borderLeft: '1.5px solid var(--accent)',
          borderRadius: '0 8px 8px 0', position: 'relative',
        }}>
          <span style={{ fontFamily: 'var(--serif)', fontStyle: 'italic', fontSize: 13.5, color: 'var(--fg)', lineHeight: 1.6 }}>
            松茸喜歡的是被擾動過、卻沒被毀掉的林子。
          </span>
          <div style={{ marginTop: 6, display: 'flex', alignItems: 'center', gap: 8, fontFamily: 'var(--mono)', fontSize: 8.5, letterSpacing: '0.14em', color: 'var(--fg-faint)' }}>
            <span>MURMUR · 04.27 14:36</span>
            <span style={{ width: 3, height: 3, borderRadius: '50%', background: 'var(--fg-faint)' }}/>
            <span>編入此處</span>
            <span style={{ flex: 1 }}/>
            <span style={{ color: 'var(--fg-muted)' }}>↺ 取消編入</span>
          </div>
        </div>

        {/* placeholder for next paragraph */}
        <p style={{
          fontFamily: 'var(--serif)', fontSize: 15.5, lineHeight: 1.8, margin: '0 0 14px',
          color: 'var(--fg-faint)', fontStyle: 'italic',
        }}>
          繼續寫下去，或從下方拖一個 murmur 進來……
        </p>
      </div>

      {/* Selection toolbar — calm formatter */}
      <div style={{
        margin: '0 22px 8px', padding: '6px 8px',
        background: 'var(--fg)', borderRadius: 999,
        display: 'flex', alignItems: 'center', justifyContent: 'space-around', gap: 4,
        boxShadow: '0 4px 16px rgba(40,30,20,0.18)',
      }}>
        {[
          ['B',  'sans',  '600'],
          ['I',  'serif', '400', 'italic'],
          ['U',  'sans',  '400', 'normal', 'underline'],
          ['""', 'serif', '400'],
          ['§',  'serif', '400'],
          ['↗',  'mono',  '400'],
        ].map(([t, fam, w, st, td], i, arr) => (
          <span key={i} style={{
            fontFamily: 'var(--' + fam + ')', fontSize: 14, fontWeight: w,
            fontStyle: st || 'normal', textDecoration: td || 'none',
            color: 'var(--bg)', padding: '4px 12px',
            borderRight: i < arr.length - 1 ? '0.5px solid rgba(255,255,255,0.12)' : 'none',
          }}>{t}</span>
        ))}
      </div>

      {/* Murmur drawer — drag in source */}
      {drawer && (
        <div style={{
          margin: '0 14px',
          background: 'var(--bg-soft)',
          borderTop: '0.5px solid var(--rule)',
          borderLeft: '0.5px solid var(--rule)',
          borderRight: '0.5px solid var(--rule)',
          borderRadius: '12px 12px 0 0',
          paddingBottom: 4,
        }}>
          {/* handle */}
          <div onClick={() => setDrawer(false)} style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            padding: '8px 16px 6px',
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <span style={{ width: 28, height: 3, borderRadius: 2, background: 'var(--rule)' }}/>
            </div>
            <div className="label-mono-sm" style={{ letterSpacing: '0.16em' }}>編入 · DRAW IN</div>
            <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)' }}>×</span>
          </div>

          {/* horizontal scroll of recent murmurs */}
          <div style={{
            display: 'flex', gap: 8, overflowX: 'auto',
            padding: '4px 16px 12px',
          }}>
            {[
              ['04.27', '松茸喜歡的是被擾動過……', true],
              ['04.27', '不必修復的鬆動感', false],
              ['04.26', '“The mushroom at the end of the world.”', false, true],
              ['04.24', '為什麼是「擾動過卻沒被毀掉」', false],
              ['04.22', 'Tsing 的 patches', false],
              ['04.21', '林下不是空的——', false],
            ].map(([d, t, used, quote], i) => (
              <div key={i} style={{
                minWidth: 168, maxWidth: 168, padding: '10px 12px',
                background: 'var(--bg)',
                border: '0.5px solid ' + (used ? 'var(--accent)' : 'var(--rule)'),
                borderRadius: 8, flexShrink: 0,
                opacity: used ? 0.6 : 1,
                position: 'relative',
              }}>
                <div style={{ fontFamily: 'var(--mono)', fontSize: 8.5, letterSpacing: '0.14em', color: 'var(--fg-faint)', marginBottom: 4 }}>
                  {quote ? 'QUOTE' : 'MURMUR'} · {d}
                </div>
                <div style={{
                  fontFamily: 'var(--serif)', fontSize: 12, lineHeight: 1.55,
                  color: 'var(--fg)', fontStyle: quote ? 'italic' : 'normal',
                  display: '-webkit-box', WebkitBoxOrient: 'vertical', WebkitLineClamp: 3, overflow: 'hidden',
                }}>{t}</div>
                {used && (
                  <div style={{
                    position: 'absolute', top: 6, right: 6,
                    fontFamily: 'var(--mono)', fontSize: 8, letterSpacing: '0.14em',
                    color: 'var(--accent)',
                  }}>已編入</div>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      <IOSKeyboard/>

      <style>{`@keyframes caret-edit { 50% { background: transparent; } }`}</style>
    </div>
  );
}

Object.assign(window, { ScreenNoteEdit });
