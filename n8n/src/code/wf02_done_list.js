const results = $input.all().map((i) => i.json).filter((j) => j.action === 'done').map((j) => j.result);
return results.length ? [{ json: { p_results: results } }] : [];
