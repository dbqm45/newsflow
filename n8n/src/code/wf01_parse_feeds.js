//@lib text
//@lib feed
const cfg = $('Load config').first().json;
const P = cfg.pipeline || {};
const maxAgeMs = (P.max_item_age_days || 4) * 86400000;
const sources = $('Prepare sources').all().map((i) => i.json);
const responses = $input.all();
const rows = [];
const results = [];
const seen = new Set();

sources.forEach((src, idx) => {
  const r = responses[idx] ? responses[idx].json : null;
  const body = r && (typeof r.body === 'string' ? r.body : r.data);
  if (!r || r.error || typeof body !== 'string' || !body.trim()) {
    const err = r && r.error ? (r.error.message || JSON.stringify(r.error)) : 'Pusta odpowiedź';
    results.push({ p_source_id: src.id, p_ok: false, p_error: String(err).slice(0, 1000) });
    return;
  }
  let parsed;
  try {
    parsed = parseFeed(body, { maxItems: (src.configuration && src.configuration.max_items) || 25 });
  } catch (e) {
    results.push({ p_source_id: src.id, p_ok: false, p_error: 'Błąd parsowania: ' + e.message });
    return;
  }
  if (!parsed.items.length) {
    results.push({ p_source_id: src.id, p_ok: false, p_error: 'Brak pozycji w feedzie (zmieniony adres?)' });
    return;
  }
  for (const it of parsed.items) {
    if (it.published_at && Date.now() - Date.parse(it.published_at) > maxAgeMs) continue;
    const canon = canonicalUrl(it.url);
    const hash = sha256(canon);
    if (seen.has(hash)) continue;
    seen.add(hash);
    rows.push({
      source_id: src.id,
      external_id: it.external_id,
      title: it.title,
      original_url: it.url,
      author: it.author,
      published_at: it.published_at,
      description: it.description,
      original_content: it.content,
      content_hash: hash,
      language: src.language,
      visibility: src.visibility || 'public',
      word_count: wordCount(it.content || it.description),
      metadata: {
        canonical_url: canon,
        media_url: it.media_url,
        transcript_url: it.transcript_url,
        duration_seconds: it.duration_seconds,
        feed_format: parsed.format,
      },
    });
  }
  results.push({ p_source_id: src.id, p_ok: true, p_error: null });
});

return [{ json: { rows, results, stats: { sources: sources.length, items_seen: rows.length, failed_sources: results.filter((r) => !r.p_ok).length } } }];
