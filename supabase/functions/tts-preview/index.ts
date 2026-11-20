// NEWSFLOW — tts-preview
// Generuje krótką próbkę głosu (OpenAI TTS lub ElevenLabs) dla ekranu „Porównanie głosów” w aplikacji.
// Klucze API są wyłącznie w sekretach Edge Functions — aplikacja ich nie zna.
//
// Bezpieczeństwo i koszty:
//  * tylko zalogowani członkowie (app_members),
//  * maks. 1500 znaków na próbkę,
//  * check_budget() przed wywołaniem dostawcy, zapis kosztu w api_usage,
//  * cache: ten sam tekst + dostawca + model + głos => plik z Storage, bez ponownej opłaty.
//
// Sekrety: OPENAI_API_KEY, ELEVENLABS_API_KEY (SUPABASE_URL i SUPABASE_SERVICE_ROLE_KEY są dostępne automatycznie).
import { createClient } from 'npm:@supabase/supabase-js@2';

const MAX_CHARS = 1500;
const BUCKET = 'audio';
const SIGNED_URL_SECONDS = 6 * 3600;
const CHARS_PER_MINUTE = 1050; // ~140 słów/min po polsku

const OPENAI_VOICES = ['alloy', 'ash', 'ballad', 'coral', 'echo', 'fable', 'nova', 'onyx', 'sage', 'shimmer', 'verse'];
const OPENAI_MODELS = ['gpt-4o-mini-tts', 'tts-1', 'tts-1-hd'];
const ELEVEN_MODELS = ['eleven_multilingual_v2', 'eleven_flash_v2_5', 'eleven_turbo_v2_5', 'eleven_v3'];

type Req = {
  provider: 'openai' | 'elevenlabs';
  text: string;
  model?: string;
  voice?: string;
  instructions?: string;
  speed?: number;
};

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

async function sha256(s: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json(405, { error: 'Użyj POST' });

  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  });

  // --- Autoryzacja: zalogowany członek
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  const { data: userData, error: userErr } = await admin.auth.getUser(token);
  if (userErr || !userData?.user) return json(401, { error: 'Brak sesji' });
  const { data: member } = await admin.from('app_members').select('user_id').eq('user_id', userData.user.id).maybeSingle();
  if (!member) return json(403, { error: 'Brak dostępu (app_members)' });

  // --- Walidacja wejścia
  let body: Req;
  try { body = await req.json(); } catch { return json(400, { error: 'Nieprawidłowy JSON' }); }
  const text = String(body.text ?? '').trim();
  if (!text) return json(400, { error: 'Pusty tekst' });
  if (text.length > MAX_CHARS) return json(400, { error: `Tekst dłuższy niż ${MAX_CHARS} znaków` });
  if (body.provider !== 'openai' && body.provider !== 'elevenlabs') return json(400, { error: 'provider: openai | elevenlabs' });

  const { data: cfgRows } = await admin.from('app_config').select('key,value').in('key', ['elevenlabs']);
  const elCfg = (cfgRows?.find((r) => r.key === 'elevenlabs')?.value ?? {}) as Record<string, unknown>;

  let model: string, voice: string;
  if (body.provider === 'openai') {
    model = OPENAI_MODELS.includes(body.model ?? '') ? body.model! : 'gpt-4o-mini-tts';
    voice = OPENAI_VOICES.includes(body.voice ?? '') ? body.voice! : 'coral';
  } else {
    model = ELEVEN_MODELS.includes(body.model ?? '') ? body.model! : String(elCfg.model_id ?? 'eleven_multilingual_v2');
    voice = (body.voice ?? '').trim() || String(elCfg.voice_id ?? '');
    if (!/^[A-Za-z0-9]{10,40}$/.test(voice)) return json(400, { error: 'Podaj poprawne Voice ID ElevenLabs (lub ustaw app_config.elevenlabs.voice_id)' });
  }
  const instructions = body.provider === 'openai' && model === 'gpt-4o-mini-tts'
    ? String(body.instructions ?? '').slice(0, 500) : '';
  const speed = Math.min(1.2, Math.max(0.7, Number(body.speed ?? 1) || 1));

  // --- Cache
  const key = await sha256(JSON.stringify([body.provider, model, voice, instructions, speed, text]));
  const path = `previews/${key}.mp3`;
  const meta = { provider: body.provider, model, voice, characters: text.length };
  const { data: existing } = await admin.storage.from(BUCKET).list('previews', { search: `${key}.mp3`, limit: 1 });
  if (existing && existing.length > 0) {
    const { data: signed } = await admin.storage.from(BUCKET).createSignedUrl(path, SIGNED_URL_SECONDS);
    if (signed?.signedUrl) return json(200, { ...meta, url: signed.signedUrl, cached: true, cost_usd: 0, generation_ms: 0 });
  }

  // --- Budżet
  const { data: budget, error: budgetErr } = await admin.rpc('check_budget', { p_provider: body.provider });
  if (budgetErr) return json(500, { error: 'check_budget: ' + budgetErr.message });
  if (!budget?.allowed) return json(429, { error: 'Limit kosztów osiągnięty', budget });

  // --- Generowanie
  const started = Date.now();
  let audio: ArrayBuffer;
  let cost = 0;
  if (body.provider === 'openai') {
    const apiKey = Deno.env.get('OPENAI_API_KEY');
    if (!apiKey) return json(500, { error: 'Brak sekretu OPENAI_API_KEY' });
    const payload: Record<string, unknown> = { model, voice, input: text, response_format: 'mp3', speed };
    if (instructions) payload.instructions = instructions;
    const r = await fetch('https://api.openai.com/v1/audio/speech', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    if (!r.ok) return json(502, { error: `OpenAI ${r.status}: ${(await r.text()).slice(0, 500)}` });
    audio = await r.arrayBuffer();
    // Szacunek: gpt-4o-mini-tts ≈ 0,015 USD/min; tts-1 = 15 USD/1M znaków; tts-1-hd = 30 USD/1M znaków
    cost = model === 'gpt-4o-mini-tts' ? (text.length / CHARS_PER_MINUTE) * 0.015
      : text.length * (model === 'tts-1-hd' ? 30 : 15) / 1e6;
  } else {
    const apiKey = Deno.env.get('ELEVENLABS_API_KEY');
    if (!apiKey) return json(500, { error: 'Brak sekretu ELEVENLABS_API_KEY' });
    const payload: Record<string, unknown> = {
      text,
      model_id: model,
      voice_settings: { ...((elCfg.voice_settings as object) ?? {}), speed },
    };
    if (/flash|turbo|v3/.test(model)) payload.language_code = 'pl';
    const r = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voice}?output_format=mp3_44100_96`, {
      method: 'POST',
      headers: { 'xi-api-key': apiKey, 'Content-Type': 'application/json', Accept: 'audio/mpeg' },
      body: JSON.stringify(payload),
    });
    if (!r.ok) return json(502, { error: `ElevenLabs ${r.status}: ${(await r.text()).slice(0, 500)}` });
    audio = await r.arrayBuffer();
    const creditFactor = /flash|turbo/.test(model) ? 0.5 : 1;
    cost = (text.length * creditFactor / 1000) * Number(elCfg.usd_per_1k_characters ?? 0.22);
  }
  const generationMs = Date.now() - started;
  cost = Math.round(cost * 1e6) / 1e6;

  // --- Zapis, koszt, URL
  const { error: upErr } = await admin.storage.from(BUCKET).upload(path, audio, { contentType: 'audio/mpeg', upsert: true });
  if (upErr) return json(500, { error: 'Storage: ' + upErr.message });
  await admin.from('api_usage').insert({
    workflow: 'APP_tts_preview', provider: body.provider, operation: 'voice_preview', model,
    characters: text.length, cost_usd: cost, metadata: { voice, generation_ms: generationMs, bytes: audio.byteLength },
  });
  const { data: signed, error: signErr } = await admin.storage.from(BUCKET).createSignedUrl(path, SIGNED_URL_SECONDS);
  if (signErr || !signed) return json(500, { error: 'Signed URL: ' + signErr?.message });

  return json(200, { ...meta, url: signed.signedUrl, cached: false, cost_usd: cost, generation_ms: generationMs, bytes: audio.byteLength });
});
