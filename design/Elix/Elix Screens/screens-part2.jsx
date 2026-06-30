// screens-part2.jsx — Forum + Trust + Identity + Daily nav

function ScreenForumList() {
  const threads = [
    { tagEn:'PHIL', tag:'哲學', title:'我們在重建什麼樣的網路？', body:'不只是技術選擇——是一種對信任的重新想像。default-on 的時代過去了……', author:'Mira', replies:23, ago:'2小時前', heat:'warm', from:6 },
    { tagEn:'TOOL', tag:'工具', title:'passkey 在跨平台還是不夠順', body:'最近實驗了三種，Apple Keychain 還是最好，但 Android 跟桌面的橋接還是斷的。', author:'kr.', replies:41, ago:'今晨', heat:'hot', from:3 },
    { tagEn:'NOTE', tag:'隨筆', title:'刪掉社群帳號的第 47 天', body:'一開始焦慮，後來空洞，然後是一種很久沒有過的清醒。也許網路上太久沒有「不在場」這件事了。', author:'路過的人', replies:7, ago:'昨日', heat:'cool', from:2 },
    { tagEn:'DSGN', tag:'設計', title:'介面如何邀請慢一點？', body:'不是少功能，而是讓每個動作都帶一點摩擦——剛好夠讓你停下來想一秒。', author:'Tris', replies:14, ago:'3天前', heat:'warm', from:4 },
  ];
  const heatBar = h => ({hot:{w:28,c:'var(--amber)'}, warm:{w:16,c:'var(--fg-muted)'}, cool:{w:6,c:'var(--fg-faint)'}}[h]);
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, paddingBottom:50, display:'flex', flexDirection:'column' }}>
      <PhHeader chip="公開 · OPEN" dot="var(--amber)"/>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'0 22px 12px' }}>
        <span style={{ fontFamily:'var(--serif)', fontSize:22, fontWeight:500, color:'var(--fg)' }}>討論串</span>
        <div style={{ display:'flex', gap:12 }}>
          <span style={{ fontFamily:'var(--mono)', fontSize:10, letterSpacing:'0.16em', color:'var(--fg-muted)' }}>↓ 最近</span>
          <span style={{ fontFamily:'var(--mono)', fontSize:10, letterSpacing:'0.16em', color:'var(--fg-faint)' }}>圈內</span>
        </div>
      </div>
      <div style={{ display:'flex', gap:6, padding:'0 22px 14px', flexWrap:'wrap' }}>
        {[['全部',true],['哲學',false],['工具',false],['設計',false],['隨筆',false],['+',false]].map(([t,on]) => (
          <span key={t} style={{ padding:'4px 11px', borderRadius:999, border:'0.5px solid '+(on?'var(--fg)':'var(--rule)'), fontFamily:'var(--serif)', fontSize:12, color: on?'var(--fg)':'var(--fg-muted)', background: on?'var(--bg-soft)':'transparent' }}>{t}</span>
        ))}
      </div>
      <div style={{ flex:1, overflowY:'auto' }}>
        {threads.map((t,i) => {
          const h = heatBar(t.heat);
          return (
            <div key={i} style={{ padding:'14px 22px', borderBottom:'0.5px solid var(--rule-soft)', display:'flex', flexDirection:'column', gap:7 }}>
              <div style={{ display:'flex', alignItems:'center', gap:8 }}>
                <span className="label-mono-sm">{t.tagEn} · {t.tag}</span>
                <span style={{ width:h.w, height:1, background:h.c, opacity:0.7 }}/>
              </div>
              <div style={{ fontFamily:'var(--serif)', fontSize:16.5, lineHeight:1.4, color:'var(--fg)', fontWeight:500 }}>{t.title}</div>
              <div style={{ fontFamily:'var(--serif)', fontSize:12.5, lineHeight:1.55, color:'var(--fg-muted)', display:'-webkit-box', WebkitBoxOrient:'vertical', WebkitLineClamp:2, overflow:'hidden' }}>{t.body}</div>
              <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', marginTop:2, fontFamily:'var(--mono)', fontSize:9.5, color:'var(--fg-faint)', letterSpacing:'0.06em' }}>
                <div style={{ display:'flex', alignItems:'center', gap:8 }}>
                  <span style={{ fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11, color:'var(--fg-muted)' }}>{t.author}</span>
                  <span>·</span><span>{t.replies} 回</span><span>·</span>
                  <span style={{ display:'inline-flex', alignItems:'center', gap:4 }}>
                    <ElxMark size={9} color="var(--fg-faint)" dot="var(--amber)"/>
                    來自 {t.from}
                  </span>
                </div>
                <span>{t.ago}</span>
              </div>
            </div>
          );
        })}
      </div>
      <div style={{ position:'absolute', bottom:50, right:22 }}>
        <button style={{ background:'var(--fg)', color:'var(--bg)', width:56, height:56, borderRadius:'50%', border:'none', boxShadow:'0 6px 20px rgba(60,40,20,0.22)', display:'flex', alignItems:'center', justifyContent:'center' }}>
          <svg width="18" height="18" viewBox="0 0 18 18"><path d="M 3 14 L 13 4 M 11 4 h 3 v 3" stroke="var(--bg)" strokeWidth="1.4" fill="none" strokeLinecap="round" strokeLinejoin="round"/></svg>
        </button>
      </div>
    </div>
  );
}

function ScreenForumThread() {
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, paddingBottom:70, display:'flex', flexDirection:'column' }}>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'8px 22px 8px' }}>
        <span className="label-mono-sm">← 討論串</span>
        <span style={{ fontFamily:'var(--mono)', fontSize:14, color:'var(--fg-muted)' }}>···</span>
      </div>
      <div style={{ flex:1, overflowY:'auto', padding:'8px 22px 14px' }}>
        <span className="label-mono-sm">PHIL · 哲學</span>
        <h1 style={{ fontFamily:'var(--serif)', fontWeight:500, fontSize:25, lineHeight:1.3, margin:'8px 0 14px', color:'var(--fg)' }}>我們在重建什麼樣的網路？</h1>
        <div style={{ display:'flex', alignItems:'center', gap:10, padding:'8px 0', borderTop:'0.5px solid var(--rule-soft)', borderBottom:'0.5px solid var(--rule-soft)' }}>
          <div style={{ width:26, height:26, borderRadius:'50%', background:'var(--amber)', display:'flex', alignItems:'center', justifyContent:'center', fontFamily:'var(--serif)', fontSize:11, color:'var(--bg)' }}>M</div>
          <div style={{ display:'flex', flexDirection:'column' }}>
            <span style={{ display:'flex', alignItems:'center', gap:5, fontFamily:'var(--serif)', fontSize:12, color:'var(--fg)' }}>
              Mira <ElxMark size={9} color="var(--amber)" dot="var(--amber)"/>
            </span>
            <span className="label-mono-sm">2 小時前 · 公開 · 已簽署</span>
          </div>
          <span style={{ flex:1 }}/>
          <span style={{ display:'inline-flex', alignItems:'center', gap:6 }}>
            <ElxMark size={10} color="var(--fg-faint)" dot="var(--amber)"/>
            <span className="label-mono-sm">來自 6 個 murmur</span>
          </span>
        </div>
        <div style={{ fontFamily:'var(--serif)', fontSize:14.5, lineHeight:1.75, color:'var(--fg)', padding:'14px 0', borderBottom:'0.5px solid var(--rule)' }}>
          不只是技術選擇——是一種對信任的重新想像。default-on 的時代過去了。把所有人預設成可見、可追蹤、可被推送的對象，這是上一個時代的代價。
          <br/><br/>
          現在我們在練習的，是一種「先靜默」的網路。要被看見，要說一聲。要被搜尋到，要願意。每一個動作都是一個選擇。
        </div>
        <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'14px 0 10px' }}>
          <span style={{ fontFamily:'var(--serif)', fontSize:13, color:'var(--fg)' }}>23 個回應</span>
          <span className="label-mono-sm">↓ 最舊先</span>
        </div>
        {[
          { who:'kr.', ago:'1小時前', viz:'public', signed:true, body:'我覺得「靜默」這個詞還是太被動了。我們在做的更像是「邀請」——你必須被邀請才看得到我。' },
          { who:'Tris', ago:'52 分前', viz:'circle', signed:true, body:'技術層面，每個動作都簽名其實是 Elix 最關鍵的設計。沒有簽名的內容根本進不了流。' },
          { who:'路過的人', ago:'38 分前', viz:'public', signed:false, body:'+1 Mira 這段。第一次看到有產品說：「不是你預設可見，而是你選擇出現。」' },
        ].map((r,i) => (
          <div key={i} style={{ padding:'12px 0', borderBottom:'0.5px solid var(--rule-soft)', display:'flex', gap:10 }}>
            <div style={{ width:22, height:22, borderRadius:'50%', background:'var(--bg-deep)', flexShrink:0, display:'flex', alignItems:'center', justifyContent:'center', fontFamily:'var(--serif)', fontSize:10, color:'var(--fg-muted)' }}>{r.who[0]}</div>
            <div style={{ flex:1 }}>
              <div style={{ display:'flex', alignItems:'center', gap:8 }}>
                <span style={{ fontFamily:'var(--serif)', fontSize:12, color:'var(--fg)' }}>{r.who}</span>
                <PhVizChip kind={r.viz} size="sm"/>
                {r.signed && <span style={{ width:5, height:5, borderRadius:'50%', background:'var(--amber)' }}/>}
                <span className="label-mono-sm" style={{ marginLeft:'auto' }}>{r.ago}</span>
              </div>
              <div style={{ fontFamily:'var(--serif)', fontSize:13, lineHeight:1.65, color:'var(--fg)', marginTop:5 }}>{r.body}</div>
              <div style={{ display:'flex', gap:16, marginTop:6 }}>
                <span className="label-mono-sm">↳ 回</span>
                <span className="label-mono-sm">↗ 編入我的筆記</span>
                <span className="label-mono-sm" style={{ color:'var(--amber)' }}>✦ resonate</span>
              </div>
            </div>
          </div>
        ))}
      </div>
      <div style={{ position:'absolute', bottom:34, left:0, right:0, padding:'10px 22px', background:'var(--bg)', borderTop:'0.5px solid var(--rule)', display:'flex', alignItems:'center', gap:10 }}>
        <div style={{ flex:1, padding:'10px 14px', borderRadius:999, background:'var(--bg-soft)', fontFamily:'var(--serif)', fontStyle:'italic', fontSize:13, color:'var(--fg-faint)' }}>寫一段回應……</div>
        <div style={{ width:40, height:40, borderRadius:'50%', background:'var(--fg)', display:'flex', alignItems:'center', justifyContent:'center' }}>
          <svg width="14" height="14" viewBox="0 0 14 14"><path d="M 2 7 h 10 M 7 2 l 5 5 -5 5" stroke="var(--bg)" strokeWidth="1.4" fill="none" strokeLinecap="round"/></svg>
        </div>
      </div>
    </div>
  );
}

function ScreenSourceBoundary() {
  const [picked, setPicked] = React.useState('circle');
  const Row = ({ id, label, en, sub, last }) => {
    const on = picked === id;
    return (
      <div onClick={()=>setPicked(id)} style={{ padding:'14px 22px', display:'flex', gap:14, alignItems:'flex-start', borderBottom: last?'none':'0.5px solid var(--rule-soft)', background: on?'var(--bg-soft)':'transparent', cursor:'pointer' }}>
        <div style={{ width:16, height:16, borderRadius:'50%', border:'0.5px solid '+(on?'var(--fg)':'var(--rule)'), marginTop:4, flexShrink:0, position:'relative', background: on?'var(--fg)':'transparent' }}>
          {on && <div style={{ position:'absolute', top:4, left:4, width:6, height:6, borderRadius:'50%', background:'var(--bg)' }}/>}
        </div>
        <div style={{ flex:1 }}>
          <div style={{ display:'flex', alignItems:'baseline', gap:10 }}>
            <span style={{ fontFamily:'var(--serif)', fontSize:16, fontWeight:500, color:'var(--fg)' }}>{label}</span>
            <span className="label-mono-sm">{en}</span>
          </div>
          <div style={{ fontFamily:'var(--serif)', fontSize:12.5, lineHeight:1.5, color:'var(--fg-muted)', marginTop:4 }}>{sub}</div>
        </div>
      </div>
    );
  };
  const cta_txt = picked==='private'?'保留在本地':picked==='circle'?'送往讀書圈':'公開發布';
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, paddingBottom:50, display:'flex', flexDirection:'column' }}>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'8px 22px 16px' }}>
        <span className="label-mono-sm">← 取消</span>
        <span className="label-mono-sm">邊界 · BOUNDARY</span>
        <span className="label-mono-sm">　</span>
      </div>
      <div style={{ flex:1, overflowY:'auto' }}>
        <div style={{ padding:'0 22px 18px' }}>
          <div className="label-mono-sm" style={{ marginBottom:8 }}>草稿 · DRAFT</div>
          <div style={{ padding:14, borderRadius:6, background:'var(--bg-soft)', borderLeft:'2px solid var(--amber)' }}>
            <div style={{ fontFamily:'var(--serif)', fontSize:14.5, fontWeight:500, color:'var(--fg)', marginBottom:4 }}>關於信任的地形</div>
            <div style={{ fontFamily:'var(--serif)', fontSize:12, lineHeight:1.6, color:'var(--fg-muted)' }}>信任不是 default-on——每一次被看見都是選擇。</div>
          </div>
        </div>
        <div className="label-mono-sm" style={{ padding:'0 22px 8px' }}>送到哪裡 · WHERE</div>
        <div style={{ borderTop:'0.5px solid var(--rule)', borderBottom:'0.5px solid var(--rule)' }}>
          <Row id="private" label="留在本地" en="PRIVATE" sub="只這台裝置與你信任的同步圈。沒有他人可見。"/>
          <Row id="circle" label="讀書圈" en="CIRCLE · 4 人" sub="Mira · kr. · 路過的人。passkey 點對點傳遞，無伺服器。"/>
          <Row id="public" label="公開發布" en="PUBLIC" sub="任何拿到連結的人都能讀。會以你的公開身分簽署。" last/>
        </div>
        {picked !== 'private' && (
          <div style={{ marginTop:22 }}>
            <div className="label-mono-sm" style={{ padding:'0 22px 8px' }}>以哪個身分 · AS</div>
            <div style={{ padding:'12px 22px', display:'flex', alignItems:'center', gap:12, borderTop:'0.5px solid var(--rule)', borderBottom:'0.5px solid var(--rule)' }}>
              <div style={{ width:30, height:30, borderRadius:'50%', background:'var(--amber)', color:'var(--bg)', display:'flex', alignItems:'center', justifyContent:'center', fontFamily:'var(--serif)', fontSize:13 }}>T</div>
              <div style={{ flex:1 }}>
                <div style={{ fontFamily:'var(--serif)', fontSize:14, color:'var(--fg)' }}>{picked==='circle'?'讀書圈 · Tris':'公開 · Tris'}</div>
                <div className="label-mono-sm">pk · 6f3a … 9c1e</div>
              </div>
              <span className="label-mono-sm">切換 →</span>
            </div>
            <div style={{ padding:'12px 22px', fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11.5, color:'var(--fg-faint)', lineHeight:1.7 }}>
              這篇會以這個身分簽署。對方看到的是這個名字——你的根身分不會跟著走。
            </div>
          </div>
        )}
        <div style={{ height:24 }}/>
      </div>
      <div style={{ position:'absolute', bottom:34, left:0, right:0, padding:'12px 22px', background:'var(--bg)', borderTop:'0.5px solid var(--rule)' }}>
        <button style={{ ...cta(), width:'100%' }}>
          <span>{cta_txt}</span>
          <svg width="14" height="10" viewBox="0 0 14 10"><path d="M 1 5 h 11 M 8 1 l 4 4 -4 4" stroke="var(--bg)" strokeWidth="1.3" fill="none" strokeLinecap="round"/></svg>
        </button>
      </div>
    </div>
  );
}

function ScreenCircle() {
  const members = [
    { glyph:'T', name:'Tris', sub:'你 · 發起人', role:'founder' },
    { glyph:'k', name:'kr.', sub:'passkey 已交換 · 18 天', role:'writer' },
    { glyph:'M', name:'Mira', sub:'passkey 已交換 · 11 天', role:'writer' },
    { glyph:'路', name:'路過的人', sub:'昨日加入', role:'observer' },
  ];
  const roleLabel = { founder:'發起人', writer:'可發布', observer:'僅瀏覽' };
  const roleEn = { founder:'FOUNDER', writer:'WRITER', observer:'OBSERVER' };
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, paddingBottom:40, display:'flex', flexDirection:'column' }}>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'8px 22px 14px' }}>
        <span className="label-mono-sm">← 圈</span>
        <span style={{ fontFamily:'var(--mono)', fontSize:14, color:'var(--fg-muted)' }}>···</span>
      </div>
      <div style={{ flex:1, overflowY:'auto' }}>
        <div style={{ padding:'0 22px 18px' }}>
          <div className="label-mono-sm" style={{ marginBottom:6 }}>圈 · CIRCLE</div>
          <div style={{ fontFamily:'var(--serif)', fontSize:28, fontWeight:500, lineHeight:1.15, color:'var(--fg)' }}>週四讀書圈</div>
          <div style={{ fontFamily:'var(--serif-en)', fontStyle:'italic', fontSize:14, color:'var(--fg-muted)', marginTop:2 }}>thursday reading circle</div>
          <div style={{ display:'flex', alignItems:'center', gap:14, marginTop:14, flexWrap:'wrap' }}>
            <span style={{ display:'inline-flex', alignItems:'center', gap:6, color:'var(--fg-muted)' }}>
              <ElxMark size={11} color="var(--sage)" dot="var(--amber)"/>
              <span className="label-mono-sm">本地 · LOCAL</span>
            </span>
            <span className="label-mono-sm">4 個成員</span>
            <span className="label-mono-sm">無伺服器</span>
          </div>
        </div>
        <div className="label-mono-sm" style={{ padding:'4px 22px 8px' }}>成員 · MEMBERS</div>
        <div style={{ borderTop:'0.5px solid var(--rule)', borderBottom:'0.5px solid var(--rule)' }}>
          {members.map((m,i,arr) => (
            <div key={i} style={{ padding:'12px 22px', display:'flex', alignItems:'center', gap:12, borderBottom: i===arr.length-1?'none':'0.5px solid var(--rule-soft)' }}>
              <div style={{ width:34, height:34, borderRadius:'50%', background: m.role==='founder'?'rgba(185,122,60,0.15)':'var(--bg-soft)', border:'0.5px solid '+(m.role==='founder'?'var(--amber)':'var(--rule)'), display:'flex', alignItems:'center', justifyContent:'center', fontFamily:'var(--serif)', fontSize:14, color: m.role==='founder'?'var(--amber)':'var(--fg-muted)', flexShrink:0 }}>{m.glyph}</div>
              <div style={{ flex:1, minWidth:0 }}>
                <div style={{ fontFamily:'var(--serif)', fontSize:14.5, color:'var(--fg)' }}>{m.name}</div>
                <div style={{ fontFamily:'var(--serif)', fontSize:11.5, color:'var(--fg-faint)', marginTop:2 }}>{m.sub}</div>
              </div>
              <div style={{ textAlign:'right' }}>
                <div style={{ fontFamily:'var(--serif)', fontSize:11.5, color:'var(--fg-muted)' }}>{roleLabel[m.role]}</div>
                <div className="label-mono-sm" style={{ marginTop:1 }}>{roleEn[m.role]}</div>
              </div>
            </div>
          ))}
        </div>
        <div style={{ padding:'14px 22px' }}>
          <div style={{ padding:'14px 16px', borderRadius:8, border:'0.5px dashed var(--rule)', display:'flex', alignItems:'center', gap:12 }}>
            <ElxMark size={22} color="var(--fg-muted)" dot="var(--amber)"/>
            <div style={{ flex:1 }}>
              <div style={{ fontFamily:'var(--serif)', fontSize:13.5, color:'var(--fg)' }}>邀請新成員</div>
              <div style={{ fontFamily:'var(--serif)', fontSize:11.5, color:'var(--fg-faint)', marginTop:2 }}>透過 passkey 直接交換 · 無中介伺服器</div>
            </div>
            <span style={{ fontFamily:'var(--mono)', fontSize:14, color:'var(--fg-muted)' }}>＋</span>
          </div>
        </div>
        <div className="label-mono-sm" style={{ padding:'12px 22px 8px' }}>邊界 · RULES</div>
        <div style={{ padding:'0 22px', display:'flex', flexDirection:'column', gap:10 }}>
          {[
            ['圈內成員都能寫','回覆與筆記都共享在這個圈裡。'],
            ['同步靠 passkey','每對成員之間直接交換，沒有中央伺服器。'],
            ['退出即不可見','離開的人裝置上會保留副本，但同步停止。'],
          ].map(([t,sub],i) => (
            <div key={i} style={{ display:'flex', gap:12, alignItems:'flex-start' }}>
              <span style={{ width:14, marginTop:5, height:1, background:'var(--fg-faint)', flexShrink:0 }}/>
              <div>
                <div style={{ fontFamily:'var(--serif)', fontSize:13, color:'var(--fg)', fontWeight:500 }}>{t}</div>
                <div style={{ fontFamily:'var(--serif)', fontSize:12, color:'var(--fg-muted)', marginTop:2, lineHeight:1.55 }}>{sub}</div>
              </div>
            </div>
          ))}
        </div>
        <div style={{ height:24 }}/>
      </div>
    </div>
  );
}

function ScreenWallet() {
  const Card = ({ name, en, type, sub, uses, age, primary, accent, dim }) => (
    <div style={{ padding:'16px 18px', borderRadius:8, background: primary?'var(--bg-soft)':'transparent', border:'0.5px solid '+(primary?'var(--fg)':'var(--rule)'), display:'flex', flexDirection:'column', gap:10, opacity: dim?0.65:1, position:'relative' }}>
      {accent && <div style={{ position:'absolute', left:0, top:14, bottom:14, width:2, background:'var(--amber)', borderRadius:1 }}/>}
      <div style={{ display:'flex', alignItems:'baseline', justifyContent:'space-between' }}>
        <span className="label-mono-sm">{en}</span>
        <span className="label-mono-sm">{age}</span>
      </div>
      <div style={{ display:'flex', alignItems:'baseline', gap:10 }}>
        <span style={{ fontFamily:'var(--serif)', fontSize: primary?22:17, fontWeight:500, color:'var(--fg)' }}>{name}</span>
        {primary && <span style={{ fontFamily:'var(--mono)', fontSize:8, letterSpacing:'0.18em', color:'var(--amber)', padding:'2px 6px', border:'0.5px solid var(--amber)', borderRadius:2 }}>主</span>}
      </div>
      <div style={{ fontFamily:'var(--serif)', fontSize:12.5, lineHeight:1.55, color:'var(--fg-muted)', fontStyle:'italic' }}>{sub}</div>
      <div style={{ fontFamily:'var(--mono)', fontSize:10, color:'var(--fg-faint)', letterSpacing:'0.06em' }}>
        {primary ? 'pk · 6f3a … 9c1e' : 'pk · '+Math.random().toString(36).slice(2,6)+' … '+Math.random().toString(36).slice(2,6)}
      </div>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', paddingTop:8, borderTop:'0.5px solid var(--rule-soft)' }}>
        <span style={{ fontFamily:'var(--serif)', fontSize:11, color:'var(--fg-muted)' }}>{type}</span>
        <span className="label-mono-sm">{uses}</span>
      </div>
    </div>
  );
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, paddingBottom:50, display:'flex', flexDirection:'column' }}>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'8px 22px 14px' }}>
        <span className="label-mono-sm">← 設定</span>
        <span className="label-mono-sm">WALLET</span>
        <span className="label-mono-sm">　</span>
      </div>
      <div style={{ flex:1, overflowY:'auto', padding:'0 22px' }}>
        <div className="label-mono-sm" style={{ marginBottom:6 }}>身分 · IDENTITIES</div>
        <h1 style={{ fontFamily:'var(--serif)', fontSize:26, fontWeight:500, margin:'0 0 6px', color:'var(--fg)' }}>鑰匙圈</h1>
        <div style={{ fontFamily:'var(--serif-en)', fontStyle:'italic', fontSize:13, color:'var(--fg-muted)', marginBottom:14 }}>one device, many selves</div>
        <div style={{ fontFamily:'var(--serif)', fontSize:13, lineHeight:1.6, color:'var(--fg-muted)', marginBottom:18 }}>這些都是你。但你選擇在哪裡是哪一個。</div>
        <div style={{ display:'flex', flexDirection:'column', gap:12 }}>
          <Card primary name="本人" en="ROOT · MASTER PASSKEY" type="master passkey" sub="此裝置上產生的源頭。不能改名、不能複製、不能離開這台。" uses="所有圈與發布物的根" age="建立 312 天前"/>
          <Card accent name="公開 · Tris" en="PUBLIC HANDLE" type="衍生身分" sub="在討論串裡露出的名字。讀者只會看到這個。" uses="公開討論 · 23 處" age="278 天"/>
          <Card name="讀書圈 · Tris" en="CIRCLE HANDLE" type="圈內身分" sub="只在「週四讀書圈」內可見。離開圈就消失。" uses="1 個圈" age="92 天"/>
          <Card dim name="匿名瀏覽" en="OBSERVER" type="只讀身分" sub="拿來閱讀別人的公開內容；不留下任何痕跡。" uses="未啟用" age="未使用"/>
        </div>
        <button style={{ marginTop:18, width:'100%', padding:'14px 16px', borderRadius:8, background:'transparent', color:'var(--fg)', border:'0.5px dashed var(--rule)', fontFamily:'var(--serif)', fontSize:14, display:'flex', alignItems:'center', justifyContent:'center', gap:10 }}>
          <span style={{ fontSize:16, color:'var(--fg-muted)' }}>＋</span>
          <span>產生新身分</span>
        </button>
        <div style={{ marginTop:22, padding:'14px 16px', background:'var(--bg-soft)', borderRadius:6, fontFamily:'var(--serif)', fontSize:12, lineHeight:1.7, color:'var(--fg-muted)', fontStyle:'italic' }}>
          身分都從「本人」衍生而來。彼此之間不可互推。<br/>就算公開的我被看穿了，圈內的我仍是隱密的。
        </div>
        <div style={{ height:12 }}/>
      </div>
    </div>
  );
}

function ScreenSyncSettings() {
  const devices = [
    { name:'這支 iPhone', sub:'這台 · 主裝置', state:'on', last:'即時' },
    { name:'MacBook · 工作', sub:'passkey 配對 · 18 天前', state:'on', last:'12 分鐘前' },
    { name:'iPad · 床頭', sub:'passkey 配對 · 31 天前', state:'paused', last:'昨日 23:08' },
  ];
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, paddingBottom:40, display:'flex', flexDirection:'column' }}>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'8px 22px 14px' }}>
        <span className="label-mono-sm">← 設定</span>
        <span className="label-mono-sm">SYNC</span>
        <span className="label-mono-sm">　</span>
      </div>
      <div style={{ flex:1, overflowY:'auto', padding:'0 22px' }}>
        <div className="label-mono-sm" style={{ marginBottom:6 }}>同步 · PEER-TO-PEER</div>
        <h1 style={{ fontFamily:'var(--serif)', fontSize:26, fontWeight:500, margin:'0 0 6px', color:'var(--fg)' }}>裝置間直接傳</h1>
        <div style={{ fontFamily:'var(--serif)', fontSize:13, lineHeight:1.65, color:'var(--fg-muted)', marginBottom:18 }}>不經過 Elix 的伺服器。每兩台裝置之間都有自己的鑰匙。</div>
        <div className="label-mono-sm" style={{ marginBottom:8 }}>你的裝置 · YOUR DEVICES</div>
        <div style={{ border:'0.5px solid var(--rule)', borderRadius:8, overflow:'hidden' }}>
          {devices.map((d,i,arr)=>(
            <div key={i} style={{ padding:'14px 16px', display:'flex', alignItems:'center', gap:12, borderBottom: i===arr.length-1?'none':'0.5px solid var(--rule-soft)' }}>
              <div style={{ width:36, height:36, borderRadius:8, background:'var(--bg-soft)', border:'0.5px solid var(--rule)', display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0 }}>
                <svg width="16" height="20" viewBox="0 0 16 20"><rect x="2" y="1" width="12" height="18" rx="2.5" stroke="var(--fg-muted)" strokeWidth="1" fill="none"/><circle cx="8" cy="16.5" r="0.8" fill="var(--fg-muted)"/></svg>
              </div>
              <div style={{ flex:1, minWidth:0 }}>
                <div style={{ fontFamily:'var(--serif)', fontSize:14, color:'var(--fg)' }}>{d.name}</div>
                <div style={{ fontFamily:'var(--serif)', fontSize:11.5, color:'var(--fg-faint)', marginTop:2 }}>{d.sub}</div>
              </div>
              <div style={{ textAlign:'right' }}>
                <div style={{ display:'flex', alignItems:'center', gap:5, justifyContent:'flex-end' }}>
                  <span style={{ width:6, height:6, borderRadius:'50%', background: d.state==='on'?'var(--sage)':'var(--fg-faint)' }}/>
                  <span style={{ fontFamily:'var(--mono)', fontSize:9.5, color:'var(--fg-muted)', letterSpacing:'0.12em', textTransform:'uppercase' }}>{d.state==='on'?'同步中':'暫停'}</span>
                </div>
                <div className="label-mono-sm" style={{ marginTop:2 }}>{d.last}</div>
              </div>
            </div>
          ))}
        </div>
        <button style={{ marginTop:14, width:'100%', padding:'12px 16px', borderRadius:8, background:'transparent', color:'var(--fg)', border:'0.5px dashed var(--rule)', fontFamily:'var(--serif)', fontSize:13.5 }}>＋ 加入新裝置 · 掃描 QR</button>
        <div className="label-mono-sm" style={{ marginTop:22, marginBottom:8 }}>狀態 · STATE</div>
        <div style={{ display:'flex', flexDirection:'column', gap:0, border:'0.5px solid var(--rule)', borderRadius:8, overflow:'hidden' }}>
          {[
            ['流量上限','本月 · 12.4 MB / 無上限'],
            ['加密','端到端 · X25519'],
            ['中繼伺服器','關閉'],
            ['離線時','在裝置上累積，下次配對推送'],
          ].map(([k,v],i,arr) => (
            <div key={k} style={{ padding:'12px 16px', display:'flex', justifyContent:'space-between', alignItems:'center', borderBottom: i===arr.length-1?'none':'0.5px solid var(--rule-soft)' }}>
              <span style={{ fontFamily:'var(--serif)', fontSize:13, color:'var(--fg)' }}>{k}</span>
              <span className="label-mono-sm">{v}</span>
            </div>
          ))}
        </div>
        <div style={{ height:18 }}/>
      </div>
    </div>
  );
}

function ScreenCredentialAdmin() {
  const grants = [
    { who:'MacBook · 工作', what:'讀寫所有筆記', when:'18 天前', viz:'circle' },
    { who:'iPad · 床頭', what:'僅讀 · 已暫停', when:'31 天前', viz:'private', dim:true },
    { who:'讀書圈 · 4 人', what:'圈內筆記同步', when:'92 天前', viz:'circle' },
    { who:'Mira (公開)', what:'1 篇文章的回覆權', when:'今晨', viz:'public' },
  ];
  const audit = [
    ['14:36','你 · 簽署「關於信任的地形」', 'public'],
    ['11:08','MacBook · 工作 · 編輯一則 murmur', 'local'],
    ['昨 22:18','iPad · 暫停了同步', 'system'],
    ['昨 14:02','讀書圈 · 路過的人加入', 'circle'],
    ['11.04','你 · 撤回了一個過期身分', 'system'],
  ];
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, paddingBottom:40, display:'flex', flexDirection:'column' }}>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'8px 22px 14px' }}>
        <span className="label-mono-sm">← 設定</span>
        <span className="label-mono-sm">ACCESS · AUDIT</span>
        <span className="label-mono-sm">　</span>
      </div>
      <div style={{ flex:1, overflowY:'auto', padding:'0 22px' }}>
        <div className="label-mono-sm" style={{ marginBottom:6 }}>存取 · ACCESS</div>
        <h1 style={{ fontFamily:'var(--serif)', fontSize:26, fontWeight:500, margin:'0 0 12px', color:'var(--fg)' }}>誰拿到了你的鑰匙</h1>
        <div style={{ border:'0.5px solid var(--rule)', borderRadius:8, overflow:'hidden' }}>
          {grants.map((g,i,arr)=>(
            <div key={i} style={{ padding:'12px 16px', display:'flex', alignItems:'center', gap:12, borderBottom: i===arr.length-1?'none':'0.5px solid var(--rule-soft)', opacity: g.dim?0.55:1 }}>
              <PhVizChip kind={g.viz} size="sm"/>
              <div style={{ flex:1, minWidth:0 }}>
                <div style={{ fontFamily:'var(--serif)', fontSize:13.5, color:'var(--fg)' }}>{g.who}</div>
                <div style={{ fontFamily:'var(--serif)', fontSize:11.5, color:'var(--fg-faint)', marginTop:2 }}>{g.what}</div>
              </div>
              <span className="label-mono-sm">{g.when}</span>
              <span style={{ fontFamily:'var(--mono)', fontSize:10, color:'var(--amber)', letterSpacing:'0.12em' }}>撤回</span>
            </div>
          ))}
        </div>
        <div className="label-mono-sm" style={{ marginTop:22, marginBottom:8 }}>審計 · AUDIT</div>
        <div style={{ display:'flex', flexDirection:'column', gap:0, border:'0.5px solid var(--rule)', borderRadius:8, overflow:'hidden' }}>
          {audit.map(([t,what,kind],i,arr)=>(
            <div key={i} style={{ padding:'10px 14px', display:'flex', alignItems:'baseline', gap:10, borderBottom: i===arr.length-1?'none':'0.5px solid var(--rule-soft)' }}>
              <span style={{ width:5, height:5, borderRadius:'50%', background: kind==='public'?'var(--amber)':kind==='circle'?'var(--sage)':kind==='system'?'var(--fg-faint)':'var(--fg-muted)' }}/>
              <span className="label-mono-sm" style={{ minWidth:62 }}>{t}</span>
              <span style={{ flex:1, fontFamily:'var(--serif)', fontSize:12.5, color:'var(--fg)' }}>{what}</span>
            </div>
          ))}
        </div>
        <div style={{ marginTop:14, padding:'12px 14px', background:'var(--bg-soft)', borderRadius:6, fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11.5, color:'var(--fg-muted)', lineHeight:1.7 }}>
          這份審計只在你裝置上。Elix 不會接收、儲存、或分析這些紀錄。
        </div>
        <div style={{ height:18 }}/>
      </div>
    </div>
  );
}

function ScreenSettingsHome() {
  const groups = [
    { label:'身分 · IDENTITY', items:[
      ['鑰匙圈','4 個身分','var(--amber)'],
      ['公開身分','Tris',''],
      ['封存的身分','2',''],
    ]},
    { label:'資料 · DATA', items:[
      ['同步裝置','3 台',''],
      ['存取與審計','看誰用過',''],
      ['匯出全部資料','本地檔案',''],
    ]},
    { label:'介面 · INTERFACE', items:[
      ['外觀','跟隨系統',''],
      ['提醒','安靜',''],
      ['語言','繁體中文',''],
    ]},
  ];
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, paddingBottom:50, display:'flex', flexDirection:'column' }}>
      <PhHeader/>
      <div style={{ padding:'0 22px 16px' }}>
        <div className="label-mono-sm" style={{ marginBottom:6 }}>設定 · SETTINGS</div>
        <h1 style={{ fontFamily:'var(--serif)', fontSize:26, fontWeight:500, margin:'0 0 4px', color:'var(--fg)' }}>你的</h1>
      </div>
      <div style={{ flex:1, overflowY:'auto' }}>
        {groups.map((g,i) => (
          <div key={i} style={{ marginBottom:18 }}>
            <div className="label-mono-sm" style={{ padding:'0 22px 8px' }}>{g.label}</div>
            <div style={{ borderTop:'0.5px solid var(--rule)', borderBottom:'0.5px solid var(--rule)' }}>
              {g.items.map(([k,v,c],j,arr) => (
                <div key={k} style={{ padding:'13px 22px', display:'flex', alignItems:'center', justifyContent:'space-between', borderBottom: j===arr.length-1?'none':'0.5px solid var(--rule-soft)' }}>
                  <span style={{ display:'flex', alignItems:'center', gap:8, fontFamily:'var(--serif)', fontSize:14, color:'var(--fg)' }}>
                    {c && <span style={{ width:6, height:6, borderRadius:'50%', background:c }}/>}
                    {k}
                  </span>
                  <span style={{ display:'flex', alignItems:'center', gap:6 }}>
                    <span className="label-mono-sm">{v}</span>
                    <svg width="6" height="10" viewBox="0 0 6 10"><path d="M 1 1 l 4 4 -4 4" stroke="var(--fg-faint)" strokeWidth="1" fill="none" strokeLinecap="round"/></svg>
                  </span>
                </div>
              ))}
            </div>
          </div>
        ))}
        <div style={{ padding:'0 22px 20px', textAlign:'center', fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11.5, color:'var(--fg-faint)' }}>
          Elix · 0.4.1 · 本地優先
        </div>
      </div>
    </div>
  );
}

function ScreenInbox() {
  const items = [
    { kind:'reply', who:'kr.', what:'回覆了你的「我們在重建什麼樣的網路？」', body:'我覺得「靜默」這個詞還是太被動了……', when:'1小時', signed:true },
    { kind:'invite', who:'Mira', what:'邀請你加入「週四讀書圈」', body:'4 個成員 · passkey 直連', when:'今晨', signed:true },
    { kind:'resonate', who:'路過的人', what:'與你的 murmur 共鳴', body:'「鑰匙比帳號好——因為鑰匙會被傳下去。」', when:'昨', signed:false },
    { kind:'sync', who:'系統', what:'MacBook · 工作 完成同步', body:'12 個 murmur · 2 篇筆記', when:'昨', signed:false },
  ];
  const kindLabel = { reply:'回應', invite:'邀請', resonate:'共鳴', sync:'同步' };
  const kindDot = { reply:'var(--fg)', invite:'var(--amber)', resonate:'var(--sage)', sync:'var(--fg-faint)' };
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, paddingBottom:50, display:'flex', flexDirection:'column' }}>
      <PhHeader/>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'0 22px 12px' }}>
        <span style={{ fontFamily:'var(--serif)', fontSize:22, fontWeight:500, color:'var(--fg)' }}>收信</span>
        <span className="label-mono-sm">4 則 · 今日</span>
      </div>
      <div style={{ display:'flex', gap:18, padding:'0 22px 14px', borderBottom:'0.5px solid var(--rule-soft)' }}>
        {[['全部','ALL',true],['人','PEOPLE',false],['系統','SYSTEM',false]].map(([zh,en,on]) => (
          <div key={en} style={{ display:'flex', flexDirection:'column', gap:2, paddingBottom:6, borderBottom: on?'1px solid var(--fg)':'1px solid transparent', opacity: on?1:0.5 }}>
            <span style={{ fontFamily:'var(--serif)', fontSize:13, color:'var(--fg)' }}>{zh}</span>
            <span style={{ fontFamily:'var(--mono)', fontSize:8, letterSpacing:'0.16em', color:'var(--fg-faint)' }}>{en}</span>
          </div>
        ))}
      </div>
      <div style={{ flex:1, overflowY:'auto' }}>
        {items.map((it,i,arr) => (
          <div key={i} style={{ padding:'14px 22px', borderBottom: i===arr.length-1?'none':'0.5px solid var(--rule-soft)', display:'flex', gap:12 }}>
            <span style={{ width:6, height:6, borderRadius:'50%', background:kindDot[it.kind], marginTop:9, flexShrink:0 }}/>
            <div style={{ flex:1, minWidth:0 }}>
              <div style={{ display:'flex', alignItems:'baseline', gap:8 }}>
                <span style={{ fontFamily:'var(--serif)', fontSize:13.5, fontWeight:500, color:'var(--fg)' }}>{it.who}</span>
                <span className="label-mono-sm">{kindLabel[it.kind].toUpperCase()}</span>
                {it.signed && <span style={{ width:4, height:4, borderRadius:'50%', background:'var(--amber)' }}/>}
                <span className="label-mono-sm" style={{ marginLeft:'auto' }}>{it.when}</span>
              </div>
              <div style={{ fontFamily:'var(--serif)', fontSize:13, lineHeight:1.55, color:'var(--fg)', marginTop:4 }}>{it.what}</div>
              <div style={{ fontFamily:'var(--serif)', fontStyle:'italic', fontSize:12, color:'var(--fg-muted)', marginTop:3, lineHeight:1.55, display:'-webkit-box', WebkitBoxOrient:'vertical', WebkitLineClamp:1, overflow:'hidden' }}>{it.body}</div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function ScreenSearch() {
  const recents = ['信任的地形','passkey','default-on','匿名 vs 假名','圈外'];
  const results = [
    { kind:'NOTE',  title:'關於信任的地形', from:'你 · 私人', date:'今日' },
    { kind:'MURM',  title:'如果信任是一種地形而非通道——', from:'你 · murmur', date:'14:22' },
    { kind:'THRD',  title:'我們在重建什麼樣的網路？', from:'Mira · 公開', date:'2小時' },
    { kind:'CIRCL', title:'週四讀書圈 · 信任這條主題線', from:'圈內 · 12 則', date:'本週' },
  ];
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, paddingBottom:40, display:'flex', flexDirection:'column' }}>
      <div style={{ padding:'8px 22px 14px' }}>
        <div style={{ display:'flex', alignItems:'center', gap:10, padding:'10px 14px', background:'var(--bg-soft)', borderRadius:999 }}>
          <svg width="14" height="14" viewBox="0 0 16 16"><circle cx="6" cy="6" r="4" fill="none" stroke="var(--fg-muted)" strokeWidth="1.25"/><path d="M 9.5 9.5 L 13 13" stroke="var(--fg-muted)" strokeWidth="1.25" strokeLinecap="round"/></svg>
          <input defaultValue="信任" style={{ flex:1, background:'transparent', border:'none', outline:'none', fontFamily:'var(--serif)', fontSize:15, color:'var(--fg)' }}/>
          <span className="label-mono-sm">本地</span>
        </div>
      </div>
      <div style={{ flex:1, overflowY:'auto' }}>
        <div className="label-mono-sm" style={{ padding:'4px 22px 8px' }}>結果 · 4 個</div>
        {results.map((r,i,arr) => (
          <div key={i} style={{ padding:'12px 22px', borderBottom: i===arr.length-1?'none':'0.5px solid var(--rule-soft)', display:'flex', flexDirection:'column', gap:4 }}>
            <div style={{ display:'flex', alignItems:'baseline', gap:8 }}>
              <span className="label-mono-sm">{r.kind}</span>
              <span style={{ fontFamily:'var(--serif)', fontSize:14, color:'var(--fg)', fontWeight:500 }}>{r.title}</span>
            </div>
            <div style={{ display:'flex', alignItems:'baseline', justifyContent:'space-between' }}>
              <span style={{ fontFamily:'var(--serif)', fontSize:11.5, color:'var(--fg-muted)', fontStyle:'italic' }}>{r.from}</span>
              <span className="label-mono-sm">{r.date}</span>
            </div>
          </div>
        ))}
        <div className="label-mono-sm" style={{ padding:'18px 22px 8px' }}>最近找過 · RECENT</div>
        <div style={{ display:'flex', flexWrap:'wrap', gap:8, padding:'0 22px 22px' }}>
          {recents.map(r => (
            <span key={r} style={{ padding:'5px 12px', borderRadius:999, border:'0.5px solid var(--rule)', fontFamily:'var(--serif)', fontSize:12, color:'var(--fg-muted)' }}>{r}</span>
          ))}
        </div>
        <div style={{ padding:'0 22px 22px', fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11.5, color:'var(--fg-faint)', lineHeight:1.7 }}>
          搜尋只在你裝置上的內容裡進行。公開討論串需要打開「也搜尋公開」才會跨出去。
        </div>
      </div>
    </div>
  );
}

function ScreenProfile() {
  const items = [
    { kind:'THRD', title:'我們在重建什麼樣的網路？', meta:'2小時 · 23 回 · 公開', signed:true },
    { kind:'NOTE', title:'介面如何邀請慢一點？', meta:'3天 · 公開 · 4 個 murmur', signed:true },
    { kind:'REPLY', title:'回覆「passkey 在跨平台還是不夠順」', meta:'2天 · 公開', signed:true },
  ];
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, paddingBottom:40, display:'flex', flexDirection:'column' }}>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'8px 22px 14px' }}>
        <span className="label-mono-sm">← 收信</span>
        <span style={{ fontFamily:'var(--mono)', fontSize:14, color:'var(--fg-muted)' }}>···</span>
      </div>
      <div style={{ flex:1, overflowY:'auto' }}>
        <div style={{ padding:'0 22px 18px' }}>
          <div className="label-mono-sm" style={{ marginBottom:6 }}>公開身分 · PUBLIC HANDLE</div>
          <div style={{ display:'flex', alignItems:'center', gap:14 }}>
            <div style={{ width:62, height:62, borderRadius:'50%', background:'var(--amber)', color:'var(--bg)', display:'flex', alignItems:'center', justifyContent:'center', fontFamily:'var(--serif)', fontSize:24, fontWeight:500 }}>T</div>
            <div style={{ flex:1 }}>
              <div style={{ display:'flex', alignItems:'center', gap:6 }}>
                <span style={{ fontFamily:'var(--serif)', fontSize:22, fontWeight:500, color:'var(--fg)' }}>Tris</span>
                <ElxMark size={14} color="var(--amber)" dot="var(--amber)"/>
              </div>
              <div className="label-mono-sm" style={{ marginTop:3 }}>pk · 6f3a … 9c1e · 已簽署 278 天</div>
            </div>
          </div>
          <div style={{ marginTop:14, fontFamily:'var(--serif)', fontSize:14, lineHeight:1.65, color:'var(--fg-muted)' }}>
            寫慢一點。讀久一點。在意過程多於結論。
          </div>
          <div style={{ display:'flex', gap:8, marginTop:14, flexWrap:'wrap' }}>
            <span style={{ display:'inline-flex', alignItems:'center', gap:6, padding:'5px 10px', background:'var(--bg-soft)', borderRadius:6 }}>
              <span style={{ width:5, height:5, borderRadius:'50%', background:'var(--sage)' }}/>
              <span className="label-mono-sm">23 篇公開</span>
            </span>
            <span style={{ display:'inline-flex', alignItems:'center', gap:6, padding:'5px 10px', background:'var(--bg-soft)', borderRadius:6 }}>
              <span style={{ width:5, height:5, borderRadius:'50%', background:'var(--amber)' }}/>
              <span className="label-mono-sm">key verified</span>
            </span>
            <span style={{ display:'inline-flex', alignItems:'center', gap:6, padding:'5px 10px', background:'var(--bg-soft)', borderRadius:6 }}>
              <span className="label-mono-sm">3 個圈</span>
            </span>
          </div>
        </div>
        <div className="label-mono-sm" style={{ padding:'0 22px 8px' }}>公開的痕跡 · TRAIL</div>
        <div style={{ borderTop:'0.5px solid var(--rule)' }}>
          {items.map((it,i,arr) => (
            <div key={i} style={{ padding:'13px 22px', borderBottom: i===arr.length-1?'none':'0.5px solid var(--rule-soft)' }}>
              <div style={{ display:'flex', alignItems:'baseline', gap:8 }}>
                <span className="label-mono-sm">{it.kind}</span>
                <span style={{ fontFamily:'var(--serif)', fontSize:14, color:'var(--fg)', fontWeight:500 }}>{it.title}</span>
              </div>
              <div style={{ display:'flex', alignItems:'baseline', gap:8, marginTop:4 }}>
                <span style={{ fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11.5, color:'var(--fg-muted)' }}>{it.meta}</span>
                {it.signed && <span style={{ width:4, height:4, borderRadius:'50%', background:'var(--amber)' }}/>}
              </div>
            </div>
          ))}
        </div>
        <div style={{ padding:'18px 22px', fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11.5, color:'var(--fg-faint)', lineHeight:1.7 }}>
          這些都是用「公開 · Tris」這個身分簽出去的。你其他身分的痕跡不會出現在這裡。
        </div>
      </div>
    </div>
  );
}

function ScreenMurmurDetail() {
  const grown = [
    { date:'04.27', where:'關於信任的地形', kind:'NOTE', delta:'這段被引用了一次' },
    { date:'04.28', where:'我們在重建什麼樣的網路？', kind:'THRD', delta:'被 kr. 編入回應' },
    { date:'05.02', where:'共鳴 +3', kind:'·', delta:'3 個人按下 ✦' },
  ];
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, paddingBottom:40, display:'flex', flexDirection:'column' }}>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'8px 22px 14px' }}>
        <span className="label-mono-sm">← murmurs</span>
        <span style={{ fontFamily:'var(--mono)', fontSize:14, color:'var(--fg-muted)' }}>···</span>
      </div>
      <div style={{ flex:1, overflowY:'auto', padding:'0 22px' }}>
        <div className="label-mono-sm">MURMUR · 04.27 14:36</div>
        <div style={{ margin:'14px 0 18px', padding:'18px 18px', borderLeft:'2px solid var(--amber)', background:'var(--bg-soft)', borderRadius:'0 8px 8px 0' }}>
          <div style={{ fontFamily:'var(--serif)', fontStyle:'italic', fontSize:19, lineHeight:1.6, color:'var(--fg)' }}>
            如果信任是一種地形而非通道——
          </div>
          <div style={{ display:'flex', alignItems:'center', gap:10, marginTop:14 }}>
            <PhVizChip kind="private" size="sm"/>
            <span className="label-mono-sm">本地 · 起源</span>
          </div>
        </div>

        <div className="label-mono-sm" style={{ marginBottom:6 }}>長進了哪裡 · GREW INTO</div>
        <h2 style={{ fontFamily:'var(--serif)', fontSize:18, fontWeight:500, lineHeight:1.4, color:'var(--fg)', margin:'0 0 14px' }}>
          一個 murmur 走過的路。
        </h2>

        <div style={{ position:'relative', paddingLeft:18 }}>
          <div style={{ position:'absolute', left:5, top:6, bottom:6, width:1, background:'var(--rule)' }}/>
          {grown.map((g,i) => (
            <div key={i} style={{ position:'relative', paddingBottom:18 }}>
              <span style={{ position:'absolute', left:-18, top:6, width:11, height:11, borderRadius:'50%', background:'var(--bg)', border:'1px solid var(--amber)' }}/>
              <div style={{ display:'flex', alignItems:'baseline', gap:8 }}>
                <span className="label-mono-sm">{g.date} · {g.kind}</span>
              </div>
              <div style={{ fontFamily:'var(--serif)', fontSize:14, color:'var(--fg)', marginTop:4 }}>{g.where}</div>
              <div style={{ fontFamily:'var(--serif)', fontStyle:'italic', fontSize:12, color:'var(--fg-muted)', marginTop:2 }}>{g.delta}</div>
            </div>
          ))}
        </div>

        <div style={{ marginTop:8, padding:'14px 16px', background:'var(--bg-soft)', borderRadius:6, fontFamily:'var(--serif)', fontStyle:'italic', fontSize:12, lineHeight:1.75, color:'var(--fg-muted)' }}>
          一個句子能去多遠，不是看誰看到它，而是看誰把它接住。
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenForumList, ScreenForumThread, ScreenSourceBoundary, ScreenCircle, ScreenWallet, ScreenSyncSettings, ScreenCredentialAdmin, ScreenSettingsHome, ScreenInbox, ScreenSearch, ScreenProfile, ScreenMurmurDetail });
