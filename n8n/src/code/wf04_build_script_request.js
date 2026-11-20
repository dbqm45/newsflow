//@lib llm
//@lib email
const cfg = $('Load config').first().json;
const P = cfg.pipeline || {};
const prev = $('Build briefing request').first().json;
const cands = $('Get candidates').all().map((i) => i.json).filter((c) => c && c.story_id);
const byId = Object.fromEntries(cands.map((c) => [c.story_id, c]));
const p = parseChatJson($input.first().json);
if (!p.ok) throw new Error('Briefing (LLM): ' + p.error);
const b = p.data;

// Walidacja: tylko istniejące story_id, bez powtórzeń, dokładnie jeden headline.
const seen = new Set();
b.topics = (b.topics || []).filter((t) => byId[t.story_id] && !seen.has(t.story_id) && seen.add(t.story_id));
if (!b.topics.length) throw new Error('Briefing (LLM) nie zawiera poprawnych tematów');
let head = b.topics.find((t) => t.story_id === b.headline_story_id) || b.topics.find((t) => t.section === 'headline') || b.topics[0];
b.topics.forEach((t) => { if (t !== head && t.section === 'headline') t.section = 'main'; });
head.section = 'headline';
b.headline_story_id = head.story_id;
b.topics = [head].concat(b.topics.filter((t) => t !== head));

const targetMinutes = P.audio_target_minutes || 12;
const forScript = {
  title: b.title, lead: b.lead, trends: b.trends, tools_summary: b.tools_summary,
  topics: b.topics.map((t) => ({ ...t, sources: (byId[t.story_id].items || []).map((it) => it.source).filter((v, i, a) => a.indexOf(v) === i) })),
};
const system = PROMPT('audio_script')
  .replace('{{target_minutes}}', String(targetMinutes))
  .replace('{{target_words}}', String(targetMinutes * 140))
  .replace('{{date_spoken}}', formatDatePl(prev.date));
const model = (cfg.models && cfg.models.script) || 'gpt-5';
const request = chatRequest(model, system, wrapUntrusted('briefing', JSON.stringify(forScript, null, 1)), 'newsflow_audio_script', SCHEMA_JSON('audio_script'), 20000);
if (/^(gpt-5|o\d)/.test(model)) request.reasoning_effort = 'low';
return [{ json: { date: prev.date, briefing: b, briefing_usage: p.usage, briefing_model: p.model, request } }];
