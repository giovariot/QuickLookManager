// js-yaml per JavaScriptCore: restituisce una struttura con l'ordine delle chiavi.
import * as yaml from 'js-yaml';
globalThis.QTLYaml = {
  // Ritorna JSON {docs:[...]} dove gli oggetti sono liste di [chiave, valore] per non perdere l'ordine.
  parse(text) {
    const docs = [];
    yaml.loadAll(text, d => docs.push(d), { json: true });
    const conv = v => {
      if (Array.isArray(v)) return { t: 'a', v: v.map(conv) };
      if (v instanceof Date) return { t: 's', v: v.toISOString() };
      if (v !== null && typeof v === 'object') return { t: 'o', v: Object.keys(v).map(k => [k, conv(v[k])]) };
      if (v === null || v === undefined) return { t: 'n' };
      if (typeof v === 'boolean') return { t: 'b', v };
      if (typeof v === 'number') return { t: 'd', v: String(v) };
      return { t: 's', v: String(v) };
    };
    return JSON.stringify(docs.map(conv));
  }
};
