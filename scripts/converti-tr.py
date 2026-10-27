#!/usr/bin/env python3
"""Una tantum: sostituisce le chiamate tr("italiano", "english") del modulo App con String(localized:, bundle:) e
salva le coppie in scripts/traduzioni/tr-en.json (chiave italiana con {} al posto delle interpolazioni -> inglese)."""
import re, glob, json, pathlib

root = pathlib.Path(__file__).resolve().parent.parent

def scan_literal(s, i):
    """s[i] == '"': ritorna (testo_grezzo_senza_virgolette, indice_dopo)."""
    assert s[i] == '"'
    j = i + 1
    out = []
    while j < len(s):
        c = s[j]
        if c == '\\':
            if s[j + 1] == '(':
                depth, k = 1, j + 2
                while depth:
                    if s[k] == '"':
                        _, k = scan_literal(s, k); continue
                    if s[k] == '(': depth += 1
                    elif s[k] == ')': depth -= 1
                    k += 1
                out.append(s[j:k]); j = k; continue
            out.append(s[j:j + 2]); j += 2; continue
        if c == '"':
            return ''.join(out), j + 1
        out.append(c); j += 1
    raise ValueError("literal non chiuso")

def skip_ws(s, i):
    while True:
        while i < len(s) and s[i] in ' \t\r\n': i += 1
        if s.startswith('//', i):
            while i < len(s) and s[i] != '\n': i += 1
            continue
        if s.startswith('/*', i):
            i = s.index('*/', i) + 2; continue
        return i

def scan_expr(s, i):
    """Una o più stringhe unite da +. Ritorna (pezzi, indice dopo)."""
    pieces = []
    i = skip_ws(s, i)
    while True:
        if s[i] != '"': raise ValueError("atteso literal a %d: %r" % (i, s[i:i+40]))
        txt, i = scan_literal(s, i)
        pieces.append(txt)
        k = skip_ws(s, i)
        if s[k] == '+':
            i = skip_ws(s, k + 1); continue
        return pieces, k

pairs = {}
changed = 0
for f in glob.glob(str(root / "Modules/Apps/Sources/**/*.swift"), recursive=True):
    s = open(f).read()
    out, pos, n = [], 0, 0
    for m in re.finditer(r'(?<![A-Za-z0-9_.])tr\(', s):
        if m.start() < pos: continue
        try:
            a, i = scan_expr(s, m.end())
            assert s[i] == ','
            b, i = scan_expr(s, i + 1)
            assert s[i] == ')'
        except Exception as e:
            continue   # per esempio la definizione func tr(_ italiano: String…)
        it = ''.join(a); en = ''.join(b)
        norm = lambda t: re.sub(r'\\\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)', '{}', t)
        pairs[norm(it)] = norm(en)
        out.append(s[pos:m.start()])
        out.append('String(localized: "%s", bundle: QLMBundle.framework)' % it)
        pos = i + 1; n += 1
    out.append(s[pos:])
    if n:
        open(f, 'w').write(''.join(out)); changed += n
        print(f"{pathlib.Path(f).name}: {n}")
(root / "scripts/traduzioni/tr-en.json").write_text(json.dumps(dict(sorted(pairs.items())), ensure_ascii=False, indent=1) + "\n")
print("convertite:", changed, "coppie uniche:", len(pairs))
