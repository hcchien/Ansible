// screen-wallet.jsx — passkey/identity wallet; "many selves, one device"

function ScreenWallet() {
  const Card = ({ name, en, type, sub, uses, age, primary, accent, dim }) => (
    <div style={{
      padding: '16px 18px',
      borderRadius: 8,
      background: primary ? 'var(--bg-soft)' : 'transparent',
      border: '0.5px solid ' + (primary ? 'var(--fg)' : 'var(--rule)'),
      display: 'flex', flexDirection: 'column', gap: 10,
      opacity: dim ? 0.65 : 1,
      position: 'relative',
    }}>
      {/* left rule for derived identity */}
      {accent && <div style={{
        position: 'absolute', left: 0, top: 14, bottom: 14, width: 2,
        background: 'var(--accent)', borderRadius: 1,
      }}/>}

      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
        <span style={{
          fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.18em',
          color: 'var(--fg-faint)', textTransform: 'uppercase',
        }}>{en}</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)', letterSpacing: '0.12em' }}>{age}</span>
      </div>

      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
        <span style={{ fontFamily: 'var(--serif)', fontSize: primary ? 22 : 17, fontWeight: 500, color: 'var(--fg)' }}>{name}</span>
        {primary && (
          <span style={{
            fontFamily: 'var(--mono)', fontSize: 8, letterSpacing: '0.18em',
            color: 'var(--accent)', padding: '2px 6px', border: '0.5px solid var(--accent)', borderRadius: 2,
          }}>主</span>
        )}
      </div>

      <div style={{ fontFamily: 'var(--serif)', fontSize: 12.5, lineHeight: 1.55, color: 'var(--fg-muted)', fontStyle: 'italic' }}>
        {sub}
      </div>

      {/* hashlike fragment */}
      <div style={{
        fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-faint)',
        letterSpacing: '0.06em', wordBreak: 'break-all',
      }}>
        {primary ? 'pk · 6f3a … 9c1e' : 'pk · ' + Math.random().toString(36).slice(2, 6) + ' … ' + Math.random().toString(36).slice(2, 6)}
      </div>

      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        paddingTop: 8, borderTop: '0.5px solid var(--rule-soft)',
      }}>
        <span style={{ fontFamily: 'var(--serif)', fontSize: 11, color: 'var(--fg-muted)' }}>{type}</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)', letterSpacing: '0.12em' }}>{uses}</span>
      </div>
    </div>
  );

  return (
    <div className="ph" style={{ height: '100%', paddingTop: 56, paddingBottom: 50, display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 22px 14px' }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.16em' }}>← 設定</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-faint)', letterSpacing: '0.16em' }}>WALLET</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-faint)', letterSpacing: '0.16em' }}>　</span>
      </div>

      <div style={{ flex: 1, overflowY: 'auto', padding: '0 22px' }}>
        <div className="label-mono-sm" style={{ marginBottom: 6 }}>身分 · IDENTITIES</div>
        <h1 style={{ fontFamily: 'var(--serif)', fontSize: 26, fontWeight: 500, margin: '0 0 6px', color: 'var(--fg)' }}>
          錢包
        </h1>
        <div style={{ fontFamily: 'var(--serif-en)', fontStyle: 'italic', fontSize: 13, color: 'var(--fg-muted)', marginBottom: 14 }}>
          one device, many selves
        </div>
        <div style={{ fontFamily: 'var(--serif)', fontSize: 13, lineHeight: 1.6, color: 'var(--fg-muted)', marginBottom: 18 }}>
          這些都是你。但你選擇在哪裡是哪一個。
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <Card primary
            name="本人" en="ROOT · MASTER PASSKEY" type="master passkey"
            sub="此裝置上產生的源頭。不能改名、不能複製、不能離開這台。"
            uses="所有圈與發布物的根" age="建立 312 天前"/>

          <Card accent
            name="公開 · Tris" en="PUBLIC HANDLE" type="衍生身分"
            sub="在討論串裡露出的名字。讀者只會看到這個。"
            uses="公開討論 · 23 處" age="278 天"/>

          <Card
            name="讀書會 · Tris" en="CIRCLE HANDLE" type="圈內身分"
            sub="只在「週四讀書會」內可見。離開圈就消失。"
            uses="1 個圈" age="92 天"/>

          <Card dim
            name="匿名瀏覽" en="OBSERVER" type="只讀身分"
            sub="拿來閱讀別人的公開內容；不留下任何痕跡。"
            uses="未啟用" age="未使用"/>
        </div>

        <button style={{
          marginTop: 18, width: '100%',
          padding: '14px 16px', borderRadius: 8,
          background: 'transparent', color: 'var(--fg)',
          border: '0.5px dashed var(--rule)',
          fontFamily: 'var(--serif)', fontSize: 14,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
        }}>
          <span style={{ fontSize: 16, color: 'var(--fg-muted)' }}>＋</span>
          <span>產生新身分</span>
        </button>

        <div style={{
          marginTop: 22, padding: '14px 16px',
          background: 'var(--bg-soft)', borderRadius: 6,
          fontFamily: 'var(--serif)', fontSize: 12, lineHeight: 1.7, color: 'var(--fg-muted)',
          fontStyle: 'italic',
        }}>
          身分都從「本人」衍生而來。彼此之間不可互推。<br/>
          就算公開的我被看穿了，圈內的我仍是隱密的。
        </div>

        <div style={{ height: 12 }}/>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenWallet });
