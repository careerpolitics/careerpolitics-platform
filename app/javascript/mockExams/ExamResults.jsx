import { h } from 'preact';
import { useState, useEffect } from 'preact/hooks';
import { request } from '@utilities/http';
import { QuestionDisplay } from './components/QuestionDisplay';
import { ExamComparativeResults } from './components/ExamComparativeResults';
import { ExamLeaderboard } from './components/ExamLeaderboard';

export function ExamResults({ slug, attemptId }) {
  const [results, setResults] = useState(null);
  const [loading, setLoading] = useState(true);
  const [reviewMode, setReviewMode] = useState(false);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [language, setLanguage] = useState('en');
  const [filterSection, setFilterSection] = useState('all');
  const [filterStatus, setFilterStatus] = useState('all');
  const [templateStats, setTemplateStats] = useState(null);
  const [sets, setSets] = useState([]);

  useEffect(() => {
    request(`/mock_exams/${slug}/attempts/${attemptId}/results.json`)
      .then((res) => res.json())
      .then((data) => {
        setResults(data);
        setLoading(false);
      })
      .catch(() => setLoading(false));

    request(`/mock_exams/${slug}/stats.json`)
      .then((res) => res.json())
      .then((data) => {
        if (!data.error) setTemplateStats(data);
      })
      .catch(() => {});

    request(`/mock_exams/${slug}/sets.json`)
      .then((res) => res.json())
      .then((data) => setSets(data.sets || []))
      .catch(() => {});
  }, [slug, attemptId]);

  if (loading) {
    return (
      <div class="crayons-card p-6 flex justify-center">
        <div class="crayons-loading" aria-label="Loading results..." />
      </div>
    );
  }

  if (!results) {
    return (
      <div class="crayons-card p-6">
        <p class="color-danger">Results not available.</p>
      </div>
    );
  }

  const r = results;

  // Filter questions for review mode
  const filteredQuestions = (r.questions || []).filter((q) => {
    if (filterSection !== 'all' && q.section_name !== filterSection) return false;
    if (filterStatus === 'correct' && !q.is_correct) return false;
    if (filterStatus === 'incorrect' && (q.is_correct !== false || !q.selected_option_key)) return false;
    if (filterStatus === 'unanswered' && q.selected_option_key) return false;
    return true;
  });

  const sections = [...new Set((r.questions || []).map((q) => q.section_name))];

  if (reviewMode) {
    return (
      <div>
        <div class="flex items-center justify-between mb-4 flex-wrap gap-2">
          <div class="flex items-center gap-3">
            <button class="c-btn c-btn--secondary" onClick={() => setReviewMode(false)}>
              ← Back to Results
            </button>
            <span class="color-secondary fs-s">
              {filteredQuestions.length} of {(r.questions || []).length} questions
            </span>
          </div>
          <div class="flex gap-2 flex-wrap">
            <select
              class="crayons-select fs-s"
              value={filterSection}
              onChange={(e) => { setFilterSection(e.target.value); }}
            >
              <option value="all">All Sections</option>
              {sections.map((s) => (
                <option key={s} value={s}>{s}</option>
              ))}
            </select>
            <select
              class="crayons-select fs-s"
              value={filterStatus}
              onChange={(e) => { setFilterStatus(e.target.value); }}
            >
              <option value="all">All</option>
              <option value="correct">Correct</option>
              <option value="incorrect">Incorrect</option>
              <option value="unanswered">Unanswered</option>
            </select>
            <button
              class="c-btn c-btn--secondary c-btn--s"
              onClick={() => setLanguage(language === 'en' ? 'hi' : 'en')}
            >
              {language === 'en' ? 'हिंदी' : 'English'}
            </button>
          </div>
        </div>

        {filteredQuestions.length > 0 ? (
          <div>
            {filteredQuestions.map((q) => (
              <div key={q.id} class="mb-4">
                <QuestionDisplay
                  question={q}
                  selectedOption={q.selected_option_key}
                  onSelectOption={() => {}}
                  isReview={true}
                  language={language}
                  questionNumber={q.position}
                  totalQuestions={(r.questions || []).length}
                />
              </div>
            ))}
          </div>
        ) : (
          <div class="crayons-card p-6 text-center color-secondary">
            No questions match the current filter.
          </div>
        )}
      </div>
    );
  }

  const accPct = r.accuracy_percent || 0;
  const scorePct = r.max_possible_score > 0 ? Math.round((r.total_score / r.max_possible_score) * 100) : 0;

  return (
    <div>
      {/* Header with actions */}
      <div class="flex items-center justify-between mb-4 flex-wrap gap-2">
        <h1 class="crayons-title">Exam Results</h1>
        <div class="flex gap-2">
          <button class="c-btn c-btn--primary" onClick={() => setReviewMode(true)}
                  style={{ minHeight: '36px' }}>
            Review All Questions
          </button>
          <a href={`/mock_exams/${slug}`} class="c-btn c-btn--secondary"
             style={{ minHeight: '36px' }}>
            Back to Exam
          </a>
        </div>
      </div>

      {/* Score Hero — ring + key stats */}
      <div class="crayons-card p-6 mb-4">
        <div class="flex flex-wrap gap-6 items-center justify-center">
          {/* Score Ring */}
          <div style={{ position: 'relative', width: '140px', height: '140px', flexShrink: 0 }}>
            <svg viewBox="0 0 120 120" width="140" height="140">
              <circle cx="60" cy="60" r="52" fill="none" stroke="var(--card-border)" stroke-width="10" />
              <circle cx="60" cy="60" r="52" fill="none"
                      stroke={scorePct >= 70 ? 'var(--accent-success)' : scorePct >= 40 ? 'var(--accent-warning)' : 'var(--accent-danger)'}
                      stroke-width="10" stroke-linecap="round"
                      stroke-dasharray={`${(scorePct / 100) * 327} 327`}
                      transform="rotate(-90 60 60)"
                      style={{ transition: 'stroke-dasharray 0.8s ease' }}
              />
            </svg>
            <div style={{
              position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column',
              alignItems: 'center', justifyContent: 'center',
            }}>
              <span class="fw-bold" style={{ fontSize: '1.6rem', lineHeight: 1 }}>{scorePct}%</span>
              <span class="fs-xs color-secondary">{r.total_score}/{r.max_possible_score}</span>
            </div>
          </div>

          {/* Key stats grid */}
          <div class="grid gap-3" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(100px, 1fr))', flex: '1 1 300px' }}>
            <ScoreItem label="Accuracy" value={`${accPct}%`} />
            <ScoreItem label="Correct" value={r.correct_count} color="var(--accent-success)" />
            <ScoreItem label="Incorrect" value={r.incorrect_count} color="var(--accent-danger)" />
            <ScoreItem label="Unanswered" value={r.unanswered_count} />
            <ScoreItem label="Percentile" value={`${r.percentile || 0}%`}
                       color={r.percentile >= 75 ? 'var(--accent-success)' : r.percentile >= 50 ? 'var(--accent-brand)' : 'var(--accent-warning)'} />
            <ScoreItem label="Rank" value={`#${r.rank || '—'}`} />
            <ScoreItem label="Avg Time/Q" value={`${r.avg_time_per_question || 0}s`} />
            <ScoreItem label="Questions" value={r.total_questions} />
          </div>
        </div>
      </div>

      {/* Section Breakdown — progress bars */}
      {r.section_scores && Object.keys(r.section_scores).length > 0 && (
        <div class="crayons-card p-6 mb-4">
          <h3 class="crayons-subtitle-2 mb-3">Section Breakdown</h3>
          <div class="flex flex-col gap-4">
            {Object.entries(r.section_scores).map(([name, data]) => {
              const total = (data.correct || 0) + (data.incorrect || 0) + (data.unanswered || 0);
              const pct = total > 0 ? Math.round((data.correct / total) * 100) : 0;
              return (
                <div key={name}>
                  <div class="flex justify-between items-center mb-1">
                    <span class="fw-bold fs-s">{name}</span>
                    <div class="flex gap-3 fs-xs color-secondary">
                      <span style={{ color: 'var(--accent-success)' }}>✓ {data.correct}</span>
                      <span style={{ color: 'var(--accent-danger)' }}>✗ {data.incorrect}</span>
                      <span>— {data.unanswered}</span>
                      <span class="fw-bold" style={{ color: 'inherit' }}>{data.score} pts</span>
                    </div>
                  </div>
                  <div style={{ width: '100%', height: '8px', background: 'var(--card-secondary-bg)', borderRadius: '4px', overflow: 'hidden', display: 'flex' }}>
                    <div style={{
                      width: `${total > 0 ? (data.correct / total) * 100 : 0}%`,
                      height: '100%', background: 'var(--accent-success)',
                      transition: 'width 0.5s ease',
                    }} />
                    <div style={{
                      width: `${total > 0 ? (data.incorrect / total) * 100 : 0}%`,
                      height: '100%', background: 'var(--accent-danger)',
                      transition: 'width 0.5s ease',
                    }} />
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Comparative Analytics */}
      <ExamComparativeResults attempt={r} templateStats={templateStats} />

      {/* Leaderboard */}
      <div class="mt-4 mb-4">
        <ExamLeaderboard slug={slug} currentUserId={r.user_id} currentAttemptId={r.id} sets={sets} />
      </div>

      {/* Actions */}
      <div class="flex gap-3 flex-wrap mb-4">
        <a href="/mock_exams" class="c-btn c-btn--secondary" style={{ minHeight: '36px' }}>
          All Exams
        </a>
      </div>
    </div>
  );
}

function ScoreItem({ label, value, color, accent }) {
  return (
    <div
      class="p-3 radius-default text-center"
      style={{
        background: accent ? 'var(--accent-brand)' : 'var(--card-secondary-bg)',
        color: accent ? 'white' : color || 'inherit',
      }}
    >
      <div class="fs-xs uppercase" style={{ opacity: accent ? 0.9 : 0.7 }}>
        {label}
      </div>
      <div class="fw-bold fs-xl">{value}</div>
    </div>
  );
}
