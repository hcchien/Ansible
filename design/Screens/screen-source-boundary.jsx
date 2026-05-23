// screen-source-boundary.jsx — choose 私人/圈內/公開 + control what travels with it

function ScreenSourceBoundary() {
  const [picked, setPicked] = React.useState('circle');
  const [included, setIncluded] = React.useState({
    m1: true, m2: false, m3: true, m4: true, m5: true, m6: true,
  });

  const Row = ({ id, kind, label, en, sub, dim, last }) => {
    const on = picked === id;
    return (
      <div onClick={() => setPicked(id)} style={{
        padding: '14px 22px', display: 'flex', gap: 14, alignItems: 'flex-start',
        borderBottom: last ? 'none' : '0.5px solid var(--rule-soft)',
        background: on ? 'var(--bg-soft)' : 'transparent',
        cursor: 'pointer',
      }}>
        {/* radio dot */}
        <div style={{
          width: 16, height: 16, borderRadius: '50%',
          border: '0.5px solid ' + (on ? 'var(--fg)' : 'var(--rule)'),
          marginTop: 4, flexShrink: 0, position: 'relative',
          background: on ? 'var(--fg)' : 'transparent',
        }}>
          {on && <div style={{
            position: 'absolute', top: 4, left: 4, width: 6, height: 6,
            borderRadius: '50%', background: 'var(--bg)',
          }}/>}
        </div>
        <div style={{ flex: 1, opacity: dim ? 0.55 : 1 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
            <span style={{ fontFamily: 'var(--serif)', fontSize: 16, fontWeight: 500, color: 'var(--fg)' }}>{label}</span>
            <span style={{ fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.18em', color: 'var(--fg-faint)' }}>{en}</span>
          </div>
          <div style={{ fontFamily: 'var(--serif)', fontSize: 12.5, lineHeight: 1.5, color: 'var(--fg-muted)', marginTop: 4 }}>{sub}</div>
        </div>
      </div>
    );
  };

  const ItemRow = ({ id, text, kind, last }) => {
    const on = included[id];
    return (
      <div style={{
        padding: '10px 22px 10px 38px', display: 'flex', gap: 10, alignItems: 'center',
        borderBottom: last ? 'none' : '0.5px solid var(--rule-soft)',
      }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.14em', color: 'var(--fg-faint)', width: 36 }}>{kind}</span>
        <div style={{
          flex: 1, fontFamily: 'var(--serif)', fontSize: 12.5,
          color: on ? 'var(--fg)' : 'var(--fg-faint)',
          textDecoration: on ? 'none' : 'line-through',
          textDecorationColor: 'var(--fg-faint)',
        }}>{text}</div>
        <div onClick={() => setIncluded({ ...included, [id]: !on })} style={{
          width: 30, height: 17, borderRadius: 999,
          background: on ? 'var(--fg)' : 'var(--bg-deep)',
          border: '0.5px solid ' + (on ? 'var(--fg)' : 'var(--rule)'),
          position: 'relative', cursor: 'pointer', flexShrink: 0,
        }}>
          <div style={{
            position: 'absolute', top: 1.5, left: on ? 14 : 1.5,
            width: 12, height: 12, borderRadius: '50%',
            background: on ? 'var(--bg)' : 'var(--fg-faint)',
            transition: 'left 120ms',
          }}/>
        </div>
      </div>
    );
  };

  const cta = picked === 'private' ? '保留在本地' : picked === 'circle' ? '送往松茸圈' : '公開發布';

  return (
    <div className="ph" style={{
      height: '100%', paddingTop: 56, paddingBottom: 50,
      display: 'flex', flexDirection: 'column',
    }}>
      {/* nav */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 22px 16px' }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.16em' }}>← 取消</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-faint)', letterSpacing: '0.16em' }}>邊界 · BOUNDARY</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-faint)', letterSpacing: '0.16em' }}>　</span>
      </div>

      <div style={{ flex: 1, overflowY: 'auto' }}>
        {/* draft preview */}
        <div style={{ padding: '0 22px 18px' }}>
          <div className="label-mono-sm" style={{ marginBottom: 8 }}>草稿 · DRAFT</div>
          <div style={{
            padding: 14, borderRadius: 6,
            background: 'var(--bg-soft)',
            borderLeft: '2px solid var(--accent)',
          }}>
            <div style={{ fontFamily: 'var(--serif)', fontSize: 14.5, fontWeight: 500, color: 'var(--fg)', marginBottom: 4 }}>
              廢墟中的協作
            </div>
            <div style={{ fontFamily: 'var(--serif)', fontSize: 12, lineHeight: 1.6, color: 'var(--fg-muted)' }}>
              信任不是 default-on 的。每一次被看見都是選擇——
            </div>
          </div>
        </div>

        {/* option rows */}
        <div className="label-mono-sm" style={{ padding: '0 22px 8px' }}>送到哪裡 · WHERE</div>
        <div style={{ borderTop: '0.5px solid var(--rule)', borderBottom: '0.5px solid var(--rule)' }}>
          <Row id="private" label="留在本地" en="PRIVATE"
               sub="只這台裝置與你信任的同步圈。沒有他人可見。"/>
          <Row id="circle" label="松茸圈" en="CIRCLE · 4 人"
               sub="kr. · 林下 · 路過的人。passkey 點對點傳遞，無伺服器。"/>
          <Row id="public" label="公開發布" en="PUBLIC"
               sub="任何拿到連結的人都能讀。會進入討論串。" last/>
        </div>

        {/* what travels along */}
        {picked !== 'private' && (
          <div style={{ marginTop: 22 }}>
            <div className="label-mono-sm" style={{ padding: '0 22px 4px' }}>一併帶過去 · CARRIES</div>
            <div style={{ padding: '0 22px 12px' }}>
              <div style={{ fontFamily: 'var(--serif)', fontSize: 12, lineHeight: 1.6, color: 'var(--fg-muted)', fontStyle: 'italic' }}>
                這篇筆記由 6 個 murmur 構成。可以選擇哪些一起傳出。
              </div>
            </div>
            <div style={{ borderTop: '0.5px solid var(--rule)', borderBottom: '0.5px solid var(--rule)' }}>
              <ItemRow id="m1" kind="MURM"  text="如果信任是一種地形而非通道……"/>
              <ItemRow id="m2" kind="MURM"  text="今天看到一朵不認識的菇"/>
              <ItemRow id="m3" kind="MURM"  text="Anna Tsing 寫的 patches 並不浪漫"/>
              <ItemRow id="m4" kind="QUOTE" text="“The mushroom at the end of the world.”"/>
              <ItemRow id="m5" kind="MURM"  text="也許「補丁」更接近原意"/>
              <ItemRow id="m6" kind="MURM"  text="不必修復的鬆動感" last/>
            </div>
            <div style={{
              padding: '10px 22px', fontFamily: 'var(--serif)', fontStyle: 'italic',
              fontSize: 11.5, color: 'var(--fg-faint)',
            }}>
              被排除的 murmur 不會傳出，但筆記裡仍會留有「{Object.values(included).filter(v=>!v).length} 個來源未公開」的痕跡。
            </div>
          </div>
        )}

        <div style={{ height: 24 }}/>
      </div>

      {/* sticky CTA */}
      <div style={{
        position: 'absolute', bottom: 34, left: 0, right: 0,
        padding: '12px 22px',
        background: 'var(--bg)', borderTop: '0.5px solid var(--rule)',
        display: 'flex', alignItems: 'center', gap: 12,
      }}>
        <button style={{
          flex: 1, padding: '13px 16px', borderRadius: 999,
          background: 'var(--fg)', color: 'var(--bg)', border: 'none',
          fontFamily: 'var(--serif)', fontSize: 14, letterSpacing: '0.04em',
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
        }}>
          <span>{cta}</span>
          <svg width="14" height="10" viewBox="0 0 14 10">
            <path d="M 1 5 h 11 M 8 1 l 4 4 -4 4" stroke="var(--bg)" strokeWidth="1.3" fill="none" strokeLinecap="round"/>
          </svg>
        </button>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenSourceBoundary });
