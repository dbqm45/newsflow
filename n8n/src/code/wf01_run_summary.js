const s = $('Parse feeds').first().json.stats;
return [{ json: {
  workflow: 'WF01_source_collector',
  execution_id: String($execution.id),
  status: s.failed_sources ? 'partial' : 'success',
  stats: s,
} }];
