// screen-search.jsx — search across murmur / note / thread, scoped by visibility

function ScreenSearch() {
  const [scope, setScope] = React.useState('all');
  const scopes = [['all', '全部'], ['private', '我的'], ['circle', '圈內'], ['public', '公開']];

  return (
    <div className="ph" style={{ height: '100%', paddingTop: 56, paddingBottom: 40, display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 22px 12px' }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.16em' }}>← 草地</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-faint)', letterSpacing: '0.16em' }}>SEARCH</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-faint)', letterSpacing: '0.16em' }}>　</span>
      </div>

      {/* search bar */}
      <div style={{ padding: '0 22px 12px' }}>
        <div style={{
          padding: '10px 14px', borderRadius: 8,
          background: 'var(--bg-soft)', border: '0.5px solid var(--fg)',
          display: 'flex', alignItems: 'center', gap: 10,
        }}>
          <svg width="14" height="14" viewBox="0 0 14 14">
            <circle cx="6" cy="6" r="4" fill="none" stroke="var(--fg-muted)" strokeWidth="1.1"/>
            <path d="M 9 9 l 4 4" stroke="var(--fg-muted)" strokeWidth="1.1" strokeLinecap="round"/>
          </svg>
          <span style={{ fontFamily: 'var(--serif)', fontSize: 14, color: 'var(--fg)', flex: 1 }}>廢墟</span>
          <span style={{ width: 1.5, height: 14, background: 'var(--fg)' }}/>
          <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-faint)', letterSpacing: '0.14em' }}>清除</span>
        </div>
      </div>

      {/* scope tabs */}
      <div style={{ display: 'flex', gap: 6, padding: '0 22px 14px', flexWrap: 'wrap' }}>
        {scopes.map(([id, label]) => (
          <span key={id} onClick={() => setScope(id)} style={{
            padding: '5px 12px', borderRadius: 999,
            border: '0.5px solid ' + (scope === id ? 'var(--fg)' : 'var(--rule)'),
            background: scope === id ? 'var(--fg)' : 'transparent',
            color: scope === id ? 'var(--bg)' : 'var(--fg-muted)',
            fontFamily: 'var(--serif)', fontSize: 12,
            cursor: 'pointer',
          }}>{label}</span>
        ))}
      </div>

      <div style={{ flex: 1, overflowY: 'auto' }}>
        {/* result counts */}
        <div style={{ padding: '0 22px 14px', display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
          <span style={{ fontFamily: 'var(--serif)', fontStyle: 'italic', fontSize: 13, color: 'var(--fg-muted)' }}>找到 <span style={{ color: 'var(--fg)', fontStyle: 'normal' }}>23</span> 處提及</span>
          <span style={{ fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-faint)', letterSpacing: '0.14em' }}>↓ 相關</span>
        </div>

        {/* note hits */}
        <div className="label-mono-sm" style={{ padding: '0 22px 8px' }}>筆記 · NOTES · 3</div>
        <div style={{ borderTop: '0.5px solid var(--rule)', borderBottom: '0.5px solid var(--rule)' }}>
          {[
            { title: '廢墟中的協作', body: '信任不是 default-on 的——這是<mark>廢墟</mark>狀態下協作的前提。', viz: 'private', when: '今日' },
            { title: '關於 Le Guin 的 Ansible', body: '<mark>廢墟</mark>的另一面是 distance；ansible 跨越的不只是空間。', viz: 'private', when: '3天' },
            { title: '荒涼感作為一種介面語言', body: '不是黑色工程師美學，是<mark>廢墟</mark>本身的紋理。', viz: 'public', when: '昨日' },
          ].map((r, i, a) => (
            <ResultRow key={i} {...r} kindLabel="NOTE" last={i === a.length - 1}/>
          ))}
        </div>

        {/* murmur hits */}
        <div className="label-mono-sm" style={{ padding: '20px 22px 8px' }}>碎念 · MURMURS · 14</div>
        <div style={{ borderTop: '0.5px solid var(--rule)', borderBottom: '0.5px solid var(--rule)' }}>
          {[
            { title: '', body: 'Anna Tsing 寫的 patches 並不浪漫——是在<mark>廢墟</mark>之後才看見的某種共生。', viz: 'private', when: '2小時' },
            { title: '', body: '為什麼自己會抗拒「重建」這個詞——也許因為<mark>廢墟</mark>本身已經是一種完整。', viz: 'circle', when: '昨日' },
            { title: '', body: '一張<mark>廢墟</mark>的照片：牆角的菇與灰塵共處。', viz: 'private', when: '3天' },
          ].map((r, i, a) => (
            <ResultRow key={i} {...r} kindLabel="MURM" last={i === a.length - 1}/>
          ))}
        </div>

        {/* thread hits */}
        <div className="label-mono-sm" style={{ padding: '20px 22px 8px' }}>討論串 · FORUM · 6</div>
        <div style={{ borderTop: '0.5px solid var(--rule)', borderBottom: '0.5px solid var(--rule)' }}>
          {[
            { title: '我們在「廢墟」裡到底在尋找什麼？', body: '林下 · 23 回 · 公開', viz: 'public', when: '2小時' },
            { title: '荒涼感作為一種介面語言', body: 'Tris · 14 回 · 公開', viz: 'public', when: '3天' },
          ].map((r, i, a) => (
            <ResultRow key={i} {...r} kindLabel="THRD" last={i === a.length - 1}/>
          ))}
        </div>

        <div style={{ height: 24 }}/>
      </div>
    </div>
  );
}

function ResultRow({ title, body, kindLabel, viz, when, last }) {
  return (
    <div style={{
      padding: '11px 22px',
      borderBottom: last ? 'none' : '0.5px solid var(--rule-soft)',
      display: 'flex', flexDirection: 'column', gap: 4,
    }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 8.5, letterSpacing: '0.18em', color: 'var(--fg-faint)' }}>{kindLabel}</span>
        <span style={{ width: 4, height: 4, borderRadius: '50%',
          background: viz === 'private' ? 'var(--fg-muted)' : viz === 'circle' ? 'var(--accent)' : 'var(--spore)' }}/>
        {title && <span style={{ fontFamily: 'var(--serif)', fontSize: 13.5, fontWeight: 500, color: 'var(--fg)', flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{title}</span>}
        <span style={{ flex: title ? 0 : 1 }}/>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)', letterSpacing: '0.1em' }}>{when}</span>
      </div>
      <div
        style={{ fontFamily: 'var(--serif)', fontSize: 12.5, lineHeight: 1.6, color: 'var(--fg-muted)' }}
        dangerouslySetInnerHTML={{ __html: body.replace(/<mark>/g, '<mark style="background:var(--accent-soft);color:var(--fg);padding:0 2px;border-radius:1px;">') }}
      />
    </div>
  );
}

Object.assign(window, { ScreenSearch });
