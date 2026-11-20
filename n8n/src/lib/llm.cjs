// NEWSFLOW — pomocnicze funkcje dla OpenAI (Chat Completions + Structured Outputs).

function chatRequest(model, systemPrompt, userContent, schemaName, schema, maxTokens) {
  return {
    model,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userContent },
    ],
    response_format: { type: 'json_schema', json_schema: { name: schemaName, strict: true, schema } },
    max_completion_tokens: maxTokens || 4000,
  };
}

// Treść zewnętrzna zawsze w wyraźnych ogranicznikach — to DANE, nie polecenia.
function wrapUntrusted(label, text) {
  const clean = String(text || '').replace(/<\/?untrusted_content[^>]*>/gi, '');
  return `<untrusted_content source="${label}">\n${clean}\n</untrusted_content>`;
}

function parseChatJson(resp) {
  if (!resp || resp.error) return { ok: false, error: (resp && resp.error && (resp.error.message || JSON.stringify(resp.error))) || 'no response' };
  const choice = resp.choices && resp.choices[0];
  if (!choice) return { ok: false, error: 'no choices' };
  if (choice.message && choice.message.refusal) return { ok: false, error: 'refusal: ' + choice.message.refusal };
  if (choice.finish_reason === 'length') return { ok: false, error: 'truncated (max tokens)' };
  try {
    return { ok: true, data: JSON.parse(choice.message.content), usage: resp.usage || {}, model: resp.model };
  } catch (e) {
    return { ok: false, error: 'invalid JSON: ' + e.message };
  }
}

function estimateCostUsd(model, usage, pricing) {
  if (!usage) return 0;
  const key = Object.keys(pricing || {}).filter((k) => String(model || '').startsWith(k)).sort((a, b) => b.length - a.length)[0];
  const p = key ? pricing[key] : { input: 1.25, output: 10 };
  const inp = usage.prompt_tokens || usage.input_tokens || 0;
  const out = usage.completion_tokens || usage.output_tokens || 0;
  return Math.round(((inp * p.input + out * (p.output || 0)) / 1e6) * 1e6) / 1e6;
}

function clampScore(v) {
  const n = Math.round(Number(v));
  return Number.isFinite(n) ? Math.min(10, Math.max(1, n)) : null;
}

function weightedScore(s, w, corroboration) {
  w = w || { novelty: 0.3, relevance: 0.25, practical: 0.2, reliability: 0.15, corroboration: 0.1 };
  const v = s.novelty * w.novelty + s.relevance * w.relevance + s.practical * w.practical +
    s.reliability * w.reliability + (corroboration || 2) * w.corroboration;
  return Math.round(v * 100) / 100;
}

/* @exports — wszystko poniżej jest usuwane przez build.mjs */
module.exports = { chatRequest, wrapUntrusted, parseChatJson, estimateCostUsd, clampScore, weightedScore };
