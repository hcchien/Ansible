// screen-inbox.jsx — calm inbox; replies / circle / sync grouped

function ScreenInbox() {
  const groups = [
    {
      label: '回應 · REPLIES',
      items: [
        { who: 'kr.', whoBg: 'var(--accent-soft)', whoColor: 'var(--accent)',
          where: '廢墟中的協作', text: '我在想 patches 翻譯成「斑塊」太冷了——',
          when: '14:22', unread: true, viz: 'public' },
        { who: '林下', whoBg: 'var(--bg-deep)', whoColor: 'var(--fg-muted)',
          where: 'Le Guin 的 Ansible', text: '你提到的「延遲」讓我想起 Stand on Zanzibar——',
          when: '13:08', unread: true, viz: 'circle' },
        { who: '路過的人', whoBg: 'var(--bg-deep)', whoColor: 'var(--fg-muted)',
          where: '一朵不認識的菇', text: '+1 林下這段。', when: '昨 22:14', viz: 'public' },
      ],
    },
    {
      label: '圈內 · CIRCLE',
      items: [
        { who: '週四讀書會', whoBg: 'var(--bg-soft)', whoColor: 'var(--fg-muted)',
          where: '林下', text: '加入了「廢墟中的協作」共讀',
          when: '今晨', system: true, unread: true },
        { who: '同居寫作組', whoBg: 'var(--bg-soft)', whoColor: 'var(--fg-muted)',
          where: 'kr.', text: '邀請了路過的人加入', when: '昨日', system: true },
      ],
    },
    {
      label: '裝置 · SYNC',
      items: [
        { who: 'iPad mini', whoBg: 'transparent', whoColor: 'var(--fg-muted)',
          where: '', text: '同步了 6 個 murmur · 11 篇筆記', when: '11:40', system: true, sync: true },
        { who: '舊手機', whoBg: 'transparent', whoColor: 'var(--fg-muted)',
          where: '', text: '已暫停同步 14 天', when: '2 週前', system: true, sync: true, dim: true },
      ],
    },
  ];

  return (
    <div className="ph" style={{ height: '100%', paddingTop: 56, paddingBottom: 40, display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 22px 4px' }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.16em' }}>← 草地</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.16em' }}>全部已讀</span>
      </div>

      <div style={{ padding: '8px 22px 14px' }}>
        <div className="label-mono-sm">收信 · INBOX</div>
        <h1 style={{ fontFamily: 'var(--serif)', fontSize: 26, fontWeight: 500, margin: '4px 0 6px', color: 'var(--fg)' }}>
          這一陣子
        </h1>
        <div style={{ fontFamily: 'var(--serif)', fontStyle: 'italic', fontSize: 12.5, color: 'var(--fg-faint)' }}>
          3 個還沒讀。其他都不急。
        </div>
      </div>

      <div style={{ flex: 1, overflowY: 'auto' }}>
        {groups.map((g, gi) => (
          <div key={gi}>
            <div className="label-mono-sm" style={{ padding: '14px 22px 8px' }}>{g.label}</div>
            <div style={{ borderTop: '0.5px solid var(--rule)', borderBottom: '0.5px solid var(--rule)' }}>
              {g.items.map((it, i) => (
                <div key={i} style={{
                  padding: '12px 22px', display: 'flex', gap: 12, alignItems: 'flex-start',
                  borderBottom: i === g.items.length - 1 ? 'none' : '0.5px solid var(--rule-soft)',
                  background: it.unread ? 'var(--bg-soft)' : 'transparent',
                  opacity: it.dim ? 0.6 : 1,
                  position: 'relative',
                }}>
                  {it.unread && <div style={{
                    position: 'absolute', left: 8, top: 22,
                    width: 5, height: 5, borderRadius: '50%', background: 'var(--accent)',
                  }}/>}
                  <div style={{
                    width: 28, height: 28, borderRadius: it.sync ? 4 : '50%',
                    background: it.whoBg, border: it.sync ? '0.5px solid var(--rule)' : 'none',
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    fontFamily: it.sync ? 'var(--mono)' : 'var(--serif)',
                    fontSize: it.sync ? 12 : 12, color: it.whoColor, flexShrink: 0,
                  }}>{it.sync ? '↔' : it.who[0]}</div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
                      <span style={{ fontFamily: 'var(--serif)', fontSize: 13, color: 'var(--fg)', fontWeight: it.unread ? 500 : 400 }}>{it.who}</span>
                      {it.where && (
                        <>
                          <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-faint)' }}>·</span>
                          <span style={{ fontFamily: 'var(--serif)', fontSize: 12, color: 'var(--fg-muted)', fontStyle: 'italic', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{it.where}</span>
                        </>
                      )}
                      <span style={{ flex: 1 }}/>
                      <span style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)', letterSpacing: '0.1em', flexShrink: 0 }}>{it.when}</span>
                    </div>
                    <div style={{
                      fontFamily: 'var(--serif)', fontSize: 12.5, lineHeight: 1.55,
                      color: it.system ? 'var(--fg-muted)' : 'var(--fg)',
                      marginTop: 4,
                      display: '-webkit-box', WebkitBoxOrient: 'vertical', WebkitLineClamp: 2, overflow: 'hidden',
                    }}>{it.text}</div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        ))}

        <div style={{
          padding: '24px 22px 8px', textAlign: 'center',
          fontFamily: 'var(--serif)', fontStyle: 'italic',
          fontSize: 11.5, color: 'var(--fg-faint)',
        }}>
          14 天前的都已歸檔
        </div>
        <div style={{ height: 24 }}/>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenInbox });
