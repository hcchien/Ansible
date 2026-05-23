// atoms.jsx — shared phone-screen atoms used by all Ansible screens.
// All colors come from CSS vars defined in the host page so day/night swaps work.

const PH_W = 402;

// ── Header: ansible mark + small wordmark + here chip ───────────
function PhHeader({ chip = '本地', dot = 'var(--spore)', right }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '6px 22px 14px',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
        <PhMark size={20}/>
        <span style={{
          fontFamily: 'var(--serif-en)', fontSize: 22, fontWeight: 300,
          letterSpacing: '-0.5px', color: 'var(--fg)',
        }}>ansible</span>
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

// ── The signal mark ─────────────────────────────────────────────
function PhMark({ size = 22, color = 'var(--fg)' }) {
  const s = size;
  return (
    <svg width={s} height={s} viewBox="0 0 32 32">
      <g fill="none" stroke={color} strokeLinecap="round">
        <path d="M 11 11 A 5 5 0 0 1 11 21" strokeWidth="1.5"/>
        <path d="M 11 8 A 8 8 0 0 1 11 24" strokeWidth="1" opacity="0.55"/>
      </g>
      <circle cx="11" cy="16" r="2.5" fill={color}/>
      <circle cx="24" cy="16" r="2.5" fill="none" stroke={color} strokeWidth="1.25"/>
    </svg>
  );
}

// ── Section heading: small mono uppercase + chinese caption ─────
function PhSectionHead({ en, zh, action }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
      padding: '20px 22px 10px',
    }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
        <span style={{
          fontFamily: 'var(--serif)', fontSize: 14, color: 'var(--fg)', fontWeight: 400,
        }}>{zh}</span>
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

// ── Visibility chip: 私人 / 圈內 / 公開 ─────────────────────────
function PhVizChip({ kind = 'private', size = 'sm' }) {
  const map = {
    private: { ch: '私', en: 'PRIVATE', dot: 'var(--fg-muted)', bg: 'transparent' },
    circle:  { ch: '圈', en: 'CIRCLE',  dot: 'var(--circle)',   bg: 'transparent' },
    public:  { ch: '公', en: 'PUBLIC',  dot: 'var(--accent)',   bg: 'transparent' },
  };
  const m = map[kind];
  const sm = size === 'sm';
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: sm ? 5 : 7,
      padding: sm ? '3px 7px 3px 6px' : '4px 10px 4px 8px',
      borderRadius: 999, border: '0.5px solid var(--rule)',
      fontFamily: 'var(--mono)', fontSize: sm ? 9 : 10,
      letterSpacing: '0.1em', color: 'var(--fg-muted)',
      background: m.bg, lineHeight: 1,
    }}>
      <span style={{ width: sm ? 4 : 5, height: sm ? 4 : 5, borderRadius: '50%', background: m.dot }}/>
      <span>{m.en}</span>
    </span>
  );
}

// ── Lineage row: "由 N 個 Murmur 構成" ──────────────────────────
function PhLineage({ count, dates }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 10,
      padding: '8px 0',
      fontFamily: 'var(--serif)', fontSize: 11.5, color: 'var(--fg-faint)',
    }}>
      {/* mini constellation */}
      <svg width="44" height="10" viewBox="0 0 44 10">
        {[3, 11, 18, 26, 32, 40].slice(0, Math.min(count, 6)).map((x, i) => (
          <circle key={i} cx={x} cy="5" r="1.5" fill="var(--fg-faint)" opacity={0.35 + i * 0.1}/>
        ))}
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

// ── Note row in list ────────────────────────────────────────────
function PhNoteRow({ title, body, count, date, visibility, last }) {
  return (
    <div style={{
      padding: '14px 22px',
      borderBottom: last ? 'none' : '0.5px solid var(--rule-soft)',
      display: 'flex', flexDirection: 'column', gap: 6,
    }}>
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 12 }}>
        <span style={{
          fontFamily: 'var(--serif)', fontSize: 17, fontWeight: 500,
          color: 'var(--fg)', letterSpacing: '0.01em',
        }}>{title}</span>
        <span style={{
          fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-faint)',
          letterSpacing: '0.08em', whiteSpace: 'nowrap',
        }}>{date}</span>
      </div>
      <span style={{
        fontFamily: 'var(--serif)', fontSize: 13, color: 'var(--fg-muted)',
        lineHeight: 1.5,
        display: '-webkit-box', WebkitBoxOrient: 'vertical', WebkitLineClamp: 2,
        overflow: 'hidden',
      }}>{body}</span>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 4 }}>
        <span style={{
          fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--fg-faint)',
          letterSpacing: '0.06em',
        }}>· {count} murmur</span>
        <PhVizChip kind={visibility}/>
      </div>
    </div>
  );
}

// ── Murmur row (smaller, italic-tinged) ─────────────────────────
function PhMurmurRow({ text, date, last }) {
  return (
    <div style={{
      padding: '11px 22px',
      borderBottom: last ? 'none' : '0.5px solid var(--rule-soft)',
      display: 'flex', alignItems: 'flex-start', gap: 12,
    }}>
      <span style={{
        width: 5, height: 5, borderRadius: '50%', background: 'var(--fg-faint)',
        marginTop: 8, flexShrink: 0,
      }}/>
      <span style={{
        flex: 1, fontFamily: 'var(--serif)', fontSize: 14, lineHeight: 1.55,
        color: 'var(--fg)', fontStyle: 'italic',
      }}>{text}</span>
      <span style={{
        fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--fg-faint)',
        letterSpacing: '0.08em', marginTop: 4, flexShrink: 0,
      }}>{date}</span>
    </div>
  );
}

// ── Placeholder screen ──────────────────────────────────────────
function ScreenPlaceholder({ label, hint }) {
  return (
    <div className="ph" style={{
      height: '100%', paddingTop: 64, paddingBottom: 50,
      display: 'flex', flexDirection: 'column',
    }}>
      <PhHeader/>
      <div style={{
        flex: 1, display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center', gap: 12,
        padding: '0 32px', textAlign: 'center',
      }}>
        <div style={{
          width: 60, height: 60, border: '0.5px dashed var(--rule)',
          borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: 'var(--fg-faint)',
        }}>
          <PhMark size={28} color="var(--fg-faint)"/>
        </div>
        <span style={{ fontFamily: 'var(--serif)', fontSize: 18, color: 'var(--fg-muted)' }}>{label}</span>
        <span style={{
          fontFamily: 'var(--serif)', fontSize: 12, color: 'var(--fg-faint)',
          fontStyle: 'italic', lineHeight: 1.6,
        }}>{hint}</span>
        <span style={{
          fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.18em',
          color: 'var(--fg-faint)', marginTop: 8,
        }}>TO DESIGN</span>
      </div>
    </div>
  );
}

Object.assign(window, {
  PhHeader, PhMark, PhSectionHead, PhVizChip, PhLineage, PhNoteRow, PhMurmurRow, ScreenPlaceholder,
});
