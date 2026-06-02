import { h } from 'preact';
import { useState, useEffect } from 'preact/hooks';
import { request } from '@utilities/http';
import { ExamLeaderboard } from './components/ExamLeaderboard';

export function MockExamDetail({ slug }) {
  const [template, setTemplate] = useState(null);
  const [sets, setSets] = useState([]);
  const [loading, setLoading] = useState(true);
  const [starting, setStarting] = useState(false);
  const [error, setError] = useState(null);
  const [selectedSet, setSelectedSet] = useState(null);
  const [statusFilter, setStatusFilter] = useState('all');
  const [diffFilter, setDiffFilter] = useState('all');
  const [sortBy, setSortBy] = useState('newest');
  const [showInstructions, setShowInstructions] = useState(false);
  const [pendingPoolSet, setPendingPoolSet] = useState(undefined);

  useEffect(() => {
    Promise.all([
      request(`/mock_exams/${slug}.json`).then((r) => r.json()),
      request(`/mock_exams/${slug}/sets.json`).then((r) => r.json()).catch(() => ({ sets: [] })),
    ]).then(([tmpl, setsData]) => {
      setTemplate(tmpl);
      setSets(setsData.sets || []);
      setLoading(false);
    }).catch(() => {
      setError('Failed to load exam details');
      setLoading(false);
    });
  }, [slug]);

  const openInstructions = (poolSet) => {
    setPendingPoolSet(poolSet);
    setShowInstructions(true);
    setError(null);
  };

  const handleConfirmStart = async (goFullscreen) => {
    setStarting(true);
    setError(null);

    try {
      const payload = pendingPoolSet ? { pool_set: pendingPoolSet } : {};
      const res = await request(`/mock_exams/${slug}/attempts`, {
        method: 'POST',
        body: JSON.stringify(payload),
      });

      if (res.ok) {
        const data = await res.json();
        const url = data.redirect_to || `/mock_exams/${slug}/attempts/${data.id}`;
        window.location.href = goFullscreen ? `${url}?mode=fullscreen` : url;
      } else {
        const errData = await res.json();
        setError(errData.errors?.[0] || errData.error || 'Failed to start exam');
        setStarting(false);
      }
    } catch {
      setError('Network error. Please try again.');
      setStarting(false);
    }
  };

  if (loading) {
    return (
      <div class="crayons-card p-6 flex justify-center">
        <div class="crayons-loading" aria-label="Loading..." />
      </div>
    );
  }

  if (!template) {
    return (
      <div class="crayons-card p-6">
        <p class="color-danger">Exam not found.</p>
      </div>
    );
  }

  const t = template;

  return (
    <div>
      <div class="crayons-card p-6 mb-4">
        <h1 class="crayons-title mb-2">{t.title}</h1>
        {t.description && <p class="color-secondary mb-4">{t.description}</p>}

        <div class="grid gap-3 mb-6"
             style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))' }}>
          <InfoItem label="Questions" value={t.total_questions} />
          <InfoItem label="Duration" value={`${t.duration_minutes} minutes`} />
          <InfoItem label="Marks/Correct" value={`+${t.marks_per_correct}`} />
          <InfoItem label="Negative Marks" value={`-${t.negative_marks_per_wrong}`} />
          <InfoItem label="Tag" value={t.tag_list?.[0]?.name?.replace(/_/g, ' ') || '—'} />
        </div>

        {t.sections_config?.length > 0 && (
          <div class="mb-6">
            <h3 class="crayons-subtitle-2 mb-2">Sections</h3>
            <div class="flex flex-wrap gap-2">
              {t.sections_config.map((s, i) => (
                <span key={i} class="crayons-tag">
                  {s.name} ({s.count}q)
                </span>
              ))}
            </div>
          </div>
        )}

        {t.has_calculator && (
          <p class="fs-s mb-1">On-screen calculator available</p>
        )}
        {t.has_scratchpad && (
          <p class="fs-s mb-1">Scratchpad available</p>
        )}

        {error && (
          <div class="crayons-notice crayons-notice--danger mb-4">
            {error}
          </div>
        )}

      </div>

      {/* Instruction Modal */}
      {showInstructions && template && (
        <div
          style={{
            position: 'fixed', inset: 0, zIndex: 9999,
            background: 'rgba(0,0,0,0.6)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            padding: '12px',
          }}
          onClick={(e) => { if (e.target === e.currentTarget && !starting) setShowInstructions(false); }}
        >
          <div
            class="crayons-card"
            style={{
              maxWidth: '560px', width: '100%',
              maxHeight: '90vh', overflowY: 'auto',
              padding: '24px',
            }}
          >
            <div class="flex items-center justify-between mb-3">
              <h2 class="crayons-title">{template.title}</h2>
              {!starting && (
                <button
                  class="c-btn c-btn--s c-btn--icon-alone c-btn--secondary"
                  onClick={() => setShowInstructions(false)}
                  aria-label="Close"
                  style={{ minHeight: '32px', minWidth: '32px' }}
                >✕</button>
              )}
            </div>

            <div class="grid gap-2 mb-4" style={{ gridTemplateColumns: '1fr 1fr' }}>
              <div class="p-3 radius-default" style={{ background: 'var(--card-secondary-bg)' }}>
                <div class="fs-xs color-secondary">Questions</div>
                <div class="fw-bold fs-l">{template.total_questions}</div>
              </div>
              <div class="p-3 radius-default" style={{ background: 'var(--card-secondary-bg)' }}>
                <div class="fs-xs color-secondary">Duration</div>
                <div class="fw-bold fs-l">{template.duration_minutes} min</div>
              </div>
              <div class="p-3 radius-default" style={{ background: 'var(--card-secondary-bg)' }}>
                <div class="fs-xs color-secondary">Marks/Correct</div>
                <div class="fw-bold fs-l">+{template.marks_per_correct}</div>
              </div>
              <div class="p-3 radius-default" style={{ background: 'var(--card-secondary-bg)' }}>
                <div class="fs-xs color-secondary">Negative</div>
                <div class="fw-bold fs-l">-{template.negative_marks_per_wrong}</div>
              </div>
            </div>

            <div class="mb-4 p-3 radius-default" style={{ background: 'var(--card-secondary-bg)' }}>
              <h4 class="fw-bold mb-2">Instructions</h4>
              <ul style={{ paddingLeft: '18px', lineHeight: '1.7' }}>
                <li>Complete all questions within the time limit.</li>
                <li>Each correct answer earns marks. Wrong answers may deduct marks.</li>
                <li>Navigate between questions using the question palette.</li>
                <li>Mark questions for review and come back later.</li>
                <li>Use <strong>Clear</strong> to unselect an answer.</li>
                <li>Switch between <strong>English</strong> and <strong>Hindi</strong> anytime.</li>
                <li>The exam auto-submits when the timer runs out.</li>
              </ul>
            </div>

            {error && (
              <div class="crayons-notice crayons-notice--danger mb-4">{error}</div>
            )}

            {starting ? (
              <div class="flex flex-col items-center gap-3 p-4">
                <div class="crayons-loading" aria-label="Preparing exam..." />
                <p class="color-secondary fs-s">Preparing your exam...</p>
              </div>
            ) : (
              <div class="flex gap-3">
                {typeof document.documentElement.requestFullscreen === 'function' && (
                  <button
                    class="c-btn c-btn--primary"
                    onClick={() => handleConfirmStart(true)}
                    style={{ flex: 1, padding: '12px 16px', minHeight: '48px' }}
                  >
                    Full Screen Mode
                  </button>
                )}
                <button
                  class={typeof document.documentElement.requestFullscreen === 'function' ? 'c-btn c-btn--secondary' : 'c-btn c-btn--primary'}
                  onClick={() => handleConfirmStart(false)}
                  style={{ flex: 1, padding: '12px 16px', minHeight: '48px' }}
                >
                  {typeof document.documentElement.requestFullscreen === 'function' ? 'Window Mode' : 'Start Exam'}
                </button>
              </div>
            )}

            {typeof document.documentElement.requestFullscreen === 'function' && !starting && (
              <p class="color-secondary fs-xs mt-3 text-center">
                You can switch between modes anytime during the exam.
              </p>
            )}
          </div>
        </div>
      )}

      {sets.length > 0 && (() => {
        const filtered = sets
          .filter(s => {
            if (statusFilter === 'new') return !s.user_attempted;
            if (statusFilter === 'attempted') return s.user_attempted;
            return true;
          })
          .filter(s => {
            if (diffFilter === 'all') return true;
            return s.difficulty === diffFilter;
          })
          .sort((a, b) => {
            if (sortBy === 'oldest') return a.set_number - b.set_number;
            if (sortBy === 'popular') return b.attempts_count - a.attempts_count;
            return b.set_number - a.set_number;
          });

        return (
          <div class="crayons-card p-6 mb-4">
            <div class="flex items-center justify-between mb-2">
              <h3 class="crayons-subtitle-2">Choose a Question Set</h3>
              {sets.length > 1 && t.can_attempt && (
                <button
                  class="c-btn c-btn--secondary c-btn--s"
                  onClick={() => openInstructions(null)}
                  disabled={starting}
                  title="Pick a random set"
                  style={{ padding: '4px 10px', borderRadius: '6px', fontSize: '0.8rem', gap: '4px', display: 'inline-flex', alignItems: 'center' }}
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="16 3 21 3 21 8"/><line x1="4" y1="20" x2="21" y2="3"/><polyline points="21 16 21 21 16 21"/><line x1="15" y1="15" x2="21" y2="21"/><line x1="4" y1="4" x2="9" y2="9"/></svg>
                  {starting ? '...' : 'Random'}
                </button>
              )}
            </div>

            {/* Filter / Sort bar */}
            <div class="flex flex-wrap items-center gap-3 mb-4 mt-2" style={{ fontSize: '0.8rem' }}>
              <FilterGroup label="Status" value={statusFilter} onChange={setStatusFilter}
                           options={[['all','All'],['new','New'],['attempted','Attempted']]} />
              <FilterGroup label="Difficulty" value={diffFilter} onChange={setDiffFilter}
                           options={[['all','All'],['easy','Easy'],['medium','Medium'],['hard','Hard']]} />
              <div class="flex items-center gap-1" style={{ marginLeft: 'auto' }}>
                <span class="color-secondary fw-medium" style={{ fontSize: '0.75rem' }}>Sort:</span>
                {[['newest','Newest'],['oldest','Oldest'],['popular','Popular']].map(([val,lbl]) => (
                  <button key={val}
                          class={`c-btn c-btn--s ${sortBy === val ? 'c-btn--primary' : 'c-btn--secondary'}`}
                          onClick={() => setSortBy(val)}
                          style={{ padding: '2px 8px', minHeight: '26px', fontSize: '0.75rem', borderRadius: '12px' }}
                  >{lbl}</button>
                ))}
              </div>
            </div>

            <div class="flex items-center gap-2 mb-3">
              <span class="fs-s color-secondary">{filtered.length} of {sets.length} sets</span>
              {(statusFilter !== 'all' || diffFilter !== 'all') && (
                <button class="c-btn c-btn--s c-btn--secondary" style={{ padding: '1px 8px', fontSize: '0.7rem', minHeight: '22px' }}
                        onClick={() => { setStatusFilter('all'); setDiffFilter('all'); }}>
                  Clear filters
                </button>
              )}
            </div>

            {filtered.length === 0 ? (
              <div class="p-4 text-center color-secondary fs-s">
                No sets match your filters. Try adjusting the filters above.
              </div>
            ) : (
              <div class="grid gap-3"
                   style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(240px, 1fr))' }}>
                {filtered.map((s) => {
                  const isSelected = selectedSet === s.set_number;
                  const ua = s.user_attempt_data;
                  const accColor = ua ? (ua.accuracy_percent >= 70 ? 'var(--accent-success)' : ua.accuracy_percent >= 40 ? 'var(--accent-warning)' : 'var(--accent-danger)') : null;
                  return (
                    <div
                      key={s.set_number}
                      role="button"
                      tabIndex={0}
                      aria-pressed={isSelected}
                      class="crayons-card crayons-card--secondary p-4"
                      style={{
                        cursor: t.can_attempt ? 'pointer' : 'default',
                        borderColor: isSelected
                          ? 'var(--accent-brand)' : 'var(--card-border)',
                        borderWidth: isSelected ? '2px' : '1px',
                        borderStyle: 'solid',
                        background: isSelected
                          ? 'var(--accent-brand-a10)' : 'var(--card-secondary-bg)',
                        transition: 'all 0.15s ease',
                        opacity: t.can_attempt ? 1 : 0.6,
                      }}
                      onClick={() =>
                        t.can_attempt &&
                        setSelectedSet(isSelected ? null : s.set_number)
                      }
                      onKeyDown={(e) => {
                        if (e.key === 'Enter' || e.key === ' ') {
                          e.preventDefault();
                          t.can_attempt &&
                          setSelectedSet(isSelected ? null : s.set_number);
                        }
                      }}
                    >
                      <div class="flex items-center justify-between mb-2">
                        <div class="flex items-center gap-2">
                      <span
                        style={{
                          width: '20px',
                          height: '20px',
                          borderRadius: '50%',
                          border: isSelected
                            ? '2px solid var(--accent-brand)'
                            : '2px solid var(--card-border)',
                          background: isSelected
                            ? 'var(--accent-brand)' : 'transparent',
                          display: 'inline-flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          flexShrink: 0,
                          color: '#fff',
                          fontSize: '12px',
                          fontWeight: 'bold',
                        }}
                      >
                        {isSelected ? '✓' : ''}
                      </span>
                          <span class="fw-bold">{s.label}</span>
                        </div>
                        <div class="flex items-center gap-2">
                          <DifficultyBadge difficulty={s.difficulty} />
                          <span class="fs-s color-secondary">
                        {s.question_count}q
                      </span>
                        </div>
                      </div>
                      <div class="flex items-center justify-between"
                           style={{ paddingLeft: '28px' }}>
                    <span class="fs-s color-secondary">
                      {s.attempts_count} total attempts
                    </span>
                        {s.user_attempted && (
                          <span class="crayons-tag crayons-tag--monochrome fs-xs">
                        You attempted
                      </span>
                        )}
                      </div>

                      {/* Attempted: show score + Review/Retake */}
                      {ua && (
                        <div style={{ paddingLeft: '28px', marginTop: '8px', paddingTop: '8px', borderTop: '1px solid var(--card-border)' }}>
                          <div class="flex items-center justify-between flex-wrap gap-2">
                            <div class="flex items-center gap-3 fs-xs color-secondary">
                              <span>Score: <strong style={{ color: accColor }}>{ua.total_score}/{ua.max_possible_score}</strong></span>
                              <span>Accuracy: <strong style={{ color: accColor }}>{ua.accuracy_percent}%</strong></span>
                              <span>Percentile: <strong>{ua.percentile || 0}%</strong></span>
                            </div>
                          </div>
                        </div>
                      )}

                      {/* Action buttons */}
                      {ua ? (
                        <div class="flex gap-2" style={{ marginTop: '10px' }}
                             onClick={(e) => e.stopPropagation()}>
                          <a href={`/mock_exams/${slug}/attempts/${ua.attempt_id}/results`}
                             class="c-btn c-btn--secondary"
                             style={{ flex: 1, fontSize: '0.8rem', padding: '6px 0', borderRadius: '6px', textAlign: 'center', textDecoration: 'none' }}>
                            📝 Review
                          </a>
                          <button
                            class="c-btn c-btn--primary"
                            onClick={(e) => { e.stopPropagation(); openInstructions(s.set_number); }}
                            disabled={starting || !t.can_attempt}
                            style={{ flex: 1, fontSize: '0.8rem', padding: '6px 0', borderRadius: '6px' }}
                          >
                            {starting ? '...' : '↻ Retake'}
                          </button>
                        </div>
                      ) : t.can_attempt && (
                        <button
                          class="c-btn c-btn--primary"
                          onClick={(e) => { e.stopPropagation(); openInstructions(s.set_number); }}
                          disabled={starting}
                          style={{ width: '100%', marginTop: '10px', fontSize: '0.85rem', padding: '7px 0', borderRadius: '6px' }}
                        >
                          {starting ? 'Starting...' : '▶ Start Exam'}
                        </button>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        );
      })()}

      {/* Fallback when no sets are published yet */}
      {sets.length === 0 && t.can_attempt && (
        <div class="crayons-card p-6 mb-4">
          <p class="color-secondary fs-s mb-3">
            No question sets are published yet. Check back soon.
          </p>
        </div>
      )}

      {t.stats && (
        <StatsCard stats={t.stats}
                   maxScore={t.total_questions * t.marks_per_correct} />
      )}

      {/* Leaderboard */}
      <div class="mt-4">
        <ExamLeaderboard slug={slug} sets={sets} />
      </div>
    </div>
  );
}

function InfoItem({ label, value }) {
  return (
    <div class="p-3 radius-default"
         style={{ background: 'var(--card-secondary-bg)' }}>
      <div class="fs-xs color-secondary uppercase">{label}</div>
      <div class="fw-bold fs-l">{value}</div>
    </div>
  );
}

function StatsCard({ stats, maxScore }) {
  return (
    <div class="crayons-card p-6">
      <h3 class="crayons-subtitle-2 mb-4">Community Statistics</h3>
      <div class="grid gap-4"
           style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))' }}>
        <InfoItem label="Total Attempts" value={stats.total_attempts} />
        <InfoItem label="Unique Users" value={stats.unique_users} />
        <InfoItem label="Avg Score"
                  value={`${stats.average_score} / ${maxScore}`} />
        <InfoItem label="Highest Score" value={stats.highest_score} />
        <InfoItem label="Avg Accuracy"
                  value={`${stats.average_accuracy}%`} />
        <InfoItem label="Completion Rate"
                  value={`${stats.completion_rate}%`} />
      </div>
    </div>
  );
}

function DifficultyBadge({ difficulty }) {
  const colors = {
    easy: { bg: 'rgba(0,128,0,0.1)', color: 'var(--accent-success)' },
    medium: { bg: 'rgba(255,165,0,0.1)', color: 'var(--accent-warning)' },
    hard: { bg: 'rgba(255,0,0,0.1)', color: 'var(--accent-danger)' },
    mixed: { bg: 'var(--card-secondary-bg)', color: 'var(--body-color)' },
  };
  const c = colors[difficulty] || colors.mixed;
  return (
    <span
      class="fs-xs fw-bold"
      style={{
        padding: '2px 8px',
        borderRadius: '4px',
        background: c.bg,
        color: c.color,
        textTransform: 'capitalize',
      }}
    >
      {difficulty}
    </span>
  );
}

function FilterGroup({ label, value, onChange, options }) {
  return (
    <div class="flex items-center gap-1">
      <span class="color-secondary fw-medium" style={{ fontSize: '0.75rem' }}>{label}:</span>
      {options.map(([val, lbl]) => (
        <button
          key={val}
          class={`c-btn c-btn--s ${value === val ? 'c-btn--primary' : 'c-btn--secondary'}`}
          onClick={() => onChange(val)}
          style={{
            padding: '2px 8px',
            minHeight: '26px',
            fontSize: '0.75rem',
            borderRadius: '12px',
          }}
        >
          {lbl}
        </button>
      ))}
    </div>
  );
}
