// screen-forum-list.jsx — public discussion threads, paper-mode reskin

function ScreenForumList() {
  const threads = [
    { tag: '哲學', tagEn: 'PHIL',
      title: '我們在「廢墟」裡到底在尋找什麼？',
      body: 'Anna Tsing 的 patches 並不浪漫——是在崩塌之後才看見的某種共生……',
      author: '林下', replies: 23, ago: '2小時前', heat: 'warm', from: 6 },
    { tag: '工具', tagEn: 'TOOL',
      title: 'local-first 軟體實作中，CRDT 真的夠用嗎',
      body: '最近用 automerge 寫了一個 demo，遇到一個 conflict resolution 的場景……',
      author: 'kr.', replies: 41, ago: '今晨', heat: 'hot', from: 3 },
    { tag: '隨筆', tagEn: 'NOTE',
      title: '一個老房子的牆角',
      body: '長了一朵不認識的菇。沒拍照——也許這就是松茸的反面：能被記得的、不能被拍到的。',
      author: '路過的人', replies: 7, ago: '昨日', heat: 'cool', from: 2 },
    { tag: '設計', tagEn: 'DSGN',
      title: '荒涼感作為一種介面語言',
      body: '不是黑色的工程師美學，也不是極簡的禪意；是一種知道自己快壞掉的狀態……',
      author: 'Tris', replies: 14, ago: '3天前', heat: 'warm', from: 4 },
  ];

  const heatBar = (h) => ({
    hot: { w: 28, c: 'var(--accent)' },
    warm:{ w: 16, c: 'var(--fg-muted)' },
    cool:{ w: 6,  c: 'var(--fg-faint)' },
  }[h]);

  return (
    <div className="ph" style={{
      height: '100%', paddingTop: 56, paddingBottom: 50,
      display: 'flex', flexDirection: 'column',
    }}>
      <PhHeader chip="公開 · OPEN" dot="var(--accent)"/>

      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 22px 12px',
      }}>
        <span style={{ fontFamily: 'var(--serif)', fontSize: 22, fontWeight: 500, color: 'var(--fg)' }}>討論串</span>
        <div style={{ display: 'flex', gap: 12 }}>
          <span style={{ fontFamily: 'var(--mono)', fontSize: 10, letterSpacing: '0.16em', color: 'var(--fg-muted)' }}>↓ 最近</span>
          <span style={{ fontFamily: 'var(--mono)', fontSize: 10, letterSpacing: '0.16em', color: 'var(--fg-faint)' }}>圈內</span>
        </div>
      </div>

      <div style={{
        display: 'flex', gap: 6, padding: '0 22px 14px', flexWrap: 'wrap',
      }}>
        {[['全部',true],['哲學',false],['工具',false],['設計',false],['隨筆',false],['+',false]].map(([t, on]) => (
          <span key={t} style={{
            padding: '4px 11px', borderRadius: 999,
            border: '0.5px solid ' + (on ? 'var(--fg)' : 'var(--rule)'),
            fontFamily: 'var(--serif)', fontSize: 12,
            color: on ? 'var(--fg)' : 'var(--fg-muted)',
            background: on ? 'var(--bg-soft)' : 'transparent',
          }}>{t}</span>
        ))}
      </div>

      <div style={{ flex: 1, overflowY: 'auto' }}>
        {threads.map((t, i) => {
          const h = heatBar(t.heat);
          return (
            <div key={i} style={{
              padding: '14px 22px',
              borderBottom: '0.5px solid var(--rule-soft)',
              display: 'flex', flexDirection: 'column', gap: 7,
            }}>
              {/* tag + heat */}
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span style={{
                  fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.16em',
                  color: 'var(--fg-faint)', textTransform: 'uppercase',
                }}>{t.tagEn} · {t.tag}</span>
                <span style={{ width: h.w, height: 1, background: h.c, opacity: 0.7 }}/>
              </div>

              <div style={{
                fontFamily: 'var(--serif)', fontSize: 16.5, lineHeight: 1.4,
                color: 'var(--fg)', fontWeight: 500, letterSpacing: '0.005em',
              }}>{t.title}</div>

              <div style={{
                fontFamily: 'var(--serif)', fontSize: 12.5, lineHeight: 1.55,
                color: 'var(--fg-muted)',
                display: '-webkit-box', WebkitBoxOrient: 'vertical', WebkitLineClamp: 2,
                overflow: 'hidden',
              }}>{t.body}</div>

              {/* meta row */}
              <div style={{
                display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                marginTop: 2, fontFamily: 'var(--mono)', fontSize: 9.5,
                color: 'var(--fg-faint)', letterSpacing: '0.06em',
              }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <span style={{
                    fontFamily: 'var(--serif)', fontStyle: 'italic',
                    fontSize: 11, color: 'var(--fg-muted)',
                  }}>{t.author}</span>
                  <span>·</span>
                  <span>{t.replies} 回</span>
                  <span>·</span>
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                    {/* tiny constellation echoing lineage */}
                    <svg width="14" height="6" viewBox="0 0 14 6">
                      {[2, 6, 10].map((x, j) => (
                        <circle key={j} cx={x} cy="3" r="1" fill="var(--fg-faint)" opacity={0.5 + j * 0.15}/>
                      ))}
                    </svg>
                    來自 {t.from}
                  </span>
                </div>
                <span>{t.ago}</span>
              </div>
            </div>
          );
        })}
      </div>

      {/* FAB-ish compose */}
      <div style={{
        position: 'absolute', bottom: 50, right: 22,
      }}>
        <button style={{
          background: 'var(--fg)', color: 'var(--bg)',
          width: 56, height: 56, borderRadius: '50%',
          border: 'none', boxShadow: '0 6px 20px rgba(60,40,20,0.22)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <svg width="18" height="18" viewBox="0 0 18 18">
            <path d="M 3 14 L 13 4 M 11 4 h 3 v 3" stroke="var(--bg)" strokeWidth="1.4" fill="none" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </button>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenForumList });
