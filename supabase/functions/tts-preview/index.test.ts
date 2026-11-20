// Test funkcji tts-preview z atrapami Supabase (auth/PostgREST/Storage), OpenAI i ElevenLabs.
// Uruchom (w katalogu funkcji, z deno.json {"nodeModulesDir":"auto"}): deno test --allow-env index.test.ts
import { assertEquals, assert } from 'jsr:@std/assert@1';

Deno.env.set('SUPABASE_URL', 'https://test.supabase.co');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'service');
Deno.env.set('OPENAI_API_KEY', 'sk-test');
Deno.env.set('ELEVENLABS_API_KEY', 'el-test');

let handler: (r: Request) => Promise<Response>;
// deno-lint-ignore no-explicit-any
(Deno as any).serve = (h: typeof handler) => { handler = h; };

const state = { member: true, allowed: true, cached: false, calls: [] as string[], usage: [] as unknown[] };
const ok = (body: unknown) => new Response(JSON.stringify(body), { status: 200, headers: { 'Content-Type': 'application/json' } });

globalThis.fetch = async (input: string | URL | Request, init?: RequestInit) => {
  const req = new Request(input, init);
  const u = new URL(req.url);
  state.calls.push(`${req.method} ${u.host}${u.pathname}`);
  if (u.pathname === '/auth/v1/user') return ok({ id: 'u1', aud: 'authenticated', email: 'a@b.c' });
  if (u.pathname === '/rest/v1/app_members') return state.member ? ok({ user_id: 'u1' }) : new Response('', { status: 406 });
  if (u.pathname === '/rest/v1/app_config') return ok([{ key: 'elevenlabs', value: { voice_id: 'abcdefghij1234567890', usd_per_1k_characters: 0.22 } }]);
  if (u.pathname === '/rest/v1/rpc/check_budget') return ok({ allowed: state.allowed });
  if (u.pathname === '/rest/v1/api_usage') { state.usage.push(await req.json()); return new Response(null, { status: 201 }); }
  if (u.pathname === '/storage/v1/object/list/audio') return ok(state.cached ? [{ name: 'x.mp3' }] : []);
  if (u.pathname.startsWith('/storage/v1/object/sign/audio/')) return ok({ signedURL: '/object/sign/audio/previews/x.mp3?token=t' });
  if (u.pathname.startsWith('/storage/v1/object/audio/')) return ok({ Key: 'audio/previews/x.mp3' });
  if (u.host === 'api.openai.com') {
    const b = await req.json();
    assertEquals(b.response_format, 'mp3');
    assert(b.instructions?.includes('lektor'));
    return new Response(new Uint8Array(1000), { status: 200 });
  }
  if (u.host === 'api.elevenlabs.io') {
    assertEquals(req.headers.get('xi-api-key'), 'el-test');
    const b = await req.json();
    assertEquals(b.language_code, 'pl');
    return new Response(new Uint8Array(2000), { status: 200 });
  }
  return new Response('unexpected ' + req.url, { status: 500 });
};

await import('./index.ts');

const call = (body: unknown) => handler(new Request('https://fn/tts-preview', {
  method: 'POST', headers: { Authorization: 'Bearer user-jwt', 'Content-Type': 'application/json' }, body: JSON.stringify(body),
}));

Deno.test('OpenAI: generuje, zapisuje koszt, zwraca podpisany URL', async () => {
  state.usage = [];
  const r = await call({ provider: 'openai', text: 'Dzień dobry. '.repeat(80), voice: 'nova', instructions: 'Mów jak lektor.' });
  const j = await r.json();
  assertEquals(r.status, 200, JSON.stringify(j));
  assertEquals(j.cached, false);
  assert(j.url.startsWith('https://test.supabase.co/storage/v1/object/sign/audio/'));
  assert(j.cost_usd > 0);
  assertEquals((state.usage[0] as { provider: string }).provider, 'openai');
});

Deno.test('ElevenLabs flash: połowa kredytów, voice z app_config', async () => {
  state.usage = [];
  const r = await call({ provider: 'elevenlabs', model: 'eleven_flash_v2_5', text: 'x'.repeat(1000) });
  const j = await r.json();
  assertEquals(r.status, 200, JSON.stringify(j));
  assertEquals(j.voice, 'abcdefghij1234567890');
  assertEquals(j.cost_usd, 0.11);
});

Deno.test('Cache: bez wywołania dostawcy i bez kosztu', async () => {
  state.cached = true; state.calls = [];
  const j = await (await call({ provider: 'elevenlabs', text: 'abc' })).json();
  state.cached = false;
  assertEquals(j.cached, true);
  assertEquals(j.cost_usd, 0);
  assert(!state.calls.some((c) => c.includes('elevenlabs.io')));
});

Deno.test('Odmowy: limit budżetu, brak członkostwa, za długi tekst', async () => {
  state.allowed = false;
  assertEquals((await call({ provider: 'openai', text: 'abc' })).status, 429);
  state.allowed = true;
  assertEquals((await call({ provider: 'openai', text: 'x'.repeat(1501) })).status, 400);
  state.member = false;
  assertEquals((await call({ provider: 'openai', text: 'abc' })).status, 403);
  state.member = true;
});
