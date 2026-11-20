const cfg = $('Load config').first().json;
const el = cfg.elevenlabs || {};
const files = $('Upload list').all().map((i) => i.json);
const resps = $input.all().map((i) => i.json);
const errors = resps.map((r, i) => (r && r.error ? `${files[i].storage_path}: ${r.error.message || JSON.stringify(r.error)}` : null)).filter(Boolean);
if (errors.length) throw new Error('Upload do Supabase Storage nie powiódł się: ' + errors.join('; '));
const rows = files.map((f) => ({
  kind: f.kind, briefing_id: f.briefing_id, chapter_index: f.chapter_index, title: f.title, storage_path: f.storage_path,
  duration_seconds: f.duration_seconds, size_bytes: f.size_bytes, voice_id: el.voice_id, model_id: el.model_id,
  language: 'pl', characters: f.characters, cost_usd: f.cost_usd, ai_generated: true, status: 'ready', error: null,
  metadata: { story_ids: f.story_ids, output_format: el.output_format },
}));
return [{ json: { rows } }];
