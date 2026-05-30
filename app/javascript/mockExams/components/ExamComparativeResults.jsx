import { h } from 'preact';

export function ExamComparativeResults({ attempt, templateStats }) {
  if (!templateStats || !attempt) return null;

  const s = templateStats;

  return (
    <div class="flex flex-col gap-4">
      <PercentileBar
        percentile={attempt.percentile}
        rank={attempt.rank}
        totalAttempts={s.total_attempts}
      />
      <ScoreHistogram
        distribution={s.score_distribution}
        userScore={attempt.total_score}
        maxScore={attempt.max_possible_score}
      />
      <SectionComparison
        userSections={attempt.section_scores}
        avgSections={s.section_averages}
      />
      <DifficultyBreakdown
        userAccuracy={attempt.accuracy_percent}
        difficultyAccuracy={s.difficulty_accuracy}
        userResponses={attempt.difficulty_breakdown}
      />
      <TimeAnalysis
        userAvgTime={attempt.avg_time_per_question}
        communityAvgTime={s.average_time_seconds ? (s.average_time_seconds / (attempt.total_questions || 1)).toFixed(1) : 0}
      />
    </div>
  );
}

function PercentileBar({ percentile, rank, totalAttempts }) {
  const pct = parseFloat(percentile) || 0;

  return (
    <div class="crayons-card p-6">
      <h3 class="crayons-subtitle-2 mb-3">Your Performance</h3>
      <p class="fs-xl fw-bold mb-2" style={{ color: 'var(--accent-brand)' }}>
        Better than {pct}% of aspirants
      </p>
      <p class="fs-s color-secondary mb-4">
        Rank #{rank} out of {totalAttempts} attempts
      </p>

      {/* Percentile bar */}
      <div
        style={{
          width: '100%',
          height: '24px',
          background: 'var(--card-secondary-bg)',
          borderRadius: '12px',
          position: 'relative',
          overflow: 'hidden',
        }}
      >
        <div
          style={{
            width: `${pct}%`,
            height: '100%',
            background: pct >= 75 ? 'var(--accent-success)' : pct >= 50 ? 'var(--accent-brand)' : pct >= 25 ? 'var(--accent-warning)' : 'var(--accent-danger)',
            borderRadius: '12px',
            transition: 'width 1s ease-out',
          }}
        />
        <div
          style={{
            position: 'absolute',
            left: `${pct}%`,
            top: '-4px',
            transform: 'translateX(-50%)',
            width: '8px',
            height: '32px',
            background: 'var(--body-color)',
            borderRadius: '4px',
          }}
        />
      </div>
      <div class="flex justify-between fs-xs color-secondary mt-1">
        <span>0%</span>
        <span>25%</span>
        <span>50%</span>
        <span>75%</span>
        <span>100%</span>
      </div>
    </div>
  );
}

function ScoreHistogram({ distribution, userScore, maxScore }) {
  if (!distribution || !distribution.length) return null;

  const maxCount = Math.max(...distribution.map((d) => d.count), 1);

  return (
    <div class="crayons-card p-6">
      <h3 class="crayons-subtitle-2 mb-3">Score Distribution</h3>
      <svg viewBox="0 0 400 160" width="100%" style={{ maxHeight: '180px' }}>
        {distribution.map((bucket, i) => {
          const barH = (bucket.count / maxCount) * 120;
          const x = i * 40;
          const isUserBucket = userScore >= bucket.min && userScore < bucket.max;

          return (
            <g key={i}>
              <rect
                x={x + 2}
                y={140 - barH}
                width={36}
                height={barH}
                rx={3}
                fill={isUserBucket ? 'var(--accent-brand)' : 'var(--card-secondary-bg)'}
                stroke={isUserBucket ? 'var(--accent-brand)' : 'none'}
                stroke-width={isUserBucket ? 2 : 0}
              />
              <text
                x={x + 20}
                y={155}
                text-anchor="middle"
                font-size="9"
                fill="currentColor"
                opacity={0.6}
              >
                {bucket.min}
              </text>
              {bucket.count > 0 && (
                <text
                  x={x + 20}
                  y={140 - barH - 4}
                  text-anchor="middle"
                  font-size="9"
                  fill="currentColor"
                  opacity={0.7}
                >
                  {bucket.count}
                </text>
              )}
            </g>
          );
        })}
      </svg>
      <div class="flex justify-between fs-xs color-secondary mt-1">
        <span>Low</span>
        <span>
          Your score: <strong>{userScore}</strong>
        </span>
        <span>High</span>
      </div>
    </div>
  );
}

function SectionComparison({ userSections, avgSections }) {
  if (!userSections || !avgSections) return null;

  const sections = Object.keys(userSections);
  if (!sections.length) return null;

  return (
    <div class="crayons-card p-6">
      <h3 class="crayons-subtitle-2 mb-3">Section Comparison</h3>
      <div class="flex flex-col gap-3">
        {sections.map((name) => {
          const user = userSections[name];
          const avg = avgSections[name];
          if (!user) return null;

          const userScore = user.score || 0;
          const avgScore = avg?.avg_score || 0;
          const maxWidth = Math.max(userScore, avgScore, 1);
          const isAbove = userScore >= avgScore;

          return (
            <div key={name}>
              <div class="flex justify-between fs-s mb-1">
                <span class="fw-bold">{name}</span>
                <span class={isAbove ? '' : ''} style={{ color: isAbove ? 'var(--accent-success)' : 'var(--accent-danger)' }}>
                  {userScore} {isAbove ? '▲' : '▼'}
                </span>
              </div>
              {/* Your score */}
              <div class="flex items-center gap-2 mb-1">
                <span class="fs-xs" style={{ width: '36px' }}>You</span>
                <div style={{ flex: 1, height: '14px', background: 'var(--card-secondary-bg)', borderRadius: '7px', overflow: 'hidden' }}>
                  <div
                    style={{
                      width: `${(userScore / maxWidth) * 100}%`,
                      height: '100%',
                      background: isAbove ? 'var(--accent-success)' : 'var(--accent-danger)',
                      borderRadius: '7px',
                    }}
                  />
                </div>
                <span class="fs-xs" style={{ width: '36px', textAlign: 'right' }}>{userScore}</span>
              </div>
              {/* Average */}
              <div class="flex items-center gap-2">
                <span class="fs-xs" style={{ width: '36px' }}>Avg</span>
                <div style={{ flex: 1, height: '14px', background: 'var(--card-secondary-bg)', borderRadius: '7px', overflow: 'hidden' }}>
                  <div
                    style={{
                      width: `${(avgScore / maxWidth) * 100}%`,
                      height: '100%',
                      background: 'var(--card-border)',
                      borderRadius: '7px',
                    }}
                  />
                </div>
                <span class="fs-xs" style={{ width: '36px', textAlign: 'right' }}>{avgScore}</span>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function DifficultyBreakdown({ difficultyAccuracy, userResponses }) {
  if (!difficultyAccuracy) return null;

  const levels = ['easy', 'medium', 'hard'];
  const colors = {
    easy: 'var(--accent-success)',
    medium: 'var(--accent-warning)',
    hard: 'var(--accent-danger)',
  };

  return (
    <div class="crayons-card p-6">
      <h3 class="crayons-subtitle-2 mb-3">Difficulty Breakdown</h3>
      <div class="grid gap-4" style={{ gridTemplateColumns: 'repeat(3, 1fr)' }}>
        {levels.map((level) => {
          const avgAcc = difficultyAccuracy[level] || 0;
          const userAcc = userResponses?.[level] || avgAcc;

          return (
            <div key={level} class="text-center">
              <RingChart percentage={userAcc} color={colors[level]} size={80} />
              <div class="mt-2 fw-bold fs-s" style={{ textTransform: 'capitalize' }}>{level}</div>
              <div class="fs-xs color-secondary">
                You: {userAcc}% | Avg: {avgAcc}%
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function RingChart({ percentage, color, size }) {
  const r = (size - 8) / 2;
  const circumference = 2 * Math.PI * r;
  const offset = circumference - (percentage / 100) * circumference;

  return (
    <svg width={size} height={size} style={{ display: 'block', margin: '0 auto' }}>
      <circle
        cx={size / 2}
        cy={size / 2}
        r={r}
        fill="none"
        stroke="var(--card-secondary-bg)"
        stroke-width="6"
      />
      <circle
        cx={size / 2}
        cy={size / 2}
        r={r}
        fill="none"
        stroke={color}
        stroke-width="6"
        stroke-dasharray={circumference}
        stroke-dashoffset={offset}
        stroke-linecap="round"
        transform={`rotate(-90 ${size / 2} ${size / 2})`}
      />
      <text
        x={size / 2}
        y={size / 2 + 5}
        text-anchor="middle"
        font-size="14"
        font-weight="bold"
        fill="currentColor"
      >
        {percentage}%
      </text>
    </svg>
  );
}

function TimeAnalysis({ userAvgTime, communityAvgTime }) {
  const userT = parseFloat(userAvgTime) || 0;
  const commT = parseFloat(communityAvgTime) || 0;
  const faster = userT < commT;

  return (
    <div class="crayons-card p-6">
      <h3 class="crayons-subtitle-2 mb-3">Time Analysis</h3>
      <div class="grid gap-4" style={{ gridTemplateColumns: '1fr 1fr' }}>
        <div class="text-center p-3 radius-default" style={{ background: 'var(--card-secondary-bg)' }}>
          <div class="fs-xs color-secondary">Your Avg/Question</div>
          <div class="fs-xl fw-bold">{userT}s</div>
        </div>
        <div class="text-center p-3 radius-default" style={{ background: 'var(--card-secondary-bg)' }}>
          <div class="fs-xs color-secondary">Community Avg</div>
          <div class="fs-xl fw-bold">{commT}s</div>
        </div>
      </div>
      <p class="fs-s mt-3 text-center" style={{ color: faster ? 'var(--accent-success)' : 'var(--accent-warning)' }}>
        {faster
          ? `You're ${(commT - userT).toFixed(1)}s faster than average per question`
          : `You're ${(userT - commT).toFixed(1)}s slower than average per question`}
      </p>
    </div>
  );
}
