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
    const q = filteredQuestions[currentIndex];

    return (
      <div class="crayons-layout__content">
        <div class="flex items-center justify-between mb-4">
          <button class="c-btn c-btn--secondary" onClick={() => setReviewMode(false)}>
            ← Back to Results
          </button>
          <div class="flex gap-2">
            <select
              class="crayons-select fs-s"
              value={filterSection}
              onChange={(e) => { setFilterSection(e.target.value); setCurrentIndex(0); }}
            >
              <option value="all">All Sections</option>
              {sections.map((s) => (
                <option key={s} value={s}>{s}</option>
              ))}
            </select>
            <select
              class="crayons-select fs-s"
              value={filterStatus}
              onChange={(e) => { setFilterStatus(e.target.value); setCurrentIndex(0); }}
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

        {q ? (
          <div>
            <QuestionDisplay
              question={q}
              selectedOption={q.selected_option_key}
              onSelectOption={() => {}}
              isReview={true}
              language={language}
            />
            <div class="flex items-center justify-between mt-4">
              <button
                class="c-btn c-btn--secondary"
                onClick={() => setCurrentIndex((i) => Math.max(0, i - 1))}
                disabled={currentIndex === 0}
              >
                ← Previous
              </button>
              <span class="color-secondary fs-s">
                {currentIndex + 1} / {filteredQuestions.length}
              </span>
              <button
                class="c-btn c-btn--secondary"
                onClick={() => setCurrentIndex((i) => Math.min(filteredQuestions.length - 1, i + 1))}
                disabled={currentIndex >= filteredQuestions.length - 1}
              >
                Next →
              </button>
            </div>
          </div>
        ) : (
          <div class="crayons-card p-6 text-center color-secondary">
            No questions match the current filter.
          </div>
        )}
      </div>
    );
  }

  return (
    <div class="crayons-layout__content">
      <h1 class="crayons-title mb-4">Exam Results</h1>

      {/* Score Overview */}
      <div class="crayons-card p-6 mb-4">
        <div class="grid gap-4" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))' }}>
          <ScoreItem
            label="Score"
            value={`${r.total_score} / ${r.max_possible_score}`}
            accent={true}
          />
          <ScoreItem label="Accuracy" value={`${r.accuracy_percent}%`} />
          <ScoreItem label="Correct" value={r.correct_count} color="var(--accent-success)" />
          <ScoreItem label="Incorrect" value={r.incorrect_count} color="var(--accent-danger)" />
          <ScoreItem label="Unanswered" value={r.unanswered_count} />
          <ScoreItem label="Percentile" value={`${r.percentile || 0}%`} />
          <ScoreItem label="Rank" value={`#${r.rank || '—'}`} />
          <ScoreItem label="Avg Time/Q" value={`${r.avg_time_per_question || 0}s`} />
        </div>
      </div>

      {/* Section Breakdown */}
      {r.section_scores && Object.keys(r.section_scores).length > 0 && (
        <div class="crayons-card p-6 mb-4">
          <h3 class="crayons-subtitle-2 mb-3">Section Breakdown</h3>
          <table class="crayons-table">
            <thead>
            <tr>
              <th>Section</th>
              <th>Correct</th>
              <th>Incorrect</th>
              <th>Unanswered</th>
              <th>Score</th>
            </tr>
            </thead>
            <tbody>
            {Object.entries(r.section_scores).map(([name, data]) => (
              <tr key={name}>
                <td class="fw-bold">{name}</td>
                <td style={{ color: 'var(--accent-success)' }}>{data.correct}</td>
                <td style={{ color: 'var(--accent-danger)' }}>{data.incorrect}</td>
                <td>{data.unanswered}</td>
                <td class="fw-bold">{data.score}</td>
              </tr>
            ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Comparative Analytics */}
      <ExamComparativeResults attempt={r} templateStats={templateStats} />

      {/* Leaderboard */}
      <div class="mt-4 mb-4">
        <ExamLeaderboard slug={slug} currentUserId={r.user_id} currentAttemptId={r.id} />
      </div>

      {/* Actions */}
      <div class="flex gap-4">
        <button class="c-btn c-btn--primary" onClick={() => setReviewMode(true)}>
          Review All Questions
        </button>
        <a href={`/mock_exams/${slug}`} class="c-btn c-btn--secondary">
          Back to Exam
        </a>
        <a href="/mock_exams" class="c-btn c-btn--secondary">
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
