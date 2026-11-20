const resp = $input.first().json;
const ids = $('Embedding request').first().json.ids;
const P = $('Load config').first().json.pipeline || {};
if (!resp || resp.error || !Array.isArray(resp.data)) {
  throw new Error('Embeddingi nie zostały wygenerowane: ' + JSON.stringify(resp && resp.error ? resp.error : resp).slice(0, 500));
}
return resp.data.map((d) => ({ json: {
  p_content_item_id: ids[d.index],
  p_embedding: d.embedding,
  p_threshold: P.story_similarity_threshold || 0.82,
  p_window_hours: P.story_window_hours || 96,
} }));
