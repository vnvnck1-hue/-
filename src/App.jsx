export default function App() {
  return (
    <div
      style={{
        minHeight: '100vh',
        background: '#0b1020',
        display: 'flex',
        flexDirection: 'column',
      }}
    >
      <div
        style={{
          padding: '10px 12px',
          color: '#e5e7eb',
          fontFamily: 'sans-serif',
          fontSize: 12,
          background: 'rgba(255,255,255,0.06)',
          borderBottom: '1px solid rgba(255,255,255,0.10)',
        }}
      >
        현재는 기존 단일 HTML을 그대로 표시합니다. (로직 변경 0%)
      </div>
      <iframe
        title="grid-defense-legacy"
        src="/defense_attack_visuals_bugfix_wave_exp_startlock.html"
        style={{
          flex: 1,
          width: '100%',
          border: 0,
        }}
      />
    </div>
  );
}

