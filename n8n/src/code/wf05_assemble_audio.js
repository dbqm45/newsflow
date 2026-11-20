//@lib tts
const cfg = $('Load config').first().json;
const el = cfg.elevenlabs || {};
const meta = $('Prepare TTS').all().map((i) => i.json);
const outs = $input.all();
const kbps = bitrateFromFormat(el.output_format || 'mp3_44100_96');
const failed = [];
const chapters = {};
for (let i = 0; i < meta.length; i++) {
  const o = outs[i];
  if (!o || o.json.error || !o.binary || !o.binary.data) { failed.push(`${meta[i].chapter_index}.${meta[i].chunk_index}`); continue; }
  const buf = await this.helpers.getBinaryDataBuffer(i, 'data');
  const ch = (chapters[meta[i].chapter_index] = chapters[meta[i].chapter_index] || { meta: meta[i], bufs: [], chars: 0 });
  ch.bufs.push(ch.bufs.length ? stripId3(buf) : buf);
  ch.chars += meta[i].text.length;
}
const b = meta[0];
if (failed.length) return [{ json: { failed: true, briefing_id: b.briefing_id, error: `Nie wygenerowano fragmentów: ${failed.join(', ')}` } }];

const base = `briefings/${b.briefing_date}/${b.briefing_id}`;
const usdPer1k = el.usd_per_1k_characters || 0.3;
const out = [];
const fullParts = [];
Object.keys(chapters).map(Number).sort((a, c) => a - c).forEach((ci) => {
  const ch = chapters[ci];
  const buf = Buffer.concat(ch.bufs);
  fullParts.push(fullParts.length ? stripId3(buf) : buf);
  out.push({
    json: { kind: 'briefing_chapter', briefing_id: b.briefing_id, chapter_index: ci, title: ch.meta.chapter_title,
      story_ids: ch.meta.story_ids, storage_path: `${base}/chapter-${String(ci + 1).padStart(2, '0')}.mp3`,
      size_bytes: buf.length, duration_seconds: mp3DurationSeconds(buf.length, kbps), characters: ch.chars,
      cost_usd: Math.round((ch.chars / 1000) * usdPer1k * 1e6) / 1e6 },
    binary: { data: { data: buf.toString('base64'), mimeType: 'audio/mpeg', fileName: `chapter-${ci + 1}.mp3`, fileExtension: 'mp3' } },
  });
});
const full = Buffer.concat(fullParts);
out.push({
  json: { kind: 'briefing_full', briefing_id: b.briefing_id, chapter_index: null, title: 'Pełna audycja',
    story_ids: [], storage_path: `${base}/full.mp3`, size_bytes: full.length,
    duration_seconds: mp3DurationSeconds(full.length, kbps), characters: 0, cost_usd: 0 },
  binary: { data: { data: full.toString('base64'), mimeType: 'audio/mpeg', fileName: 'full.mp3', fileExtension: 'mp3' } },
});
return out;
