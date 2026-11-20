// NEWSFLOW — narzędzia tekstowe (bez zależności; działa w węźle Code n8n i w Node.js)

const ENTITIES = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', ndash: '–', mdash: '—',
  hellip: '…', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“', laquo: '«', raquo: '»',
  copy: '©', reg: '®', trade: '™', bull: '•', middot: '·', euro: '€', shy: '',
};

function decodeEntities(s) {
  if (!s) return '';
  return String(s).replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e) => {
    if (e[0] === '#') {
      const code = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      return Number.isFinite(code) && code > 0 && code < 0x110000 ? String.fromCodePoint(code) : m;
    }
    const v = ENTITIES[e.toLowerCase()];
    return v === undefined ? m : v;
  });
}

function stripCdata(s) {
  return String(s || '').replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1');
}

const BLOCK_TAGS = /<\/?(p|div|br|li|ul|ol|h[1-6]|tr|table|section|article|blockquote|pre|header|footer|figure|figcaption|hr)\b[^>]*>/gi;

function htmlToText(html) {
  if (!html) return '';
  let s = stripCdata(String(html));
  s = s.replace(/<!--[\s\S]*?-->/g, ' ');
  s = s.replace(/<(script|style|noscript|svg|iframe|template|form|button|select)\b[\s\S]*?<\/\1>/gi, ' ');
  s = s.replace(BLOCK_TAGS, '\n');
  s = s.replace(/<[^>]+>/g, ' ');
  s = decodeEntities(s);
  s = s.replace(/[ \t\f\v ]+/g, ' ');
  s = s.replace(/ *\n */g, '\n').replace(/\n{3,}/g, '\n\n');
  return s.trim();
}

function wordCount(s) {
  if (!s) return 0;
  const m = String(s).match(/[\p{L}\p{N}][\p{L}\p{N}'’-]*/gu);
  return m ? m.length : 0;
}

function truncate(s, maxChars) {
  s = String(s || '');
  if (s.length <= maxChars) return s;
  const cut = s.slice(0, maxChars);
  const lastBreak = Math.max(cut.lastIndexOf('\n'), cut.lastIndexOf('. '));
  return (lastBreak > maxChars * 0.8 ? cut.slice(0, lastBreak + 1) : cut) + '\n[…treść skrócona…]';
}

// Ekstrakcja głównej treści artykułu (uproszczony "readability").
function extractArticle(html) {
  html = String(html || '');
  const meta = (name) => {
    const re = new RegExp(`<meta[^>]+(?:property|name)=["']${name}["'][^>]*>`, 'i');
    const tag = html.match(re);
    if (!tag) return null;
    const c = tag[0].match(/content=["']([^"']*)["']/i);
    return c ? decodeEntities(c[1]).trim() : null;
  };
  const titleTag = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  const title = meta('og:title') || (titleTag ? htmlToText(titleTag[1]) : null);
  const description = meta('og:description') || meta('description');
  const published = meta('article:published_time') || meta('og:published_time');
  const langMatch = html.match(/<html[^>]*\blang=["']([a-zA-Z-]+)["']/i);

  let body = html.replace(/<(script|style|noscript|svg|nav|aside|footer|header|form|iframe)\b[\s\S]*?<\/\1>/gi, ' ');
  let candidate = null;
  const article = body.match(/<article\b[\s\S]*?<\/article>/gi);
  if (article && article.length) {
    candidate = article.sort((a, b) => b.length - a.length)[0];
  } else {
    const main = body.match(/<main\b[\s\S]*?<\/main>/i);
    if (main) candidate = main[0];
  }
  let text = candidate ? htmlToText(candidate) : '';

  // Fallback: zbierz akapity <p> z całej strony
  if (wordCount(text) < 150) {
    const paras = (body.match(/<p\b[^>]*>[\s\S]*?<\/p>/gi) || [])
      .map(htmlToText)
      .filter((p) => wordCount(p) >= 8);
    const ptext = paras.join('\n\n');
    if (wordCount(ptext) > wordCount(text)) text = ptext;
  }
  return {
    title: title || null,
    description: description || null,
    published_at: published || null,
    language: langMatch ? langMatch[1].slice(0, 2).toLowerCase() : null,
    text,
    word_count: wordCount(text),
  };
}

// Napisy WebVTT/SRT -> czysty tekst
function subtitlesToText(s) {
  return String(s || '')
    .replace(/^WEBVTT.*$/m, '')
    .replace(/^\d+\s*$/gm, '')
    .replace(/^\s*\d{1,2}:\d{2}(:\d{2})?[.,]\d{3}\s*-->.*$/gm, '')
    .replace(/<[^>]+>/g, '')
    .replace(/\n{2,}/g, '\n')
    .split('\n').map((l) => l.trim()).filter(Boolean)
    .filter((l, i, arr) => l !== arr[i - 1])
    .join(' ')
    .trim();
}

const TRACKING_PARAMS = /^(utm_[a-z]+|fbclid|gclid|mc_cid|mc_eid|ref|ref_src|source|cmpid|igshid|si|_hsenc|_hsmi|mkt_tok)$/i;

function canonicalUrl(raw) {
  try {
    const u = new URL(String(raw).trim());
    u.hash = '';
    u.hostname = u.hostname.toLowerCase().replace(/^www\./, '');
    const keep = [];
    u.searchParams.forEach((v, k) => { if (!TRACKING_PARAMS.test(k)) keep.push([k, v]); });
    keep.sort((a, b) => a[0].localeCompare(b[0]));
    u.search = keep.length ? '?' + keep.map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&') : '';
    if (u.hostname === 'youtube.com' || u.hostname === 'm.youtube.com') {
      const v = new URL(String(raw)).searchParams.get('v');
      if (v) return `https://youtube.com/watch?v=${v}`;
    }
    if (u.hostname === 'youtu.be') return `https://youtube.com/watch?v=${u.pathname.slice(1)}`;
    if (u.pathname.length > 1 && u.pathname.endsWith('/')) u.pathname = u.pathname.replace(/\/+$/, '');
    return u.toString().replace(/^http:\/\//, 'https://');
  } catch (e) {
    return String(raw || '').trim();
  }
}

// SHA-256 (czysty JS) — n8n Cloud nie zawsze udostępnia moduł crypto
function sha256(ascii) {
  const utf8 = unescape(encodeURIComponent(String(ascii)));
  const K = [];
  const H = [];
  let primeCounter = 0;
  const isComposite = {};
  for (let candidate = 2; primeCounter < 64; candidate++) {
    if (!isComposite[candidate]) {
      for (let i = candidate * candidate; i < 313; i += candidate) isComposite[i] = candidate;
      if (primeCounter < 8) H[primeCounter] = (Math.pow(candidate, 0.5) * 0x100000000) | 0;
      K[primeCounter++] = (Math.pow(candidate, 1 / 3) * 0x100000000) | 0;
    }
  }
  const words = [];
  const bitLen = utf8.length * 8;
  let s = utf8 + '\x80';
  while ((s.length % 64) - 56) s += '\x00';
  for (let i = 0; i < s.length; i++) words[i >> 2] |= s.charCodeAt(i) << (((3 - i) % 4) * 8);
  words[words.length] = (bitLen / 0x100000000) | 0;
  words[words.length] = bitLen | 0;
  const rr = (v, n) => (v >>> n) | (v << (32 - n));
  let hash = H.slice(0, 8);
  for (let j = 0; j < words.length;) {
    const w = words.slice(j, (j += 16));
    const old = hash;
    hash = hash.slice(0, 8);
    for (let i = 0; i < 64; i++) {
      const w15 = w[i - 15], w2 = w[i - 2];
      const a = hash[0], e = hash[4];
      const t1 = hash[7] + (rr(e, 6) ^ rr(e, 11) ^ rr(e, 25)) + ((e & hash[5]) ^ (~e & hash[6])) + K[i] +
        (w[i] = i < 16 ? w[i] : (w[i - 16] + (rr(w15, 7) ^ rr(w15, 18) ^ (w15 >>> 3)) + w[i - 7] +
          (rr(w2, 17) ^ rr(w2, 19) ^ (w2 >>> 10))) | 0);
      const t2 = (rr(a, 2) ^ rr(a, 13) ^ rr(a, 22)) + ((a & hash[1]) ^ (a & hash[2]) ^ (hash[1] & hash[2]));
      hash = [(t1 + t2) | 0].concat(hash);
      hash[4] = (hash[4] + t1) | 0;
    }
    for (let i = 0; i < 8; i++) hash[i] = (hash[i] + old[i]) | 0;
  }
  let out = '';
  for (let i = 0; i < 8; i++) for (let j = 3; j + 1; j--) {
    const b = (hash[i] >> (j * 8)) & 255;
    out += (b < 16 ? '0' : '') + b.toString(16);
  }
  return out;
}

/* @exports — wszystko poniżej jest usuwane przez build.mjs */
module.exports = { decodeEntities, stripCdata, htmlToText, wordCount, truncate, extractArticle, subtitlesToText, canonicalUrl, sha256 };
