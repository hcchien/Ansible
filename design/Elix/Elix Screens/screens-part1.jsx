// screens-part1.jsx — Onboarding + Notes/capture/workspace/edit + AI review

function ScreenOnboardingWelcome() {
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, paddingBottom:44, display:'flex', flexDirection:'column', background:'var(--bg)' }}>
      <div style={{ display:'flex', justifyContent:'space-between', padding:'8px 22px' }}>
        <span className="label-mono-sm">1 / 3</span>
        <span className="label-mono-sm">跳過</span>
      </div>
      <div style={{ flex:1, display:'flex', flexDirection:'column', justifyContent:'center', padding:'0 32px', gap:28 }}>
        <ElxMark size={110} dot="var(--amber)"/>
        <ElxWord height={42}/>
        <div style={{ fontFamily:'var(--serif)', fontSize:22, lineHeight:1.55, color:'var(--fg)' }}>
          你的話、你的圈、<br/>你的鑰匙。
        </div>
        <div style={{ fontFamily:'var(--serif)', fontStyle:'italic', fontSize:14, lineHeight:1.7, color:'var(--fg-muted)', maxWidth:280 }}>
          一個重新建立信任的社群。資料留在本地，身分握在你自己手上。要被看見之前，先問過你。
        </div>
      </div>
      <div style={{ padding:'14px 22px 8px', display:'flex', flexDirection:'column', gap:14 }}>
        <button style={cta()}>
          <span style={{ width: 18 }}/>
          <span>進入</span>
          <span style={{ opacity:0.55, fontFamily:'var(--mono)', fontSize:12 }}>→</span>
        </button>
        <span className="label-mono-sm" style={{ textAlign:'center' }}>沒有帳號 · 沒有雲端 · 不會被收集</span>
      </div>
    </div>
  );
}

function ScreenOnboardingPromise() {
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, paddingBottom:44, display:'flex', flexDirection:'column', background:'var(--bg)' }}>
      <div style={{ display:'flex', justifyContent:'space-between', padding:'8px 22px' }}>
        <span className="label-mono-sm">← 上一步</span>
        <span className="label-mono-sm">2 / 3</span>
      </div>
      <div style={{ flex:1, padding:'24px 22px 0', display:'flex', flexDirection:'column', gap:18 }}>
        <div className="label-mono-sm">三條承諾 · THREE PROMISES</div>
        <div style={{ fontFamily:'var(--serif)', fontSize:24, lineHeight:1.45, color:'var(--fg)', fontWeight:500 }}>
          這是一個會跟你<br/>一起變舊的地方。
        </div>
        <div style={{ fontFamily:'var(--serif)', fontSize:13.5, lineHeight:1.75, color:'var(--fg-muted)' }}>
          所有寫下來的東西，預設只在你的裝置裡。不上雲，不索引，不分析。要送出去之前，會先問你。
        </div>
        <div style={{ marginTop:6, border:'0.5px solid var(--rule)', borderRadius:14, overflow:'hidden' }}>
          <PromiseBlock dotColor="var(--sage)" zh="留在你這裡" en="STAYS LOCAL" items={['碎念與筆記的內容','寫作的時序與停頓','草稿與沒寄出的句子']}/>
          <PromiseBlock dotColor="var(--amber)" zh="送出前會先問你" en="ASKS FIRST" items={['請 AI 整理一段內容','把筆記分享到圈子或公開','把 murmur 編入別人的討論']} last/>
        </div>
      </div>
      <div style={{ padding:'18px 22px 8px' }}>
        <button style={{ ...cta(), width:'100%' }}>
          <span>明白了 · 繼續</span>
          <span style={{ opacity:0.55, fontFamily:'var(--mono)', fontSize:12 }}>→</span>
        </button>
      </div>
    </div>
  );
}
function PromiseBlock({ zh, en, items, dotColor, last }) {
  return (
    <>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'12px 16px', borderBottom:'0.5px solid var(--rule-soft)', borderTop: last?'0.5px solid var(--rule)':'none', background:'var(--bg-soft)' }}>
        <div style={{ display:'flex', alignItems:'center', gap:10 }}>
          <span style={{ width:6, height:6, borderRadius:'50%', background:dotColor }}/>
          <span style={{ fontFamily:'var(--serif)', fontSize:13, color:'var(--fg)' }}>{zh}</span>
        </div>
        <span className="label-mono-sm">{en}</span>
      </div>
      {items.map((t, i, arr) => (
        <div key={i} style={{ padding:'10px 16px', borderBottom: i===arr.length-1 ? 'none' : '0.5px solid var(--rule-soft)', fontFamily:'var(--serif)', fontSize:13, color:'var(--fg)' }}>· {t}</div>
      ))}
    </>
  );
}

function ScreenOnboardingFirst() {
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, display:'flex', flexDirection:'column', background:'var(--bg)' }}>
      <div style={{ display:'flex', justifyContent:'space-between', padding:'8px 22px' }}>
        <span className="label-mono-sm">← 上一步</span>
        <span className="label-mono-sm">3 / 3</span>
      </div>
      <div style={{ flex:1, padding:'20px 22px 0', display:'flex', flexDirection:'column', gap:14 }}>
        <div className="label-mono-sm">第一個碎念 · FIRST MURMUR</div>
        <div style={{ fontFamily:'var(--serif)', fontSize:22, lineHeight:1.4, color:'var(--fg)', fontWeight:500 }}>
          現在腦子裡<br/>有什麼半成形的東西嗎？
        </div>
        <div style={{ fontFamily:'var(--serif)', fontStyle:'italic', fontSize:13, lineHeight:1.65, color:'var(--fg-muted)' }}>
          一句話、一個直覺、一個還沒理順的問題都可以。沒人會看到。
        </div>
        <div style={{ marginTop:8, padding:'16px 16px 14px', border:'0.5px solid var(--rule)', borderRadius:14, minHeight:180, display:'flex', flexDirection:'column', gap:10 }}>
          <div style={{ fontFamily:'var(--serif)', fontSize:16, lineHeight:1.65, color:'var(--fg-faint)', fontStyle:'italic' }}>
            這幾個月一直在想的事情是<span style={{ borderRight:'1.5px solid var(--amber)', marginLeft:1, animation:'caret 1s steps(2) infinite' }}>&nbsp;</span>
          </div>
          <div style={{ marginTop:'auto', display:'flex', flexWrap:'wrap', gap:6 }}>
            {['今天看到的一個畫面','最近反覆想到的一句','一個還沒答案的問題'].map(p => (
              <span key={p} style={{ padding:'5px 10px', borderRadius:999, border:'0.5px solid var(--rule)', fontFamily:'var(--serif)', fontSize:11, color:'var(--fg-muted)' }}>{p}</span>
            ))}
          </div>
        </div>
        <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', marginTop:4 }}>
          <div style={{ display:'flex', alignItems:'center', gap:8 }}>
            <PhVizChip kind="private"/>
            <span style={{ fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11, color:'var(--fg-faint)' }}>預設只給自己</span>
          </div>
          <span className="label-mono-sm">0 / ∞</span>
        </div>
      </div>
      <div style={{ padding:'18px 22px 12px', display:'flex', gap:10 }}>
        <button style={{ background:'transparent', color:'var(--fg-muted)', padding:'13px 18px', borderRadius:999, border:'0.5px solid var(--rule)', fontFamily:'var(--serif)', fontSize:13 }}>晚點再說</button>
        <button style={{ ...cta(), flex:1 }}>
          <span>放下 · 開始用</span>
          <span style={{ opacity:0.55, fontFamily:'var(--mono)', fontSize:12 }}>↵</span>
        </button>
      </div>
      <IOSKeyboard/>
    </div>
  );
}

function ScreenNotesHome() {
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, paddingBottom:90, display:'flex', flexDirection:'column', position:'relative', overflow:'hidden' }}>
      <PhHeader/>
      <div style={{ display:'flex', gap:18, padding:'0 22px 14px', borderBottom:'0.5px solid var(--rule-soft)' }}>
        {[['全部','ALL',true],['筆記','NOTES',false],['碎念','MURMURS',false],['討論','THREADS',false]].map(([zh,en,on]) => (
          <div key={en} style={{ display:'flex', flexDirection:'column', gap:2, paddingBottom:6, borderBottom: on?'1px solid var(--fg)':'1px solid transparent', opacity: on?1:0.5 }}>
            <span style={{ fontFamily:'var(--serif)', fontSize:13, color:'var(--fg)' }}>{zh}</span>
            <span style={{ fontFamily:'var(--mono)', fontSize:8, letterSpacing:'0.16em', color:'var(--fg-faint)' }}>{en}</span>
          </div>
        ))}
      </div>
      <div style={{ flex:1, overflowY:'auto' }}>
        <PhSectionHead zh="草地" en="WORKING NOTES · 3" action="↓ 最近"/>
        <PhNoteRow title="關於信任的地形" body="信任不是 default-on。每一次被看見都是一個選擇——不是隱私的相反，而是它的實踐。" count={6} date="今日 14:22" visibility="private"/>
        <PhNoteRow title="自主身分的形狀" body="一個身分不一定要對應一個人。它可以對應一個情境、一個圈、一段時期。鑰匙就是邊界。" count={4} date="昨日" visibility="circle"/>
        <PhNoteRow title="一個社群的健康指標" body="不是 DAU，不是停留時間。是有多少話，被它真正應該被聽見的人讀到。" count={11} date="3天前" visibility="private" last/>
        <PhSectionHead zh="散落" en="LOOSE MURMURS · 7" action="↗ 編入"/>
        <PhMurmurRow text="如果信任是一種地形而非通道——" date="14:22"/>
        <PhMurmurRow text="今天讀到一句：「我的資料不是商品。」這幾個字應該被刻在每個 App 啟動畫面。" date="11:08"/>
        <PhMurmurRow text="鑰匙這個詞比帳號好。因為鑰匙是會丟的，但也是會被傳下去的。" date="昨" last/>
      </div>
      <div style={{ position:'absolute', bottom:50, left:0, right:0, padding:'12px 22px', background:'linear-gradient(to top, var(--bg) 60%, transparent)', display:'flex', justifyContent:'center', gap:10 }}>
        <button style={{ ...cta(), flex:1 }}>
          <svg width="13" height="13" viewBox="0 0 14 14"><path d="M 7 1.5 v 11 M 1.5 7 h 11" stroke="var(--bg)" strokeWidth="1.4" strokeLinecap="round"/></svg>
          <span>記下一段碎念</span>
        </button>
        <button style={{ background:'var(--bg)', color:'var(--fg)', width:48, height:48, borderRadius:'50%', border:'0.5px solid var(--rule)', display:'flex', alignItems:'center', justifyContent:'center' }}>
          <svg width="14" height="14" viewBox="0 0 16 16"><circle cx="6" cy="6" r="4" fill="none" stroke="var(--fg)" strokeWidth="1.25"/><path d="M 9.5 9.5 L 13 13" stroke="var(--fg)" strokeWidth="1.25" strokeLinecap="round"/></svg>
        </button>
      </div>
    </div>
  );
}

function ScreenMurmurCapture() {
  return (
    <div className="ph" style={{ height:'100%', display:'flex', flexDirection:'column', paddingTop:56 }}>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'8px 22px 14px', borderBottom:'0.5px solid var(--rule-soft)' }}>
        <span className="label-mono-sm">← 收起</span>
        <div style={{ display:'flex', alignItems:'center', gap:8 }}>
          <span style={{ width:5, height:5, borderRadius:'50%', background:'var(--sage)' }}/>
          <span className="label-mono-sm">本地 · 14:36</span>
        </div>
        <span style={{ fontFamily:'var(--serif)', fontSize:13, color:'var(--fg)' }}>記下</span>
      </div>
      <div style={{ flex:1, padding:'24px 22px 12px', display:'flex', flexDirection:'column', gap:14, overflow:'hidden' }}>
        <span className="label-mono-sm">MURMUR · 碎念</span>
        <div style={{ fontFamily:'var(--serif)', fontSize:19, lineHeight:1.65, color:'var(--fg)' }}>
          一個社群網站如果不需要每天打開，是不是反而更接近健康？
          <span style={{ borderRight:'1.5px solid var(--amber)', marginLeft:1, animation:'caret 1s steps(2) infinite' }}>&nbsp;</span>
        </div>
        <div style={{ marginTop:'auto', paddingTop:14, borderTop:'0.5px solid var(--rule-soft)', display:'flex', flexDirection:'column', gap:12 }}>
          <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between' }}>
            <span className="label-mono-sm">誰能看 · VISIBILITY</span>
            <PhVizChip kind="private" size="md"/>
          </div>
          <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between' }}>
            <span className="label-mono-sm">連到 · ATTACH TO</span>
            <span style={{ display:'inline-flex', alignItems:'center', gap:6, padding:'4px 10px', borderRadius:999, border:'0.5px solid var(--rule)', fontFamily:'var(--serif)', fontSize:12, color:'var(--fg)' }}>
              <span style={{ width:5, height:5, borderRadius:'50%', background:'var(--amber)' }}/>
              一個社群的健康指標
              <span style={{ color:'var(--fg-faint)', marginLeft:4, fontFamily:'var(--mono)', fontSize:9 }}>+1</span>
            </span>
          </div>
        </div>
      </div>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'10px 22px', borderTop:'0.5px solid var(--rule-soft)', background:'var(--bg-soft)' }}>
        <div style={{ display:'flex', gap:18 }}>
          {['Aa','#','◷','📎'].map((g,i)=> <span key={i} style={{ fontFamily:'var(--mono)', fontSize:14, color:'var(--fg-muted)', opacity:0.85 }}>{g}</span>)}
        </div>
        <button style={{ ...cta(), padding:'8px 18px', fontSize:13 }}>放下 ↵</button>
      </div>
      <IOSKeyboard/>
    </div>
  );
}

function ScreenNoteWorkspace() {
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, paddingBottom:50, display:'flex', flexDirection:'column' }}>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'8px 22px 6px' }}>
        <span className="label-mono-sm">← 草地</span>
        <div style={{ display:'flex', alignItems:'center', gap:14 }}>
          <PhVizChip kind="private" size="sm"/>
          <span style={{ fontFamily:'var(--mono)', fontSize:13, color:'var(--fg-muted)' }}>···</span>
        </div>
      </div>
      <div style={{ flex:1, overflowY:'auto', padding:'6px 22px 24px' }}>
        <div className="label-mono-sm" style={{ marginBottom:12 }}>NOTE · 始於 2026.04.21</div>
        <h1 style={{ fontFamily:'var(--serif)', fontWeight:500, fontSize:30, lineHeight:1.2, margin:'0 0 16px', color:'var(--fg)' }}>關於信任的地形</h1>
        <PhLineage count={6} dates="04.21 → 04.27"/>
        <div style={{ height:0.5, background:'var(--rule-soft)', margin:'8px 0 18px' }}/>
        <p style={{ fontFamily:'var(--serif)', fontSize:15, lineHeight:1.75, margin:'0 0 14px', color:'var(--fg)' }}>
          信任不是 default-on，也不是一個開關。它更像是一種地形——有山谷、有稜線、有路徑要慢慢被踩出來。每一個人之間的信任，深淺都不一樣，這才是它真正的形狀。
        </p>
        <div style={{ margin:'6px 0 16px', padding:'10px 14px', background:'var(--bg-soft)', borderLeft:'1.5px solid var(--amber)', borderRadius:'0 8px 8px 0' }}>
          <span style={{ fontFamily:'var(--serif)', fontStyle:'italic', fontSize:13.5, color:'var(--fg)', lineHeight:1.6 }}>
            如果信任是一種地形而非通道——
          </span>
          <div style={{ marginTop:6, display:'flex', alignItems:'center', gap:8 }}>
            <span className="label-mono-sm" style={{ letterSpacing:'0.14em' }}>MURMUR · 04.27 14:36</span>
            <span style={{ width:3, height:3, borderRadius:'50%', background:'var(--fg-faint)' }}/>
            <span className="label-mono-sm">本地</span>
          </div>
        </div>
        <p style={{ fontFamily:'var(--serif)', fontSize:15, lineHeight:1.75, margin:'0 0 14px', color:'var(--fg)' }}>
          Elix 在做的事，也許是把這個地形畫出來——而不是強迫大家走同一條公路。
        </p>
        <p style={{ fontFamily:'var(--serif)', fontSize:15, lineHeight:1.75, margin:'0 0 14px', color:'var(--fg-muted)', fontStyle:'italic' }}>
          ……（往下還有幾段筆記與三則 murmur）
        </p>
        <div style={{ height:0.5, background:'var(--rule-soft)', margin:'24px 0 16px' }}/>
        <div className="label-mono-sm" style={{ marginBottom:8 }}>來源 · LINEAGE</div>
        <div style={{ display:'flex', flexDirection:'column', gap:7 }}>
          {[
            ['04.21 11:02','信任的開關隱喻太簡化了——'],
            ['04.22 09:14','「鑰匙」比「帳號」好的地方'],
            ['04.24 22:08','default-on 是誰的預設？'],
            ['04.27 14:36','如果信任是一種地形——'],
          ].map(([d,t]) => (
            <div key={d} style={{ display:'flex', alignItems:'baseline', gap:12 }}>
              <span style={{ fontFamily:'var(--mono)', fontSize:9, letterSpacing:'0.1em', color:'var(--fg-faint)', minWidth:86 }}>{d}</span>
              <span style={{ fontFamily:'var(--serif)', fontSize:12, color:'var(--fg-muted)', fontStyle:'italic' }}>{t}</span>
            </div>
          ))}
          <span className="label-mono-sm" style={{ marginTop:4 }}>+ 還有 2 則</span>
        </div>
      </div>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'12px 22px', borderTop:'0.5px solid var(--rule-soft)', background:'var(--bg-soft)' }}>
        <div style={{ display:'flex', gap:18 }}>
          <span className="label-mono-sm">編輯</span>
          <span className="label-mono-sm">分享</span>
        </div>
        <button style={{ background:'transparent', color:'var(--fg)', padding:'7px 14px', borderRadius:999, border:'0.5px solid var(--rule)', fontFamily:'var(--serif)', fontSize:12, display:'flex', alignItems:'center', gap:8 }}>
          <span style={{ width:5, height:5, borderRadius:'50%', background:'var(--amber)' }}/>
          請 AI 整理這篇 →
        </button>
      </div>
    </div>
  );
}

function ScreenNoteEdit() {
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, display:'flex', flexDirection:'column' }}>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'8px 22px 8px', borderBottom:'0.5px solid var(--rule-soft)' }}>
        <span className="label-mono-sm">取消</span>
        <span className="label-mono-sm">編輯中 · EDITING</span>
        <span style={{ fontFamily:'var(--serif)', fontSize:13, color:'var(--amber)' }}>完成</span>
      </div>
      <div style={{ flex:1, padding:'18px 22px', display:'flex', flexDirection:'column', gap:12, overflow:'hidden' }}>
        <input defaultValue="關於信任的地形" style={{ fontFamily:'var(--serif)', fontSize:26, fontWeight:500, color:'var(--fg)', background:'transparent', border:'none', outline:'none', padding:0, borderBottom:'1px solid var(--amber)', paddingBottom:6 }}/>
        <PhLineage count={6} dates="04.21 → 04.27"/>
        <div style={{ fontFamily:'var(--serif)', fontSize:15, lineHeight:1.75, color:'var(--fg)' }}>
          信任不是 default-on，也不是一個開關。它更像是一種<span style={{ background:'rgba(185,122,60,0.15)' }}>地形</span>——有山谷、有稜線、有路徑要慢慢被踩出來<span style={{ borderRight:'1.5px solid var(--amber)', marginLeft:1, animation:'caret 1s steps(2) infinite' }}>&nbsp;</span>
        </div>
        <div style={{ marginTop:'auto', padding:'10px 12px', background:'var(--bg-soft)', borderRadius:8, display:'flex', alignItems:'center', gap:10 }}>
          <ElxMark size={14} color="var(--amber)" dot="var(--amber)"/>
          <span style={{ flex:1, fontFamily:'var(--serif)', fontSize:12, color:'var(--fg-muted)', fontStyle:'italic' }}>偵測到 1 處可能想成段——要請 AI 建議結構嗎？</span>
          <span style={{ fontFamily:'var(--mono)', fontSize:10, color:'var(--amber)', letterSpacing:'0.12em' }}>稍後</span>
        </div>
      </div>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'8px 22px', borderTop:'0.5px solid var(--rule-soft)', background:'var(--bg-soft)' }}>
        <div style={{ display:'flex', gap:20 }}>
          {['B','I','U','· ·','H','”','#'].map((g,i)=> <span key={i} style={{ fontFamily:'var(--serif)', fontSize:14, color:'var(--fg-muted)' }}>{g}</span>)}
        </div>
        <span className="label-mono-sm">2,318 字</span>
      </div>
      <IOSKeyboard/>
    </div>
  );
}

function ScreenAIReview() {
  return (
    <div className="ph" style={{ height:'100%', paddingTop:56, paddingBottom:50, display:'flex', flexDirection:'column' }}>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'8px 22px 14px' }}>
        <span className="label-mono-sm">← 回到筆記</span>
        <span className="label-mono-sm">越界提示 · REVIEW</span>
        <span className="label-mono-sm">　</span>
      </div>
      <div style={{ flex:1, overflowY:'auto', padding:'0 22px' }}>
        <div className="label-mono-sm" style={{ color:'var(--amber)', marginBottom:6 }}>● 送出前 · ASKS FIRST</div>
        <h1 style={{ fontFamily:'var(--serif)', fontWeight:500, fontSize:24, lineHeight:1.35, margin:'0 0 12px', color:'var(--fg)' }}>
          這段要請 AI 整理嗎？<br/>
          <span style={{ color:'var(--fg-muted)', fontStyle:'italic', fontSize:18 }}>它會離開你的裝置。</span>
        </h1>
        <div style={{ padding:14, borderRadius:8, background:'var(--bg-soft)', borderLeft:'2px solid var(--amber)', marginBottom:18 }}>
          <div style={{ fontFamily:'var(--serif)', fontSize:13.5, lineHeight:1.65, color:'var(--fg)' }}>
            信任不是 default-on，也不是一個開關。它更像是一種地形——有山谷、有稜線、有路徑要慢慢被踩出來。
          </div>
        </div>
        <div className="label-mono-sm" style={{ marginBottom:8 }}>會發生什麼 · WHAT HAPPENS</div>
        <div style={{ display:'flex', flexDirection:'column', gap:10, marginBottom:16 }}>
          {[
            ['這段文字會送到 AI 服務','僅這次。不會留下副本。'],
            ['身分不會一起送','對 AI 而言這是一段匿名片段。'],
            ['結果回來後仍只在本地','你決定要不要採用——預設不採用。'],
          ].map(([t,sub],i)=>(
            <div key={i} style={{ display:'flex', gap:10 }}>
              <span style={{ width:14, marginTop:6, height:1, background:'var(--fg-faint)', flexShrink:0 }}/>
              <div>
                <div style={{ fontFamily:'var(--serif)', fontSize:13, color:'var(--fg)', fontWeight:500 }}>{t}</div>
                <div style={{ fontFamily:'var(--serif)', fontSize:11.5, color:'var(--fg-muted)', marginTop:2 }}>{sub}</div>
              </div>
            </div>
          ))}
        </div>
        <div style={{ padding:'12px 14px', background:'var(--bg-soft)', borderRadius:6, fontFamily:'var(--serif)', fontSize:11.5, color:'var(--fg-muted)', fontStyle:'italic', lineHeight:1.7 }}>
          這是越界動作。我們把它做得慢一點，是希望你願意停下來看一眼。
        </div>
      </div>
      <div style={{ display:'flex', gap:10, padding:'12px 22px', borderTop:'0.5px solid var(--rule)' }}>
        <button style={{ flex:1, background:'transparent', color:'var(--fg)', padding:'13px 16px', borderRadius:999, border:'0.5px solid var(--rule)', fontFamily:'var(--serif)', fontSize:13 }}>不送 · 留在本地</button>
        <button style={{ ...cta(), flex:1.2 }}>
          <span>送出 · 一次</span>
          <span style={{ opacity:0.55, fontFamily:'var(--mono)', fontSize:11 }}>→</span>
        </button>
      </div>
    </div>
  );
}

function cta() {
  return {
    background:'var(--fg)', color:'var(--bg)',
    padding:'15px 22px', borderRadius:999, border:'none',
    fontFamily:'var(--serif)', fontSize:15, letterSpacing:'0.08em',
    display:'flex', alignItems:'center', justifyContent:'space-between',
    gap:10, boxShadow:'0 4px 16px rgba(60,40,20,0.18)',
  };
}

Object.assign(window, { ScreenOnboardingWelcome, ScreenOnboardingPromise, ScreenOnboardingFirst, ScreenNotesHome, ScreenMurmurCapture, ScreenNoteWorkspace, ScreenNoteEdit, ScreenAIReview, cta });
