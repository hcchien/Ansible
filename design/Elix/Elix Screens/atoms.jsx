// atoms.jsx — Elix-branded shared atoms for the social network screens.

// ─── Constellation mark (rotated 30°) ──────────────────────
function ElxMark({ size = 22, color = 'var(--fg)', dot = 'var(--amber)' }) {
  return (
    <svg width={size} height={size} viewBox="-100 -100 200 200">
      <g transform="rotate(30)">
        <g stroke={color} strokeWidth="9" strokeLinecap="round">
          <line x1="-60" y1="40" x2="60" y2="40"/>
          <line x1="-60" y1="40" x2="0" y2="-60"/>
          <line x1="60" y1="40" x2="0" y2="-60"/>
        </g>
        <g fill={color}>
          <circle cx="-60" cy="40" r="14"/>
          <circle cx="60" cy="40" r="14"/>
          <circle cx="0" cy="-60" r="14"/>
        </g>
        <circle cx="0" cy="6" r="8" fill={dot}/>
      </g>
    </svg>
  );
}

// ─── Elix wordmark (with amber tittle on I, broken X) ──────
function ElxWord({ height = 22, color = 'var(--fg)', accent = 'var(--amber)' }) {
  const sw = 14, H = 100;
  const mid = (H - sw) / 2, bot = H - sw;
  const iTop = sw * 1.7;
  const E = `M 0 0 L 64 0 L 64 ${sw} L ${sw} ${sw} L ${sw} ${mid} L 50 ${mid} L 50 ${mid+sw} L ${sw} ${mid+sw} L ${sw} ${bot} L 64 ${bot} L 64 ${H} L 0 ${H} Z`;
  const L = `M 88 0 L ${88+sw} 0 L ${88+sw} ${bot} L ${88+64} ${bot} L ${88+64} ${H} L 88 ${H} Z`;
  const I = `M 176 ${iTop} L ${176+sw} ${iTop} L ${176+sw} ${H} L 176 ${H} Z`;
  return (
    <svg viewBox={`-${sw/2} -${sw/2} ${292+sw} ${H+sw}`} height={height}
         style={{overflow:'visible', display:'block'}}>
      <path d={E} fill={color}/>
      <path d={L} fill={color}/>
      <path d={I} fill={color}/>
      <circle cx={176 + sw/2} cy={sw*0.62} r={sw*0.62} fill={accent}/>
      <line x1="214" y1="0"   x2="246.7" y2="43" stroke={color} strokeWidth={sw}/>
      <line x1="290" y1="0"   x2="257.3" y2="43" stroke={color} strokeWidth={sw}/>
      <line x1="214" y1="100" x2="246.7" y2="57" stroke={color} strokeWidth={sw}/>
      <line x1="290" y1="100" x2="257.3" y2="57" stroke={color} strokeWidth={sw}/>
    </svg>
  );
}

// ─── Header ─────────────────────────────────────────────────
function PhHeader({ chip = '本地', dot = 'var(--sage)', right }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '6px 22px 14px',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <ElxMark size={20}/>
        <ElxWord height={15}/>
      </div>
      {right || (
        <div style={{
          display: 'flex', alignItems: 'center', gap: 6,
          padding: '4px 10px', borderRadius: 999,
          border: '0.5px solid var(--rule)',
          fontFamily: 'var(--mono)', fontSize: 10, letterSpacing: '0.06em',
          color: 'var(--fg-muted)',
        }}>
          <span style={{ width: 6, height: 6, borderRadius: '50%', background: dot }}/>
          <span>{chip}</span>
        </div>
      )}
    </div>
  );
}

// ─── Section heading ───────────────────────────────────────
function PhSectionHead({ en, zh, action }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
      padding: '20px 22px 10px',
    }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
        <span style={{ fontFamily: 'var(--serif)', fontSize: 14, color: 'var(--fg)' }}>{zh}</span>
        <span style={{
          fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-faint)',
          letterSpacing: '0.18em', textTransform: 'uppercase',
        }}>{en}</span>
      </div>
      {action && (
        <span style={{
          fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--fg-muted)',
          letterSpacing: '0.1em',
        }}>{action}</span>
      )}
    </div>
  );
}

// ─── Visibility chip (Elix: trust dot = amber) ─────────────
function PhVizChip({ kind = 'private', size = 'sm' }) {
  const map = {
    private: { en: 'PRIVATE', dot: 'var(--fg-muted)' },
    circle:  { en: 'CIRCLE',  dot: 'var(--sage)' },
    public:  { en: 'PUBLIC',  dot: 'var(--amber)' },
    signed:  { en: 'SIGNED',  dot: 'var(--amber)' },
  };
  const m = map[kind];
  const sm = size === 'sm';
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: sm ? 5 : 7,
      padding: sm ? '3px 7px 3px 6px' : '4px 10px 4px 8px',
      borderRadius: 999, border: '0.5px solid var(--rule)',
      fontFamily: 'var(--mono)', fontSize: sm ? 9 : 10,
      letterSpacing: '0.1em', color: 'var(--fg-muted)', lineHeight: 1,
    }}>
      <span style={{ width: sm ? 4 : 5, height: sm ? 4 : 5, borderRadius: '50%', background: m.dot }}/>
      <span>{m.en}</span>
    </span>
  );
}

// ─── Lineage row — small constellation echo ────────────────
function PhLineage({ count, dates }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 10,
      padding: '8px 0', fontFamily: 'var(--serif)', fontSize: 11.5, color: 'var(--fg-faint)',
    }}>
      <svg width="38" height="14" viewBox="-19 -7 38 14">
        <g transform="rotate(30)">
          <line x1="-9" y1="6" x2="9" y2="6" stroke="var(--fg-faint)" strokeWidth="0.7"/>
          <line x1="-9" y1="6" x2="0" y2="-9" stroke="var(--fg-faint)" strokeWidth="0.7"/>
          <line x1="9" y1="6" x2="0" y2="-9" stroke="var(--fg-faint)" strokeWidth="0.7"/>
          <circle cx="-9" cy="6" r="1.8" fill="var(--fg-faint)"/>
          <circle cx="9" cy="6" r="1.8" fill="var(--fg-faint)"/>
          <circle cx="0" cy="-9" r="1.8" fill="var(--fg-faint)"/>
          <circle cx="0" cy="1" r="1.2" fill="var(--amber)"/>
        </g>
      </svg>
      <span>由 {count} 個 murmur 編成</span>
      {dates && (
        <span style={{
          fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.1em',
          color: 'var(--fg-faint)', opacity: 0.7, marginLeft: 'auto',
        }}>{dates}</span>
      )}
    </div>
  );
}

// ─── Note row ──────────────────────────────────────────────
function PhNoteRow({ title, body, count, date, visibility, last }) {
  return (
    <div style={{
      padding: '14px 22px',
      borderBottom: last ? 'none' : '0.5px solid var(--rule-soft)',
      display: 'flex', flexDirection: 'column', gap: 6,
    }}>
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 12 }}>
        <span style={{ fontFamily: 'var(--serif)', fontSize: 17, fontWeight: 500, color: 'var(--fg)' }}>{title}</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-faint)', letterSpacing: '0.08em', whiteSpace: 'nowrap' }}>{date}</span>
      </div>
      <span style={{
        fontFamily: 'var(--serif)', fontSize: 13, color: 'var(--fg-muted)', lineHeight: 1.5,
        display: '-webkit-box', WebkitBoxOrient: 'vertical', WebkitLineClamp: 2, overflow: 'hidden',
      }}>{body}</span>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 4 }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-faint)', letterSpacing: '0.06em' }}>· {count} murmur</span>
        <PhVizChip kind={visibility}/>
      </div>
    </div>
  );
}

function PhMurmurRow({ text, date, last }) {
  return (
    <div style={{
      padding: '11px 22px',
      borderBottom: last ? 'none' : '0.5px solid var(--rule-soft)',
      display: 'flex', alignItems: 'flex-start', gap: 12,
    }}>
      <span style={{ width: 5, height: 5, borderRadius: '50%', background: 'var(--amber)', marginTop: 8, flexShrink: 0, opacity: 0.7 }}/>
      <span style={{ flex: 1, fontFamily: 'var(--serif)', fontSize: 14, lineHeight: 1.55, color: 'var(--fg)', fontStyle: 'italic' }}>{text}</span>
      <span style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)', letterSpacing: '0.08em', marginTop: 4, flexShrink: 0 }}>{date}</span>
    </div>
  );
}

Object.assign(window, { ElxMark, ElxWord, PhHeader, PhSectionHead, PhVizChip, PhLineage, PhNoteRow, PhMurmurRow });
