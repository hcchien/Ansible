// screen-forum-thread.jsx — single thread with replies

function ScreenForumThread() {
  return (
    <div className="ph" style={{
      height: '100%', paddingTop: 56, paddingBottom: 70,
      display: 'flex', flexDirection: 'column',
    }}>
      {/* nav */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '8px 22px 8px',
      }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.16em' }}>← 討論串</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.16em' }}>···</span>
      </div>

      <div style={{ flex: 1, overflowY: 'auto', padding: '8px 22px 14px' }}>
        {/* tag */}
        <span style={{
          fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.18em',
          color: 'var(--fg-faint)', textTransform: 'uppercase',
        }}>PHIL · 哲學</span>

        {/* title */}
        <h1 style={{
          fontFamily: 'var(--serif)', fontWeight: 500,
          fontSize: 25, lineHeight: 1.3, margin: '8px 0 14px',
          color: 'var(--fg)',
        }}>我們在「廢墟」裡<br/>到底在尋找什麼？</h1>

        {/* OP meta */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 10,
          padding: '8px 0', borderTop: '0.5px solid var(--rule-soft)',
          borderBottom: '0.5px solid var(--rule-soft)',
        }}>
          <div style={{
            width: 26, height: 26, borderRadius: '50%',
            background: 'var(--bg-deep)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontFamily: 'var(--serif)', fontSize: 11, color: 'var(--fg-muted)',
          }}>林</div>
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            <span style={{ fontFamily: 'var(--serif)', fontSize: 12, color: 'var(--fg)' }}>林下</span>
            <span style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)', letterSpacing: '0.1em' }}>2 小時前 · 公開</span>
          </div>
          <span style={{ flex: 1 }}/>
          <span style={{
            fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)',
            letterSpacing: '0.14em', display: 'inline-flex', alignItems: 'center', gap: 6,
          }}>
            <svg width="14" height="6" viewBox="0 0 14 6">
              {[2,6,10].map((x,j)=>(<circle key={j} cx={x} cy="3" r="1" fill="var(--fg-faint)" opacity={0.5+j*0.15}/>))}
            </svg>
            來自 6 個 murmur
          </span>
        </div>

        {/* OP body */}
        <div style={{
          fontFamily: 'var(--serif)', fontSize: 14.5, lineHeight: 1.75,
          color: 'var(--fg)', padding: '14px 0',
          borderBottom: '0.5px solid var(--rule)',
        }}>
          Anna Tsing 的 patches 並不浪漫——是在崩塌之後才看見的某種共生。我們現在用「廢墟」這個字也許太美學了一點。
          <br/><br/>
          松茸不長在乾淨的森林裡。它喜歡被擾動過、卻沒被毀掉的地方。我覺得我們做這個工具的時候，常常在描述那種「太完整的森林長不出來」的狀態。
        </div>

        {/* replies header */}
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '14px 0 10px',
        }}>
          <span style={{ fontFamily: 'var(--serif)', fontSize: 13, color: 'var(--fg)' }}>23 個回應</span>
          <span style={{ fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-muted)', letterSpacing: '0.14em' }}>↓ 最舊先</span>
        </div>

        {/* replies */}
        {[
          { who: 'kr.', whoBg: 'var(--accent-soft)', ago: '1小時前', viz: 'public',
            body: '我在想 patches 翻譯成「斑塊」太冷了。也許「補丁」更接近它的多義——縫補與不完整。' },
          { who: 'Tris', whoBg: 'var(--bg-deep)', ago: '52 分前', viz: 'circle',
            body: '其實我覺得我們在尋找的是一種「不必修復」的鬆動感。修復本身就是一種對完整的執著。' },
          { who: '路過的人', whoBg: 'var(--bg-deep)', ago: '38 分前', viz: 'public',
            body: '+1 林下這段。我也一直在想為什麼自己會抗拒「重建」這個詞。' },
        ].map((r, i) => (
          <div key={i} style={{
            padding: '12px 0',
            borderBottom: '0.5px solid var(--rule-soft)',
            display: 'flex', gap: 10,
          }}>
            <div style={{
              width: 22, height: 22, borderRadius: '50%',
              background: r.whoBg, flexShrink: 0,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontFamily: 'var(--serif)', fontSize: 10, color: 'var(--fg-muted)',
            }}>{r.who[0]}</div>
            <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 5 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span style={{ fontFamily: 'var(--serif)', fontSize: 12, color: 'var(--fg)' }}>{r.who}</span>
                <PhVizChip kind={r.viz} size="sm"/>
                <span style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)', letterSpacing: '0.1em', marginLeft: 'auto' }}>{r.ago}</span>
              </div>
              <div style={{ fontFamily: 'var(--serif)', fontSize: 13, lineHeight: 1.65, color: 'var(--fg)' }}>{r.body}</div>
              <div style={{ display: 'flex', gap: 16, marginTop: 2 }}>
                <span style={{ fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.12em', color: 'var(--fg-faint)' }}>↳ 回</span>
                <span style={{ fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.12em', color: 'var(--fg-faint)' }}>↗ 編入我的筆記</span>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* compose dock */}
      <div style={{
        position: 'absolute', bottom: 34, left: 0, right: 0,
        padding: '10px 22px',
        background: 'var(--bg)',
        borderTop: '0.5px solid var(--rule)',
        display: 'flex', alignItems: 'center', gap: 10,
      }}>
        <div style={{
          flex: 1, padding: '10px 14px', borderRadius: 999,
          background: 'var(--bg-soft)',
          fontFamily: 'var(--serif)', fontStyle: 'italic',
          fontSize: 13, color: 'var(--fg-faint)',
        }}>寫一段回應……</div>
        <div style={{
          width: 40, height: 40, borderRadius: '50%',
          background: 'var(--fg)', color: 'var(--bg)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <svg width="14" height="14" viewBox="0 0 14 14">
            <path d="M 2 7 h 10 M 7 2 l 5 5 -5 5" stroke="var(--bg)" strokeWidth="1.4" fill="none" strokeLinecap="round"/>
          </svg>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenForumThread });
