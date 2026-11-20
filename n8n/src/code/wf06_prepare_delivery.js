const b = $input.first() ? $input.first().json : {};
if (!b || !b.id) return [{ json: { missing: true, audio_path: null } }];
return [{ json: { ...b, missing: false } }];
