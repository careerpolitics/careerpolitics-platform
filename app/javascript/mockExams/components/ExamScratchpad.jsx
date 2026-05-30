import { h } from 'preact';
import { useState, useEffect, useRef, useCallback } from 'preact/hooks';

const STORAGE_KEY_PREFIX = 'mock_exam_scratchpad_';

export function ExamScratchpad({ visible, onClose, attemptId }) {
  const [text, setText] = useState('');
  const [position, setPosition] = useState({ x: 340, y: 80 });
  const [size, setSize] = useState({ w: 360, h: 300 });
  const dragging = useRef(false);
  const resizing = useRef(false);
  const dragOffset = useRef({ x: 0, y: 0 });
  const textareaRef = useRef(null);

  // Load from localStorage
  useEffect(() => {
    try {
      const stored = localStorage.getItem(`${STORAGE_KEY_PREFIX}${attemptId}`);
      if (stored) setText(stored);
    } catch {
      // ignore
    }
  }, [attemptId]);

  // Save to localStorage on change
  const handleChange = useCallback(
    (e) => {
      const value = e.target.value;
      setText(value);
      try {
        localStorage.setItem(`${STORAGE_KEY_PREFIX}${attemptId}`, value);
      } catch {
        // quota exceeded
      }
    },
    [attemptId],
  );

  // Dragging
  const handleHeaderMouseDown = useCallback((e) => {
    dragging.current = true;
    dragOffset.current = {
      x: e.clientX - position.x,
      y: e.clientY - position.y,
    };
    e.preventDefault();
  }, [position]);

  // Resizing
  const handleResizeMouseDown = useCallback((e) => {
    resizing.current = true;
    dragOffset.current = {
      x: e.clientX,
      y: e.clientY,
      w: size.w,
      h: size.h,
    };
    e.preventDefault();
    e.stopPropagation();
  }, [size]);

  useEffect(() => {
    const handleMouseMove = (e) => {
      if (dragging.current) {
        setPosition({
          x: e.clientX - dragOffset.current.x,
          y: e.clientY - dragOffset.current.y,
        });
      } else if (resizing.current) {
        setSize({
          w: Math.max(240, dragOffset.current.w + (e.clientX - dragOffset.current.x)),
          h: Math.max(200, dragOffset.current.h + (e.clientY - dragOffset.current.y)),
        });
      }
    };
    const handleMouseUp = () => {
      dragging.current = false;
      resizing.current = false;
    };

    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);
    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };
  }, []);

  // Focus textarea when opened
  useEffect(() => {
    if (visible && textareaRef.current) {
      textareaRef.current.focus();
    }
  }, [visible]);

  if (!visible) return null;

  return (
    <div
      style={{
        position: 'fixed',
        left: `${position.x}px`,
        top: `${position.y}px`,
        width: `${size.w}px`,
        height: `${size.h}px`,
        zIndex: 999,
        background: 'var(--card-bg)',
        border: '1px solid var(--card-border)',
        borderRadius: '12px',
        boxShadow: '0 8px 32px rgba(0,0,0,0.15)',
        display: 'flex',
        flexDirection: 'column',
        overflow: 'hidden',
      }}
    >
      {/* Title bar */}
      <div
        class="flex items-center justify-between p-2"
        style={{
          borderBottom: '1px solid var(--card-border)',
          cursor: 'move',
          userSelect: 'none',
          flexShrink: 0,
        }}
        onMouseDown={handleHeaderMouseDown}
      >
        <span class="fw-bold fs-s">Scratchpad</span>
        <div class="flex items-center gap-2">
          <button
            onClick={() => { setText(''); try { localStorage.removeItem(`${STORAGE_KEY_PREFIX}${attemptId}`); } catch {} }}
            style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: '12px', padding: '2px 6px' }}
            title="Clear"
          >
            Clear
          </button>
          <button
            onClick={onClose}
            style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: '16px', padding: '4px' }}
          >
            ✕
          </button>
        </div>
      </div>

      {/* Textarea */}
      <textarea
        ref={textareaRef}
        value={text}
        onInput={handleChange}
        placeholder="Use this space for rough work..."
        style={{
          flex: 1,
          width: '100%',
          border: 'none',
          outline: 'none',
          resize: 'none',
          padding: '12px',
          fontFamily: 'monospace',
          fontSize: '0.85rem',
          lineHeight: '1.5',
          background: 'var(--body-bg)',
          color: 'inherit',
        }}
      />

      {/* Resize handle */}
      <div
        onMouseDown={handleResizeMouseDown}
        style={{
          position: 'absolute',
          bottom: 0,
          right: 0,
          width: '16px',
          height: '16px',
          cursor: 'nwse-resize',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          color: 'var(--card-border)',
          fontSize: '10px',
        }}
      >
        ⟋
      </div>
    </div>
  );
}
