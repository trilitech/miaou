import { readFile } from 'node:fs/promises';
import { relative, resolve } from 'node:path';

export async function loadManifest(root) {
  const raw = await readFile(resolve(root, 'snippets.json'), 'utf8');
  return JSON.parse(raw);
}

export async function extractSnippet(root, id, entry) {
  const repoRoot = resolve(root, '..');
  const sourcePath = resolve(root, entry.source);
  const rel = relative(repoRoot, sourcePath);
  if (rel.startsWith('..') || rel.startsWith('/')) {
    throw new Error(
      `Snippet ${id} source ${entry.source} escapes the repository root`,
    );
  }
  const source = await readFile(sourcePath, 'utf8');
  const start = `(* docs:start:${id} *)`;
  const end = `(* docs:end:${id} *)`;
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end);

  if (startIndex < 0) {
    throw new Error(`Missing snippet start marker ${start} in ${entry.source}`);
  }

  if (endIndex < 0 || endIndex <= startIndex) {
    throw new Error(`Missing snippet end marker ${end} in ${entry.source}`);
  }

  return source.slice(startIndex + start.length, endIndex).trim();
}

export function escapeHtml(value) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

const ocamlTokenPattern = /\(\*[\s\S]*?\*\)|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])'|\b(?:and|as|assert|begin|class|constraint|do|done|downto|else|end|exception|external|false|for|fun|function|functor|if|in|include|inherit|initializer|lazy|let|match|method|module|mutable|new|nonrec|object|of|open|or|private|rec|sig|struct|then|to|true|try|type|val|virtual|when|while|with)\b|\b[A-Z][A-Za-z0-9_']*\b|`[A-Za-z_][A-Za-z0-9_']*|\b\d+(?:\.\d+)?\b/g;

function ocamlTokenClass(token) {
  if (token.startsWith('(*')) return 'hl-comment';
  if (token.startsWith('"') || token.startsWith("'")) return 'hl-string';
  if (token.startsWith('`')) return 'hl-constructor';
  if (/^\d/.test(token)) return 'hl-number';
  if (/^[A-Z]/.test(token)) return 'hl-module';
  return 'hl-keyword';
}

function highlightOcaml(code) {
  let output = '';
  let lastIndex = 0;

  for (const match of code.matchAll(ocamlTokenPattern)) {
    const token = match[0];
    const index = match.index ?? 0;
    output += escapeHtml(code.slice(lastIndex, index));
    output += `<span class="${ocamlTokenClass(token)}">${escapeHtml(token)}</span>`;
    lastIndex = index + token.length;
  }

  return output + escapeHtml(code.slice(lastIndex));
}

function highlightCode(language, code) {
  if (language === 'ocaml') {
    return highlightOcaml(code);
  }

  return escapeHtml(code);
}

export function renderSnippet(id, entry, code) {
  const language = entry.language ?? 'text';
  const caption = entry.caption ?? entry.source;

  return `<figure class="snippet-card" data-snippet="${escapeHtml(id)}">
  <figcaption>${escapeHtml(caption)}</figcaption>
  <pre><code class="language-${escapeHtml(language)}">${highlightCode(language, code)}</code></pre>
</figure>`;
}
