//@lib text
// Decyduje, jak pozyskać treść: 'done' (treść już jest), 'fetch' (strona/napisy), 'transcript' (YouTube).
const P = $('Load config').first().json.pipeline || {};
const minC = P.min_words_complete || 250;
const minP = P.min_words_partial || 80;
const items = $input.all().map((i) => i.json).filter((x) => x && x.id);
const out = [];
for (const it of items) {
  const meta = it.metadata || {};
  const feedWords = wordCount(it.original_content);
  const descWords = wordCount(it.description);
  const base = { id: it.id, source_type: it.source_type, original_url: it.original_url, attempts: it.extraction_attempts,
    feed_content: it.original_content || '', description: it.description || '' };

  if (it.source_type === 'gmail') {
    out.push({ ...base, action: 'done', result: { id: it.id, status: 'extracted', word_count: feedWords } });
  } else if (it.source_type === 'youtube') {
    out.push({ ...base, action: 'transcript' });
  } else if (it.source_type === 'podcast') {
    if (meta.transcript_url) out.push({ ...base, action: 'fetch', fetch_url: meta.transcript_url, mode: 'subtitles' });
    else if (descWords >= minP) out.push({ ...base, action: 'done', result: { id: it.id, status: 'extracted', original_content: it.description, word_count: descWords, metadata: { content_basis: 'show_notes', partial: true } } });
    else out.push({ ...base, action: 'done', result: { id: it.id, status: 'incomplete', error: 'Brak transkrypcji i za krótki opis odcinka' } });
  } else if (feedWords >= minC) {
    out.push({ ...base, action: 'done', result: { id: it.id, status: 'extracted', word_count: feedWords, metadata: { content_basis: 'feed' } } });
  } else if (it.source_type === 'reddit') {
    if (feedWords >= minP) out.push({ ...base, action: 'done', result: { id: it.id, status: 'extracted', word_count: feedWords, metadata: { content_basis: 'feed', partial: true } } });
    else out.push({ ...base, action: 'done', result: { id: it.id, status: 'incomplete', error: 'Post bez treści (link/obraz)' } });
  } else {
    out.push({ ...base, action: 'fetch', fetch_url: it.original_url, mode: 'article' });
  }
}
return out.map((j) => ({ json: j }));
