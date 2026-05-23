// screen-notes-home.jsx — index of working notes + recent murmurs

function ScreenNotesHome() {
  return (
    <div className="ph" style={{
      height: '100%', paddingTop: 56, paddingBottom: 90,
      display: 'flex', flexDirection: 'column',
      position: 'relative', overflow: 'hidden',
    }}>
      <PhHeader/>

      {/* — gentle filter bar — */}
      <div style={{
        display: 'flex', gap: 18, padding: '0 22px 14px',
        borderBottom: '0.5px solid var(--rule-soft)',
      }}>
        {[['全部','ALL', true],['筆記','NOTES', false],['碎念','MURMURS', false],['討論','THREADS', false]].map(([zh, en, on]) => (
          <div key={en} style={{
            display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: 2,
            paddingBottom: 6,
            borderBottom: on ? '1px solid var(--fg)' : '1px solid transparent',
            opacity: on ? 1 : 0.5,
          }}>
            <span style={{ fontFamily: 'var(--serif)', fontSize: 13, color: 'var(--fg)' }}>{zh}</span>
            <span style={{ fontFamily: 'var(--mono)', fontSize: 8, letterSpacing: '0.16em', color: 'var(--fg-faint)' }}>{en}</span>
          </div>
        ))}
      </div>

      <div style={{ flex: 1, overflowY: 'auto' }}>
        <PhSectionHead zh="草地" en="WORKING NOTES · 3" action="↓ 最近"/>
        <PhNoteRow
          title="末日松茸採集"
          body="一朵一朵地撿，慢慢撿。林下不是空的——只是看不見的方式生長著。Anna Tsing 把廢墟當成可棲居的地方，不是要修復，而是要學會在裡面活。"
          count={6} date="今日 14:22" visibility="private"/>
        <PhNoteRow
          title="廢墟中的協作"
          body="信任不是 default-on。每一次被看見都是一個選擇——不是隱私的相反，而是它的實踐。"
          count={4} date="昨日" visibility="circle"/>
        <PhNoteRow
          title="關於 Le Guin 的 ansible"
          body="瞬時通訊器。距離不再是延遲，但人心的延遲依舊。也許 ansible 真正的功能不是消滅延遲，而是讓延遲被看見。"
          count={11} date="3天前" visibility="private" last/>

        <PhSectionHead zh="散落" en="LOOSE MURMURS · 7" action="↗ 編入"/>
        <PhMurmurRow text="如果信任是一種地形而非通道——" date="14:22"/>
        <PhMurmurRow text="今天看到老房子的牆角長了一朵不認識的菇。沒拍照。" date="11:08"/>
        <PhMurmurRow text="patches: Tsing 用來描述多物種共處的最小單位" date="昨" last/>
      </div>

      {/* Bottom capture cluster */}
      <div style={{
        position: 'absolute', bottom: 50, left: 0, right: 0,
        padding: '12px 22px',
        background: 'linear-gradient(to top, var(--bg) 60%, transparent)',
        display: 'flex', justifyContent: 'center', gap: 10,
      }}>
        <button style={{
          flex: 1, background: 'var(--fg)', color: 'var(--bg)',
          padding: '14px 22px', borderRadius: 999,
          fontFamily: 'var(--serif)', fontSize: 15,
          letterSpacing: '0.08em', border: 'none',
          boxShadow: '0 4px 16px rgba(60,40,20,0.18)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
        }}>
          <svg width="13" height="13" viewBox="0 0 14 14">
            <path d="M 7 1.5 v 11 M 1.5 7 h 11" stroke="var(--bg)" strokeWidth="1.4" strokeLinecap="round"/>
          </svg>
          <span>記下一段碎念</span>
        </button>
        <button style={{
          background: 'var(--bg)', color: 'var(--fg)',
          width: 48, height: 48, borderRadius: '50%',
          border: '0.5px solid var(--rule)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <svg width="14" height="14" viewBox="0 0 16 16">
            <circle cx="6" cy="6" r="4" fill="none" stroke="var(--fg)" strokeWidth="1.25"/>
            <path d="M 9.5 9.5 L 13 13" stroke="var(--fg)" strokeWidth="1.25" strokeLinecap="round"/>
          </svg>
        </button>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenNotesHome });
