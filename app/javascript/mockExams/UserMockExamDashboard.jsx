import { h } from 'preact';
import { useState, useEffect, useMemo } from 'preact/hooks';
import { request } from '@utilities/http';

export function UserMockExamDashboard() {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [sortBy, setSortBy] = useState('newest');
  const [perfFilter, setPerfFilter] = useState('all');

  useEffect(() => {
    request('/mock_exams/dashboard.json')
      .then((res) => res.json())
      .then((d) => {
        setData(d);
        setLoading(false);
      })
      .catch(() => setLoading(false));
  }, []);

  const filteredAttempts = useMemo(() => {
    if (!data?.attempts) return [];
    let list = data.attempts;

    if (search) {
      const q = search.toLowerCase();
      list = list.filter((a) => a.template_title?.toLowerCase().includes(q));
    }
    if (perfFilter === 'high') list = list.filter((a) => a.accuracy_percent >= 70);
    if (perfFilter === 'mid') list = list.filter((a) => a.accuracy_percent >= 40 && a.accuracy_percent < 70);
    if (perfFilter === 'low') list = list.filter((a) => a.accuracy_percent < 40);

    const sorted = [...list];
    if (sortBy === 'oldest') sorted.reverse();
    if (sortBy === 'score_high') sorted.sort((a, b) => b.accuracy_percent - a.accuracy_percent);
    if (sortBy === 'score_low') sorted.sort((a, b) => a.accuracy_percent - b.accuracy_percent);
    if (sortBy === 'percentile') sorted.sort((a, b) => (b.percentile || 0) - (a.percentile || 0));
    return sorted;
  }, [data, search, sortBy, perfFilter]);

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

  const hasFilters = search || perfFilter !== 'all';

  return (
    <div>
      <div class="flex items-center justify-between mb-4 flex-wrap gap-2">
        <h1 class="crayons-title">My Mock Exams</h1>
        <a href="/mock_exams" class="c-btn c-btn--primary c-btn--s">
          Browse Exams
        </a>
      </div>

      {!data.is_premium && data.upgrade_url && (
        <div class="p-4 radius-default mb-4"
             style={{ background: 'var(--accent-brand-a10)', border: '1px solid var(--accent-brand)' }}>
          <div class="flex items-center justify-between flex-wrap gap-3">
            <div>
              <p class="fw-bold fs-s" style={{ color: 'var(--accent-brand)' }}>
                Start a free trial or subscribe to access mock exams
              </p>
              <p class="fs-s color-secondary mt-1">
                Start a free trial or subscribe for CP++ mock exam access
              </p>
            </div>
            <a href={data.upgrade_url} class="c-btn c-btn--primary"
               style={{ whiteSpace: 'nowrap' }}>
              Upgrade to Premium
            </a>
          </div>
        </div>
      )}

      {/* Summary Cards */}
      <div class="grid gap-3 mb-6" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(130px, 1fr))' }}>
        <SummaryCard label="Total Attempts" value={data.total_attempts} />
        <SummaryCard label="Completed" value={data.completed_attempts} />
        <SummaryCard label="Best Score" value={data.best_score ? `${data.best_score}%` : '—'} accent />
        <SummaryCard label="Avg Accuracy" value={data.avg_accuracy ? `${data.avg_accuracy}%` : '—'} />
        <SummaryCard label="Streak" value={`${data.streak_days || 0}d`} />
      </div>

      {/* Performance Trend + Topic Strengths side by side on desktop */}
      <div class="grid gap-4 mb-4" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))' }}>
        {data.trend && data.trend.length > 1 && (
          <div class="crayons-card p-6">
            <h3 class="crayons-subtitle-2 mb-3">Performance Trend</h3>
            <PerformanceTrend trend={data.trend} />
          </div>
        )}
        {data.section_accuracy && Object.keys(data.section_accuracy).length > 0 && (
          <div class="crayons-card p-6">
            <h3 class="crayons-subtitle-2 mb-3">Topic Strengths</h3>
            <TopicRadar sections={data.section_accuracy} />
          </div>
        )}
      </div>

      {/* Attempt History */}
      <div class="crayons-card p-6">
        <h3 class="crayons-subtitle-2 mb-3">Attempt History</h3>

        {data.attempts && data.attempts.length > 0 && (
          <div class="mb-4">
            {/* Filter bar */}
            <div class="flex flex-wrap items-center gap-3 mb-3" style={{ fontSize: '0.8rem' }}>
              <div style={{ flex: '1 1 180px', maxWidth: '260px' }}>
                <input type="text" class="crayons-textfield" placeholder="Search by exam name..."
                       value={search} onInput={(e) => setSearch(e.target.value)}
                       style={{ height: '32px', fontSize: '0.8rem' }} />
              </div>

              <DashPillGroup label="Performance" value={perfFilter} onChange={setPerfFilter}
                             options={[['all', 'All'], ['high', '≥70%'], ['mid', '40-69%'], ['low', '<40%']]} />

              <div class="flex items-center gap-1" style={{ marginLeft: 'auto' }}>
                <span class="color-secondary fw-medium" style={{ fontSize: '0.75rem' }}>Sort:</span>
                {[['newest', 'Newest'], ['oldest', 'Oldest'], ['score_high', 'Best'], ['score_low', 'Worst'], ['percentile', 'Percentile']].map(([val, lbl]) => (
                  <button key={val}
                          class={`c-btn c-btn--s ${sortBy === val ? 'c-btn--primary' : 'c-btn--secondary'}`}
                          onClick={() => setSortBy(val)}
                          style={{ padding: '2px 7px', minHeight: '26px', fontSize: '0.72rem', borderRadius: '12px' }}
                  >{lbl}</button>
                ))}
              </div>
            </div>

            {hasFilters && (
              <div class="flex items-center gap-2 mb-3">
                <span class="fs-s color-secondary">{filteredAttempts.length} of {data.attempts.length} attempts</span>
                <button class="c-btn c-btn--s c-btn--secondary"
                        style={{ padding: '1px 8px', fontSize: '0.7rem', minHeight: '22px' }}
                        onClick={() => { setSearch(''); setPerfFilter('all'); }}>
                  Clear
                </button>
              </div>
            )}
          </div>
        )}

        {(!data.attempts || data.attempts.length === 0) ? (
          <p class="color-secondary text-center">
            No attempts yet. <a href="/mock_exams">Start your first exam!</a>
          </p>
        ) : filteredAttempts.length === 0 ? (
          <p class="color-secondary text-center">No attempts match your filters.</p>
        ) : (
          <div class="flex flex-col gap-3">
            {filteredAttempts.map((a) => (
              <AttemptCard key={a.id} attempt={a} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function AttemptCard({ attempt: a }) {
  const accColor = a.accuracy_percent >= 70 ? 'var(--accent-success)'
    : a.accuracy_percent >= 40 ? 'var(--accent-warning)' : 'var(--accent-danger)';
  const pctColor = a.percentile >= 75 ? 'var(--accent-success)'
    : a.percentile >= 50 ? 'var(--accent-brand)' : 'var(--accent-warning)';

  return (
    <div class="crayons-card crayons-card--secondary p-4"
         style={{ border: '1px solid var(--card-border)' }}>
      <div class="flex items-center justify-between flex-wrap gap-2">
        <div style={{ flex: '1 1 200px' }}>
          <div class="fw-bold">{a.template_title}</div>
          <div class="fs-xs color-secondary mt-1">{formatDate(a.submitted_at)}</div>
        </div>

        <div class="flex items-center gap-4 flex-wrap" style={{ fontSize: '0.85rem' }}>
          <div class="text-center">
            <div class="fs-xs color-secondary">Score</div>
            <div class="fw-bold">{a.total_score}/{a.max_possible_score}</div>
          </div>
          <div class="text-center">
            <div class="fs-xs color-secondary">Accuracy</div>
            <div class="fw-bold" style={{ color: accColor }}>{a.accuracy_percent}%</div>
          </div>
          <div class="text-center">
            <div class="fs-xs color-secondary">Percentile</div>
            <div class="fw-bold" style={{ color: pctColor }}>{a.percentile || 0}%</div>
          </div>
          <a href={`/mock_exams/${a.template_slug}/attempts/${a.id}/results`}
             class="c-btn c-btn--secondary c-btn--s" style={{ minHeight: '32px' }}>
            Review
          </a>
        </div>
      </div>

      {/* Accuracy bar */}
      <div style={{ width: '100%', height: '4px', background: 'var(--card-secondary-bg)', borderRadius: '2px', overflow: 'hidden', marginTop: '8px' }}>
        <div style={{
          width: `${a.accuracy_percent || 0}%`,
          height: '100%', background: accColor, borderRadius: '2px',
          transition: 'width 0.5s ease',
        }} />
      </div>
    </div>
  );
}

function DashPillGroup({ label, value, onChange, options }) {
  return (
    <div class="flex items-center gap-1">
      <span class="color-secondary fw-medium" style={{ fontSize: '0.75rem' }}>{label}:</span>
      {options.map(([val, lbl]) => (
        <button key={val}
                class={`c-btn c-btn--s ${value === val ? 'c-btn--primary' : 'c-btn--secondary'}`}
                onClick={() => onChange(val)}
                style={{ padding: '2px 8px', minHeight: '26px', fontSize: '0.75rem', borderRadius: '12px' }}
        >{lbl}</button>
      ))}
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
