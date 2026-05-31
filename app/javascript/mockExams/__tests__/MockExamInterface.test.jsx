import { h } from 'preact';
import { render, waitFor, fireEvent } from '@testing-library/preact';
import { MockExamInterface } from '../MockExamInterface';
import '@testing-library/jest-dom';

// The http utility is the only network dependency; stub it so the component
// can load its (in-memory) exam data without touching the network.
jest.mock('@utilities/http', () => ({
  request: jest.fn(),
}));

// Child components are exercised elsewhere; render them as no-ops so this spec
// stays focused on the submit/fullscreen flow.
jest.mock('../components/ExamTimer', () => ({ ExamTimer: () => null }));
jest.mock('../components/QuestionDisplay', () => ({ QuestionDisplay: () => null }));
jest.mock('../components/QuestionPalette', () => ({ QuestionPalette: () => null }));
jest.mock('../components/ExamCalculator', () => ({ ExamCalculator: () => null }));
jest.mock('../components/ExamScratchpad', () => ({ ExamScratchpad: () => null }));

import { request } from '@utilities/http';

const examPayload = {
  template: {
    title: 'Sample Exam',
    duration_minutes: 30,
    marks_per_correct: 4,
    negative_marks_per_wrong: 1,
    has_calculator: false,
    has_scratchpad: false,
  },
  time_remaining_seconds: 1800,
  responses: {},
  questions: [
    { id: 1, body: 'Q1', options: [], correct_option_key: 'a' },
    { id: 2, body: 'Q2', options: [], correct_option_key: 'b' },
  ],
};

const startExam = async (getByText) => {
  // The intro screen renders "Window Mode" when fullscreen is supported.
  const startButton = getByText('Window Mode');
  fireEvent.click(startButton);
  await waitFor(() => getByText('Submit Exam'));
};

describe('<MockExamInterface />', () => {
  let requestFullscreenMock;

  beforeEach(() => {
    // jsdom does not implement matchMedia; default to desktop viewport.
    window.matchMedia = jest.fn().mockImplementation(() => ({
      matches: false,
      addEventListener: jest.fn(),
      removeEventListener: jest.fn(),
    }));

    request.mockResolvedValue({ json: async () => examPayload });

    // Simulate Fullscreen API support.
    requestFullscreenMock = jest.fn().mockResolvedValue(undefined);
    document.documentElement.requestFullscreen = requestFullscreenMock;
    document.exitFullscreen = jest.fn().mockResolvedValue(undefined);
    Object.defineProperty(document, 'fullscreenElement', {
      configurable: true,
      writable: true,
      value: null,
    });

    jest.spyOn(window, 'confirm').mockReturnValue(true);
  });

  afterEach(() => {
    jest.clearAllMocks();
    localStorage.clear();
  });

  it('shows a custom confirmation modal instead of window.confirm on submit', async () => {
    const { getByText } = render(
      <MockExamInterface slug="sample" attemptId={42} />,
    );
    await waitFor(() => getByText('Sample Exam'));
    await startExam(getByText);

    fireEvent.click(getByText('Submit Exam'));

    // Native confirm must NOT be used (it forces fullscreen exit).
    expect(window.confirm).not.toHaveBeenCalled();
    // The in-DOM modal should appear instead.
    expect(getByText('Submit exam?')).toBeInTheDocument();
  });

  it('re-enters fullscreen when the user cancels the submit confirmation', async () => {
    const { getByText } = render(
      <MockExamInterface slug="sample" attemptId={42} />,
    );
    await waitFor(() => getByText('Sample Exam'));

    // Enter the exam in fullscreen mode.
    fireEvent.click(getByText('Full Screen Mode'));
    await waitFor(() => getByText('Submit Exam'));
    document.fullscreenElement = document.documentElement;
    requestFullscreenMock.mockClear();

    // Open the confirm modal (the native dialog would have exited fullscreen,
    // which we simulate by clearing fullscreenElement).
    fireEvent.click(getByText('Submit Exam'));
    document.fullscreenElement = null;

    fireEvent.click(getByText('Cancel'));

    // Cancel must restore fullscreen from within the click handler.
    expect(requestFullscreenMock).toHaveBeenCalledTimes(1);
    expect(getByText('Submit Exam')).toBeInTheDocument();
  });

  it('does not request fullscreen on cancel when the exam was windowed', async () => {
    const { getByText } = render(
      <MockExamInterface slug="sample" attemptId={42} />,
    );
    await waitFor(() => getByText('Sample Exam'));
    await startExam(getByText);
    requestFullscreenMock.mockClear();

    fireEvent.click(getByText('Submit Exam'));
    fireEvent.click(getByText('Cancel'));

    expect(requestFullscreenMock).not.toHaveBeenCalled();
  });

  it('submits the attempt when the user confirms', async () => {
    delete window.location;
    window.location = { href: '' };
    request.mockResolvedValueOnce({ json: async () => examPayload });
    request.mockResolvedValue({
      json: async () => ({ redirect_to: '/results/42' }),
    });

    const { getByText } = render(
      <MockExamInterface slug="sample" attemptId={42} />,
    );
    await waitFor(() => getByText('Sample Exam'));
    await startExam(getByText);

    fireEvent.click(getByText('Submit Exam'));
    fireEvent.click(getByText('Submit'));

    await waitFor(() =>
      expect(request).toHaveBeenCalledWith(
        '/mock_exams/sample/attempts/42/submit',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );
  });
});
