// screen-feed.jsx — Feed page, faithful to the Elix brand system mockup
// Header: ElixMark + circle/open toggle
// Rows: avatar + name + constellation trust + handle/time/signed + body + ✦ resonates / ✎ reply / ↗ pass on
// Tabbar: constellation (home) + profile + compose + circle

function FeedItem({ name, handle, time, body, resonates, trusted, signed, isYou, last }) {
  return (
    <div style={{ padding:'18px 22px', borderBottom: last ? 'none' : '0.5px solid var(--rule-soft)' }}>
      <div style={{ display:'flex', alignItems:'center', gap:10, marginBottom:10 }}>
        <div style={{
          width:34, height:34, borderRadius:'50%',
          background: isYou ? 'var(--amber)' : 'var(--bg-deep)',
          color: isYou ? 'var(--bg)' : 'var(--fg-muted)',
          display:'flex', alignItems:'center', justifyContent:'center',
          fontFamily:'var(--serif)', fontSize:13, fontWeight:500, flexShrink:0,
        }}>{name[0]}</div>
        <div style={{ flex:1, minWidth:0 }}>
          <div style={{ display:'flex', alignItems:'center', gap:6 }}>
            <span style={{ fontFamily:'var(--serif)', fontSize:13.5, fontWeight:500, color:'var(--fg)' }}>{name}</span>
            {trusted && <ElxMark size={10} color="var(--amber)" dot="var(--amber)"/>}
          </div>
          <div style={{ fontFamily:'var(--mono)', fontSize:9.5, color:'var(--fg-faint)', letterSpacing:'0.06em', marginTop:1 }}>
            @{handle} · {time}{signed ? ' · signed' : ''}
          </div>
        </div>
        {signed && <span style={{ width:6, height:6, borderRadius:'50%', background:'var(--amber)' }}/>}
      </div>
      <div style={{ fontFamily:'var(--serif)', fontSize:14.5, lineHeight:1.6, color:'var(--fg)' }}>{body}</div>
      <div style={{ display:'flex', gap:18, marginTop:11, fontFamily:'var(--mono)', fontSize:10, color:'var(--fg-faint)', letterSpacing:'0.06em' }}>
        <span>✦ {resonates}</span>
        <span>✎ reply</span>
        <span>↗ pass on</span>
      </div>
    </div>
  );
}

function ScreenFeed() {
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, paddingBottom:60, display:'flex', flexDirection:'column', position:'relative' }}>
      {/* Header */}
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'12px 22px 14px', borderBottom:'0.5px solid var(--rule-soft)' }}>
        <ElxWord height={18}/>
        <div style={{ display:'flex', alignItems:'center', gap:14, fontFamily:'var(--mono)', fontSize:10, letterSpacing:'0.1em', color:'var(--fg-muted)' }}>
          <span style={{ display:'inline-flex', alignItems:'center', gap:5 }}>
            <span style={{ width:5, height:5, borderRadius:'50%', background:'var(--fg)' }}/>
            your circle
          </span>
          <span style={{ color:'var(--fg-faint)', opacity:0.6, display:'inline-flex', alignItems:'center', gap:5 }}>
            <span style={{ width:5, height:5, borderRadius:'50%', border:'0.5px solid var(--fg-faint)' }}/>
            open
          </span>
        </div>
      </div>

      {/* Feed */}
      <div style={{ flex:1, overflowY:'auto' }}>
        <FeedItem name="韓康" handle="hankang" time="2h" trusted signed resonates={12}
          body="搬到柏林的第二週。第一次覺得不貼東西不是因為害怕，而是沒必要證明。"/>
        <FeedItem name="Mira O." handle="mira" time="5h" trusted resonates={4}
          body="The opposite of an algorithm is a friend who tells you what they're reading."/>
        <FeedItem name="You" handle="you" time="yesterday" isYou trusted signed resonates={2}
          body="一個社群網站如果不需要每天打開，是不是更接近健康？"/>
        <FeedItem name="Léa" handle="lea" time="2d" resonates={8}
          body="My identity isn't a product. It's a key — and Elix is the door that recognizes it."/>
        <FeedItem name="kr." handle="kr" time="3d" trusted resonates={6} last
          body="鑰匙這個詞比帳號好——因為鑰匙是會丟的，但也是會被傳下去的。"/>
      </div>

      {/* Tabbar */}
      <div style={{
        position:'absolute', bottom:34, left:0, right:0, height:54,
        background:'var(--bg)', borderTop:'0.5px solid var(--rule-soft)',
        display:'flex', alignItems:'center', justifyContent:'space-around', padding:'0 30px',
      }}>
        {/* home — constellation, active */}
        <div style={{ display:'flex', flexDirection:'column', alignItems:'center', gap:3 }}>
          <ElxMark size={22} color="var(--fg)" dot="var(--amber)"/>
        </div>
        {/* circle */}
        <div style={{ display:'flex', flexDirection:'column', alignItems:'center', gap:3 }}>
          <svg width="22" height="22" viewBox="0 0 22 22"><circle cx="11" cy="11" r="8" fill="none" stroke="var(--fg-faint)" strokeWidth="1.4"/></svg>
        </div>
        {/* compose */}
        <div style={{ display:'flex', flexDirection:'column', alignItems:'center', gap:3 }}>
          <svg width="22" height="22" viewBox="0 0 22 22"><path d="M 4 16 L 14 6 M 12 6 h 4 v 4" stroke="var(--fg-faint)" strokeWidth="1.4" fill="none" strokeLinecap="round" strokeLinejoin="round"/></svg>
        </div>
        {/* profile */}
        <div style={{ display:'flex', flexDirection:'column', alignItems:'center', gap:3 }}>
          <svg width="22" height="22" viewBox="0 0 22 22"><rect x="3" y="3" width="16" height="16" rx="3" fill="none" stroke="var(--fg-faint)" strokeWidth="1.4"/></svg>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenFeed, FeedItem });
