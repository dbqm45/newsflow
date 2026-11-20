//@lib llm
const cfg = $('Load config').first().json;
const P = cfg.pipeline || {};
const stats = $('Get stats').first().json;
const cands = $input.all().map((i) => i.json).filter((c) => c && c.story_id);
if (!cands.length) throw new Error('Brak kandydatów do briefingu z ostatnich ' + (P.briefing_hours || 24) + ' h — sprawdź WF01–WF03.');
const date = $now.setZone('Europe/Warsaw').toFormat('yyyy-MM-dd');
const compact = cands.map((c) => ({
  story_id: c.story_id,
  title: c.title,
  subcategory: c.subcategory_slug,
  adjusted_score: Number(c.adjusted_score),
  importance_score: Number(c.importance_score),
  reliability_score: Number(c.reliability_score),
  source_count: c.source_count,
  items: (c.items || []).slice(0, 4).map((it) => ({
    source: it.source, title: it.title, published_at: it.published_at, summary: it.summary,
    key_points: it.key_points, practical_value: it.practical_value, claims: (it.claims || []).slice(0, 6),
  })),
}));
const system = PROMPT('daily_briefing')
  .replace('{{min_topics}}', String(Math.min(P.briefing_min_topics || 5, cands.length)))
  .replace('{{max_topics}}', String(P.briefing_max_topics || 10));
const user = `Data wydania: ${date}\nStatystyki ostatnich 24 h: ${JSON.stringify(stats)}\n\nKandydaci (${cands.length}):\n` +
  wrapUntrusted('candidates', JSON.stringify(compact, null, 1));
const model = (cfg.models && cfg.models.briefing) || 'gpt-5';
const request = chatRequest(model, system, user, 'newsflow_briefing', SCHEMA_JSON('briefing'), 16000);
if (/^(gpt-5|o\d)/.test(model)) request.reasoning_effort = 'medium';
return [{ json: { date, request } }];
