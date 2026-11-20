//@lib text
//@lib llm
const SYSTEM = PROMPT('analyze_item');
const SCHEMA = SCHEMA_JSON('analysis');
const cfg = $('Load config').first().json;
const model = (cfg.models && cfg.models.analysis) || 'gpt-5-mini';
const maxChars = (cfg.pipeline && cfg.pipeline.max_content_chars) || 24000;
const items = $input.all().map((i) => i.json).filter((x) => x && x.id);
return items.map((it) => {
  const header = [
    `Źródło: ${it.source_name} (typ: ${it.source_type}, priorytet ${it.source_priority}/5)`,
    `Tytuł oryginalny: ${it.title}`,
    `Autor: ${it.author || 'brak danych'}`,
    `Data publikacji: ${it.published_at || 'brak danych'}`,
    `URL: ${it.original_url}`,
    `Liczba słów treści: ${it.word_count || 'nieznana'}`,
  ].join('\n');
  const user = header + '\n\n' + wrapUntrusted(it.source_name, truncate(it.content || it.description || '', maxChars)) +
    '\n\nPrzygotuj analizę tego materiału zgodnie ze schematem odpowiedzi.';
  const request = chatRequest(model, SYSTEM, user, 'newsflow_analysis', SCHEMA, 8000);
  if (/^(gpt-5|o\d)/.test(model)) request.reasoning_effort = 'low';
  return { json: { id: it.id, request } };
});
