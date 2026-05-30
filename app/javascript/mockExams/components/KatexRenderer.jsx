import { h } from 'preact';
import { useState, useEffect, useRef } from 'preact/hooks';

let katexLoaded = false;
let katexLoadPromise = null;

function loadKatex() {
  if (katexLoaded) return Promise.resolve();
  if (katexLoadPromise) return katexLoadPromise;

  katexLoadPromise = new Promise((resolve) => {
    // Load CSS
    if (!document.querySelector('link[href*="katex"]')) {
      const link = document.createElement('link');
      link.rel = 'stylesheet';
      link.href = 'https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css';
      link.crossOrigin = 'anonymous';
      document.head.appendChild(link);
    }

    // Load JS
    if (window.katex) {
      katexLoaded = true;
      resolve();
      return;
    }

    const script = document.createElement('script');
    script.src = 'https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js';
    script.crossOrigin = 'anonymous';
    script.onload = () => {
      // Load auto-render extension
      const autoRenderScript = document.createElement('script');
      autoRenderScript.src =
        'https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/contrib/auto-render.min.js';
      autoRenderScript.crossOrigin = 'anonymous';
      autoRenderScript.onload = () => {
        katexLoaded = true;
        resolve();
      };
      document.head.appendChild(autoRenderScript);
    };
    document.head.appendChild(script);
  });

  return katexLoadPromise;
}

export function hasMath(text) {
  if (!text) return false;
  return /\$[^$]+\$|\\\(|\\\[/.test(text);
}

export function KatexText({ text }) {
  const ref = useRef(null);
  const [ready, setReady] = useState(katexLoaded);

  useEffect(() => {
    if (!hasMath(text)) return;
    loadKatex().then(() => setReady(true));
  }, [text]);

  useEffect(() => {
    if (!ready || !ref.current || !window.renderMathInElement) return;
    window.renderMathInElement(ref.current, {
      delimiters: [
        { left: '$$', right: '$$', display: true },
        { left: '$', right: '$', display: false },
        { left: '\\(', right: '\\)', display: false },
        { left: '\\[', right: '\\]', display: true },
      ],
      throwOnError: false,
    });
  }, [ready, text]);

  if (!hasMath(text)) {
    return <span>{text}</span>;
  }

  return (
    <span ref={ref} style={{ whiteSpace: 'pre-wrap' }}>
      {text}
    </span>
  );
}

export function KatexHtml({ html }) {
  const ref = useRef(null);
  const [ready, setReady] = useState(katexLoaded);

  useEffect(() => {
    if (!html) return;
    loadKatex().then(() => setReady(true));
  }, [html]);

  useEffect(() => {
    if (!ready || !ref.current || !window.renderMathInElement) return;
    window.renderMathInElement(ref.current, {
      delimiters: [
        { left: '$$', right: '$$', display: true },
        { left: '$', right: '$', display: false },
        { left: '\\(', right: '\\)', display: false },
        { left: '\\[', right: '\\]', display: true },
      ],
      throwOnError: false,
    });
  }, [ready, html]);

  return <div ref={ref} dangerouslySetInnerHTML={{ __html: html }} />;
}
