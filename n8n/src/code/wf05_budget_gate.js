const budget = $input.first().json;
if (!budget.allowed) throw new Error('Limit kosztów ElevenLabs osiągnięty — briefing zostanie dostarczony bez audio. ' + JSON.stringify(budget));
return [{ json: { budget } }];
