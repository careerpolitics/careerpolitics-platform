import { h } from 'preact';
import { useState, useEffect } from 'preact/hooks';
import { request } from '@utilities/http';

export function MockExamDetail({ slug }) {
  const [template, setTemplate] = useState(null);
  const [loading, setLoading] = useState(true);
  const [starting, setStarting] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    request(`/mock_exams/${slug}.json`)
      .then((res) => res.json())
      .then((data) => {
        setTemplate(data);
        setLoading(false);
      })
      .catch(() => {
        setError('Failed to load exam details');
        setLoading(false);
      });
  }, [slug]);

  const handleStart = async () => {
    setStarting(true);
    setError(null);

    try {
      const res = await request(`/mock_exams/${slug}/attempts`, {
        method: 'POST',
      });

      if (res.ok) {
        const data = await res.json();
        window.location.href = `/mock_exams/${slug}/attempts/${data.id}`;
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
    <div class="crayons-layout__content">
      <div class="crayons-card p-6 mb-4">
        <h1 class="crayons-title mb-2">{t.title}</h1>
        {t.description && <p class="color-secondary mb-4">{t.description}</p>}

        <div class="grid gap-4 mb-6" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))' }}>
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
          <p class="fs-s mb-1">🖩 On-screen calculator available</p>
        )}
        {t.has_scratchpad && (
          <p class="fs-s mb-1">📝 Scratchpad available</p>
        )}

        {error && (
          <div class="crayons-notice crayons-notice--danger mb-4">
            {error}
          </div>
        )}

        <div class="flex items-center gap-4 mt-4">
          <button
            class="c-btn c-btn--primary"
            onClick={handleStart}
            disabled={starting || !t.can_attempt}
          >
            {starting ? 'Starting...' : 'Start Exam'}
          </button>
          {!t.can_attempt && t.user_attempts_today !== undefined && (
            <span class="color-secondary fs-s">
              Daily limit reached ({t.user_attempts_today} attempts today)
            </span>
          )}
        </div>
      </div>

      {t.stats && <StatsCard stats={t.stats} maxScore={t.total_questions * t.marks_per_correct} />}
    </div>
  );
}

function InfoItem({ label, value }) {
  return (
    <div class="p-3 radius-default" style={{ background: 'var(--card-secondary-bg)' }}>
      <div class="fs-xs color-secondary uppercase">{label}</div>
      <div class="fw-bold fs-l">{value}</div>
    </div>
  );
}

function StatsCard({ stats, maxScore }) {
  return (
    <div class="crayons-card p-6">
      <h3 class="crayons-subtitle-2 mb-4">Community Statistics</h3>
      <div class="grid gap-4" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))' }}>
        <InfoItem label="Total Attempts" value={stats.total_attempts} />
        <InfoItem label="Unique Users" value={stats.unique_users} />
        <InfoItem label="Avg Score" value={`${stats.average_score} / ${maxScore}`} />
        <InfoItem label="Highest Score" value={stats.highest_score} />
        <InfoItem label="Avg Accuracy" value={`${stats.average_accuracy}%`} />
        <InfoItem label="Completion Rate" value={`${stats.completion_rate}%`} />
      </div>
    </div>
  );
}
