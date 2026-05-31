import { h } from 'preact';
import { render, screen, waitFor } from '@testing-library/preact';
import '@testing-library/jest-dom';
import { QuestionDisplay } from '../components/QuestionDisplay';
import { __clearTranslationCache } from '../translateClient';

// Render KaTeX/HTML helpers as plain text so we can assert on visible strings.
// `h` is required lazily inside the factory because jest.mock is hoisted above
// the module-level import.
jest.mock('../components/KatexRenderer', () => {
  const { h: createElement } = require('preact');
  return {
    KatexText: ({ text }) => createElement('span', null, text),
    KatexHtml: ({ text }) => createElement('span', null, text),
    hasMath: () => false,
  };
});

const baseQuestion = {
  id: 1,
  position: 1,
  section_name: 'General Knowledge',
  question_text: 'What is the capital of France?',
  question_html: '<p>What is the capital of France?</p>',
  correct_option_key: 'A',
  options: [
    { key: 'A', text: 'Paris' },
    { key: 'B', text: 'London' },
    { key: 'C', text: 'Berlin' },
    { key: 'D', text: 'Madrid' },
  ],
};

describe('QuestionDisplay translation toggle', () => {
  beforeEach(() => {
    __clearTranslationCache();
    global.fetch = jest.fn();
  });

  afterEach(() => {
    jest.resetAllMocks();
  });

  it('renders English text without calling the translation endpoint', () => {
    render(
      <QuestionDisplay
        question={baseQuestion}
        selectedOption={null}
        onSelectOption={() => {}}
        isReview={false}
        language="en"
      />,
    );

    expect(screen.getByText('What is the capital of France?')).toBeInTheDocument();
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('prefers pre-translated Hindi columns and never fetches', () => {
    const question = {
      ...baseQuestion,
      text_hi: 'फ्रांस की राजधानी क्या है?',
      options: [
        { key: 'A', text: 'Paris', text_hi: 'पेरिस' },
        { key: 'B', text: 'London', text_hi: 'लंदन' },
        { key: 'C', text: 'Berlin', text_hi: 'बर्लिन' },
        { key: 'D', text: 'Madrid', text_hi: 'मैड्रिड' },
      ],
    };

    render(
      <QuestionDisplay
        question={question}
        selectedOption={null}
        onSelectOption={() => {}}
        isReview={false}
        language="hi"
      />,
    );

    expect(screen.getByText('फ्रांस की राजधानी क्या है?')).toBeInTheDocument();
    expect(screen.getByText('पेरिस')).toBeInTheDocument();
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('machine-translates on demand when no pre-translation exists', async () => {
    const translations = {
      'What is the capital of France?': 'फ्रांस की राजधानी क्या है?',
      Paris: 'पेरिस',
      London: 'लंदन',
      Berlin: 'बर्लिन',
      Madrid: 'मैड्रिड',
    };
    global.fetch.mockImplementation((url) => {
      const q = new URL(url).searchParams.get('q');
      return Promise.resolve({
        ok: true,
        json: async () => [[[translations[q] || q, q]]],
      });
    });

    render(
      <QuestionDisplay
        question={baseQuestion}
        selectedOption={null}
        onSelectOption={() => {}}
        isReview={false}
        language="hi"
      />,
    );

    await waitFor(() => {
      expect(screen.getByText('फ्रांस की राजधानी क्या है?')).toBeInTheDocument();
    });
    expect(screen.getByText('पेरिस')).toBeInTheDocument();
    expect(global.fetch).toHaveBeenCalled();
  });

  it('falls back to original text and shows a notice when translation fails', async () => {
    global.fetch.mockRejectedValue(new Error('rate limited'));

    render(
      <QuestionDisplay
        question={baseQuestion}
        selectedOption={null}
        onSelectOption={() => {}}
        isReview={false}
        language="hi"
      />,
    );

    await waitFor(() => {
      expect(screen.getByText(/Translation unavailable/)).toBeInTheDocument();
    });
    // Original English text is still shown (never blank).
    expect(screen.getByText('What is the capital of France?')).toBeInTheDocument();
    expect(screen.getByText('Paris')).toBeInTheDocument();
  });
});
