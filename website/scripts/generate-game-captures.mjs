import { execFileSync } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const repo = dirname(root);
const outDir = join(root, 'src/media/captures');
const cols = '120';
const rows = '36';

function run(command, args) {
  execFileSync(command, args, {
    cwd: repo,
    stdio: 'inherit',
    env: {
      ...process.env,
      TERM: 'xterm-256color',
      MIAOU_CAPTURE_COLS: cols,
      MIAOU_CAPTURE_ROWS: rows,
    },
  });
}

const games = [
  {
    name: 'miaou-force',
    exe: '_build/default/example/demos/miaou_force/main.exe',
    keys: ['0.7:Enter', '0.7:Right', '0.5:Space', '0.5:Down', '0.5:Space'],
  },
  {
    name: 'miaou-crypt',
    exe: '_build/default/example/demos/miaou_crypt/main.exe',
    keys: [
      '0.7:Enter',
      '0.8:Up',
      '0.8:Up',
      '0.8:Right',
      '0.8:Up',
      '0.8:Left',
      '0.8:Up',
      '0.8:Space',
      '0.8:Right',
      '0.8:Up',
    ],
  },
  {
    name: 'miaou-links',
    exe: '_build/default/example/demos/miaou_links/main.exe',
    keys: ['0.7:Enter', '0.7:s', '0.7:Space', '0.7:Space', '0.7:Right'],
  },
  {
    name: 'geo-quiz',
    exe: '_build/default/example/demos/geo_quiz/main.exe',
    keys: ['0.7:Enter', '0.7:Right', '0.7:Down', '0.7:Right', '0.7:Enter'],
  },
];

await mkdir(outDir, { recursive: true });

for (const game of games) {
  const cast = join(outDir, `${game.name}.cast`);
  run('asciinema', [
    'rec',
    '--overwrite',
    '--cols',
    cols,
    '--rows',
    rows,
    '--command',
    `python3 website/scripts/drive-demo.py ${game.exe} ${game.keys.join(' ')}`,
    cast,
  ]);
}

console.log('Generated asciinema game captures');
