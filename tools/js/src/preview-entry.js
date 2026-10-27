// Renderer per la pagina dell'anteprima: Markdown (vari dialetti) e altri linguaggi di markup -> HTML.
import MarkdownIt from 'markdown-it';
import footnote from 'markdown-it-footnote';
import taskLists from 'markdown-it-task-lists';
import sub from 'markdown-it-sub';
import sup from 'markdown-it-sup';
import mark from 'markdown-it-mark';
import deflist from 'markdown-it-deflist';
import abbr from 'markdown-it-abbr';
import { full as emoji } from 'markdown-it-emoji';
import container from 'markdown-it-container';
import anchor from 'markdown-it-anchor';
import { tex } from '@mdit/plugin-tex';
import katex from 'katex';
import hljs from 'highlight.js';
import textile from 'textile-js';
import { creole, bbcode, rst, man } from './extra.js';

const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function highlight(code, lang) {
  if (lang === 'mermaid') return '<pre class="mermaid">' + esc(code) + '</pre>';
  try {
    if (lang && hljs.getLanguage(lang)) return '<pre><code class="hljs language-' + esc(lang) + '">' + hljs.highlight(code, { language: lang, ignoreIllegals: true }).value + '</code></pre>';
  } catch (e) {}
  return '<pre><code class="hljs">' + esc(code) + '</code></pre>';
}

function frontMatter(src) {
  // YAML front matter o metadati MultiMarkdown in testa al documento.
  let m = /^---\r?\n([\s\S]*?)\r?\n(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/.exec(src);
  if (m) return { rows: m[1].split(/\r?\n/).filter(l => /^[\w .-]+:/.test(l)).map(l => { const k = l.indexOf(':'); return [l.slice(0, k).trim(), l.slice(k + 1).trim()]; }), rest: src.slice(m[0].length), raw: m[1] };
  m = /^((?:[A-Za-z][\w .-]*:[^\n]*\n)+)\r?\n/.exec(src);
  if (m) return { rows: m[1].trim().split('\n').map(l => { const k = l.indexOf(':'); return [l.slice(0, k).trim(), l.slice(k + 1).trim()]; }), rest: src.slice(m[0].length) };
  return null;
}

function markdown(src, o) {
  const flavor = o.flavor || 'typora';
  let md;
  if (flavor === 'commonmark') md = new MarkdownIt('commonmark', { html: true, highlight });
  else md = new MarkdownIt({ html: true, linkify: true, typographer: flavor === 'typora', highlight });
  if (flavor !== 'commonmark') {
    md.use(taskLists, { enabled: false, label: true }).use(footnote).use(anchor, { permalink: false });
    if (o.math !== false) md.use(tex, { render: (c, display) => katex.renderToString(c, { displayMode: display, throwOnError: false }) });
  }
  if (flavor === 'typora' || flavor === 'multimarkdown') md.use(sub).use(sup).use(mark).use(deflist).use(abbr).use(emoji).use(container, 'note').use(container, 'warning');
  let fm = null, body = src;
  if (flavor !== 'commonmark') { fm = frontMatter(src); if (fm) body = fm.rest; }
  let html = md.render(body);
  if (fm && fm.rows.length) html = '<table class="frontmatter"><tbody>' + fm.rows.map(([k, v]) => `<tr><th>${esc(k)}</th><td>${esc(v)}</td></tr>`).join('') + '</tbody></table>' + html;
  if (flavor === 'typora') {
    const heads = [...html.matchAll(/<h([1-6])\s[^>]*?id="([^"]+)"[^>]*>(.*?)<\/h\1>/g)];
    if (/<p>\[toc\]<\/p>/i.test(html)) html = html.replace(/<p>\[toc\]<\/p>/i, '<nav class="toc">' + heads.map(h => `<div class="toc-${h[1]}"><a href="#${h[2]}">${h[3].replace(/<[^>]+>/g, '')}</a></div>`).join('') + '</nav>');
  }
  return html;
}

async function render(kind, src, opts) {
  opts = opts || {};
  switch (kind) {
    case 'markdown': return markdown(src, opts);
    case 'textile': return textile(src);
    case 'creole': return creole(src);
    case 'rst': return rst(src);
    case 'bbcode': return bbcode(src);
    case 'man': return '<div class="manpage">' + man(src) + '</div>';
    case 'asciidoc': {
      const A = globalThis.QTLAsciidoctor; if (!A) return '<p>AsciiDoc non disponibile.</p>';
      return await A.convert(src, { safe: 'secure', standalone: false, attributes: { showtitle: true, 'source-highlighter': 'none' } });
    }
    case 'html': return src;
    default: return '<pre>' + esc(src) + '</pre>';
  }
}

globalThis.QTL = {
  render,
  hasMermaid: () => !!document.querySelector('pre.mermaid'),
  hasAsciidoc: kind => kind === 'asciidoc',
};
