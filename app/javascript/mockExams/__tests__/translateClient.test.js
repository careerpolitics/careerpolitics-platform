import { translateText, __clearTranslationCache } from '../translateClient';

describe('translateClient', () => {
  beforeEach(() => {
    __clearTranslationCache();
    global.fetch = jest.fn();
  });

  afterEach(() => {
    jest.resetAllMocks();
  });

  const gtxResponse = (segments) => [
    segments.map((s) => [s, 'original', null, null, 1]),
    null,
    'en',
  ];

  it('returns the original text unchanged for empty/blank input without fetching', async () => {
    const result = await translateText('   ', 'hi');
    expect(result).toEqual({ text: '   ', translated: false });
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('translates via the keyless gtx endpoint and concatenates segments', async () => {
    global.fetch.mockResolvedValue({
      ok: true,
      json: async () => gtxResponse(['नमस्ते ', 'दुनिया']),
    });

    const result = await translateText('Hello world', 'hi');

    expect(result).toEqual({ text: 'नमस्ते दुनिया', translated: true });
    const calledUrl = global.fetch.mock.calls[0][0];
    expect(calledUrl).toContain('translate.googleapis.com/translate_a/single');
    expect(calledUrl).toContain('client=gtx');
    expect(calledUrl).toContain('tl=hi');
  });

  it('caches results so repeated calls do not re-fetch', async () => {
    global.fetch.mockResolvedValue({
      ok: true,
      json: async () => gtxResponse(['अनुवाद']),
    });

    await translateText('Translate me', 'hi');
    await translateText('Translate me', 'hi');

    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  it('falls back to the original text on a network error and does not cache the failure', async () => {
    global.fetch.mockRejectedValueOnce(new Error('network down'));
    const first = await translateText('Question text', 'hi');
    expect(first).toEqual({ text: 'Question text', translated: false });

    // A later success should still be attempted (failure not cached).
    global.fetch.mockResolvedValueOnce({
      ok: true,
      json: async () => gtxResponse(['प्रश्न']),
    });
    const second = await translateText('Question text', 'hi');
    expect(second).toEqual({ text: 'प्रश्न', translated: true });
    expect(global.fetch).toHaveBeenCalledTimes(2);
  });

  it('falls back when the endpoint returns a non-OK status', async () => {
    global.fetch.mockResolvedValue({ ok: false, status: 429, json: async () => ({}) });
    const result = await translateText('Rate limited', 'hi');
    expect(result).toEqual({ text: 'Rate limited', translated: false });
  });

  it('falls back when the response shape is unexpected', async () => {
    global.fetch.mockResolvedValue({ ok: true, json: async () => ({ unexpected: true }) });
    const result = await translateText('Weird shape', 'hi');
    expect(result).toEqual({ text: 'Weird shape', translated: false });
  });
});
