#!/usr/bin/env node
// NEWSFLOW — generator workflow n8n.
// Składa pliki JSON do importu w n8n z: kodu węzłów (src/code), bibliotek (src/lib),
// promptów (../prompts), schematów (../schemas) i szablonu e-mail (../email).
//
//   node n8n/build.mjs                       -> placeholder adresu Supabase
//   SUPABASE_URL=https://abc.supabase.co node n8n/build.mjs
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const SB = (process.env.SUPABASE_URL || 'https://YOUR-PROJECT-REF.supabase.co').replace(/\/$/, '');
const OUT = join(HERE, 'workflows');

const CRED = {
  supabase: { httpCustomAuth: { id: 'REPLACE_SUPABASE_CRED', name: 'NEWSFLOW Supabase' } },
  openai: { openAiApi: { id: 'REPLACE_OPENAI_CRED', name: 'NEWSFLOW OpenAI' } },
  eleven: { httpHeaderAuth: { id: 'REPLACE_ELEVENLABS_CRED', name: 'NEWSFLOW ElevenLabs' } },
  transcript: { httpHeaderAuth: { id: 'REPLACE_TRANSCRIPT_CRED', name: 'NEWSFLOW Transcript API' } },
  gmail: { gmailOAuth2: { id: 'REPLACE_GMAIL_CRED', name: 'NEWSFLOW Gmail' } },
};

// ---------------------------------------------------------------- kod
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const stripExports = (s) => s.split('/* @exports')[0].trimEnd();
function compileCode(file) {
  let src = read(`n8n/src/code/${file}`);
  const libs = [];
  src = src.replace(/^\/\/@lib (\w+)\s*$/gm, (m, name) => {
    if (name === 'feed' && !libs.includes('text')) throw new Error(`${file}: //@lib feed wymaga wcześniej //@lib text`);
    libs.push(name);
    return `// ---- lib/${name}.cjs ----\n${stripExports(read(`n8n/src/lib/${name}.cjs`))}\n// ---- /lib/${name}.cjs ----`;
  });
  src = src.replace(/PROMPT\('(\w+)'\)/g, (m, n) => JSON.stringify(read(`prompts/${n}.md`)));
  src = src.replace(/SCHEMA_JSON\('(\w+)'\)/g, (m, n) => JSON.stringify(JSON.parse(read(`schemas/${n}.schema.json`))));
  src = src.replace(/TEMPLATE_HTML\('(\w+)'\)/g, (m, n) => JSON.stringify(read(`email/${n}.html`)));
  src = src.replace(/\{\{SUPABASE_URL\}\}/g, SB);
  return `// NEWSFLOW — wygenerowane z n8n/src/code/${file} (nie edytuj w n8n — edytuj źródło i przebuduj)\n${src}`;
}

// ---------------------------------------------------------------- węzły
const uuid = (wf, name) => {
  const h = createHash('sha1').update(wf + '/' + name).digest('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-a${h.slice(17, 20)}-${h.slice(20, 32)}`;
};

function schedule(name, cron) {
  return { name, type: 'n8n-nodes-base.scheduleTrigger', typeVersion: 1.2,
    parameters: { rule: { interval: [{ field: 'cronExpression', expression: cron }] } } };
}
const manual = (name = 'Run manually') => ({ name, type: 'n8n-nodes-base.manualTrigger', typeVersion: 1, parameters: {} });

function code(name, file, extra = {}) {
  return { name, type: 'n8n-nodes-base.code', typeVersion: 2,
    parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: compileCode(file) }, ...extra };
}

function http(name, { method = 'GET', url, cred, headers = [], body, binaryField, responseText, responseFile,
  timeout = 30000, batch, query, ...extra }) {
  const p = { method, url, options: { timeout } };
  if (cred === 'supabase') Object.assign(p, { authentication: 'genericCredentialType', genericAuthType: 'httpCustomAuth' });
  if (cred === 'eleven' || cred === 'transcript') Object.assign(p, { authentication: 'genericCredentialType', genericAuthType: 'httpHeaderAuth' });
  if (cred === 'openai') Object.assign(p, { authentication: 'predefinedCredentialType', nodeCredentialType: 'openAiApi' });
  if (headers.length) Object.assign(p, { sendHeaders: true, headerParameters: { parameters: headers.map(([n, v]) => ({ name: n, value: v })) } });
  if (query) Object.assign(p, { sendQuery: true, queryParameters: { parameters: query.map(([n, v]) => ({ name: n, value: v })) } });
  if (body !== undefined) Object.assign(p, { sendBody: true, specifyBody: 'json', jsonBody: body });
  if (binaryField) Object.assign(p, { sendBody: true, contentType: 'binaryData', inputDataFieldName: binaryField });
  if (responseText) p.options.response = { response: { responseFormat: 'text', outputPropertyName: 'body' } };
  if (responseFile) p.options.response = { response: { responseFormat: 'file', outputPropertyName: 'data' } };
  if (batch) p.options.batching = { batch: { batchSize: batch[0], batchInterval: batch[1] } };
  const n = { name, type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2, parameters: p, ...extra };
  if (cred) n.credentials = CRED[cred];
  return n;
}

// Skróty Supabase (PostgREST / Storage)
const sbRpc = (name, fn, body, extra = {}) =>
  http(name, { method: 'POST', url: `${SB}/rest/v1/rpc/${fn}`, cred: 'supabase', body, ...extra });
const sbInsert = (name, table, body, { onConflict, merge = false, returnRows = false, ...extra } = {}) =>
  http(name, {
    method: 'POST',
    url: `${SB}/rest/v1/${table}${onConflict ? `?on_conflict=${onConflict}` : ''}`,
    cred: 'supabase',
    headers: [['Prefer', [onConflict ? (merge ? 'resolution=merge-duplicates' : 'resolution=ignore-duplicates') : null,
      returnRows ? 'return=representation' : 'return=minimal'].filter(Boolean).join(',')]],
    body,
    alwaysOutputData: true,
    ...extra,
  });
const sbPatch = (name, tableQuery, body, extra = {}) =>
  http(name, { method: 'PATCH', url: `${SB}/rest/v1/${tableQuery}`, cred: 'supabase',
    headers: [['Prefer', 'return=minimal']], body, alwaysOutputData: true, ...extra });
const loadConfig = () => sbRpc('Load config', 'get_config', '{}');
const logRun = (name = 'Log run') => sbInsert(name, 'pipeline_runs', '={{ JSON.stringify($json) }}');
const CONTINUE = { onError: 'continueRegularOutput' };

// ---------------------------------------------------------------- workflow
function workflow(file, name, description, nodes, edges, layout) {
  const byName = Object.fromEntries(nodes.map((n) => [n.name, n]));
  for (const [a, b] of edges) {
    if (!byName[a]) throw new Error(`${file}: brak węzła ${a}`);
    if (!byName[b]) throw new Error(`${file}: brak węzła ${b}`);
  }
  const connections = {};
  for (const [a, b] of edges) {
    connections[a] = connections[a] || { main: [[]] };
    connections[a].main[0].push({ node: b, type: 'main', index: 0 });
  }
  const wf = {
    name,
    nodes: nodes.map((n) => {
      const pos = layout[n.name];
      if (!pos) throw new Error(`${file}: brak pozycji dla ${n.name}`);
      return { id: uuid(file, n.name), position: [pos[0] * 240, pos[1] * 180], ...n };
    }),
    connections,
    settings: { executionOrder: 'v1', timezone: 'Europe/Warsaw', saveManualExecutions: true, callerPolicy: 'workflowsFromSameOwner' },
    pinData: {},
    active: false,
    meta: { templateCredsSetupCompleted: false },
    tags: [],
  };
  // notatka opisująca workflow
  wf.nodes.push({ id: uuid(file, '__note'), name: 'Opis', type: 'n8n-nodes-base.stickyNote', typeVersion: 1,
    position: [0, -260], parameters: { content: description, width: 720, height: 220 } });
  mkdirSync(OUT, { recursive: true });
  writeFileSync(join(OUT, file), JSON.stringify(wf, null, 2) + '\n');
  console.log(`✓ ${file} (${nodes.length} węzłów)`);
}

// =====================================================================
// WF01 — SOURCE COLLECTOR
// =====================================================================
workflow('WF01_source_collector.json', 'NEWSFLOW WF01 – Source Collector',
  '## WF01 – Source Collector\nCo 2 h: pobiera źródła z `get_sources_due` (RSS, YouTube, Medium, blogi, Reddit, podcasty), parsuje feedy, deduplikuje po `content_hash` (sha256 kanonicznego URL) i zapisuje nowe materiały jako `pending`.\nGałąź Gmail (etykieta **AI-READ**) jest **wyłączona** do czasu skonfigurowania credentials i ID etykiety.\nKolejny krok: WF02 przetwarza materiały ze statusem `pending`.',
  [
    schedule('Every 2 hours', '0 */2 * * *'),
    manual(),
    loadConfig(),
    sbRpc('Get due sources', 'get_sources_due',
      '={{ JSON.stringify({ p_types: ["rss","youtube","medium","blog","web","podcast","reddit"], p_force: $("Run manually").isExecuted }) }}'),
    code('Prepare sources', 'wf01_prepare_sources.js'),
    http('Fetch feed', { url: '={{ $json.url }}', responseText: true, timeout: 20000, batch: [5, 500],
      headers: [['User-Agent', 'Mozilla/5.0 (compatible; NEWSFLOW-Personal/0.1; RSS reader)'], ['Accept', 'application/rss+xml, application/atom+xml, application/xml, text/xml, */*']],
      ...CONTINUE }),
    code('Parse feeds', 'wf01_parse_feeds.js'),
    sbInsert('Insert new items', 'content_items', '={{ JSON.stringify($json.rows) }}', { onConflict: 'content_hash' }),
    code('Source results', 'wf01_source_results.js'),
    sbRpc('Mark source checked', 'mark_source_checked', '={{ JSON.stringify($json) }}', { ...CONTINUE }),
    code('Run summary', 'wf01_run_summary.js'),
    logRun(),
    // --- Gmail ---
    http('Get Gmail source', { url: `${SB}/rest/v1/sources?type=eq.gmail&active=eq.true&select=id,visibility,configuration&limit=1`, cred: 'supabase' }),
    { name: 'Gmail: AI-READ', type: 'n8n-nodes-base.gmail', typeVersion: 2.1, disabled: true,
      notes: 'Włącz po skonfigurowaniu credentials. Wybierz etykietę AI-READ z listy (pole Label IDs).',
      parameters: { resource: 'message', operation: 'getAll', returnAll: false, limit: 30, simple: false,
        filters: { labelIds: ['REPLACE_WITH_AI_READ_LABEL_ID'], q: 'newer_than:2d' }, options: {} },
      credentials: CRED.gmail },
    code('Normalize newsletters', 'wf01_normalize_newsletters.js'),
    sbInsert('Insert newsletters', 'content_items', '={{ JSON.stringify($json.rows) }}', { onConflict: 'content_hash' }),
    sbRpc('Mark Gmail checked', 'mark_source_checked', '={{ JSON.stringify({ p_source_id: $("Get Gmail source").first().json.id, p_ok: true }) }}'),
  ],
  [
    ['Every 2 hours', 'Load config'], ['Run manually', 'Load config'],
    ['Load config', 'Get due sources'], ['Get due sources', 'Prepare sources'], ['Prepare sources', 'Fetch feed'],
    ['Fetch feed', 'Parse feeds'], ['Parse feeds', 'Insert new items'], ['Insert new items', 'Source results'],
    ['Source results', 'Mark source checked'], ['Mark source checked', 'Run summary'], ['Run summary', 'Log run'],
    ['Load config', 'Get Gmail source'], ['Get Gmail source', 'Gmail: AI-READ'], ['Gmail: AI-READ', 'Normalize newsletters'],
    ['Normalize newsletters', 'Insert newsletters'], ['Insert newsletters', 'Mark Gmail checked'],
  ],
  {
    'Every 2 hours': [0, 0], 'Run manually': [0, 1], 'Load config': [1, 0.5], 'Get due sources': [2, 0], 'Prepare sources': [3, 0],
    'Fetch feed': [4, 0], 'Parse feeds': [5, 0], 'Insert new items': [6, 0], 'Source results': [7, 0], 'Mark source checked': [8, 0],
    'Run summary': [9, 0], 'Log run': [10, 0],
    'Get Gmail source': [2, 1.5], 'Gmail: AI-READ': [3, 1.5], 'Normalize newsletters': [4, 1.5], 'Insert newsletters': [5, 1.5], 'Mark Gmail checked': [6, 1.5],
  });

// =====================================================================
// WF02 — CONTENT EXTRACTOR
// =====================================================================
workflow('WF02_content_extractor.json', 'NEWSFLOW WF02 – Content Extractor',
  '## WF02 – Content Extractor\nCo 2 h (:20): pobiera paczkę `pending` (`claim_items_for_extraction`), decyduje skąd wziąć treść: z feedu, ze strony (ekstrakcja artykułu), z transkrypcji podcastu lub (opcjonalnie) z API transkrypcji YouTube.\nZbyt mała treść ⇒ `incomplete` (NIE jest streszczana). Błąd ⇒ `failed` (max 3 próby).\nWęzeł **Transcript API (optional)** jest wyłączony — bez niego filmy YouTube trafiają jako `incomplete`.',
  [
    schedule('Every 2 hours', '20 */2 * * *'),
    manual(),
    loadConfig(),
    sbRpc('Claim items', 'claim_items_for_extraction', '={{ JSON.stringify({ p_limit: ($json.pipeline || {}).extract_batch || 20 }) }}'),
    code('Route items', 'wf02_route_items.js'),
    code('Done list', 'wf02_done_list.js'),
    sbRpc('Save ready', 'apply_extraction_results', '={{ JSON.stringify($json) }}'),
    code('Fetch list', 'wf02_fetch_list.js'),
    http('Fetch page', { url: '={{ $json.fetch_url }}', responseText: true, timeout: 25000, batch: [4, 1000],
      headers: [['User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15 NEWSFLOW-Personal/0.1'],
        ['Accept', 'text/html,application/xhtml+xml,text/plain,text/vtt,*/*'], ['Accept-Language', 'en,pl;q=0.8']],
      ...CONTINUE }),
    code('Extract pages', 'wf02_extract_pages.js'),
    sbRpc('Save extracted', 'apply_extraction_results', '={{ JSON.stringify($json) }}'),
    code('Transcript list', 'wf02_transcript_list.js'),
    http('Transcript API (optional)', { url: 'https://api.supadata.ai/v1/youtube/transcript', cred: 'transcript',
      query: [['url', '={{ $json.original_url }}'], ['text', 'true']], timeout: 60000, batch: [1, 1000],
      disabled: true, notes: 'Opcjonalne, płatne API transkrypcji YouTube (np. Supadata). Włącz po dodaniu credentials „NEWSFLOW Transcript API” (nagłówek x-api-key). Możesz podmienić na innego dostawcę zwracającego {content: "..."}',
      ...CONTINUE }),
    code('Apply transcripts', 'wf02_apply_transcripts.js'),
    sbRpc('Save transcripts', 'apply_extraction_results', '={{ JSON.stringify($json) }}'),
  ],
  [
    ['Every 2 hours', 'Load config'], ['Run manually', 'Load config'], ['Load config', 'Claim items'], ['Claim items', 'Route items'],
    ['Route items', 'Done list'], ['Done list', 'Save ready'],
    ['Route items', 'Fetch list'], ['Fetch list', 'Fetch page'], ['Fetch page', 'Extract pages'], ['Extract pages', 'Save extracted'],
    ['Route items', 'Transcript list'], ['Transcript list', 'Transcript API (optional)'], ['Transcript API (optional)', 'Apply transcripts'], ['Apply transcripts', 'Save transcripts'],
  ],
  {
    'Every 2 hours': [0, 0], 'Run manually': [0, 1], 'Load config': [1, 0.5], 'Claim items': [2, 0.5], 'Route items': [3, 0.5],
    'Done list': [4, -0.5], 'Save ready': [5, -0.5],
    'Fetch list': [4, 0.5], 'Fetch page': [5, 0.5], 'Extract pages': [6, 0.5], 'Save extracted': [7, 0.5],
    'Transcript list': [4, 1.5], 'Transcript API (optional)': [5, 1.5], 'Apply transcripts': [6, 1.5], 'Save transcripts': [7, 1.5],
  });

// =====================================================================
// WF03 — AI EDITOR
// =====================================================================
workflow('WF03_ai_editor.json', 'NEWSFLOW WF03 – AI Editor',
  '## WF03 – AI Editor\nCo 2 h (:40): sprawdza budżet OpenAI, pobiera paczkę materiałów `extracted`, analizuje każdy (Structured Outputs, prompt `analyze_item`), liczy ważoną ocenę, zapisuje analizy i koszty, a następnie liczy embeddingi i grupuje materiały w wydarzenia (`assign_item_to_story`).\nMateriały poniżej `pipeline.min_importance` są oznaczane jako odrzucone.',
  [
    schedule('Every 2 hours', '40 */2 * * *'),
    manual(),
    loadConfig(),
    sbRpc('Check budget', 'check_budget', '={{ JSON.stringify({ p_provider: "openai" }) }}'),
    code('Budget gate', 'wf03_budget_gate.js'),
    sbRpc('Claim items', 'claim_items_for_analysis', '={{ JSON.stringify($json) }}'),
    code('Build analysis requests', 'wf03_build_requests.js'),
    http('OpenAI: analyze', { method: 'POST', url: 'https://api.openai.com/v1/chat/completions', cred: 'openai',
      body: '={{ JSON.stringify($json.request) }}', timeout: 240000, batch: [4, 1500], ...CONTINUE }),
    code('Parse analyses', 'wf03_parse_analyses.js'),
    sbInsert('Save analyses', 'analyses', '={{ JSON.stringify($json.analysisRows) }}', { onConflict: 'content_item_id', merge: true }),
    sbRpc('Save statuses', 'apply_analysis_status', '={{ JSON.stringify({ p_rows: $("Parse analyses").first().json.statusRows }) }}', { alwaysOutputData: true }),
    sbInsert('Log usage', 'api_usage', '={{ JSON.stringify($("Parse analyses").first().json.usageRows) }}'),
    code('Embedding request', 'wf03_embedding_request.js'),
    http('OpenAI: embeddings', { method: 'POST', url: 'https://api.openai.com/v1/embeddings', cred: 'openai',
      body: '={{ JSON.stringify($json.request) }}', timeout: 60000, ...CONTINUE }),
    code('Story assignments', 'wf03_story_assignments.js'),
    sbRpc('Assign to story', 'assign_item_to_story', '={{ JSON.stringify($json) }}', { batch: [1, 0], ...CONTINUE }),
    code('Run summary', 'wf03_run_summary.js'),
    logRun(),
  ],
  [
    ['Every 2 hours', 'Load config'], ['Run manually', 'Load config'], ['Load config', 'Check budget'], ['Check budget', 'Budget gate'],
    ['Budget gate', 'Claim items'], ['Claim items', 'Build analysis requests'], ['Build analysis requests', 'OpenAI: analyze'],
    ['OpenAI: analyze', 'Parse analyses'], ['Parse analyses', 'Save analyses'], ['Save analyses', 'Save statuses'],
    ['Save statuses', 'Log usage'], ['Log usage', 'Embedding request'], ['Embedding request', 'OpenAI: embeddings'],
    ['OpenAI: embeddings', 'Story assignments'], ['Story assignments', 'Assign to story'], ['Assign to story', 'Run summary'],
    ['Run summary', 'Log run'],
  ],
  {
    'Every 2 hours': [0, 0], 'Run manually': [0, 1], 'Load config': [1, 0.5], 'Check budget': [2, 0.5], 'Budget gate': [3, 0.5],
    'Claim items': [4, 0.5], 'Build analysis requests': [5, 0.5], 'OpenAI: analyze': [6, 0.5], 'Parse analyses': [7, 0.5],
    'Save analyses': [8, 0.5], 'Save statuses': [9, 0.5], 'Log usage': [10, 0.5],
    'Embedding request': [7, 1.7], 'OpenAI: embeddings': [8, 1.7], 'Story assignments': [9, 1.7], 'Assign to story': [10, 1.7],
    'Run summary': [11, 1.7], 'Log run': [12, 1.7],
  });

// =====================================================================
// WF04 — DAILY INTELLIGENCE
// =====================================================================
workflow('WF04_daily_intelligence.json', 'NEWSFLOW WF04 – Daily Intelligence',
  '## WF04 – Daily Intelligence\nCodziennie 07:00 (Europe/Warsaw): pobiera wydarzenia z ostatnich 24 h (`get_briefing_candidates` — z bonusem z Twoich ocen), redaktor AI wybiera 5–10 tematów i pisze briefing, scenarzysta AI pisze scenariusz audycji (~12 min). Zapis do `daily_briefings` + `briefing_stories`. Ponowne uruchomienie w tym samym dniu nadpisuje briefing.',
  [
    schedule('Daily 07:00', '0 7 * * *'),
    manual(),
    loadConfig(),
    sbRpc('Check budget', 'check_budget', '={{ JSON.stringify({ p_provider: "openai" }) }}'),
    code('Budget gate', 'wf04_budget_gate.js'),
    sbRpc('Get stats', 'briefing_stats', '={{ JSON.stringify($json) }}'),
    sbRpc('Get candidates', 'get_briefing_candidates',
      '={{ JSON.stringify({ p_hours: $("Load config").first().json.pipeline.briefing_hours || 24, p_limit: $("Load config").first().json.pipeline.briefing_candidates || 30 }) }}',
      { alwaysOutputData: true }),
    code('Build briefing request', 'wf04_build_briefing_request.js'),
    http('OpenAI: briefing', { method: 'POST', url: 'https://api.openai.com/v1/chat/completions', cred: 'openai',
      body: '={{ JSON.stringify($json.request) }}', timeout: 300000, retryOnFail: true, maxTries: 2, waitBetweenTries: 5000 }),
    code('Build script request', 'wf04_build_script_request.js'),
    http('OpenAI: audio script', { method: 'POST', url: 'https://api.openai.com/v1/chat/completions', cred: 'openai',
      body: '={{ JSON.stringify($json.request) }}', timeout: 300000, retryOnFail: true, maxTries: 2, waitBetweenTries: 5000, ...CONTINUE }),
    code('Assemble briefing', 'wf04_assemble_briefing.js'),
    sbInsert('Save briefing', 'daily_briefings', '={{ JSON.stringify($json.row) }}', { onConflict: 'briefing_date,edition', merge: true, returnRows: true }),
    code('Briefing story rows', 'wf04_briefing_story_rows.js'),
    http('Clear briefing stories', { method: 'DELETE', url: `=${SB}/rest/v1/briefing_stories?briefing_id=eq.{{ $json.briefing_id }}`, cred: 'supabase', alwaysOutputData: true }),
    sbInsert('Save briefing stories', 'briefing_stories', '={{ JSON.stringify($("Briefing story rows").first().json.rows) }}'),
    sbInsert('Log usage', 'api_usage', '={{ JSON.stringify($("Assemble briefing").first().json.usage) }}'),
    code('Run summary', 'wf04_run_summary.js'),
    logRun(),
  ],
  [
    ['Daily 07:00', 'Load config'], ['Run manually', 'Load config'], ['Load config', 'Check budget'], ['Check budget', 'Budget gate'],
    ['Budget gate', 'Get stats'], ['Get stats', 'Get candidates'], ['Get candidates', 'Build briefing request'],
    ['Build briefing request', 'OpenAI: briefing'], ['OpenAI: briefing', 'Build script request'], ['Build script request', 'OpenAI: audio script'],
    ['OpenAI: audio script', 'Assemble briefing'], ['Assemble briefing', 'Save briefing'], ['Save briefing', 'Briefing story rows'],
    ['Briefing story rows', 'Clear briefing stories'], ['Clear briefing stories', 'Save briefing stories'], ['Save briefing stories', 'Log usage'],
    ['Log usage', 'Run summary'], ['Run summary', 'Log run'],
  ],
  {
    'Daily 07:00': [0, 0], 'Run manually': [0, 1], 'Load config': [1, 0.5], 'Check budget': [2, 0.5], 'Budget gate': [3, 0.5],
    'Get stats': [4, 0.5], 'Get candidates': [5, 0.5], 'Build briefing request': [6, 0.5], 'OpenAI: briefing': [7, 0.5],
    'Build script request': [8, 0.5], 'OpenAI: audio script': [9, 0.5], 'Assemble briefing': [10, 0.5],
    'Save briefing': [4, 1.8], 'Briefing story rows': [5, 1.8], 'Clear briefing stories': [6, 1.8], 'Save briefing stories': [7, 1.8],
    'Log usage': [8, 1.8], 'Run summary': [9, 1.8], 'Log run': [10, 1.8],
  });

// =====================================================================
// WF05 — AUDIO GENERATOR
// =====================================================================
workflow('WF05_audio_generator.json', 'NEWSFLOW WF05 – Audio Generator',
  '## WF05 – Audio Generator\nCodziennie 07:25: bierze dzisiejszy briefing ze statusem `script_ready`/`audio_failed`, sprawdza budżet ElevenLabs, normalizuje tekst pod odsłuch, dzieli na fragmenty ≤2500 znaków (na granicach zdań), generuje głos (eleven_multilingual_v2), skleja MP3 per rozdział + pełną audycję, wysyła do prywatnego bucketu `audio` i zapisuje `audio_assets` oraz rozdziały z czasami.\nBłąd ⇒ status `audio_failed` — WF06 wyśle wtedy wersję tekstową.',
  [
    schedule('Daily 07:25', '25 7 * * *'),
    manual(),
    loadConfig(),
    sbRpc('Check budget', 'check_budget', '={{ JSON.stringify({ p_provider: "elevenlabs" }) }}'),
    code('Budget gate', 'wf05_budget_gate.js'),
    http('Get briefing', { cred: 'supabase',
      url: `=${SB}/rest/v1/daily_briefings?briefing_date=eq.{{ $now.setZone('Europe/Warsaw').toFormat('yyyy-MM-dd') }}&edition=eq.ai-daily&status=in.(script_ready,audio_failed,audio_generating)&select=id,briefing_date,title,script&limit=1` }),
    sbPatch('Mark generating', '=daily_briefings?id=eq.{{ $json.id }}', '={{ JSON.stringify({ status: "audio_generating" }) }}'),
    code('Prepare TTS', 'wf05_prepare_tts.js'),
    http('ElevenLabs: TTS', { method: 'POST', cred: 'eleven',
      url: '=https://api.elevenlabs.io/v1/text-to-speech/{{ $json.voice_id }}?output_format={{ $json.output_format }}',
      headers: [['Accept', 'audio/mpeg']], body: '={{ JSON.stringify($json.body) }}', responseFile: true, timeout: 180000,
      batch: [1, 300], retryOnFail: true, maxTries: 3, waitBetweenTries: 5000, ...CONTINUE }),
    code('Assemble audio', 'wf05_assemble_audio.js'),
    code('Upload list', 'wf05_upload_list.js'),
    http('Upload to Storage', { method: 'POST', cred: 'supabase', url: `=${SB}/storage/v1/object/audio/{{ $json.storage_path }}`,
      headers: [['x-upsert', 'true'], ['Content-Type', 'audio/mpeg'], ['Cache-Control', 'max-age=31536000']],
      binaryField: 'data', timeout: 120000, batch: [1, 0], ...CONTINUE }),
    code('Asset rows', 'wf05_asset_rows.js'),
    sbInsert('Save audio assets', 'audio_assets', '={{ JSON.stringify($json.rows) }}', { onConflict: 'storage_path', merge: true, returnRows: true }),
    code('Finalize', 'wf05_finalize.js'),
    sbPatch('Mark audio ready', '=daily_briefings?id=eq.{{ $json.briefing_id }}', '={{ JSON.stringify($json.patch) }}'),
    sbInsert('Log usage', 'api_usage', '={{ JSON.stringify($("Finalize").first().json.usage) }}'),
    sbInsert('Log run', 'pipeline_runs', '={{ JSON.stringify($("Finalize").first().json.run) }}'),
    code('Failure', 'wf05_failure.js'),
    sbPatch('Mark audio failed', '=daily_briefings?id=eq.{{ $json.briefing_id }}', '={{ JSON.stringify({ status: "audio_failed", error: $json.error }) }}'),
    sbInsert('Log failure', 'pipeline_runs', '={{ JSON.stringify({ workflow: "WF05_audio_generator", execution_id: String($execution.id), status: "error", error: $("Failure").first().json.error }) }}'),
  ],
  [
    ['Daily 07:25', 'Load config'], ['Run manually', 'Load config'], ['Load config', 'Check budget'], ['Check budget', 'Budget gate'],
    ['Budget gate', 'Get briefing'], ['Get briefing', 'Mark generating'], ['Mark generating', 'Prepare TTS'], ['Prepare TTS', 'ElevenLabs: TTS'],
    ['ElevenLabs: TTS', 'Assemble audio'], ['Assemble audio', 'Upload list'], ['Assemble audio', 'Failure'],
    ['Upload list', 'Upload to Storage'], ['Upload to Storage', 'Asset rows'], ['Asset rows', 'Save audio assets'], ['Save audio assets', 'Finalize'],
    ['Finalize', 'Mark audio ready'], ['Mark audio ready', 'Log usage'], ['Log usage', 'Log run'],
    ['Failure', 'Mark audio failed'], ['Mark audio failed', 'Log failure'],
  ],
  {
    'Daily 07:25': [0, 0], 'Run manually': [0, 1], 'Load config': [1, 0.5], 'Check budget': [2, 0.5], 'Budget gate': [3, 0.5],
    'Get briefing': [4, 0.5], 'Mark generating': [5, 0.5], 'Prepare TTS': [6, 0.5], 'ElevenLabs: TTS': [7, 0.5], 'Assemble audio': [8, 0.5],
    'Upload list': [9, 0], 'Upload to Storage': [10, 0], 'Asset rows': [11, 0], 'Save audio assets': [12, 0], 'Finalize': [13, 0],
    'Mark audio ready': [14, 0], 'Log usage': [15, 0], 'Log run': [16, 0],
    'Failure': [9, 1.3], 'Mark audio failed': [10, 1.3], 'Log failure': [11, 1.3],
  });

// =====================================================================
// WF06 — DELIVERY AND ARCHIVE
// =====================================================================
workflow('WF06_delivery_archive.json', 'NEWSFLOW WF06 – Delivery & Archive',
  '## WF06 – Delivery & Archive\nCodziennie 08:00: pobiera dzisiejszy briefing, tworzy podpisany link do MP3 (ważny 7 dni), renderuje e-mail (szablon `email/briefing.html`) i wysyła go przez Gmail. Brak audio ⇒ wysyła wersję tekstową z informacją o problemie. Brak briefingu ⇒ wysyła alert.\nWęzeł „Sign audio URL” celowo kończy się błędem, gdy nie ma audio (ustawienie Continue).',
  [
    schedule('Daily 08:00', '0 8 * * *'),
    manual(),
    loadConfig(),
    http('Get briefing', { cred: 'supabase', alwaysOutputData: true,
      url: `=${SB}/rest/v1/v_briefings?briefing_date=eq.{{ $now.setZone('Europe/Warsaw').toFormat('yyyy-MM-dd') }}&edition=eq.ai-daily&select=*&limit=1` }),
    code('Prepare delivery', 'wf06_prepare_delivery.js'),
    http('Sign audio URL', { method: 'POST', cred: 'supabase', url: `=${SB}/storage/v1/object/sign/audio/{{ $json.audio_path || '__no_audio__' }}`,
      body: '={{ JSON.stringify({ expiresIn: (($("Load config").first().json.delivery || {}).signed_url_days || 7) * 86400 }) }}',
      alwaysOutputData: true, ...CONTINUE }),
    code('Render email', 'wf06_render_email.js'),
    { name: 'Gmail: send briefing', type: 'n8n-nodes-base.gmail', typeVersion: 2.1,
      parameters: { resource: 'message', operation: 'send', sendTo: '={{ $json.to }}', subject: '={{ $json.subject }}',
        emailType: 'html', message: '={{ $json.html }}', options: { appendAttribution: false } },
      credentials: CRED.gmail },
    sbPatch('Mark delivered', `=daily_briefings?id=eq.{{ $("Render email").first().json.briefing_id || '00000000-0000-0000-0000-000000000000' }}`,
      '={{ JSON.stringify({ status: $("Render email").first().json.status || "failed", email_sent_at: $now.toISO() }) }}'),
    code('Run summary', 'wf06_run_summary.js'),
    logRun(),
  ],
  [
    ['Daily 08:00', 'Load config'], ['Run manually', 'Load config'], ['Load config', 'Get briefing'], ['Get briefing', 'Prepare delivery'],
    ['Prepare delivery', 'Sign audio URL'], ['Sign audio URL', 'Render email'], ['Render email', 'Gmail: send briefing'],
    ['Gmail: send briefing', 'Mark delivered'], ['Mark delivered', 'Run summary'], ['Run summary', 'Log run'],
  ],
  {
    'Daily 08:00': [0, 0], 'Run manually': [0, 1], 'Load config': [1, 0.5], 'Get briefing': [2, 0.5], 'Prepare delivery': [3, 0.5],
    'Sign audio URL': [4, 0.5], 'Render email': [5, 0.5], 'Gmail: send briefing': [6, 0.5], 'Mark delivered': [7, 0.5],
    'Run summary': [8, 0.5], 'Log run': [9, 0.5],
  });

// =====================================================================
// WF99 — ERROR HANDLER
// =====================================================================
workflow('WF99_error_handler.json', 'NEWSFLOW WF99 – Error Handler',
  '## WF99 – Error Handler\nUstaw ten workflow jako **Error workflow** w ustawieniach WF01–WF06. Każdy nieobsłużony błąd trafia do `pipeline_runs` (status `error`) — widać go w aplikacji (Ustawienia → Stan systemu).',
  [
    { name: 'Error Trigger', type: 'n8n-nodes-base.errorTrigger', typeVersion: 1, parameters: {} },
    code('Build error row', 'wf99_error_row.js'),
    logRun(),
  ],
  [['Error Trigger', 'Build error row'], ['Build error row', 'Log run']],
  { 'Error Trigger': [0, 0], 'Build error row': [1, 0], 'Log run': [2, 0] });

console.log(`\nSupabase URL w workflow: ${SB}`);
