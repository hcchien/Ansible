/* Elix Web — frame matrix builder: 6 pages × 3 sizes.
   Each page is defined once and rendered at desktop / tablet / mobile. */
(function(){
  const seal = s => `<span class="seal"><svg width="${s||14}" height="${s||14}"><use href="#ic-seal"/></svg></span>`;
  const ic = (id,s) => `<svg width="${s}" height="${s}"><use href="#ic-${id}"/></svg>`;

  // ── shared chrome ──
  function wtop(active, guest){
    const ctx = guest
      ? `<button class="btn-signin">登入</button><span class="ghost-pill">匿名 · 唯讀</span>`
      : `<button class="icon-btn">${ic('bell',17)}<span class="badge"></span></button><span class="session-chip"><span class="av">T</span><span class="who">tris.elix.cool</span><span class="tier">PK</span></span>`;
    return `<div class="wtop">
      <div class="brand"><svg width="24" height="24" style="color:var(--fg)"><use href="#elx-mark"/></svg><span class="word">Elix</span>${guest?'<span class="tag">Social Identity</span>':''}</div>
      <div class="wsearch">${ic('search',16)}找人、找討論板、找關鍵字 …</div>
      <div class="ctx">${ctx}</div>
    </div>`;
  }
  const NAV = [['home','動態','home'],['search','發現','discover'],['bell','通知','notif'],['board','看板','board'],['eye','你','you']];
  function railFull(active){
    const items = NAV.map(([i,zh,key])=>`<a class="rail-item ${key===active?'on':''}" href="#">${ic(i,22)}<span>${zh}</span>${key==='notif'?'<span class="nd"></span>':''}</a>`).join('');
    return `<aside class="rail">
      <div><h4>探索 · Navigate</h4>${items}</div>
      <div><h4>追蹤的人 · 8</h4>
        <a class="follow-row signed" href="#"><span class="av">M</span><div class="meta"><span class="n">mira.elix.cool${seal(12)}</span><span class="h">signed</span></div><span class="ago">2h</span></a>
        <a class="follow-row signed" href="#"><span class="av">K</span><div class="meta"><span class="n">kr.elix.cool${seal(12)}</span><span class="h">signed</span></div><span class="ago">5h</span></a>
        <a class="follow-row" href="#"><span class="av">N</span><div class="meta"><span class="n">nadia.elix.cool</span><span class="h">basic</span></div><span class="ago">1d</span></a>
      </div>
      <div><h4>訂閱的板 · 3</h4>
        <a class="follow-row" href="#"><span class="hashav">#</span><div class="meta"><span class="n">philosophy</span><span class="h">關於信任的地形</span></div><span class="ago">3 新</span></a>
        <a class="follow-row" href="#"><span class="hashav">#</span><div class="meta"><span class="n">tools</span><span class="h">passkey & 同步</span></div><span class="ago">12 新</span></a>
        <a class="follow-row" href="#"><span class="hashav">#</span><div class="meta"><span class="n">design</span><span class="h">介面設計</span></div><span class="ago">1 新</span></a>
      </div>
    </aside>`;
  }
  function railIcons(active){
    return `<aside class="rail icons">${NAV.map(([i,zh,key])=>`<a class="rail-item ${key===active?'on':''}" href="#">${ic(i,22)}<span>${zh}</span>${key==='notif'?'<span class="nd"></span>':''}</a>`).join('')}</aside>`;
  }
  function mtop(right){ return `<div class="mtop"><span class="brand"><svg width="22" height="22" style="color:var(--fg)"><use href="#elx-mark"/></svg>Elix</span>${right||'<span class="session-chip"><span class="av">T</span><span class="tier">PK</span></span>'}</div>`; }
  function mtab(active){
    const T=[['home','home'],['circle','circle'],['plus','center'],['bell','notif'],['eye','you']];
    return `<div class="mtabbar">${T.map(([i,k])=>{
      if(k==='center') return `<div class="tab center">${ic('plus',20)}</div>`;
      return `<div class="tab ${k===active?'on':''}">${ic(i,20)}${k==='notif'?'<span class="nd"></span>':''}</div>`;
    }).join('')}</div>`;
  }
  const trends = `<aside class="side"><div class="card"><h5>熱門看板 · Trending</h5>
      <div class="trend"><div class="tag"># philosophy</div><div class="n">3 串 · 已訂閱</div></div>
      <div class="trend"><div class="tag"># tools</div><div class="n">12 則新貼文</div></div>
      <div class="trend"><div class="tag"># design</div><div class="n">1 則新貼文</div></div></div>
    <div class="card"><h5>你的承諾 · Local-first</h5>
      <div class="mini-promise"><span class="dot" style="background:var(--sage)"></span><div class="tx"><b>資料留在本地。</b>不上雲、不索引、不分析。</div></div>
      <div class="mini-promise" style="margin-top:12px;"><span class="dot" style="background:var(--amber)"></span><div class="tx"><b>送出前先問你。</b>網頁只有你在 app 核准的權限。</div></div></div></aside>`;

  // ── post card ──
  function post(o){
    const fs = o.fs ? ` style="font-size:${o.fs}px;"` : '';
    const acts = o.mini
      ? `<div class="actions"><button class="act heart ${o.heartOn?'on':''}">${ic('heart',21)}<span class="c">${o.hearts}</span></button><button class="act">${ic('comment',21)}<span class="c">${o.comments}</span></button></div>`
      : `<div class="actions">
          <button class="act heart ${o.heartOn?'on':''}">${ic('heart',21)}<span class="c">${o.hearts}</span></button>
          <button class="act">${ic('comment',21)}<span class="c">${o.comments}</span></button>
          <button class="act">${ic('repost',21)}</button>
          <button class="act share">${ic('share',21)}</button></div>`;
    return `<article class="post ${o.signed?'signed':''} ${o.anon?'anon':''}">
      <div class="lane"><span class="av">${o.av}</span>${o.line?'<span class="thread-line"></span>':''}</div>
      <div class="body">
        <div class="row1"><span class="handle">${o.handle}${o.signed?seal(o.mini?13:14):''}</span><span class="when">${o.when}</span></div>
        ${o.src?`<div class="src">${o.src}</div>`:''}
        ${o.heading?`<h3 class="heading"${o.fs?` style="font-size:${o.fs+1}px;"`:''}>${o.heading}</h3>`:''}
        <div class="text"${fs}>${o.text}</div>
        ${o.photo?`<div class="photo">${o.photo}</div>`:''}
        ${acts}
      </div></article>`;
  }

  // ── pages (return inner surface HTML) ──
  const feedPosts = compact => [
    post({signed:1,line:1,av:'M',handle:'mira.elix.cool',when:'2h',src:'追蹤中 · <span class="b">signed</span>',heading:'我們在重建什麼樣的網路？',text:'<p>關於默許可見、身分自主、社群健康的長對話。<span class="muted">便利往往是監控偽裝的禮物。</span></p>',photo:compact?null:'PHOTO · 舊筆記內頁',heartOn:1,hearts:42,comments:7,fs:compact?15:null}),
    post({signed:1,line:1,av:'K',handle:'kr.elix.cool',when:'5h',src:'看板 · <span class="b">#philosophy</span>',text:'<p>passkey 在跨平台上還是不夠順，今天在 Linux 上重新登入花了 40 分鐘。但這就是「不便」的成本。</p>'+(compact?'':'<p class="quote">便利往往是監控偽裝成的禮物。</p>'),heartOn:1,hearts:28,comments:41,fs:compact?15:null}),
    post({anon:1,av:'·',handle:'匿名 · anon_x9b3',when:'昨日',src:'看板 · <span class="b">#philosophy</span> · 匿名發文',text:'<p>刪掉社群帳號的第 47 天。第一個月最難，你會發現自己一天打開 18 次空白的桌面。</p>',hearts:156,comments:23,fs:compact?15:null})
  ].join('');

  function pageFeed(size){
    if(size==='m') return mtop()+`<div class="mpad">${feedPosts(true)}</div>`+mtab('home');
    const rail = size==='t'?railIcons('home'):railFull('home');
    const side = size==='t'?trends:trends; // both show trends
    return wtop('home')+`<div class="cols ${size==='t'?'tablet':''}">${rail}
      <main class="feed"><div class="compose"><span class="av">T</span><span class="hint">說點什麼，tris…</span><button class="btn-post">發布</button></div>${feedPosts(false)}</main>${side}</div>`;
  }

  const boardThreads = `
    <div class="bthread"><div class="st"><span class="d new"></span>0 則回覆 · 新討論</div><div class="ttl">大家好，我是 B（測試追蹤）</div><div class="by"><span class="av">大</span><span class="n"><span class="did-handle" style="font-size:12.5px;">did:eli…pg7h74</span> <span class="pk-pill">✓ PK</span></span><span class="m">· 2026-06-21 14:16 UTC</span></div></div>
    <div class="bthread"><div class="st"><span class="d"></span>2 則回覆 · 進行中</div><div class="ttl">不見了</div><div class="by"><span class="av">不</span><span class="n"><span class="did-handle" style="font-size:12.5px;">did:plc…5xozmu</span> <span class="pk-pill">✓ PK</span></span><span class="m">· 2026-06-20 03:08 UTC</span></div></div>`;
  const boardBanner = `<div class="board-banner"><div class="crumb" style="font-family:var(--mono);font-size:11px;letter-spacing:0.14em;color:var(--fg-faint);text-transform:uppercase;">Board · 討論板</div><div class="h">FIFA2026</div><div class="blurb">這個板會作為 feed 的一個來源。你可以閱讀 thread，也可以把 Note 或 Murmur 延伸成板上的討論。</div><div class="stats"><span class="s">權限 <b style="color:var(--amber);">唯讀</b></span><span class="s">信任層級 <b style="color:var(--amber);">匿名</b></span></div><button class="sub-btn">登入後發文</button></div>`;

  function pageBoard(size){
    const listHead = `<div style="display:flex;align-items:baseline;justify-content:space-between;padding:16px 4px 4px;"><span style="font-family:var(--sans);font-size:14px;font-weight:700;color:var(--fg);">討論串 · 2</span><span style="font-family:var(--mono);font-size:11px;letter-spacing:0.16em;color:var(--fg-faint);text-transform:uppercase;">Board Activity</span></div>`;
    if(size==='m') return `<div class="mtop"><span class="brand">${ic('chev',18)}<span style="font-family:var(--mono);font-size:12px;letter-spacing:0.14em;color:var(--amber);">FIFA2026</span></span><button class="icon-btn">${ic('plus',16)}</button></div>`
      + `<div class="mpad plain">${boardBanner}${listHead}${boardThreads}</div>`+mtab('board');
    const rail = size==='t'?railIcons('board'):railFull('board');
    return wtop('board')+`<div class="cols ${size==='t'?'tablet':''}">${rail}
      <main class="feed">${boardBanner}${listHead}${boardThreads}</main>
      <aside class="side"><div class="card"><h5>看板資訊 · Board</h5><div class="mini-promise"><span class="dot" style="background:var(--amber)"></span><div class="tx"><b>唯讀看板。</b>信任層級：匿名。登入後可發文。</div></div><button class="sub-btn" style="margin-top:14px;">登入後發文</button></div></aside></div>`;
  }

  const articleHd = `<div class="thread-hd"><div class="crumb">Thread · 討論串</div><div class="ttl">不見了</div><div class="meta"><span class="did-handle">did:plc…5xozmu</span> <span class="pk-pill">✓ PK</span> · 2 則回覆 · 2026-06-20 03:08 UTC</div></div>`;
  function reply(o){
    const av = o.anon ? '<span class="rav anon">·</span>' : `<span class="rav signed">${o.av}</span>`;
    const name = o.anon ? '<span class="rname anon">匿名</span>' : `<span class="rname">${o.handle}</span>`;
    return `<div class="reply">${av}<div class="rc"><div class="rtop">${name}<span class="rwhen">${o.when}</span></div><div class="rbody">${o.text}</div><div class="ract"><span class="m ${o.heartOn?'on':''}">${ic('heart',16)}${o.hearts}</span><span class="m">${ic('comment',16)}回覆</span></div></div></div>`;
  }
  function articleBody(compact){
    const op = post({signed:1,line:1,av:'不',handle:'did:plc…5xozmu',when:'2026-06-20 03:08 UTC',src:compact?null:'起頭 · <span class="b">signed · PK</span>',text:'<p>不見了</p>',heartOn:0,hearts:3,comments:2,fs:compact?15:null});
    const reps = `<div class="replies"><div class="replies-head">回覆 · <b>2</b></div>`
      + reply({anon:1,when:'2026-06-20 05:12 UTC',text:'文章不見了？！',hearts:1})
      + reply({anon:1,when:'2026-06-20 06:40 UTC',text:'不然呢？！',hearts:0})
      + `</div>`;
    const box = `<div class="reply-box"><span class="av">T</span><span class="field">回覆這則討論…</span><button class="send">回覆</button></div>`;
    return op+box+reps;
  }
  function pageArticle(size){
    if(size==='m') return `<div class="mtop"><span class="brand">${ic('chev',18)}<span style="font-family:var(--mono);font-size:12px;letter-spacing:0.14em;color:var(--amber);">回到看板</span></span><button class="icon-btn">${ic('share',16)}</button></div>`
      + `<div class="mpad plain">${articleHd}</div><div class="mpad">${articleBody(true)}</div>`+mtab('board');
    const rail = size==='t'?railIcons('board'):railFull('board');
    return wtop('board')+`<div class="cols ${size==='t'?'tablet':''}">${rail}
      <main class="feed">${articleHd}${articleBody(false)}</main>
      <aside class="side"><div class="card"><h5>看板 · Board</h5><div class="mini-promise"><span class="dot" style="background:var(--amber)"></span><div class="tx"><b># FIFA2026</b> · 唯讀 · 信任層級：匿名。</div></div></div></aside></div>`;
  }

  const notifRows = `
    <div class="notif"><span class="g">${ic('comment',20)}</span><div class="tx"><div class="who">mira.elix.cool</div><div class="what">回覆了你的留言</div></div><div class="meta"><span class="when">13 小時前</span><span class="dot"></span></div></div>
    <div class="notif"><span class="g">${ic('heart',20)}</span><div class="tx"><div class="who">kr.elix.cool</div><div class="what">對你的貼文按了愛心</div></div><div class="meta"><span class="when">15 小時前</span><span class="dot"></span></div></div>
    <div class="notif"><span class="g">${ic('circle',20)}</span><div class="tx"><div class="who">nadia.elix.cool</div><div class="what">開始追蹤你</div></div><div class="meta"><span class="when">16 小時前</span></div></div>
    <div class="notif"><span class="g">${ic('repost',20)}</span><div class="tx"><div class="who">boheng.elix.cool</div><div class="what">轉發了你在 #philosophy 的貼文</div></div><div class="meta"><span class="when">1 天前</span></div></div>`;
  function pageNotif(size){
    if(size==='m') return mtop('<span class="nav-link">全部已讀</span>')+`<div class="mpad plain">${notifRows}</div>`+mtab('notif');
    const rail = size==='t'?railIcons('notif'):railFull('notif');
    return wtop('notif')+`<div class="cols two ${size==='t'?'tablet':''}" style="grid-template-columns:${size==='t'?'64px':'248px'} minmax(0,1fr);">${rail}
      <main class="feed"><div style="display:flex;align-items:baseline;justify-content:space-between;padding:2px 4px 6px;"><div class="page-title" style="padding:0;">通知</div><span class="nav-link">全部已讀</span></div>${notifRows}</main></div>`;
  }

  function loginPanel(state){ // state: 'idle' interactive, 'wait' static
    const idle = state==='idle';
    return `<div class="login-panel">
      <span class="kick">App Login · APP 登入</span>
      <h2>用 Elix app 登入</h2>
      <p class="lede">產生 QR code，然後用 Elix app 掃描核准。網頁端不會拿到你的私鑰。</p>
      <button class="btn-gen" ${idle?'data-gen':''}>${ic('qr',20)}<span ${idle?'data-genlabel':''}>${idle?'產生登入 QR code':'等待 app 掃描…'}</span></button>
      <div class="gen-status" ${idle?'data-status':''}>${idle?'尚未產生 QR code。':'<span class="pulse"></span>等待 Elix app 掃描核准…'}</div>
      <div class="scopes-head">Requested Scopes · 要求權限</div>
      <div class="scope-empty" ${idle?'data-empty':''} ${idle?'':'style="display:none"'}>尚未授權任何權限。</div>
      <div class="scope-list ${idle?'':'show'}" ${idle?'data-scopes':''}>
        <div class="scope"><span class="g">${ic('read',18)}</span><div><div class="nm">讀取動態<span class="en">read feed</span></div></div><span class="ok">✓ 允許</span></div>
        <div class="scope"><span class="g">${ic('write',18)}</span><div><div class="nm">代發貼文<span class="en">post</span></div></div><span class="ok">✓ 允許</span></div>
        <div class="scope"><span class="g">${ic('person',18)}</span><div><div class="nm">讀取 handle<span class="en">identity</span></div></div><span class="ok">✓ 允許</span></div>
      </div>
    </div>`;
  }
  const loginNote = `<div class="login-note"><span class="dot"></span><div><div class="zh">身分留在 Elix app</div><div class="tx">在 Elix 核准一次，讓這個瀏覽器取得有限、可隨時撤銷的權限。<code>key material</code> 不會離開 app。</div></div></div>`;
  function qrStage(live){
    const empty = `<div class="qr-empty">${ic('qr',40)}<span class="lab">尚未產生 QR code</span></div>`;
    const code = `<svg class="qr-code" viewBox="0 0 100 100" shape-rendering="crispEdges"><use href="#qr-pattern"/></svg>`;
    return `<div class="qr-stage ${live?'live':''}" ${live?'':'data-stage'}><div class="qr-box">${empty}${code}</div>
      <div class="qr-cap"><div class="zh" ${live?'':'data-zh'}>${live?'用 Elix app 掃描':'按下產生後掃描'}</div><div class="sub" ${live?'':'data-sub'}>${live?'開啟 Elix app → 設定 → 掃描登入。':'按下右側按鈕後，用 Elix app 掃描這裡的 QR code。'}</div></div></div>`;
  }
  function pageLogin(size){
    if(size==='m') return mtop('<span class="ghost-pill">匿名 · 唯讀</span>')
      + `<div class="login-wrap stack"><div class="login-vis">${qrStage(true)}</div>${loginPanel('wait')}</div>${loginNote}`;
    // desktop interactive, tablet static-wait
    const interactive = size==='d';
    return wtop(null,true)+`<div class="login-wrap"><div class="login-vis">${qrStage(!interactive)}</div>${loginPanel(interactive?'idle':'wait')}</div>${loginNote}`;
  }

  function pageSettings(size){
    const groups = `
      <div class="set-group"><div class="glabel">此瀏覽器的存取 · Web session</div>
        <div class="set-row"><span class="g">${ic('wallet',20)}</span><div><div class="nm">已授權的權限</div><div class="sub">讀取動態、代發貼文、讀取 handle 身分</div></div><span class="val">3 項 ${ic('chev',16)}</span></div>
        <div class="set-row"><span class="g">${ic('sync',20)}</span><div><div class="nm">Elix Relay</div><div class="sub">同步中繼設定</div></div><span class="val">已連線 ${ic('chev',16)}</span></div>
        <div class="set-row"><span class="g">${ic('finger',20)}</span><div><div class="nm">撤銷此瀏覽器</div><div class="sub">登出並移除這台裝置的權限</div></div><span class="val" style="color:var(--ember);">撤銷 ${ic('chev',16)}</span></div>
      </div>
      <div class="set-group"><div class="glabel">介面 · 每版的光</div>
        <div class="swrow"><div class="swatch sel"><span class="chip paper"></span><span class="nm">Paper</span></div><div class="swatch"><span class="chip ink"></span><span class="nm">Ink</span></div><div class="swatch"><span class="chip auto"></span><span class="nm">Auto</span></div></div>
        <div class="set-row" style="margin-top:12px;"><span class="g">${ic('lang',20)}</span><div><div class="nm">語言</div><div class="sub">介面語言</div></div><span class="val">跟隨系統 ${ic('chev',16)}</span></div>
      </div>`;
    const profile = `<div class="set-profile"><span class="avb">${ic('person',size==='m'?28:34)}</span><div><h2>tris.elix.cool <span class="pk-badge">✓ PK</span></h2><div class="did">web session · did:plc:tris</div></div>${size==='m'?'':'<span class="edit">編輯</span>'}</div>`;
    if(size==='m') return mtop()+`<div class="m-set">${profile}${groups}</div>`+mtab('you');
    return wtop('you')+`<div class="set-wrap">${profile}${groups}</div>`;
  }

  // ── matrix ──
  const PAGES = [
    ['登入 / QR → app', pageLogin, {d:'elix.social/login',t:'elix.social/login',m:'elix.social/login'}],
    ['動態 / Timeline', pageFeed, {d:'elix.social/home',t:'elix.social/home',m:'elix.social/home'}],
    ['看板 / Board（討論串列表）', pageBoard, {d:'elix.social/b/philosophy',t:'elix.social/b/philosophy',m:'elix.social/b/philosophy'}],
    ['單篇文章 / Article + 留言', pageArticle, {d:'elix.social/b/philosophy/…',t:'elix.social/b/philosophy/…',m:'elix.social/b/philosophy/…'}],
    ['通知 / Notifications', pageNotif, {d:'elix.social/notifications',t:'elix.social/notifications',m:'elix.social/notifications'}],
    ['設定 / Settings', pageSettings, {d:'elix.social/settings',t:'elix.social/settings',m:'elix.social/settings'}],
  ];
  const SIZES = [['d','DESKTOP','1280','','桌機 · 三欄'],['t','TABLET','834','tablet','平板 · 細導覽列'],['m','MOBILE','404','mobile','手機 · 單欄＋底部導覽']];

  const row = document.getElementById('frameRow');
  let html = '';
  SIZES.forEach(([sk,slabel,swidth,scls,ssub])=>{
    html += `<div class="size-divider"><span class="lbl">${slabel} · ${swidth}</span><span class="sub">${ssub}</span><span class="line"></span></div>`;
    PAGES.forEach(([name,fn,urls],i)=>{
      const n = String(i+1).padStart(2,'0');
      const lock = urls[sk].endsWith('login') ? '🔒' : '🔒';
      html += `<div>
        <div class="frame-cap"><span class="kind">${slabel[0]}${n}</span><span class="name">${name}</span><span class="w">${slabel} · ${swidth}</span></div>
        <div class="browser ${scls}"><div class="chrome"><div class="dots"><i></i><i></i><i></i></div><div class="url"${sk==='m'?' style="font-size:10.5px;"':''}><span class="lock">${lock}</span>${urls[sk]}</div></div>
        <div class="surface">${fn(sk)}</div></div>
      </div>`;
    });
  });
  row.innerHTML = html;

  // ── desktop login interactivity ──
  const genBtn = row.querySelector('[data-gen]');
  if(genBtn){
    const scope = genBtn.closest('.surface');
    const stage = scope.querySelector('[data-stage]');
    const status = scope.querySelector('[data-status]');
    const genLabel = scope.querySelector('[data-genlabel]');
    const empty = scope.querySelector('[data-empty]');
    const scopes = scope.querySelector('[data-scopes]');
    const zh = scope.querySelector('[data-zh]');
    const sub = scope.querySelector('[data-sub]');
    let state = 0;
    genBtn.addEventListener('click',()=>{
      if(state===2){ state=0; stage.classList.remove('live'); scopes.classList.remove('show'); empty.style.display='';
        genLabel.textContent='產生登入 QR code'; status.innerHTML='尚未產生 QR code。';
        zh.textContent='按下產生後掃描'; sub.textContent='按下右側按鈕後，用 Elix app 掃描這裡的 QR code。'; return; }
      state=1; stage.classList.add('live'); genLabel.textContent='等待 app 掃描…';
      status.innerHTML='<span class="pulse"></span>等待 Elix app 掃描核准…';
      zh.textContent='用 Elix app 掃描'; sub.textContent='開啟 Elix app → 設定 → 掃描登入，對準這個 QR code。';
      setTimeout(()=>{ state=2; empty.style.display='none'; scopes.classList.add('show');
        genLabel.textContent='已核准 · 進入 Elix'; status.innerHTML='✓ 已在 app 核准 · 此瀏覽器已取得有限權限';
        zh.textContent='已核准 ✓'; sub.textContent='身分留在 app，這個瀏覽器只拿到你允許的權限。'; },2600);
    });
  }
})();
