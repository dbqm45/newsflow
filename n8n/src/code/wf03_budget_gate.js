const budget = $input.first().json;
const cfg = $('Load config').first().json;
if (!budget.allowed) return [];   // limit kosztów OpenAI osiągnięty — spróbujemy w kolejnym przebiegu
return [{ json: { p_limit: (cfg.pipeline && cfg.pipeline.analyze_batch) || 15 } }];
