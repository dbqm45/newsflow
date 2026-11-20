const s = $('Parse analyses').first().json.stats;
const assigned = $input.all().filter((i) => !i.json.error).length;
return [{ json: {
  workflow: 'WF03_ai_editor',
  execution_id: String($execution.id),
  status: s.failed ? 'partial' : 'success',
  stats: { ...s, stories_assigned: assigned },
} }];
