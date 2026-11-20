const P = $('Parse analyses').first().json;
const cfg = $('Load config').first().json;
if (!P.embedItems.length) return [];
return [{ json: {
  ids: P.embedItems.map((e) => e.id),
  request: { model: (cfg.models && cfg.models.embedding) || 'text-embedding-3-small', input: P.embedItems.map((e) => e.text.slice(0, 8000)) },
} }];
