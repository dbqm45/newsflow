//@lib llm
const SYSTEM = PROMPT('analyze_item');
const PROMPT_VERSION = (SYSTEM.match(/prompt_version:\s*([\w.-]+)/) || [])[1] || 'unknown';
const cfg = $('Load config').first().json;
const weights = cfg.scoring_weights;
const pricing = cfg.pricing_usd_per_1m_tokens || {};
const minImportance = (cfg.pipeline && cfg.pipeline.min_importance) || 4.5;
const reqs = $('Build analysis requests').all().map((i) => i.json);
const resps = $input.all();
const analysisRows = [], statusRows = [], usageRows = [], embedItems = [];

reqs.forEach((rq, idx) => {
  const resp = resps[idx] ? resps[idx].json : null;
  const p = parseChatJson(resp);
  if (!p.ok) { statusRows.push({ id: rq.id, status: 'failed', error: String(p.error).slice(0, 1000) }); return; }
  const d = p.data;
  const scores = {
    novelty: clampScore(d.scores.novelty), relevance: clampScore(d.scores.relevance),
    practical: clampScore(d.scores.practical), reliability: clampScore(d.scores.reliability),
  };
  const importance = weightedScore(scores, weights, 2);
  const relevant = d.is_relevant && d.category === 'ai' && d.completeness !== 'insufficient';
  const keep = relevant && importance >= minImportance;
  const tokensIn = (p.usage && p.usage.prompt_tokens) || 0;
  const tokensOut = (p.usage && p.usage.completion_tokens) || 0;
  const cost = estimateCostUsd(p.model || rq.request.model, p.usage, pricing);
  analysisRows.push({
    content_item_id: rq.id,
    is_relevant: keep,
    reject_reason: keep ? null : (relevant ? `Niska ważność (${importance})` : (d.reject_reason || 'Poza tematyką AI')),
    title_pl: d.title_pl,
    summary: d.summary,
    key_points: (d.key_points || []).slice(0, 5),
    practical_value: d.practical_value,
    why_it_matters: d.why_it_matters,
    claims: d.claims || [],
    entities: d.entities || [],
    completeness: d.completeness,
    source_language: d.source_language,
    novelty_score: scores.novelty,
    relevance_score: scores.relevance,
    practical_score: scores.practical,
    reliability_score: scores.reliability,
    importance_score: importance,
    subcategory_slug: d.subcategory,
    analysis_model: p.model || rq.request.model,
    prompt_version: PROMPT_VERSION,
    tokens_input: tokensIn,
    tokens_output: tokensOut,
    cost_usd: cost,
    raw_response: {
      secondary_subcategories: d.secondary_subcategories || [],
      subcategory_confidence: d.subcategory_confidence,
      reliability_notes: d.reliability_notes,
      injection_detected: !!d.injection_detected,
      llm_is_relevant: d.is_relevant,
    },
  });
  statusRows.push({ id: rq.id, status: keep ? 'analyzed' : 'rejected', error: null });
  usageRows.push({ workflow: 'WF03_ai_editor', provider: 'openai', operation: 'analyze_item', model: p.model || rq.request.model,
    tokens_input: tokensIn, tokens_output: tokensOut, cost_usd: cost, content_item_id: rq.id });
  if (keep) embedItems.push({ id: rq.id, text: [d.title_pl, d.summary].concat(d.key_points || []).join('\n') });
});

return [{ json: { analysisRows, statusRows, usageRows, embedItems,
  stats: { claimed: reqs.length, analyzed: analysisRows.length, kept: embedItems.length, failed: statusRows.filter((s) => s.status === 'failed').length,
           cost_usd: usageRows.reduce((a, u) => a + u.cost_usd, 0) } } }];
