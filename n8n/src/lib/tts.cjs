// NEWSFLOW — przygotowanie tekstu do syntezy mowy i obliczenia audio.

// Normalizacja tekstu pod odsłuch po polsku (skróty, symbole, URL-e).
function prepareForSpeech(text) {
  let s = String(text || '');
  s = s.replace(/https?:\/\/[^\s,;)]+/g, '').replace(/\s+([,.;:])/g, '$1'); // linki nie są czytane
  s = s.replace(/[*_#`>|]/g, '');                     // markdown
  s = s.replace(/\s*[–—]\s*/g, ' – ');
  s = s.replace(/(\d)\s?%/g, '$1 procent');
  s = s.replace(/\$\s?(\d[\d.,]*)\s?(mld|mln|tys\.)?/g, (m, n, u) => `${n}${u ? ' ' + u : ''} dolarów`);
  s = s.replace(/€\s?(\d[\d.,]*)/g, '$1 euro');
  s = s.replace(/\bnp\./g, 'na przykład').replace(/\bm\.in\./g, 'między innymi').replace(/\btzw\./g, 'tak zwany');
  s = s.replace(/\bitd\./g, 'i tak dalej').replace(/\bok\.\s(?=\d)/g, 'około ');
  s = s.replace(/\bAI\b/g, 'AI').replace(/\bvs\.?\b/g, 'kontra');
  s = s.replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim();
  return s;
}

// Dzieli tekst na fragmenty <= maxChars, wyłącznie na granicach zdań/akapitów.
function chunkText(text, maxChars) {
  maxChars = maxChars || 2500;
  const paragraphs = String(text || '').split(/\n{2,}/).map((p) => p.trim()).filter(Boolean);
  const chunks = [];
  let cur = '';
  const push = () => { if (cur.trim()) chunks.push(cur.trim()); cur = ''; };
  for (const p of paragraphs) {
    if ((cur + '\n\n' + p).length <= maxChars) { cur = cur ? cur + '\n\n' + p : p; continue; }
    push();
    if (p.length <= maxChars) { cur = p; continue; }
    const sentences = p.match(/[^.!?…]+[.!?…]+["”»)]*\s*|[^.!?…]+$/g) || [p];
    for (const s of sentences) {
      if ((cur + s).length > maxChars) push();
      if (s.length > maxChars) { for (let i = 0; i < s.length; i += maxChars) chunks.push(s.slice(i, i + maxChars).trim()); continue; }
      cur += s;
    }
  }
  push();
  return chunks;
}

// Bitrate z formatu ElevenLabs, np. "mp3_44100_96" -> 96
function bitrateFromFormat(fmt) {
  const m = String(fmt || '').match(/^mp3_\d+_(\d+)$/);
  return m ? parseInt(m[1], 10) : 128;
}

// Czas trwania MP3 CBR na podstawie rozmiaru
function mp3DurationSeconds(bytes, kbps) {
  return Math.round((bytes * 8) / (kbps * 1000) * 100) / 100;
}

// Usuwa nagłówek ID3v2 (przy sklejaniu fragmentów zostawiamy tylko pierwszy)
function stripId3(buf) {
  if (buf.length > 10 && buf[0] === 0x49 && buf[1] === 0x44 && buf[2] === 0x33) {
    const size = ((buf[6] & 0x7f) << 21) | ((buf[7] & 0x7f) << 14) | ((buf[8] & 0x7f) << 7) | (buf[9] & 0x7f);
    return buf.subarray(10 + size);
  }
  return buf;
}

// Rozdziały z czasami startu
function buildChapters(parts) {
  let t = 0;
  return parts.map((p, i) => {
    const ch = { index: i, title: p.title, start_seconds: Math.round(t * 100) / 100, duration_seconds: p.duration_seconds, audio_asset_id: p.audio_asset_id || null, story_ids: p.story_ids || [] };
    t += p.duration_seconds;
    return ch;
  });
}

/* @exports — wszystko poniżej jest usuwane przez build.mjs */
module.exports = { prepareForSpeech, chunkText, bitrateFromFormat, mp3DurationSeconds, stripId3, buildChapters };
