// Miaou Web Terminal Client
// Connects to the Miaou web driver via WebSocket and renders using xterm.js.

(function () {
  'use strict';

  var statusEl = document.getElementById('status');
  var role = null;

  function setStatus(msg, cls) {
    statusEl.textContent = msg;
    statusEl.className = cls || '';
  }

  // Map DOM KeyboardEvent to Miaou key string
  function mapKey(ev) {
    // Ctrl combinations
    if (ev.ctrlKey && ev.key.length === 1) {
      return 'C-' + ev.key.toLowerCase();
    }

    switch (ev.key) {
      case 'Enter': return 'Enter';
      case 'Escape': return 'Esc';
      case 'Tab': return ev.shiftKey ? 'Shift-Tab' : 'Tab';
      case 'Backspace': return 'Backspace';
      case 'Delete': return 'Delete';
      case 'ArrowUp': return 'Up';
      case 'ArrowDown': return 'Down';
      case 'ArrowLeft': return 'Left';
      case 'ArrowRight': return 'Right';
      case 'Home': return 'Home';
      case 'End': return 'End';
      case 'PageUp': return 'PageUp';
      case 'PageDown': return 'PageDown';
      case 'F1': return 'F1';
      case 'F2': return 'F2';
      case 'F3': return 'F3';
      case 'F4': return 'F4';
      case 'F5': return 'F5';
      case 'F6': return 'F6';
      case 'F7': return 'F7';
      case 'F8': return 'F8';
      case 'F9': return 'F9';
      case 'F10': return 'F10';
      case 'F11': return 'F11';
      case 'F12': return 'F12';
      case 'Shift':
      case 'Control':
      case 'Alt':
      case 'Meta':
      case 'CapsLock':
      case 'NumLock':
      case 'ScrollLock':
        return null; // Ignore modifier-only keys
      default:
        if (ev.key.length === 1) return ev.key;
        return null;
    }
  }

  // Create xterm.js terminal
  var term = new window.Terminal({
    cursorBlink: false,
    cursorStyle: 'block',
    scrollback: 0,
    disableStdin: true, // We handle input ourselves
    convertEol: false,
    theme: {
      background: '#1e1e1e',
      foreground: '#d4d4d4'
    }
  });

  var fitAddon = new window.FitAddon.FitAddon();
  term.loadAddon(fitAddon);
  term.open(document.getElementById('terminal'));
  fitAddon.fit();

  // Connect WebSocket
  var protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
  var ws = new WebSocket(protocol + '//' + location.host + '/ws');

  ws.onopen = function () {
    // Don't set status yet — wait for the role message from the server
    if (role === null) {
      setStatus('Connected', 'connected');
    }
  };

  ws.onmessage = function (event) {
    // First message should be a role assignment
    if (role === null) {
      try {
        var msg = JSON.parse(event.data);
        if (msg.type === 'role') {
          role = msg.role;
          if (role === 'controller') {
            setStatus('Connected', 'connected');
            // Send initial terminal size
            var dims = fitAddon.proposeDimensions();
            if (dims) {
              ws.send(JSON.stringify({
                type: 'resize',
                rows: dims.rows,
                cols: dims.cols
              }));
            }
          } else {
            setStatus('Connected (read-only viewer)', 'viewer');
          }
          return;
        }
      } catch (e) {
        // Not JSON, treat as ANSI data below
      }
    }

    // Server sends raw ANSI data as text frames
    term.write(event.data);
  };

  ws.onclose = function () {
    setStatus('Disconnected', 'disconnected');
  };

  ws.onerror = function () {
    setStatus('Connection error', 'disconnected');
  };

  // Intercept all keyboard events and send to server
  term.attachCustomKeyEventHandler(function (ev) {
    if (ev.type !== 'keydown') return false;
    if (role === 'viewer') return false;
    if (ws.readyState !== WebSocket.OPEN) return false;

    var key = mapKey(ev);
    if (key) {
      ws.send(JSON.stringify({ type: 'key', key: key }));
    }
    return false; // Prevent xterm.js from processing
  });

  // Handle mouse clicks
  document.getElementById('terminal').addEventListener('mousedown', function (ev) {
    if (role === 'viewer') return;
    if (ws.readyState !== WebSocket.OPEN) return;

    // Convert pixel coordinates to terminal cell coordinates
    var cellSize = fitAddon.proposeDimensions();
    if (!cellSize) return;

    var termEl = term.element;
    if (!termEl) return;

    var rect = termEl.querySelector('.xterm-screen').getBoundingClientRect();
    var cellWidth = rect.width / cellSize.cols;
    var cellHeight = rect.height / cellSize.rows;

    var col = Math.floor((ev.clientX - rect.left) / cellWidth);
    var row = Math.floor((ev.clientY - rect.top) / cellHeight);

    if (row >= 0 && col >= 0) {
      ws.send(JSON.stringify({ type: 'mouse', row: row, col: col }));
    }
  });

  // Handle terminal resize
  window.addEventListener('resize', function () {
    fitAddon.fit();
    if (role === 'viewer') return;
    if (ws.readyState === WebSocket.OPEN) {
      var dims = fitAddon.proposeDimensions();
      if (dims) {
        ws.send(JSON.stringify({
          type: 'resize',
          rows: dims.rows,
          cols: dims.cols
        }));
      }
    }
  });
})();
