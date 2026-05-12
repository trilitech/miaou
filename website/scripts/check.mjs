import { access, readFile, readdir } from 'node:fs/promises';
import { dirname, join, normalize } from 'node:path';
import { extractSnippet, loadManifest } from './snippets.mjs';

const root = process.cwd();
const required = ['src/index.html', 'src/styles.css', 'snippets.json'];

for (const file of required) {
  await access(join(root, file));
}

const manifest = await loadManifest(root);

async function htmlFiles(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...await htmlFiles(path));
    } else if (entry.isFile() && entry.name.endsWith('.html')) {
      files.push(path);
    }
  }

  return files;
}

const referenced = [];

for (const htmlFile of await htmlFiles(join(root, 'src'))) {
  const html = await readFile(htmlFile, 'utf8');
  referenced.push(...[...html.matchAll(/<div data-snippet="([^"]+)"><\/div>/g)].map((match) => match[1]));

  for (const match of html.matchAll(/<img\s+[^>]*src="([^"]+)"/g)) {
    const src = match[1];
    if (src.startsWith('http://') || src.startsWith('https://')) {
      continue;
    }

    await access(normalize(join(dirname(htmlFile), src)));
  }

  for (const match of html.matchAll(/AsciinemaPlayer\.create\('([^']+)'/g)) {
    const src = match[1];
    await access(normalize(join(dirname(htmlFile), src)));
  }
}

for (const id of referenced) {
  const entry = manifest[id];
  if (!entry) {
    throw new Error(`Snippet ${id} is referenced by src/index.html but not listed in snippets.json`);
  }

  await extractSnippet(root, id, entry);
}

for (const id of Object.keys(manifest)) {
  await extractSnippet(root, id, manifest[id]);
}

console.log('Website source check passed.');
