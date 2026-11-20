//@lib text
// Jeśli węzeł "Transcript API (optional)" jest wyłączony, przychodzą tu niezmienione elementy
// (bez pola content) — materiały YouTube zostaną oznaczone jako niekompletne.
const P = $('Load config').first().json.pipeline || {};
const minP = P.min_words_partial || 80;
const reqs = $('Transcript list').all().map((i) => i.json);
const resps = $input.all();
const results = reqs.map((rq, idx) => {
  const r = resps[idx] ? resps[idx].json : {};
  const text = typeof r.content === 'string' ? r.content
    : Array.isArray(r.content) ? r.content.map((c) => c.text).join(' ') : '';
  const words = wordCount(text);
  if (words >= minP) return { id: rq.id, status: 'extracted', transcript: truncate(text, 80000), word_count: words, language: r.lang || null, metadata: { content_basis: 'youtube_transcript' } };
  if (r.error) return { id: rq.id, status: rq.attempts >= 3 ? 'incomplete' : 'failed', error: String(r.error.message || JSON.stringify(r.error)).slice(0, 1000) };
  return { id: rq.id, status: 'incomplete', error: 'Brak transkrypcji (włącz węzeł "Transcript API (optional)" w WF02)' };
});
return [{ json: { p_results: results } }];
