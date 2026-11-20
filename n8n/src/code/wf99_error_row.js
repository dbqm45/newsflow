const e = $input.first().json;
const ex = e.execution || {};
return [{ json: {
  workflow: (e.workflow && e.workflow.name) || 'unknown',
  execution_id: ex.id ? String(ex.id) : null,
  status: 'error',
  error: String((ex.error && (ex.error.message || ex.error.description)) || 'Nieznany błąd').slice(0, 4000),
  stats: { last_node: ex.lastNodeExecuted || null, url: ex.url || null, mode: ex.mode || null },
} }];
