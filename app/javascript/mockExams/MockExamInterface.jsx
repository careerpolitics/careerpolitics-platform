import { h } from 'preact';
import { useState, useEffect, useCallback, useRef } from 'preact/hooks';
import { request } from '@utilities/http';
import { ExamTimer } from './components/ExamTimer';
import { QuestionDisplay } from './components/QuestionDisplay';
import { QuestionPalette } from './components/QuestionPalette';
import { ExamCalculator } from './components/ExamCalculator';
import { ExamScratchpad } from './components/ExamScratchpad';

const STORAGE_KEY_PREFIX = 'mock_exam_responses_';

export function MockExamInterface({ slug, attemptId }) {
  const [examData, setExamData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [responses, setResponses] = useState({});
  const [submitting, setSubmitting] = useState(false);
  const [showCalculator, setShowCalculator] = useState(false);
  const [showScratchpad, setShowScratchpad] = useState(false);
  const [language, setLanguage] = useState('en');
  const [examStarted, setExamStarted] = useState(false);
  const timePerQuestion = useRef({});
  const questionStartTime = useRef(Date.now());

  // Load exam data
  useEffect(() => {
    request(`/mock_exams/${slug}/attempts/${attemptId}.json`)
      .then((res) => res.json())
      .then((data) => {
        setExamData(data);
        // Initialize responses from server + localStorage
        const serverResponses = data.responses || {};
        const storedStr = localStorage.getItem(`${STORAGE_KEY_PREFIX}${attemptId}`);
        const storedResponses = storedStr ? JSON.parse(storedStr) : {};
        const merged = { ...storedResponses };
        // Server responses take priority for persisted data
        Object.entries(serverResponses).forEach(([qId, resp]) => {
          merged[qId] = { ...merged[qId], ...resp };
        });
        setResponses(merged);
        setLoading(false);
      })
      .catch(() => setLoading(false));
  }, [slug, attemptId]);

  // Persist responses to localStorage
  useEffect(() => {
    if (Object.keys(responses).length > 0) {
      try {
        localStorage.setItem(`${STORAGE_KEY_PREFIX}${attemptId}`, JSON.stringify(responses));
      } catch {
        // quota exceeded
      }
    }
  }, [responses, attemptId]);

  // Track time on current question
  useEffect(() => {
    questionStartTime.current = Date.now();
  }, [currentIndex]);

  const recordTimeOnQuestion = useCallback(() => {
    if (!examData) return;
    const q = examData.questions[currentIndex];
    if (!q) return;
    const elapsed = Math.round((Date.now() - questionStartTime.current) / 1000);
    const prev = timePerQuestion.current[q.id] || 0;
    timePerQuestion.current[q.id] = prev + elapsed;
    questionStartTime.current = Date.now();
  }, [currentIndex, examData]);

  const saveResponse = useCallback(
    async (questionId, data) => {
      const resp = responses[questionId];
      const payload = {
        mock_exam_response: {
          selected_option_key: data.selected_option_key,
          marked_for_review: data.marked_for_review || false,
          time_spent_seconds: timePerQuestion.current[questionId] || 0,
        },
      };

      try {
        if (resp?.id) {
          await request(`/mock_exam_responses/${resp.id}`, {
            method: 'PATCH',
            body: JSON.stringify(payload),
            headers: { 'Content-Type': 'application/json' },
          });
        } else {
          const res = await request('/mock_exam_responses', {
            method: 'POST',
            body: JSON.stringify({
              mock_exam_attempt_id: attemptId,
              mock_exam_question_id: questionId,
              ...payload,
            }),
            headers: { 'Content-Type': 'application/json' },
          });
          const saved = await res.json();
          setResponses((prev) => ({
            ...prev,
            [questionId]: { ...prev[questionId], id: saved.id },
          }));
        }
      } catch {
        // will retry on next interaction
      }
    },
    [responses, attemptId],
  );

  const handleSelectOption = useCallback(
    (questionId, optionKey) => {
      recordTimeOnQuestion();
      setResponses((prev) => {
        const updated = {
          ...prev,
          [questionId]: {
            ...prev[questionId],
            selected_option_key: optionKey,
          },
        };
        saveResponse(questionId, updated[questionId]);
        return updated;
      });
    },
    [recordTimeOnQuestion, saveResponse],
  );

  const handleMarkForReview = useCallback(
    (questionId) => {
      setResponses((prev) => {
        const current = prev[questionId] || {};
        const updated = {
          ...prev,
          [questionId]: {
            ...current,
            marked_for_review: !current.marked_for_review,
          },
        };
        saveResponse(questionId, updated[questionId]);
        return updated;
      });
    },
    [saveResponse],
  );

  const handleClearResponse = useCallback(
    (questionId) => {
      setResponses((prev) => {
        const updated = {
          ...prev,
          [questionId]: {
            ...prev[questionId],
            selected_option_key: null,
          },
        };
        saveResponse(questionId, updated[questionId]);
        return updated;
      });
    },
    [saveResponse],
  );

  const handleSubmit = useCallback(async () => {
    if (submitting) return;

    const confirmed = window.confirm(
      'Are you sure you want to submit? You cannot change answers after submission.',
    );
    if (!confirmed) return;

    setSubmitting(true);
    recordTimeOnQuestion();

    try {
      const res = await request(`/mock_exams/${slug}/attempts/${attemptId}/submit`, {
        method: 'PATCH',
        body: JSON.stringify({ time_per_question: timePerQuestion.current }),
        headers: { 'Content-Type': 'application/json' },
      });
      const data = await res.json();
      // Clean up localStorage
      localStorage.removeItem(`${STORAGE_KEY_PREFIX}${attemptId}`);
      localStorage.removeItem(`mock_exam_scratchpad_${attemptId}`);
      window.location.href = data.redirect_to;
    } catch {
      setSubmitting(false);
      alert('Failed to submit. Please try again.');
    }
  }, [slug, attemptId, submitting, recordTimeOnQuestion]);

  const handleTimeUp = useCallback(() => {
    handleSubmit();
  }, [handleSubmit]);

  const handleNavigate = useCallback(
    (index) => {
      recordTimeOnQuestion();
      setCurrentIndex(index);
    },
    [recordTimeOnQuestion],
  );

// Exit full-screen on unmount
  useEffect(() => {
    return () => {
      if (document.fullscreenElement) {
        document.exitFullscreen().catch(() => {});
      }
    };
  }, []);

  if (loading) {
    return (
      <div style={{height: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'var(--body-bg)'}}>
        <div class="crayons-loading" aria-label="Loading exam..." />
      </div>
    );
  }

  if (!examStarted) {
    const enterExam = () => {
      const el = document.documentElement;
      if (el.requestFullscreen && !document.fullscreenElement) {
        el.requestFullscreen().catch(() => {});
      }
      setExamStarted(true);
    };

    return (
      <div style={{ height: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'var(--body-bg)' }}>
        <div class="crayons-card p-8 text-center" style={{ maxWidth: '480px' }}>
          <h2 class="crayons-title mb-2">{examData?.template?.title || 'Mock Exam'}</h2>
          <p class="color-secondary mb-1">{examData?.questions?.length || '—'} questions</p>
          <p class="color-secondary mb-4 fs-s">
            The exam will open in full-screen mode. Press <strong>Esc</strong> to exit full-screen at any time.
          </p>
          <button class="c-btn c-btn--primary" onClick={enterExam} style={{ fontSize: '1.1rem', padding: '12px 32px' }}>
            Begin Exam
          </button>
        </div>
      </div>
    );
  }

  if (!examData || !examData.questions?.length) {
    return (
      <div class="crayons-card p-6">
        <h2 class="crayons-title mb-2">Preparing Your Exam</h2>
        <p class="color-secondary">
          Questions are being generated. Please refresh in a moment...
        </p>
        <button class="c-btn c-btn--secondary mt-4" onClick={() => window.location.reload()}>
          Refresh
        </button>
      </div>
    );
  }

  const questions = examData.questions;
  const currentQuestion = questions[currentIndex];
  const currentResponse = responses[currentQuestion.id] || {};
  const template = examData.template;

  const answeredCount = questions.filter(
    (q) => responses[q.id]?.selected_option_key,
  ).length;

  return (
    <div class="flex gap-4" style={{ minHeight: '80vh' }}>
      {/* Main content */}
      <div style={{ flex: 1 }}>
        {/* Top bar */}
        <div class="crayons-card p-3 mb-4 flex items-center justify-between">
          <div class="fw-bold">{template.title}</div>
          <div class="flex items-center gap-4">
            <ExamTimer
              timeRemainingSeconds={examData.time_remaining_seconds}
              onTimeUp={handleTimeUp}
            />
            <div class="flex gap-2">
              {template.has_calculator && (
                <button
                  class={`c-btn c-btn--s ${showCalculator ? 'c-btn--primary' : 'c-btn--secondary'}`}
                  onClick={() => setShowCalculator(!showCalculator)}
                  title="Calculator"
                >
                  🖩
                </button>
              )}
              {template.has_scratchpad && (
                <button
                  class={`c-btn c-btn--s ${showScratchpad ? 'c-btn--primary' : 'c-btn--secondary'}`}
                  onClick={() => setShowScratchpad(!showScratchpad)}
                  title="Scratchpad"
                >
                  📝
                </button>
              )}
              <button
                class="c-btn c-btn--s c-btn--secondary"
                onClick={() => setLanguage(language === 'en' ? 'hi' : 'en')}
              >
                {language === 'en' ? 'हिंदी' : 'EN'}
              </button>
            </div>
          </div>
        </div>

        {/* Question */}
        <QuestionDisplay
          question={currentQuestion}
          selectedOption={currentResponse.selected_option_key}
          onSelectOption={(key) => handleSelectOption(currentQuestion.id, key)}
          isReview={false}
          language={language}
        />

        {/* Question actions */}
        <div class="flex items-center justify-between mt-4">
          <div class="flex gap-2">
            <button
              class="c-btn c-btn--secondary"
              onClick={() => handleNavigate(Math.max(0, currentIndex - 1))}
              disabled={currentIndex === 0}
            >
              ← Previous
            </button>
            <button
              class="c-btn c-btn--secondary"
              onClick={() =>
                handleNavigate(Math.min(questions.length - 1, currentIndex + 1))
              }
              disabled={currentIndex >= questions.length - 1}
            >
              Next →
            </button>
          </div>

          <div class="flex gap-2">
            <button
              class="c-btn c-btn--secondary c-btn--s"
              onClick={() => handleClearResponse(currentQuestion.id)}
            >
              Clear
            </button>
            <button
              class={`c-btn c-btn--s ${
                currentResponse.marked_for_review
                  ? 'c-btn--primary'
                  : 'c-btn--secondary'
              }`}
              onClick={() => handleMarkForReview(currentQuestion.id)}
            >
              {currentResponse.marked_for_review ? '★ Marked' : '☆ Mark for Review'}
            </button>
          </div>
        </div>

        {/* Submit */}
        <div class="mt-6 flex justify-between items-center">
          <span class="color-secondary fs-s">
            {answeredCount} / {questions.length} answered
          </span>
          <button
            class="c-btn c-btn--primary"
            onClick={handleSubmit}
            disabled={submitting}
          >
            {submitting ? 'Submitting...' : 'Submit Exam'}
          </button>
        </div>
      </div>

      {/* Sidebar — Question Palette */}
      <div style={{ width: '240px', flexShrink: 0 }}>
        <QuestionPalette
          questions={questions}
          responses={responses}
          currentIndex={currentIndex}
          onNavigate={handleNavigate}
        />
      </div>

      {/* Floating tools */}
      {template.has_calculator && (
        <ExamCalculator visible={showCalculator} onClose={() => setShowCalculator(false)} />
      )}
      {template.has_scratchpad && (
        <ExamScratchpad
          visible={showScratchpad}
          onClose={() => setShowScratchpad(false)}
          attemptId={attemptId}
        />
      )}
    </div>
  );
}
