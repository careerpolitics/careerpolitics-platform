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

  const handleStart = async (poolSet) => {
    setStarting(true);
    setError(null);

    try {
      const body = poolSet ? JSON.stringify({ pool_set: poolSet }) : undefined;
      const headers = poolSet ? { 'Content-Type': 'application/json' } : {};
      const res = await request(`/mock_exams/${slug}/attempts`, {
        method: 'POST',
        body,
        headers,
      });

      if (res.ok) {
        const data = await res.json();
        window.location.href = data.redirect_to || `/mock_exams/${slug}/attempts/${data.id}`;
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

        <div class="grid gap-4 mb-6"
             style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))' }}>
          <InfoItem label="Questions" value={t.total_questions} />
          <InfoItem label="Duration" value={`${t.duration_minutes} minutes`} />
          <InfoItem label="Marks/Correct" value={`+${t.marks_per_correct}`} />
          <InfoItem label="Negative Marks" value={`-${t.negative_marks_per_wrong}`} />
          <InfoItem label="Category" value={t.exam_category?.replace(/_/g, ' ')} />
          <InfoItem label="Difficulty" value={t.difficulty_level} />
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

      {/* Question Sets — select and attempt */}
      {sets.length > 0 && (
        <div class="crayons-card p-6 mb-4">
          <h3 class="crayons-subtitle-2 mb-1">Choose a Question Set</h3>
          <p class="color-secondary fs-s mb-4">Select a set below to start your exam.</p>
          <div class="grid gap-3"
               style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))' }}>
            {sets.map((s) => {
              const isSelected = selectedSet === s.set_number;
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
                      <span class="fw-bold">Set {s.set_number}</span>
                    </div>
                    <span class="fs-s color-secondary">
                      {s.question_count} questions
                    </span>
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
                </div>
              );
            })}
          </div>

          <div class="flex items-center gap-3 mt-4">
            <button
              class="c-btn c-btn--primary"
              onClick={() => handleStart(selectedSet)}
              disabled={starting || !t.can_attempt || !selectedSet}
            >
              {starting
                ? 'Starting...'
                : selectedSet
                  ? `Start Set ${selectedSet}`
                  : 'Select a set to begin'}
            </button>
            {sets.length > 1 && t.can_attempt && (
              <button
                class="c-btn c-btn--secondary"
                onClick={() => handleStart(null)}
                disabled={starting}
              >
                {starting ? 'Starting...' : 'Random Set'}
              </button>
            )}
          </div>
        </div>
      )}

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
