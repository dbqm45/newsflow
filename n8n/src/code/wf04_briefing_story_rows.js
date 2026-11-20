const saved = $('Save briefing').first().json;
const id = saved.id;
if (!id) throw new Error('Nie udało się zapisać briefingu: ' + JSON.stringify(saved).slice(0, 500));
const sections = $('Assemble briefing').first().json.row.sections;
return [{ json: {
  briefing_id: id,
  rows: sections.map((t) => ({ briefing_id: id, story_id: t.story_id, position: t.position, section: t.section, why_it_matters: t.why_it_matters })),
} }];
