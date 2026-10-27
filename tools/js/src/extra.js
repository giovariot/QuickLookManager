// Convertitori minimi per i linguaggi di markup senza una libreria adatta: Creole, reStructuredText, BBCode.
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

export function creole(src) {
  const inline = t => {
    t = esc(t);
    t = t.replace(/\{\{\{(.+?)\}\}\}/g, '<code>$1</code>');
    t = t.replace(/\[\[([^\]|]+)\|([^\]]+)\]\]/g, '<a href="$1">$2</a>');
    t = t.replace(/\[\[([^\]]+)\]\]/g, '<a href="$1">$1</a>');
    t = t.replace(/\{\{([^}|]+)\|([^}]*)\}\}/g, '<img src="$1" alt="$2">');
    t = t.replace(/\{\{([^}]+)\}\}/g, '<img src="$1">');
    t = t.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
    t = t.replace(/(^|[^:])\/\/(.+?)\/\//g, '$1<em>$2</em>');
    t = t.replace(/\\\\/g, '<br>');
    return t;
  };
  const out = []; const lines = src.replace(/\r\n?/g, '\n').split('\n');
  let i = 0, para = [], list = [];
  const flushP = () => { if (para.length) { out.push('<p>' + inline(para.join(' ')) + '</p>'); para = []; } };
  const flushL = () => {
    if (!list.length) return;
    let html = '', stack = [];
    for (const [ord, depth, text] of list) {
      while (stack.length < depth) { html += ord ? '<ol>' : '<ul>'; stack.push(ord); }
      while (stack.length > depth) html += stack.pop() ? '</ol>' : '</ul>';
      html += '<li>' + inline(text) + '</li>';
    }
    while (stack.length) html += stack.pop() ? '</ol>' : '</ul>';
    out.push(html); list = [];
  };
  while (i < lines.length) {
    const l = lines[i];
    if (/^\{\{\{\s*$/.test(l)) { flushP(); flushL(); const b = []; i++; while (i < lines.length && !/^\}\}\}\s*$/.test(lines[i])) b.push(lines[i++]); out.push('<pre><code>' + esc(b.join('\n')) + '</code></pre>'); i++; continue; }
    let m;
    if ((m = /^\s*(={1,6})\s*(.*?)\s*=*\s*$/.exec(l))) { flushP(); flushL(); out.push(`<h${m[1].length}>${inline(m[2])}</h${m[1].length}>`); }
    else if (/^\s*-{4,}\s*$/.test(l)) { flushP(); flushL(); out.push('<hr>'); }
    else if ((m = /^\s*([*#]+)\s*(.*)$/.exec(l)) && !/^\s*\*\*/.test(l)) { flushP(); list.push([m[1][0] === '#', m[1].length, m[2]]); }
    else if (/^\s*\|/.test(l)) {
      flushP(); flushL(); const rows = [];
      while (i < lines.length && /^\s*\|/.test(lines[i])) {
        const cells = lines[i].trim().replace(/^\||\|$/g, '').split('|');
        rows.push('<tr>' + cells.map(c => c.startsWith('=') ? `<th>${inline(c.slice(1).trim())}</th>` : `<td>${inline(c.trim())}</td>`).join('') + '</tr>'); i++;
      }
      out.push('<table>' + rows.join('') + '</table>'); continue;
    }
    else if (/^\s*$/.test(l)) { flushP(); flushL(); }
    else { flushL(); para.push(l.trim()); }
    i++;
  }
  flushP(); flushL(); return out.join('\n');
}

export function bbcode(src) {
  let t = esc(src.replace(/\r\n?/g, '\n'));
  const pairs = [['b', 'strong'], ['i', 'em'], ['u', 'u'], ['s', 's'], ['sub', 'sub'], ['sup', 'sup'], ['h1', 'h1'], ['h2', 'h2'], ['h3', 'h3'], ['quote', 'blockquote'], ['code', 'pre'], ['list', 'ul'], ['table', 'table'], ['tr', 'tr'], ['td', 'td'], ['th', 'th'], ['center', 'div style="text-align:center"']];
  t = t.replace(/\[code(?:=[^\]]*)?\]([\s\S]*?)\[\/code\]/gi, (_, c) => '<pre><code>' + c + '</code></pre>');
  for (const [b, h] of pairs) {
    if (b === 'code') continue;
    const close = h.split(' ')[0];
    t = t.replace(new RegExp('\\[' + b + '\\]', 'gi'), '<' + h + '>').replace(new RegExp('\\[/' + b + '\\]', 'gi'), '</' + close + '>');
  }
  t = t.replace(/\[quote=([^\]]+)\]/gi, '<blockquote><strong>$1:</strong> ');
  t = t.replace(/\[\*\]\s*/g, '<li>').replace(/\[list=1\]/gi, '<ol>').replace(/\[\/list\]/gi, '</ul>');
  t = t.replace(/\[url=([^\]]+)\]([\s\S]*?)\[\/url\]/gi, '<a href="$1">$2</a>').replace(/\[url\]([\s\S]*?)\[\/url\]/gi, '<a href="$1">$1</a>');
  t = t.replace(/\[img(?:=[^\]]*)?\]([\s\S]*?)\[\/img\]/gi, '<img src="$1">');
  t = t.replace(/\[color=([^\]]+)\]([\s\S]*?)\[\/color\]/gi, '<span style="color:$1">$2</span>').replace(/\[size=([^\]]+)\]([\s\S]*?)\[\/size\]/gi, '<span>$2</span>');
  return t.split(/\n{2,}/).map(p => /^\s*<(h\d|ul|ol|pre|blockquote|table|div)/.test(p) ? p : '<p>' + p.replace(/\n/g, '<br>') + '</p>').join('\n');
}

export function rst(src) {
  const inline = t => {
    t = esc(t);
    t = t.replace(/``(.+?)``/g, '<code>$1</code>').replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>').replace(/(^|[^*])\*([^*\s][^*]*?)\*/g, '$1<em>$2</em>');
    t = t.replace(/`([^`<]+?)\s*&lt;([^`]+?)&gt;`_+/g, '<a href="$2">$1</a>').replace(/:(?:ref|doc|class|func|meth|mod):`([^`]+)`/g, '<code>$1</code>');
    return t;
  };
  const lines = src.replace(/\r\n?/g, '\n').replace(/\t/g, '    ').split('\n');
  const out = [], levels = []; let i = 0, para = [];
  const flush = () => { if (para.length) { out.push('<p>' + inline(para.join(' ')) + '</p>'); para = []; } };
  const underline = l => /^([=\-`:'"~^_*+#<>.])\1{2,}\s*$/.test(l);
  const indented = l => /^\s+\S/.test(l);
  while (i < lines.length) {
    const l = lines[i], next = lines[i + 1] || '';
    if (l.trim() && underline(next) && next.trim().length >= l.trim().length && !underline(l)) {
      flush(); const c = next[0]; let lv = levels.indexOf(c); if (lv < 0) { levels.push(c); lv = levels.length - 1; }
      out.push(`<h${Math.min(lv + 1, 6)}>${inline(l.trim())}</h${Math.min(lv + 1, 6)}>`); i += 2; continue;
    }
    if (underline(l) && lines[i + 2] && underline(lines[i + 2]) && lines[i + 1].trim()) { flush(); const c = l[0]; const key = 'o' + c; let lv = levels.indexOf(key); if (lv < 0) { levels.push(key); lv = levels.length - 1; } out.push(`<h${Math.min(lv + 1, 6)}>${inline(lines[i + 1].trim())}</h${Math.min(lv + 1, 6)}>`); i += 3; continue; }
    let m;
    if ((m = /^\.\. ([\w-]+)::\s*(.*)$/.exec(l))) {
      flush(); const name = m[1], arg = m[2]; const body = []; i++;
      while (i < lines.length && (!lines[i].trim() || indented(lines[i]))) body.push(lines[i++].replace(/^ {3}/, ''));
      const content = body.filter((b, k) => !(b.trim().startsWith(':') && k < 4)).join('\n').trim();
      if (/^(code-block|code|sourcecode)$/.test(name)) out.push('<pre><code class="language-' + esc(arg) + '">' + esc(content) + '</code></pre>');
      else if (/^(note|warning|tip|important|caution|danger|attention|hint|error|seealso)$/.test(name)) out.push(`<blockquote class="admonition ${name}"><strong>${name[0].toUpperCase() + name.slice(1)}</strong><p>${inline(arg + ' ' + content)}</p></blockquote>`);
      else if (name === 'image' || name === 'figure') out.push(`<p><img src="${esc(arg)}"></p>`);
      else out.push(`<p>${inline(content || arg)}</p>`);
      continue;
    }
    if (/^\.\. /.test(l) || /^\.\.\s*$/.test(l)) { i++; while (i < lines.length && indented(lines[i])) i++; continue; }
    if ((m = /^(\s*)([-*+]|\d+[.)]|#\.)\s+(.*)$/.exec(l))) {
      flush(); const ord = !/[-*+]/.test(m[2]); const items = [];
      while (i < lines.length && (m = /^\s*([-*+]|\d+[.)]|#\.)\s+(.*)$/.exec(lines[i]))) { let t = m[2]; i++; while (i < lines.length && indented(lines[i]) && !/^\s*([-*+]|\d+[.)])\s/.test(lines[i])) t += ' ' + lines[i++].trim(); items.push('<li>' + inline(t) + '</li>'); }
      out.push((ord ? '<ol>' : '<ul>') + items.join('') + (ord ? '</ol>' : '</ul>')); continue;
    }
    if (/^:[^:]+:\s/.test(l)) { flush(); const rows = []; while (i < lines.length && (m = /^:([^:]+):\s*(.*)$/.exec(lines[i]))) { rows.push(`<tr><th>${inline(m[1])}</th><td>${inline(m[2])}</td></tr>`); i++; } out.push('<table>' + rows.join('') + '</table>'); continue; }
    if (/::\s*$/.test(l) && !/^\s*$/.test(l)) {
      para.push(l.replace(/\s*::\s*$/, ':')); flush(); i++; while (i < lines.length && !lines[i].trim()) i++;
      const b = []; while (i < lines.length && (!lines[i].trim() || indented(lines[i]))) b.push(lines[i++].replace(/^ {1,4}/, ''));
      out.push('<pre><code>' + esc(b.join('\n').trimEnd()) + '</code></pre>'); continue;
    }
    if (/^\s*\+[-=+]+\+\s*$/.test(l) || /^\s*=+(\s+=+)+\s*$/.test(l)) { flush(); const b = []; while (i < lines.length && lines[i].trim()) b.push(lines[i++]); out.push('<pre>' + esc(b.join('\n')) + '</pre>'); continue; }
    if (/^\s*$/.test(l)) flush(); else para.push(l.trim());
    i++;
  }
  flush(); return out.join('\n');
}

// Pagine man: macro man(7) e mdoc(7) (le più usate), convertite in HTML.
export function man(src) {
  const lines = src.replace(/\r\n?/g, '\n').split('\n');
  const isMdoc = lines.some(l => /^\.(Dd|Dt|Os)\b/.test(l));
  const out = []; let listStack = [], title = '', section = '', inPre = false, nameDone = false;
  const fonts = t => {
    t = esc(t).replace(/\\&amp;/g, '').replace(/\\e/g, '\\').replace(/\\-/g, '-').replace(/\\\(em/g, '—').replace(/\\\(en/g, '–').replace(/\\\(aq/g, "'").replace(/\\\(lq/g, '“').replace(/\\\(rq/g, '”').replace(/\\\(bu/g, '•').replace(/\\\(co/g, '©').replace(/\\ /g, ' ').replace(/\\~/g, ' ').replace(/\\\|/g, '').replace(/\\\^/g, '').replace(/\\"[^\n]*/g, '').replace(/\\\*\(\w\w/g, '').replace(/\\\*\[[^\]]*\]/g, '');
    let o = '', open = '';
    const parts = t.split(/(\\f(?:\[[A-Za-z]+\]|\([A-Za-z]{2}|[A-Za-z0-9]))/);
    for (const p of parts) {
      const m = /^\\f(?:\[([A-Za-z]+)\]|\(([A-Za-z]{2})|([A-Za-z0-9]))$/.exec(p);
      if (!m) { o += p; continue; }
      o += open; open = ''; const f = m[1] || m[2] || m[3];
      if (f === 'B' || f === 'BI') { o += '<strong>'; open = '</strong>'; } else if (f === 'I' || f === 'BI') { o += '<em>'; open = '</em>'; } else if (/^C/.test(f)) { o += '<code>'; open = '</code>'; }
    }
    return o + open;
  };
  const args = l => { const r = []; const re = /"((?:[^"]|"")*)"|(\S+)/g; let m; l = l.replace(/^\.\S+\s*/, ''); while ((m = re.exec(l))) r.push(m[1] !== undefined ? m[1].replace(/""/g, '"') : m[2]); return r; };
  const close = () => { while (listStack.length) out.push(listStack.pop()); };
  const para = html => out.push('<p>' + html + '</p>');
  let pendingTag = null;
  const text = [];
  const flushText = () => { if (text.length) { para(text.join(' ')); text.length = 0; } };
  const KNOWN = new Set(['Nm','Fl','Ar','Cm','Sy','Pa','Li','Ic','Ev','Va','Fn','Ft','Cd','Dv','Er','Tn','Em','Op','Xr','Sx','Dq','Sq','Aq','An','Mt','Lk','Pq','Qq','Bq','Brq']);
  let nm = '';
  const rend = toks => {
    const parts = []; let k = 0;
    while (k < toks.length) {
      const t = toks[k];
      if (KNOWN.has(t)) {
        let j = k + 1; while (j < toks.length && !KNOWN.has(toks[j])) j++;
        const inner = toks.slice(k + 1, j);
        // i macro che racchiudono rendono anche i macro seguenti
        const encl = ['Op', 'Pq', 'Qq', 'Bq', 'Brq', 'Dq', 'Sq', 'Aq'].includes(t);
        if (encl) { j = toks.length; parts.push(wrap(t, rend(toks.slice(k + 1)))); k = j; continue; }
        parts.push(inl(t, inner)); k = j;
      } else { parts.push(esc(t)); k++; }
    }
    return parts.join(' ').replace(/ ([.,;:)\]])/g, '$1');
  };
  const wrap = (m, h) => ({ Op: '[' + h + ']', Pq: '(' + h + ')', Qq: '"' + h + '"', Bq: '[' + h + ']', Brq: '{' + h + '}', Dq: '“' + h + '”', Sq: '‘' + h + '’', Aq: '&lt;' + h + '&gt;' })[m];
  const inl = (macro, a) => {
    const j = a.map(esc).join(' ');
    switch (macro) {
      case 'Nm': if (a[0] && !nm) nm = a[0]; return '<strong>' + (j || esc(nm || title)) + '</strong>';
      case 'Fl': return '<strong>-' + j + '</strong>'; case 'Ar': return '<em>' + (j || 'file') + '</em>'; case 'Cm': case 'Sy': return '<strong>' + j + '</strong>';
      case 'Pa': case 'Li': case 'Ic': case 'Ev': case 'Va': case 'Fn': case 'Ft': case 'Cd': case 'Dv': case 'Er': case 'Tn': return '<code>' + j + '</code>';
      case 'Em': return '<em>' + j + '</em>'; case 'Xr': return '<code>' + esc(a[0] || '') + '(' + esc(a[1] || '') + ')</code>';
      case 'Sx': return j; case 'An': return j; case 'Mt': case 'Lk': return '<a href="' + esc(a[0] || '') + '">' + esc(a[1] || a[0] || '') + '</a>';
      default: return j;
    }
  };
  const mdocInline = (macro, a) => KNOWN.has(macro) ? rend([macro, ...a]) : null;
  for (let i = 0; i < lines.length; i++) {
    let l = lines[i];
    if (/^\.\\"|^'\\"|^\\"/.test(l) || /^\.\s*$/.test(l)) continue;
    if (inPre && !/^[.']/.test(l)) { out.push(fonts(l) + '\n'); continue; }
    if (!/^[.']/.test(l)) { text.push(fonts(l.trim())); if (l.trim() === '') flushText(); continue; }
    const mm = /^[.']\s*(\S+)/.exec(l); const macro = mm ? mm[1] : ''; const a = args(l);
    if (isMdoc) {
      switch (macro) {
        case 'Dd': case 'Os': continue;
        case 'Dt': title = (a[0] || '') + '(' + (a[1] || '') + ')'; out.push('<p class="man-head"><strong>' + esc(title) + '</strong></p>'); continue;
        case 'Sh': flushText(); close(); out.push('<h2>' + esc(a.join(' ')) + '</h2>'); section = a.join(' ').toUpperCase(); continue;
        case 'Ss': flushText(); out.push('<h3>' + esc(a.join(' ')) + '</h3>'); continue;
        case 'Pp': flushText(); continue;
        case 'Nd': text.push('— ' + esc(a.join(' '))); continue;
        case 'Bl': { flushText(); const type = a.find(x => /^-(tag|bullet|item|enum|dash|hang|ohang|inset|diag|column)/.test(x)) || '-item'; listStack.push(/enum/.test(type) ? '</ol>' : /bullet|dash|item/.test(type) ? '</ul>' : '</dl>'); out.push(/enum/.test(type) ? '<ol>' : /bullet|dash|item/.test(type) ? '<ul>' : '<dl>'); continue; }
        case 'El': flushText(); if (listStack.length) out.push(listStack.pop()); continue;
        case 'It': { flushText(); const top = listStack[listStack.length - 1]; if (top === '</dl>') { const t = a.map(x => { const m = mdocInline(x, []); return esc(x); }).join(' '); let tag = lines[i].replace(/^\.It\s*/, ''); const mac = /^(\w\w)\s*(.*)$/.exec(tag); out.push('<dt>' + (mac && mdocInline(mac[1], args('.X ' + mac[2])) || esc(a.join(' '))) + '</dt><dd>'); i++; const body = []; while (i < lines.length && !/^\.(It|El)\b/.test(lines[i])) body.push(lines[i++]); i--; out.push(man(body.join('\n')) + '</dd>'); } else { out.push('<li>'); i++; const body = []; while (i < lines.length && !/^\.(It|El)\b/.test(lines[i])) body.push(lines[i++]); i--; out.push(man('.Dd x\n' + body.join('\n')) + '</li>'); } continue; }
        case 'Bd': flushText(); out.push('<pre>'); inPre = true; continue;
        case 'Ed': inPre = false; out.push('</pre>'); continue;
        default: { const h = mdocInline(macro, a); if (h !== null) { text.push(h); continue; } continue; }
      }
    }
    switch (macro) {
      case 'TH': title = (a[0] || '') + '(' + (a[1] || '') + ')'; out.push('<p class="man-head"><strong>' + esc(title) + '</strong>' + (a[3] ? ' — ' + esc(a[4] || a[3]) : '') + '</p>'); continue;
      case 'SH': flushText(); close(); out.push('<h2>' + fonts(a.join(' ')) + '</h2>'); continue;
      case 'SS': flushText(); out.push('<h3>' + fonts(a.join(' ')) + '</h3>'); continue;
      case 'PP': case 'P': case 'LP': case 'sp': case 'br': flushText(); continue;
      case 'B': case 'SB': text.push('<strong>' + esc(a.join(' ')) + '</strong>'); if (!a.length && lines[i + 1]) { text.push('<strong>' + esc(lines[++i]) + '</strong>'); } continue;
      case 'I': text.push('<em>' + esc(a.join(' ')) + '</em>'); continue;
      case 'SM': text.push(esc(a.join(' '))); continue;
      case 'BR': case 'BI': case 'RB': case 'RI': case 'IB': case 'IR': { const f = macro.split(''); text.push(a.map((x, k) => (f[k % 2] === 'B' ? '<strong>' : f[k % 2] === 'I' ? '<em>' : '') + esc(x) + (f[k % 2] === 'B' ? '</strong>' : f[k % 2] === 'I' ? '</em>' : '')).join('')); continue; }
      case 'TP': { flushText(); const tag = lines[++i] || ''; out.push('<dl><dt>' + fonts(tag.replace(/^\.\S+\s*/, '')) + '</dt><dd>'); const body = []; while (i + 1 < lines.length && !/^\.(TP|SH|SS|PP|P|LP|IP)\b/.test(lines[i + 1])) body.push(lines[++i]); out.push(man(body.join('\n')) + '</dd></dl>'); continue; }
      case 'IP': { flushText(); out.push('<dl><dt>' + fonts(a[0] || '•') + '</dt><dd>'); const body = []; while (i + 1 < lines.length && !/^\.(TP|SH|SS|PP|P|LP|IP)\b/.test(lines[i + 1])) body.push(lines[++i]); out.push(man(body.join('\n')) + '</dd></dl>'); continue; }
      case 'RS': flushText(); out.push('<blockquote>'); continue; case 'RE': flushText(); out.push('</blockquote>'); continue;
      case 'nf': case 'EX': flushText(); out.push('<pre>'); inPre = true; continue; case 'fi': case 'EE': out.push('</pre>'); inPre = false; continue;
      default: continue;
    }
  }
  flushText(); close();
  return out.join('\n');
}
