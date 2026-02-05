// Miaou Web Terminal Client
// Composable factory: MiaouTerminal(container, options)

window.MiaouTerminal = function (container, options) {
  'use strict';

  options = options || {};
  var wsPath = options.wsPath || '/ws';
  var initialPassword = options.password || null;
  var onRole = options.onRole || function () {};
  var onStatusChange = options.onStatusChange || function () {};
  var onAuthRequired = options.onAuthRequired || null;

  var storageKey = 'miaou_password_' + wsPath;
  var role = null;
  var ws = null;

  // Map DOM KeyboardEvent to Miaou key string
  function mapKey(ev) {
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
        return null;
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
    disableStdin: true,
    convertEol: false,
    theme: {
      background: '#1e1e1e',
      foreground: '#d4d4d4'
    }
  });

  var fitAddon = new window.FitAddon.FitAddon();
  term.loadAddon(fitAddon);
  term.open(container);
  // Defer initial fit so the browser has settled the layout
  requestAnimationFrame(function () { fitAddon.fit(); });

  function buildWsUrl(password) {
    var protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    var url = protocol + '//' + location.host + wsPath;
    if (password) {
      url += '?password=' + encodeURIComponent(password);
    }
    return url;
  }

  function connect(password) {
    role = null;
    var gotRole = false;
    ws = new WebSocket(buildWsUrl(password));

    ws.onopen = function () {
      if (role === null) {
        onStatusChange('connected', 'Connected');
      }
    };

    ws.onmessage = function (event) {
      if (role === null) {
        try {
          var msg = JSON.parse(event.data);
          if (msg.type === 'role') {
            role = msg.role;
            gotRole = true;
            if (password) {
              sessionStorage.setItem(storageKey, password);
            }
            onRole(role);
            if (role === 'controller') {
              onStatusChange('connected', 'Connected');
              fitAddon.fit();
              var dims = fitAddon.proposeDimensions();
              if (dims) {
                ws.send(JSON.stringify({
                  type: 'resize',
                  rows: dims.rows,
                  cols: dims.cols
                }));
              }
            } else {
              onStatusChange('viewer', 'Connected (read-only viewer)');
            }
            return;
          }
        } catch (e) {
          // Not JSON, treat as ANSI data below
        }
      }
      term.write(event.data);
    };

    ws.onclose = function () {
      onStatusChange('disconnected', 'Disconnected');
      if (!gotRole) {
        sessionStorage.removeItem(storageKey);
        if (onAuthRequired) {
          onAuthRequired(!!password, function (newPassword) {
            connect(newPassword);
          });
        }
      }
    };

    ws.onerror = function () {
      onStatusChange('disconnected', 'Connection error');
    };
  }

  // Intercept keyboard events
  term.attachCustomKeyEventHandler(function (ev) {
    if (ev.type !== 'keydown') return false;
    if (role === 'viewer') return false;
    if (!ws || ws.readyState !== WebSocket.OPEN) return false;

    var key = mapKey(ev);
    if (key) {
      ws.send(JSON.stringify({ type: 'key', key: key }));
    }
    return false;
  });

  // Handle mouse clicks
  container.addEventListener('mousedown', function (ev) {
    if (role === 'viewer') return;
    if (!ws || ws.readyState !== WebSocket.OPEN) return;

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
    if (ws && ws.readyState === WebSocket.OPEN) {
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

  // Initial connection
  var saved = sessionStorage.getItem(storageKey);
  connect(initialPassword || saved || '');

  return {
    term: term,
    fitAddon: fitAddon,
    reconnect: function (pw) { connect(pw); },
    getRole: function () { return role; }
  };
};
