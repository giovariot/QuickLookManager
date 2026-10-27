// Colla tra Swift e il renderer: caricamento degli script pesanti solo quando servono.
function qtlLoad(name) {
  return new Promise((resolve, reject) => {
    const s = document.createElement('script');
    s.src = name; s.onload = resolve; s.onerror = () => reject(new Error('script ' + name));
    document.head.appendChild(s);
  });
}

async function qtlMount(kind, source, opts) {
  const root = document.getElementById('write');
  document.getElementById('theme').textContent = opts.themeCSS || '';
  document.getElementById('user').textContent = opts.userCSS || '';
  document.documentElement.style.setProperty('--qtl-font-size', opts.fontSize + 'px');
  document.documentElement.style.setProperty('--qtl-max-width', opts.maxWidth > 0 ? opts.maxWidth + 'px' : 'none');
  if (kind === 'asciidoc') await qtlLoad('asciidoctor.js');
  root.innerHTML = kind === 'html' ? source : await QTL.render(kind, source, opts);
  // I link non devono mai navigare dentro l'anteprima; i collegamenti interni (#) restano.
  document.querySelectorAll('a[href]').forEach(a => { if (!a.getAttribute('href').startsWith('#')) a.setAttribute('target', '_blank'); });
  // Il linguaggio dei blocchi con evidenziazione già fatta non va ripetuto.
  const mm = document.querySelectorAll('pre.mermaid');
  if (opts.diagrams && mm.length) {
    await qtlLoad('mermaid.js');
    // I diagrammi prendono i colori dal tema attivo (variabili CSS), così coincidono con chiaro/scuro e con i temi.
    const cv = document.createElement('canvas'); cv.width = cv.height = 1;
    const cx = cv.getContext('2d', { willReadFrequently: true });
    const probe = document.createElement('span'); document.body.appendChild(probe);
    const rgb = v => { probe.style.color = 'var(' + v + ')'; cx.clearRect(0, 0, 1, 1); cx.fillStyle = '#000'; cx.fillStyle = getComputedStyle(probe).color; cx.fillRect(0, 0, 1, 1);
      const d = cx.getImageData(0, 0, 1, 1).data; return '#' + [d[0], d[1], d[2]].map(n => n.toString(16).padStart(2, '0')).join(''); };
    const vars = { background: rgb('--bg'), primaryColor: rgb('--code-bg'), primaryTextColor: rgb('--fg'), primaryBorderColor: rgb('--muted'), lineColor: rgb('--muted'),
      secondaryColor: rgb('--code-bg'), tertiaryColor: rgb('--bg'), textColor: rgb('--fg'), noteBkgColor: rgb('--code-bg'), noteTextColor: rgb('--fg'), edgeLabelBackground: rgb('--bg'), fontFamily: getComputedStyle(document.body).fontFamily };
    probe.remove();
    mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: 'base', themeVariables: vars });
    try { await mermaid.run({ nodes: mm }); } catch (e) { /* un diagramma errato resta visibile come testo */ }
  }
  return document.body.scrollHeight;
}
