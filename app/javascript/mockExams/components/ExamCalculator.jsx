import { h } from 'preact';
import { useState, useEffect, useRef, useCallback } from 'preact/hooks';

export function ExamCalculator({ visible, onClose }) {
  const [display, setDisplay] = useState('0');
  const [memory, setMemory] = useState(0);
  const [waitingForOperand, setWaitingForOperand] = useState(false);
  const [pendingOperator, setPendingOperator] = useState(null);
  const [storedValue, setStoredValue] = useState(null);
  const [position, setPosition] = useState({ x: 20, y: 80 });
  const dragging = useRef(false);
  const dragOffset = useRef({ x: 0, y: 0 });

  // Dragging
  const handleHeaderMouseDown = useCallback((e) => {
    dragging.current = true;
    dragOffset.current = {
      x: e.clientX - position.x,
      y: e.clientY - position.y,
    };
    e.preventDefault();
  }, [position]);

  useEffect(() => {
    const handleMouseMove = (e) => {
      if (dragging.current) {
        setPosition({
          x: e.clientX - dragOffset.current.x,
          y: e.clientY - dragOffset.current.y,
        });
      }
    };
    const handleMouseUp = () => { dragging.current = false; };

    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);
    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };
  }, []);

  const inputDigit = (digit) => {
    if (waitingForOperand) {
      setDisplay(String(digit));
      setWaitingForOperand(false);
    } else {
      setDisplay(display === '0' ? String(digit) : display + digit);
    }
  };

  const inputDecimal = () => {
    if (waitingForOperand) {
      setDisplay('0.');
      setWaitingForOperand(false);
      return;
    }
    if (!display.includes('.')) {
      setDisplay(display + '.');
    }
  };

  const clearAll = () => {
    setDisplay('0');
    setStoredValue(null);
    setPendingOperator(null);
    setWaitingForOperand(false);
  };

  const toggleSign = () => {
    const value = parseFloat(display);
    setDisplay(String(-value));
  };

  const inputPercent = () => {
    const value = parseFloat(display);
    setDisplay(String(value / 100));
  };

  const performOperation = (nextOperator) => {
    const inputValue = parseFloat(display);

    if (storedValue === null) {
      setStoredValue(inputValue);
    } else if (pendingOperator) {
      const result = calculate(storedValue, inputValue, pendingOperator);
      setStoredValue(result);
      setDisplay(String(result));
    }

    setWaitingForOperand(true);
    setPendingOperator(nextOperator);
  };

  const calculate = (a, b, op) => {
    switch (op) {
      case '+': return a + b;
      case '-': return a - b;
      case '×': return a * b;
      case '÷': return b !== 0 ? a / b : 0;
      default: return b;
    }
  };

  const handleEquals = () => {
    if (storedValue === null || pendingOperator === null) return;
    const inputValue = parseFloat(display);
    const result = calculate(storedValue, inputValue, pendingOperator);
    setDisplay(String(result));
    setStoredValue(null);
    setPendingOperator(null);
    setWaitingForOperand(true);
  };

  const handleSqrt = () => {
    const value = parseFloat(display);
    setDisplay(String(Math.sqrt(Math.abs(value))));
    setWaitingForOperand(true);
  };

  const handlePower = () => {
    const value = parseFloat(display);
    setDisplay(String(value * value));
    setWaitingForOperand(true);
  };

  const memoryStore = () => setMemory(parseFloat(display));
  const memoryRecall = () => { setDisplay(String(memory)); setWaitingForOperand(true); };
  const memoryClear = () => setMemory(0);
  const memoryAdd = () => setMemory(memory + parseFloat(display));

  if (!visible) return null;

  const btnStyle = {
    padding: '8px',
    border: '1px solid var(--card-border)',
    borderRadius: '6px',
    background: 'var(--card-secondary-bg)',
    cursor: 'pointer',
    fontSize: '0.9rem',
    fontWeight: 'bold',
  };

  const opStyle = {
    ...btnStyle,
    background: 'var(--accent-brand)',
    color: 'white',
  };

  return (
    <div
      style={{
        position: 'fixed',
        left: `${position.x}px`,
        top: `${position.y}px`,
        zIndex: 999,
        background: 'var(--card-bg)',
        border: '1px solid var(--card-border)',
        borderRadius: '12px',
        boxShadow: '0 8px 32px rgba(0,0,0,0.15)',
        width: '260px',
        overflow: 'hidden',
      }}
    >
      {/* Title bar */}
      <div
        class="flex items-center justify-between p-2"
        style={{ borderBottom: '1px solid var(--card-border)', cursor: 'move', userSelect: 'none' }}
        onMouseDown={handleHeaderMouseDown}
      >
        <span class="fw-bold fs-s">Calculator</span>
        <button
          onClick={onClose}
          style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: '16px' }}
        >
          ✕
        </button>
      </div>

      <div class="p-3">
        {/* Display */}
        <div
          class="p-3 mb-3 text-right fw-bold fs-xl radius-default"
          style={{
            background: 'var(--body-bg)',
            border: '1px solid var(--card-border)',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
            fontVariantNumeric: 'tabular-nums',
          }}
        >
          {display}
        </div>

        {/* Memory row */}
        <div class="grid gap-1 mb-2" style={{ gridTemplateColumns: 'repeat(4, 1fr)' }}>
          <button style={btnStyle} onClick={memoryClear}>MC</button>
          <button style={btnStyle} onClick={memoryRecall}>MR</button>
          <button style={btnStyle} onClick={memoryStore}>MS</button>
          <button style={btnStyle} onClick={memoryAdd}>M+</button>
        </div>

        {/* Function row */}
        <div class="grid gap-1 mb-2" style={{ gridTemplateColumns: 'repeat(4, 1fr)' }}>
          <button style={btnStyle} onClick={clearAll}>AC</button>
          <button style={btnStyle} onClick={toggleSign}>±</button>
          <button style={btnStyle} onClick={handleSqrt}>√</button>
          <button style={btnStyle} onClick={handlePower}>x²</button>
        </div>

        {/* Number pad + operators */}
        <div class="grid gap-1" style={{ gridTemplateColumns: 'repeat(4, 1fr)' }}>
          {[7,8,9].map(d => <button key={d} style={btnStyle} onClick={() => inputDigit(d)}>{d}</button>)}
          <button style={opStyle} onClick={() => performOperation('÷')}>÷</button>

          {[4,5,6].map(d => <button key={d} style={btnStyle} onClick={() => inputDigit(d)}>{d}</button>)}
          <button style={opStyle} onClick={() => performOperation('×')}>×</button>

          {[1,2,3].map(d => <button key={d} style={btnStyle} onClick={() => inputDigit(d)}>{d}</button>)}
          <button style={opStyle} onClick={() => performOperation('-')}>−</button>

          <button style={btnStyle} onClick={() => inputDigit(0)}>0</button>
          <button style={btnStyle} onClick={inputDecimal}>.</button>
          <button style={btnStyle} onClick={inputPercent}>%</button>
          <button style={opStyle} onClick={() => performOperation('+')}>+</button>
        </div>

        {/* Equals */}
        <button
          class="mt-2"
          style={{
            ...opStyle,
            width: '100%',
            padding: '10px',
            fontSize: '1.1rem',
          }}
          onClick={handleEquals}
        >
          =
        </button>
      </div>
    </div>
  );
}
