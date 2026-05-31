import { h } from 'preact';

export function QuestionPalette({ questions, responses, currentIndex, onNavigate }) {
  const getStatus = (question) => {
    const resp = responses[question.id];
    if (!resp) return 'not_visited';
    if (resp.marked_for_review && resp.selected_option_key) return 'answered_review';
    if (resp.marked_for_review) return 'review';
    if (resp.selected_option_key) return 'answered';
    return 'not_answered';
  };

  const statusColors = {
    not_visited: 'var(--card-secondary-bg)',
    not_answered: 'var(--accent-danger)',
    answered: 'var(--accent-success)',
    review: 'var(--accent-warning)',
    answered_review: '#9b59b6',
  };

  const statusLabels = {
    not_visited: 'Not Visited',
    not_answered: 'Not Answered',
    answered: 'Answered',
    review: 'Marked for Review',
    answered_review: 'Answered & Marked',
  };

  const counts = {};
  questions.forEach((q) => {
    const s = getStatus(q);
    counts[s] = (counts[s] || 0) + 1;
  });

  return (
    <div>
      <h4 class="fw-bold mb-3 fs-s">Question Palette</h4>

      <div
        class="grid gap-1 mb-4"
        style={{ gridTemplateColumns: 'repeat(5, 1fr)' }}
      >
        {questions.map((q, i) => {
          const status = getStatus(q);
          const isCurrent = i === currentIndex;

          return (
            <button
              key={q.id}
              onClick={() => onNavigate(i)}
              style={{
                width: '100%',
                minWidth: '36px',
                height: '40px',
                borderRadius: '6px',
                border: isCurrent ? '2px solid var(--body-color)' : '1px solid transparent',
                background: statusColors[status],
                color: status === 'not_visited' ? 'inherit' : 'white',
                cursor: 'pointer',
                fontSize: '0.75rem',
                fontWeight: isCurrent ? 'bold' : 'normal',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              }}
              title={`Q${i + 1}: ${statusLabels[status]}`}
            >
              {i + 1}
            </button>
          );
        })}
      </div>

      {/* Legend */}
      <div class="flex flex-col gap-1">
        {Object.entries(statusLabels).map(([key, label]) => (
          <div key={key} class="flex items-center gap-2 fs-xs">
            <div
              style={{
                width: '12px',
                height: '12px',
                borderRadius: '3px',
                background: statusColors[key],
                flexShrink: 0,
              }}
            />
            <span>
              {label} ({counts[key] || 0})
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
