const r = $('Render email').first().json;
return [{ json: {
  workflow: 'WF06_delivery_archive',
  execution_id: String($execution.id),
  status: r.briefing_id ? (r.status === 'delivered' ? 'success' : 'partial') : 'error',
  stats: { briefing_id: r.briefing_id, delivery_status: r.status, subject: r.subject },
} }];
