import { h } from 'preact';
import { useState, useEffect } from 'preact/hooks';
import { request } from '@utilities/http';

export function UserMockExamDashboard() {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    request('/mock_exams/dashboard.json')
      .then((res) => res.json())
      .then((d) => {
        setData(d);
        setLoading(false);
      })
      .catch(() => setLoading(false));
  }, []);

  if (loading) {
    return (
      <div class="crayons-card p-6 flex justify-center">
        <div class="crayons-loading" aria-label="Loading dashboard..." />
      </div>
    );
  }

  if (!data) {
    return (
      <div class="crayons-card p-6 text-center">
        <p class="color-secondary">Unable to load your dashboard.</p>
      </div>
    );
  }

  return (
    <div>
      <h1 class="crayons-title mb-4">My Mock Exams</h1>

      {/* Summary Cards */}
      <div class="grid gap-4 mb-6" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))' }}>
        <SummaryCard label="Total Attempts" value={data.total_attempts} />
        <SummaryCard label="Exams Completed" value={data.completed_attempts} />
        <SummaryCard label="Best Score" value={data.best_score ? `${data.best_score}%` : '—'} accent />
        <SummaryCard label="Avg Accuracy" value={data.avg_accuracy ? `${data.avg_accuracy}%` : '—'} />
        <SummaryCard label="Current Streak" value={`${data.streak_days || 0} days`} />
      </div>

      {/* Performance Trend */}
      {data.trend && data.trend.length > 1 && (
        <div class="crayons-card p-6 mb-4">
          <h3 class="crayons-subtitle-2 mb-3">Performance Trend</h3>
          <PerformanceTrend trend={data.trend} />
        </div>
      )}

      {/* Topic Strengths */}
      {data.section_accuracy && Object.keys(data.section_accuracy).length > 0 && (
        <div class="crayons-card p-6 mb-4">
          <h3 class="crayons-subtitle-2 mb-3">Topic Strengths</h3>
          <TopicRadar sections={data.section_accuracy} />
        </div>
      )}

      {/* Attempt History */}
      <div class="crayons-card p-6">
        <h3 class="crayons-subtitle-2 mb-3">Attempt History</h3>
        {(!data.attempts || data.attempts.length === 0) ? (
          <p class="color-secondary text-center">
            No attempts yet. <a href="/mock_exams">Start your first exam!</a>
          </p>
        ) : (
          <table class="crayons-table" style={{ width: '100%' }}>
            <thead>
            <tr>
              <th>Exam</th>
              <th>Score</th>
              <th>Accuracy</th>
              <th>Percentile</th>
              <th>Date</th>
              <th></th>
            </tr>
            </thead>
            <tbody>
            {data.attempts.map((a) => (
              <tr key={a.id}>
                <td class="fw-bold">{a.template_title}</td>
                <td>{a.total_score} / {a.max_possible_score}</td>
                <td>{a.accuracy_percent}%</td>
                <td>
                    <span
                      class="fw-bold"
                      style={{
                        color: a.percentile >= 75 ? 'var(--accent-success)'
                          : a.percentile >= 50 ? 'var(--accent-brand)'
                            : 'var(--accent-warning)',
                      }}
                    >
                      {a.percentile}%
                    </span>
                </td>
                <td class="fs-s color-secondary">{formatDate(a.submitted_at)}</td>
                <td>
                  <a
                    href={`/mock_exams/${a.template_slug}/attempts/${a.id}/results`}
                    class="c-btn c-btn--secondary c-btn--s"
                  >
                    Review
                  </a>
                </td>
              </tr>
            ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

function SummaryCard({ label, value, accent }) {
  return (
    <div
      class="p-4 radius-default text-center"
      style={{
        background: accent ? 'var(--accent-brand)' : 'var(--card-secondary-bg)',
        color: accent ? 'white' : 'inherit',
      }}
    >
      <div class="fs-xs uppercase" style={{ opacity: 0.7 }}>{label}</div>
      <div class="fs-xl fw-bold mt-1">{value}</div>
    </div>
  );
}

function PerformanceTrend({ trend }) {
  if (!trend || trend.length < 2) return null;

  const scores = trend.map((t) => t.accuracy_percent || 0);
  const maxScore = Math.max(...scores, 1);
  const width = 400;
  const height = 120;
  const padding = 20;

  const points = scores.map((s, i) => {
    const x = padding + (i / (scores.length - 1)) * (width - 2 * padding);
    const y = height - padding - (s / maxScore) * (height - 2 * padding);
    return `${x},${y}`;
  });

  const polyline = points.join(' ');

  return (
    <svg viewBox={`0 0 ${width} ${height}`} width="100%" style={{ maxHeight: '140px' }}>
      {/* Grid lines */}
      {[0, 25, 50, 75, 100].map((pct) => {
        const y = height - padding - (pct / maxScore) * (height - 2 * padding);
        return (
          <g key={pct}>
            <line x1={padding} y1={y} x2={width - padding} y2={y} stroke="var(--card-border)" stroke-dasharray="4" />
            <text x={padding - 4} y={y + 3} text-anchor="end" font-size="8" fill="currentColor" opacity={0.5}>{pct}%</text>
          </g>
        );
      })}
      <polyline
        points={polyline}
        fill="none"
        stroke="var(--accent-brand)"
        stroke-width="2"
        stroke-linejoin="round"
      />
      {scores.map((s, i) => {
        const x = padding + (i / (scores.length - 1)) * (width - 2 * padding);
        const y = height - padding - (s / maxScore) * (height - 2 * padding);
        return (
          <circle key={i} cx={x} cy={y} r="3" fill="var(--accent-brand)" />
        );
      })}
    </svg>
  );
}

function TopicRadar({ sections }) {
  const names = Object.keys(sections);
  if (!names.length) return null;

  return (
    <div class="flex flex-col gap-2">
      {names.map((name) => {
        const acc = sections[name] || 0;
        const color = acc >= 70 ? 'var(--accent-success)' : acc >= 40 ? 'var(--accent-warning)' : 'var(--accent-danger)';

        return (
          <div key={name}>
            <div class="flex justify-between fs-s mb-1">
              <span>{name}</span>
              <span class="fw-bold" style={{ color }}>{acc}%</span>
            </div>
            <div style={{ width: '100%', height: '8px', background: 'var(--card-secondary-bg)', borderRadius: '4px', overflow: 'hidden' }}>
              <div
                style={{
                  width: `${acc}%`,
                  height: '100%',
                  background: color,
                  borderRadius: '4px',
                  transition: 'width 0.5s ease',
                }}
              />
            </div>
          </div>
        );
      })}
    </div>
  );
}

function formatDate(dateStr) {
  if (!dateStr) return '—';
  const d = new Date(dateStr);
  return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
}
