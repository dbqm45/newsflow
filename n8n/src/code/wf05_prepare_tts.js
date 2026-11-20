//@lib tts
const cfg = $('Load config').first().json;
const el = cfg.elevenlabs || {};
const b = $('Get briefing').first().json;
const budget = $('Budget gate').first().json.budget;
if (!el.voice_id || /^REPLACE/.test(el.voice_id)) throw new Error('Ustaw app_config.elevenlabs.voice_id (polski głos z ElevenLabs Voice Library)');
if (!b.script || !Array.isArray(b.script.chapters) || !b.script.chapters.length) throw new Error('Briefing nie ma scenariusza audio');

const items = [];
b.script.chapters.forEach((ch, ci) => {
  const text = prepareForSpeech(ch.text);
  chunkText(text, el.max_chunk_chars || 2500).forEach((chunk, k) => {
    items.push({ briefing_id: b.id, briefing_date: b.briefing_date, chapter_index: ci, chunk_index: k,
      chapter_title: ch.title, chapter_kind: ch.kind, story_ids: ch.story_ids || [], text: chunk });
  });
});
const totalChars = items.reduce((a, it) => a + it.text.length, 0);
const monthlyLimit = budget.limits && budget.limits.monthly_characters;
if (monthlyLimit && Number(budget.month_characters) + totalChars > monthlyLimit) {
  throw new Error(`Przekroczony miesięczny limit znaków ElevenLabs (${budget.month_characters} + ${totalChars} > ${monthlyLimit})`);
}
const modelId = el.model_id || 'eleven_multilingual_v2';
return items.map((it, i) => {
  const body = { text: it.text, model_id: modelId, voice_settings: el.voice_settings || {} };
  if (i > 0 && items[i - 1].chapter_index === it.chapter_index) body.previous_text = items[i - 1].text.slice(-400);
  if (i < items.length - 1 && items[i + 1].chapter_index === it.chapter_index) body.next_text = items[i + 1].text.slice(0, 400);
  if (/flash|turbo|v3/.test(modelId)) body.language_code = 'pl';
  return { json: { ...it, voice_id: el.voice_id, output_format: el.output_format || 'mp3_44100_96', total_characters: totalChars, body } };
});
