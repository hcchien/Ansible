// screen-note-workspace.jsx — open note: serif body + lineage rail

function ScreenNoteWorkspace() {
  return (
    <div className="ph" style={{
      height: '100%', paddingTop: 56, paddingBottom: 50,
      display: 'flex', flexDirection: 'column',
    }}>
      {/* breadcrumb-style nav */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '8px 22px 6px',
      }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.16em' }}>← 草地</span>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
          <PhVizChip kind="private" size="sm"/>
          <span style={{ fontFamily: 'var(--mono)', fontSize: 13, color: 'var(--fg-muted)' }}>···</span>
        </div>
      </div>

      <div style={{ flex: 1, overflowY: 'auto', padding: '6px 22px 24px' }}>
        {/* meta line */}
        <div style={{
          fontFamily: 'var(--mono)', fontSize: 9.5, letterSpacing: '0.18em',
          color: 'var(--fg-faint)', textTransform: 'uppercase',
          marginBottom: 12,
        }}>NOTE · 始於 2026.04.21</div>

        {/* title */}
        <h1 style={{
          fontFamily: 'var(--serif)', fontWeight: 500,
          fontSize: 30, lineHeight: 1.2, margin: '0 0 16px',
          color: 'var(--fg)', letterSpacing: '0.005em',
        }}>末日松茸採集</h1>

        {/* lineage rail (極淡 inline) */}
        <PhLineage count={6} dates="04.21 → 04.27"/>
        <div style={{ height: 0.5, background: 'var(--rule-soft)', margin: '8px 0 18px' }}/>

        {/* body — interleaved murmurs marked with a tiny anchor */}
        <p style={{ fontFamily: 'var(--serif)', fontSize: 15, lineHeight: 1.75, margin: '0 0 14px', color: 'var(--fg)' }}>
          一朵一朵地撿，慢慢撿。林下不是空的——只是用看不見的方式生長著。Anna Tsing 把廢墟當成可棲居的地方；不是要修復，而是要學會在裡面活下去。
        </p>

        {/* a quoted murmur, set off */}
        <div style={{
          margin: '6px 0 16px', padding: '10px 14px',
          background: 'var(--bg-soft)', borderLeft: '1.5px solid var(--accent)',
          borderRadius: '0 8px 8px 0',
        }}>
          <span style={{ fontFamily: 'var(--serif)', fontStyle: 'italic', fontSize: 13.5, color: 'var(--fg)', lineHeight: 1.6 }}>
            松茸喜歡的是被擾動過、卻沒被毀掉的林子。
          </span>
          <div style={{ marginTop: 6, display: 'flex', alignItems: 'center', gap: 8, fontFamily: 'var(--mono)', fontSize: 8.5, letterSpacing: '0.14em', color: 'var(--fg-faint)' }}>
            <span>MURMUR · 04.27 14:36</span>
            <span style={{ width: 3, height: 3, borderRadius: '50%', background: 'var(--fg-faint)' }}/>
            <span>本地</span>
          </div>
        </div>

        <p style={{ fontFamily: 'var(--serif)', fontSize: 15, lineHeight: 1.75, margin: '0 0 14px', color: 'var(--fg)' }}>
          這也許正是 ansible 想做的事——不是消除距離，而是讓我們在距離中也能慢慢累積一點什麼。
        </p>

        <p style={{ fontFamily: 'var(--serif)', fontSize: 15, lineHeight: 1.75, margin: '0 0 14px', color: 'var(--fg-muted)', fontStyle: 'italic' }}>
          ……（往下還有幾段筆記與三則 murmur）
        </p>

        {/* divider */}
        <div style={{ height: 0.5, background: 'var(--rule-soft)', margin: '24px 0 16px' }}/>

        {/* bottom: where this note has been — sources */}
        <div style={{
          fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.18em',
          color: 'var(--fg-faint)', textTransform: 'uppercase',
          marginBottom: 8,
        }}>來源 · LINEAGE</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 7 }}>
          {[
            ['04.21 11:02', '林下不是空的——'],
            ['04.22 09:14', 'Tsing 的 patches'],
            ['04.24 22:08', '為什麼是「擾動過卻沒被毀掉」'],
            ['04.27 14:36', '松茸喜歡的是…'],
          ].map(([d, t]) => (
            <div key={d} style={{ display: 'flex', alignItems: 'baseline', gap: 12 }}>
              <span style={{ fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.1em', color: 'var(--fg-faint)', minWidth: 86 }}>{d}</span>
              <span style={{ fontFamily: 'var(--serif)', fontSize: 12, color: 'var(--fg-muted)', fontStyle: 'italic' }}>{t}</span>
            </div>
          ))}
          <span style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)', letterSpacing: '0.1em', marginTop: 4 }}>+ 還有 2 則</span>
        </div>
      </div>

      {/* Bottom action bar */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '12px 22px', borderTop: '0.5px solid var(--rule-soft)',
        background: 'var(--bg-soft)',
      }}>
        <div style={{ display: 'flex', gap: 18 }}>
          <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.14em' }}>編輯</span>
          <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.14em' }}>分享</span>
        </div>
        <button style={{
          background: 'transparent', color: 'var(--fg)',
          padding: '7px 14px', borderRadius: 999,
          border: '0.5px solid var(--rule)',
          fontFamily: 'var(--serif)', fontSize: 12, letterSpacing: '0.05em',
          display: 'flex', alignItems: 'center', gap: 8,
        }}>
          <span style={{ width: 5, height: 5, borderRadius: '50%', background: 'var(--accent)' }}/>
          請 AI 整理這篇 →
        </button>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenNoteWorkspace });
