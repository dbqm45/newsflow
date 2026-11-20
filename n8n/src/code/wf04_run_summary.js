const a = $('Assemble briefing').first().json;
return [{ json: {
  workflow: 'WF04_daily_intelligence',
  execution_id: String($execution.id),
  status: a.row.status === 'script_ready' ? 'success' : 'partial',
  stats: { topics: a.row.sections.length, considered: a.row.items_considered, cost_usd: a.row.cost_usd, error: a.row.error },
} }];
