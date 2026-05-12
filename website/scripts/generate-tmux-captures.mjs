import { execFileSync } from 'node:child_process';
import { mkdir, rm, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const repo = dirname(root);
const outDir = join(root, 'src/media/captures');
const frameDir = join(outDir, '_frames');

function sh(command, args, options = {}) {
  try {
    return execFileSync(command, args, {
      cwd: repo,
      encoding: 'utf8',
      stdio: options.stdio ?? ['ignore', 'pipe', 'pipe'],
      env: { ...process.env, TERM: 'xterm-256color' },
    });
  } catch (error) {
    if (options.allowFailure) return '';
    throw error;
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function escapeXml(value) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

const xtermPalette = [
  '#000000', '#cd0000', '#00cd00', '#cdcd00', '#0000ee', '#cd00cd', '#00cdcd', '#e5e5e5',
  '#7f7f7f', '#ff0000', '#00ff00', '#ffff00', '#5c5cff', '#ff00ff', '#00ffff', '#ffffff',
];

for (let r = 0; r < 6; r += 1) {
  for (let g = 0; g < 6; g += 1) {
    for (let b = 0; b < 6; b += 1) {
      const component = (n) => (n === 0 ? 0 : 55 + n * 40);
      xtermPalette.push(
        `#${component(r).toString(16).padStart(2, '0')}${component(g).toString(16).padStart(2, '0')}${component(b).toString(16).padStart(2, '0')}`,
      );
    }
  }
}

for (let i = 0; i < 24; i += 1) {
  const level = 8 + i * 10;
  const hex = level.toString(16).padStart(2, '0');
  xtermPalette.push(`#${hex}${hex}${hex}`);
}

function sgrColor(index, fallback) {
  return xtermPalette[index] ?? fallback;
}

function applySgr(style, params) {
  const codes = params.length === 0 ? [0] : params.map((p) => (p === '' ? 0 : Number(p)));
  for (let i = 0; i < codes.length; i += 1) {
    const code = codes[i];
    if (code === 0) {
      style.fg = '#e7f8ff';
      style.bg = null;
      style.bold = false;
    } else if (code === 1) {
      style.bold = true;
    } else if (code === 2) {
      style.fg = '#98a4b8';
    } else if (code === 22) {
      style.bold = false;
    } else if (code === 7) {
      style.inverse = true;
    } else if (code === 27) {
      style.inverse = false;
    } else if (code === 39) {
      style.fg = '#e7f8ff';
    } else if (code === 49) {
      style.bg = null;
    } else if (code >= 30 && code <= 37) {
      style.fg = sgrColor(code - 30, style.fg);
    } else if (code >= 40 && code <= 47) {
      style.bg = sgrColor(code - 40, style.bg);
    } else if (code >= 90 && code <= 97) {
      style.fg = sgrColor(code - 90 + 8, style.fg);
    } else if (code >= 100 && code <= 107) {
      style.bg = sgrColor(code - 100 + 8, style.bg);
    } else if ((code === 38 || code === 48) && codes[i + 1] === 5) {
      const color = sgrColor(codes[i + 2], code === 38 ? style.fg : style.bg);
      if (code === 38) style.fg = color;
      else style.bg = color;
      i += 2;
    }
  }
}

function parseAnsi(pane, maxRows) {
  const rows = [[]];
  const freshStyle = () => ({ fg: '#e7f8ff', bg: null, bold: false, inverse: false });
  let style = freshStyle();
  let row = 0;
  let col = 0;

  for (let i = 0; i < pane.length; i += 1) {
    if (pane[i] === '\x1b') {
      if (pane[i + 1] === ']') {
        const bel = pane.indexOf('\x07', i + 2);
        const st = pane.indexOf('\x1b\\', i + 2);
        const end = bel >= 0 && (st < 0 || bel < st) ? bel + 1 : st >= 0 ? st + 2 : i + 2;
        i = end - 1;
        continue;
      }
      if (pane[i + 1] === '[') {
        const match = pane.slice(i).match(/^\x1b\[([0-9;?]*)([ -/]*)([@-~])/);
        if (match) {
          if (match[3] === 'm') applySgr(style, match[1].split(';'));
          i += match[0].length - 1;
          continue;
        }
      }
      i += 1;
      continue;
    }

    const ch = pane[i];
    if (ch === '\r') continue;
    if (ch === '\n') {
      row += 1;
      col = 0;
      style = freshStyle();
      if (row >= maxRows) break;
      rows[row] = [];
      continue;
    }

    const fg = style.inverse ? (style.bg ?? '#050813') : style.fg;
    const bg = style.inverse ? style.fg : style.bg;
    rows[row].push({ ch, col, fg, bg, bold: style.bold });
    col += 1;
  }

  return rows.filter((line) => line.some((cell) => cell.ch.trim() !== '' || cell.bg));
}

const svgWidth = 1120;
const svgHeight = 680;

function frameBody({ pane, cols = 132, rows = 40 }) {
  const width = 1120;
  const height = 680;
  const marginX = 38;
  const startY = 86;
  const cellW = Math.max(6.5, Math.min(9.5, (width - 76) / cols));
  const lineHeight = Math.max(14, Math.min(19, (height - 116) / rows));
  const fontSize = Math.max(10, Math.min(14, cellW * 1.45));
  const lines = parseAnsi(pane, rows);
  const bg = [];
  const fg = [];

  for (let y = 0; y < lines.length; y += 1) {
    for (const cell of lines[y]) {
      const x = marginX + cell.col * cellW;
      const textY = startY + y * lineHeight;
      if (cell.bg) {
        bg.push(`<rect x="${x.toFixed(1)}" y="${(textY - fontSize).toFixed(1)}" width="${cellW.toFixed(1)}" height="${lineHeight.toFixed(1)}" fill="${cell.bg}" />`);
      }
      if (cell.ch !== ' ') {
        fg.push(`<text x="${x.toFixed(1)}" y="${textY.toFixed(1)}" fill="${cell.fg}"${cell.bold ? ' font-weight="700"' : ''}>${escapeXml(cell.ch)}</text>`);
      }
    }
  }

  return `${bg.join('\n')}
${fg.join('\n')}`;
}

function svgShell({ title, body }) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${svgWidth}" height="${svgHeight}" viewBox="0 0 ${svgWidth} ${svgHeight}" role="img" aria-label="${escapeXml(title)}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#1b0b2b" />
      <stop offset="0.48" stop-color="#081724" />
      <stop offset="1" stop-color="#100812" />
    </linearGradient>
  </defs>
  <rect width="${svgWidth}" height="${svgHeight}" rx="30" fill="url(#bg)" />
  <rect x="18" y="18" width="1084" height="644" rx="24" fill="#050813" opacity="0.96" stroke="#5f7191" stroke-opacity="0.38" />
  <circle cx="48" cy="48" r="7" fill="#ff7ac8" />
  <circle cx="72" cy="48" r="7" fill="#ffd36e" />
  <circle cx="96" cy="48" r="7" fill="#82ffbd" />
  <text x="126" y="54" font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" font-size="15" fill="#ffd36e">${escapeXml(title)}</text>
  <g font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" font-size="12" xml:space="preserve">
${body}
  </g>
</svg>
`;
}

function svg({ title, pane, cols = 132, rows = 40 }) {
  return svgShell({ title, body: frameBody({ pane, cols, rows }) });
}

function animatedSvg({ title, captures }) {
  const count = captures.length;
  const duration = Math.max(1, count * 0.9);
  const keyTimes = Array.from({ length: count + 1 }, (_, i) => (i / count).toFixed(4)).join(';');
  const groups = captures
    .map((capture, index) => {
      const values = Array.from({ length: count + 1 }, (_, i) => ((i % count) === index ? '1' : '0')).join(';');
      return `<g opacity="${index === 0 ? '1' : '0'}">
${frameBody({ pane: capture.pane, cols: capture.cols, rows: capture.rows })}
<animate attributeName="opacity" values="${values}" keyTimes="${keyTimes}" dur="${duration}s" repeatCount="indefinite" calcMode="discrete" />
</g>`;
    })
    .join('\n');
  return svgShell({ title, body: groups });
}

async function withTmux({ name, exe, cols, rows, setup, frames }) {
  sh('tmux', ['kill-session', '-t', name], { stdio: 'ignore', allowFailure: true });
  sh('tmux', [
    'new-session',
    '-d',
    '-s',
    name,
    '-x',
    String(cols),
    '-y',
    String(rows),
    `cd ${repo} && TERM=xterm-256color MIAOU_DRIVER=matrix opam exec -- dune exec ${exe}`,
  ]);

  try {
    await sleep(1400);
    if (setup) await setup(name);

    const captured = [];
    for (const frame of frames) {
      if (frame.resize) {
        sh('tmux', ['resize-window', '-t', name, '-x', String(frame.resize.cols), '-y', String(frame.resize.rows)]);
      }
      if (frame.keys) {
        for (const key of frame.keys) sh('tmux', ['send-keys', '-t', name, key]);
      }
      await sleep(frame.delay ?? 500);
      const pane = sh('tmux', ['capture-pane', '-t', name, '-p', '-e', '-S', `-${rows}`]);
      captured.push({
        cols: frame.resize?.cols ?? cols,
        rows: frame.resize?.rows ?? rows,
        gifDelay: frame.gifDelay,
        pane,
      });
    }
    return captured;
  } finally {
    sh('tmux', ['kill-session', '-t', name], { stdio: 'ignore', allowFailure: true });
  }
}

async function writeSvgFrame(file, title, capture) {
  await writeFile(
    file,
    svg({ title, pane: capture.pane, cols: capture.cols, rows: capture.rows }),
  );
}

async function writeGif(name, title, captures) {
  const dir = join(frameDir, name);
  await rm(dir, { recursive: true, force: true });
  await mkdir(dir, { recursive: true });
  const files = [];
  for (let i = 0; i < captures.length; i += 1) {
    const file = join(dir, `${String(i).padStart(3, '0')}.svg`);
    await writeSvgFrame(file, title, captures[i]);
    files.push(file);
  }
  sh('magick', ['-delay', String(captures[0]?.gifDelay ?? 120), ...files, '-loop', '0', join(outDir, `${name}.gif`)]);
}

async function main() {
  await mkdir(outDir, { recursive: true });

  const responsive = await withTmux({
    name: 'miaou-responsive-cap',
    exe: 'example/demos/responsive/main.exe',
    cols: 112,
    rows: 30,
    frames: [
      { resize: { cols: 112, rows: 30 }, delay: 1300, gifDelay: 180 },
      { resize: { cols: 82, rows: 30 }, delay: 1300, gifDelay: 180 },
      { resize: { cols: 52, rows: 30 }, delay: 1300, gifDelay: 180 },
      { resize: { cols: 112, rows: 30 }, delay: 1300, gifDelay: 180 },
    ],
  });
  await writeGif('responsive', 'Responsive layout demo', responsive);

  const table = await withTmux({
    name: 'miaou-table-cap',
    exe: 'example/demos/table/main.exe',
    cols: 112,
    rows: 32,
    frames: [{ delay: 1400 }],
  });
  await writeSvgFrame(join(outDir, 'table.svg'), 'Table demo', table[0]);

  const styleSystem = await withTmux({
    name: 'miaou-style-system-cap',
    exe: 'example/demos/style_system/main.exe',
    cols: 112,
    rows: 32,
    frames: [
      { delay: 1200, gifDelay: 180 },
      { keys: ['2'], delay: 1200, gifDelay: 180 },
      { keys: ['3'], delay: 1200, gifDelay: 180 },
      { keys: ['1'], delay: 1200, gifDelay: 180 },
    ],
  });
  await writeGif('style-system', 'Style system theme switching', styleSystem);

  await rm(frameDir, { recursive: true, force: true });
  console.log('Generated tmux feature captures in website/src/media/captures');
}

main();
