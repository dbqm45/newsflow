const budget = $input.first().json;
if (!budget.allowed) throw new Error('Limit kosztów OpenAI osiągnięty — briefing nie zostanie wygenerowany. ' + JSON.stringify(budget));
return [{ json: { p_hours: ($('Load config').first().json.pipeline || {}).briefing_hours || 24 } }];
