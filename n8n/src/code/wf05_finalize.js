//@lib tts
const assets = $input.all().map((i) => i.json).filter((a) => a && a.id);
const full = assets.find((a) => a.kind === 'briefing_full');
if (!full) throw new Error('Brak zapisanego pliku pełnej audycji');
const chapterAssets = assets.filter((a) => a.kind === 'briefing_chapter').sort((a, b) => a.chapter_index - b.chapter_index);
const chapters = buildChapters(chapterAssets.map((a) => ({
  title: a.title, duration_seconds: Number(a.duration_seconds), audio_asset_id: a.id, story_ids: (a.metadata || {}).story_ids || [],
})));
const characters = chapterAssets.reduce((s, a) => s + (a.characters || 0), 0);
const cost = chapterAssets.reduce((s, a) => s + Number(a.cost_usd || 0), 0);
return [{ json: {
  briefing_id: full.briefing_id,
  patch: { audio_asset_id: full.id, chapters, status: 'audio_ready', error: null },
  usage: [{ workflow: 'WF05_audio_generator', provider: 'elevenlabs', operation: 'tts_briefing', model: full.model_id,
            characters, cost_usd: Math.round(cost * 1e6) / 1e6, briefing_id: full.briefing_id }],
  run: { workflow: 'WF05_audio_generator', execution_id: String($execution.id), status: 'success',
         stats: { chapters: chapters.length, duration_seconds: Number(full.duration_seconds), characters, cost_usd: cost } },
} }];
