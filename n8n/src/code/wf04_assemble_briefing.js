//@lib llm
const SUBCATEGORY_NAMES = {
  llm: 'Modele językowe i LLM', agents: 'Agenci AI', automation: 'Automatyzacja', tools: 'Narzędzia AI',
  'image-video': 'Generowanie obrazu i wideo', 'voice-audio': 'Generowanie głosu i audio', 'open-source': 'Open source',
  research: 'Badania naukowe', startups: 'Startupy AI', business: 'AI w biznesie', coding: 'AI w programowaniu',
  productivity: 'AI w produktywności', robotics: 'Robotyka i systemy autonomiczne', infrastructure: 'Infrastruktura i sprzęt AI',
  'policy-safety': 'Regulacje i bezpieczeństwo AI',
};
const cfg = $('Load config').first().json;
const pricing = cfg.pricing_usd_per_1m_tokens || {};
const prev = $('Build script request').first().json;
const stats = $('Get stats').first().json;
const cands = $('Get candidates').all().map((i) => i.json).filter((c) => c && c.story_id);
const byId = Object.fromEntries(cands.map((c) => [c.story_id, c]));
const b = prev.briefing;
const s = parseChatJson($input.first().json);

let script = null;
if (s.ok && s.data.chapters && s.data.chapters.length) {
  script = s.data;
  const disclosure = 'Audycję przygotowała i czyta sztuczna inteligencja.';
  if (!/sztuczn\w+ inteligencj/i.test(script.chapters[0].text)) script.chapters[0].text = script.chapters[0].text + '\n\n' + disclosure;
}

const sections = b.topics.map((t, i) => {
  const c = byId[t.story_id];
  return {
    position: i, section: t.section, story_id: t.story_id,
    headline: t.headline, summary: t.summary, why_it_matters: t.why_it_matters,
    practical_use: t.practical_use, discrepancies: t.discrepancies,
    subcategory: SUBCATEGORY_NAMES[c.subcategory_slug] || c.subcategory_slug,
    importance_score: Number(c.importance_score), source_count: c.source_count,
    sources: (c.items || []).slice(0, 6).map((it) => ({ content_item_id: it.content_item_id, title: it.title, source: it.source, url: it.url })),
  };
});

const md = [];
md.push(`# ${b.title}`, '', b.lead, '');
const label = { headline: 'Najważniejsza informacja dnia', main: 'Główne informacje', tools: 'Narzędzia i zastosowania', brief: 'W skrócie' };
let lastSection = null;
for (const t of sections) {
  if (t.section !== lastSection) { md.push(`## ${label[t.section] || t.section}`, ''); lastSection = t.section; }
  md.push(`### ${t.headline}`, '', t.summary, '');
  if (t.why_it_matters) md.push(`**Dlaczego to ważne:** ${t.why_it_matters}`, '');
  if (t.practical_use) md.push(`**Zastosowanie:** ${t.practical_use}`, '');
  if (t.discrepancies) md.push(`**Rozbieżności:** ${t.discrepancies}`, '');
  md.push('Źródła: ' + t.sources.map((x) => `[${x.source}](${x.url})`).join(' · '), '');
}
if (b.tools_summary) md.push('## Narzędzia – podsumowanie', '', b.tools_summary, '');
md.push('## Trendy i wnioski', '', b.trends, '');
md.push('---', '_Briefing przygotowany automatycznie przez AI na podstawie podlinkowanych źródeł._');

const c1 = estimateCostUsd(prev.briefing_model, prev.briefing_usage, pricing);
const c2 = s.ok ? estimateCostUsd(s.model, s.usage, pricing) : 0;
const row = {
  briefing_date: prev.date,
  edition: 'ai-daily',
  title: b.title,
  summary: b.lead,
  text_content: md.join('\n'),
  sections,
  trends: b.trends,
  stats: { ...stats, quiet_day: !!b.quiet_day },
  script: script ? { ...script, tools_summary: b.tools_summary } : null,
  chapters: [],
  headline_story_id: b.headline_story_id,
  audio_asset_id: null,
  status: script ? 'script_ready' : 'draft',
  items_considered: cands.length,
  items_analyzed: stats.analyzed,
  items_rejected: stats.rejected,
  analysis_model: prev.briefing_model,
  cost_usd: Math.round((c1 + c2) * 1e6) / 1e6,
  error: s.ok ? null : 'Scenariusz audio: ' + s.error,
  email_sent_at: null,
};
const usage = [
  { workflow: 'WF04_daily_intelligence', provider: 'openai', operation: 'briefing', model: prev.briefing_model,
    tokens_input: (prev.briefing_usage || {}).prompt_tokens || 0, tokens_output: (prev.briefing_usage || {}).completion_tokens || 0, cost_usd: c1 },
];
if (s.ok) usage.push({ workflow: 'WF04_daily_intelligence', provider: 'openai', operation: 'audio_script', model: s.model,
  tokens_input: (s.usage || {}).prompt_tokens || 0, tokens_output: (s.usage || {}).completion_tokens || 0, cost_usd: c2 });
return [{ json: { row, usage } }];
