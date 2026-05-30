import { h } from 'preact';
import { useState, useEffect } from 'preact/hooks';
import { request } from '@utilities/http';

const TIME_FILTERS = [
  { key: 'all', label: 'All Time' },
  { key: 'month', label: 'This Month' },
  { key: 'week', label: 'This Week' },
];

export function ExamLeaderboard({ slug, currentUserId, currentAttemptId }) {
  const [entries, setEntries] = useState([]);
  const [loading, setLoading] = useState(true);
  const [timeFilter, setTimeFilter] = useState('all');

  useEffect(() => {
    setLoading(true);
    request(`/mock_exams/${slug}/leaderboard.json?filter=${timeFilter}`)
      .then((res) => res.json())
      .then((data) => {
        setEntries(data.entries || []);
        setLoading(false);
      })
      .catch(() => setLoading(false));
  }, [slug, timeFilter]);

  if (loading) {
    return (
      <div class="crayons-card p-6 flex justify-center">
        <div class="crayons-loading" aria-label="Loading leaderboard..." />
      </div>
    );
  }

  return (
    <div class="crayons-card p-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="crayons-subtitle-2">Leaderboard</h3>
        <div class="flex gap-1">
          {TIME_FILTERS.map((f) => (
            <button
              key={f.key}
              class={`c-btn c-btn--s ${timeFilter === f.key ? 'c-btn--primary' : 'c-btn--secondary'}`}
              onClick={() => setTimeFilter(f.key)}
            >
              {f.label}
            </button>
          ))}
        </div>
      </div>

      {entries.length === 0 ? (
        <p class="color-secondary text-center">No attempts yet for this period.</p>
      ) : (
        <table class="crayons-table" style={{ width: '100%' }}>
          <thead>
          <tr>
            <th style={{ width: '50px' }}>#</th>
            <th>User</th>
            <th>Score</th>
            <th>Accuracy</th>
            <th>Time</th>
          </tr>
          </thead>
          <tbody>
          {entries.map((entry, i) => {
            const isCurrentUser = entry.user_id === currentUserId;
            const isCurrentAttempt = entry.attempt_id === currentAttemptId;

            return (
              <tr
                key={entry.attempt_id}
                style={{
                  background: isCurrentUser ? 'var(--accent-brand-a10)' : 'transparent',
                  fontWeight: isCurrentUser ? 'bold' : 'normal',
                }}
              >
                <td>
                  <RankBadge rank={i + 1} />
                </td>
                <td>
                  <div class="flex items-center gap-2">
                    {entry.profile_image && (
                      <img
                        src={entry.profile_image}
                        alt=""
                        style={{ width: '24px', height: '24px', borderRadius: '50%' }}
                        loading="lazy"
                      />
                    )}
                    <span>
                        {entry.username}
                      {isCurrentUser && <span class="fs-xs color-secondary"> (you)</span>}
                      </span>
                  </div>
                </td>
                <td>{entry.total_score} / {entry.max_possible_score}</td>
                <td>{entry.accuracy_percent}%</td>
                <td>{formatTime(entry.time_taken_seconds)}</td>
              </tr>
            );
          })}
          </tbody>
        </table>
      )}
    </div>
  );
}

function RankBadge({ rank }) {
  const medals = { 1: '🥇', 2: '🥈', 3: '🥉' };

  if (medals[rank]) {
    return <span style={{ fontSize: '1.2rem' }}>{medals[rank]}</span>;
  }
  return <span class="color-secondary">{rank}</span>;
}

function formatTime(seconds) {
  if (!seconds) return '—';
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}m ${s}s`;
}
