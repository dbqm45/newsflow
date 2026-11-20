//@lib text
const P = $('Load config').first().json.pipeline || {};
const minC = P.min_words_complete || 250;
const minP = P.min_words_partial || 80;
const reqs = $('Fetch list').all().map((i) => i.json);
const resps = $input.all();
const results = reqs.map((rq, idx) => {
  const r = resps[idx] ? resps[idx].json : null;
  const body = r && (typeof r.body === 'string' ? r.body : r.data);
  const feedWords = wordCount(rq.feed_content);
  if (!r || r.error || typeof body !== 'string') {
    const err = r && r.error ? (r.error.message || JSON.stringify(r.error)) : 'Pusta odpowiedź';
    if (feedWords >= minP) return { id: rq.id, status: 'extracted', word_count: feedWords, metadata: { content_basis: 'feed', partial: true, fetch_error: String(err).slice(0, 300) } };
    return { id: rq.id, status: rq.attempts >= 3 ? 'incomplete' : 'failed', error: String(err).slice(0, 1000) };
  }
  let text, extra = {};
  if (rq.mode === 'subtitles') {
    text = /<html|<p\b/i.test(body) ? htmlToText(body) : subtitlesToText(body);
    extra = { content_basis: 'podcast_transcript' };
    const words = wordCount(text);
    if (words < minP) return { id: rq.id, status: 'incomplete', error: 'Transkrypcja pusta' };
    return { id: rq.id, status: 'extracted', transcript: truncate(text, 80000), word_count: words, metadata: extra };
  }
  const art = extractArticle(body);
  text = art.text;
  extra = { content_basis: 'page', page_title: art.title, page_published_at: art.published_at };
  if (wordCount(rq.feed_content) > art.word_count) { text = rq.feed_content; extra.content_basis = 'feed'; }
  const words = wordCount(text);
  if (words >= minC) return { id: rq.id, status: 'extracted', original_content: truncate(text, 60000), word_count: words, language: art.language, metadata: extra };
  if (words >= minP) return { id: rq.id, status: 'extracted', original_content: truncate(text, 60000), word_count: words, language: art.language, metadata: { ...extra, partial: true } };
  return { id: rq.id, status: 'incomplete', word_count: words, error: 'Nie udało się wyodrębnić treści (paywall/JS?)' };
});
return [{ json: { p_results: results } }];
