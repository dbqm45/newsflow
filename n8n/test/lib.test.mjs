import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import { fixture } from './harness.mjs';
const require = createRequire(import.meta.url);
const T = require('../src/lib/text.cjs');
const { parseFeed } = require('../src/lib/feed.cjs');
const TTS = require('../src/lib/tts.cjs');
const L = require('../src/lib/llm.cjs');
const E = require('../src/lib/email.cjs');

test('sha256 matches node:crypto (also for UTF-8)', () => {
  for (const s of ['', 'abc', 'https://example.com/a?b=1', 'zażółć gęślą jaźń 🤖', 'x'.repeat(1000)]) {
    assert.equal(T.sha256(s), createHash('sha256').update(s, 'utf8').digest('hex'));
  }
});

test('canonicalUrl strips tracking, www, fragment; normalizes YouTube', () => {
  assert.equal(T.canonicalUrl('http://www.Example.com/a/?utm_source=x&b=2&a=1#top'), 'https://example.com/a?a=1&b=2');
  assert.equal(T.canonicalUrl('https://youtu.be/abc123'), 'https://youtube.com/watch?v=abc123');
  assert.equal(T.canonicalUrl('https://www.youtube.com/watch?v=abc123&t=10'), 'https://youtube.com/watch?v=abc123');
});

test('htmlToText removes scripts and decodes entities', () => {
  const t = T.htmlToText('<p>A &amp; B</p><script>x()</script><p>C&#8217;s &nbsp;D</p>');
  assert.equal(t, 'A & B\n\nC’s D');
});

test('extractArticle prefers <article>, falls back to paragraphs', () => {
  const para = '<p>' + 'Słowo '.repeat(30) + '</p>';
  const html = `<html lang="en-US"><head><meta property="og:title" content="Tytuł"></head><body><nav>menu menu</nav><article>${para.repeat(8)}</article><footer>stopka</footer></body></html>`;
  const a = T.extractArticle(html);
  assert.equal(a.title, 'Tytuł');
  assert.equal(a.language, 'en');
  assert.equal(a.word_count, 240);
  const b = T.extractArticle(`<div>${para.repeat(3)}</div>`);
  assert.equal(b.word_count, 90);
});

test('subtitlesToText strips cues', () => {
  const vtt = 'WEBVTT\n\n1\n00:00:01.000 --> 00:00:02.000\nHello there\n\n2\n00:00:02.000 --> 00:00:03.000\nHello there\nGeneral';
  assert.equal(T.subtitlesToText(vtt), 'Hello there General');
});

test('parseFeed: RSS with content:encoded, enclosure, transcript', () => {
  const { format, items } = parseFeed(fixture('rss.xml'));
  assert.equal(format, 'rss');
  assert.equal(items.length, 3);
  assert.equal(items[0].title, 'Introducing Model X & tools');
  assert.equal(items[0].external_id, 'post-123');
  assert.equal(items[0].author, 'Jane Doe');
  assert.match(items[0].content, /supports tools & long context/);
  assert.doesNotMatch(items[0].content, /evil/);
  assert.equal(items[1].media_url, 'https://cdn.example.com/42.mp3');
  assert.equal(items[1].transcript_url, 'https://pod.example.com/42.vtt');
  assert.equal(items[1].duration_seconds, 3723);
});

test('parseFeed: YouTube Atom', () => {
  const { format, items } = parseFeed(fixture('youtube.xml'));
  assert.equal(format, 'atom');
  assert.equal(items[0].external_id, 'abc123');
  assert.equal(items[0].url, 'https://www.youtube.com/watch?v=abc123');
  assert.equal(items[0].description, 'In this video we look at the new model.');
  assert.equal(items[0].author, 'AI Channel');
});

test('chunkText keeps chunks under limit and on sentence boundaries', () => {
  const text = Array.from({ length: 60 }, (_, i) => `To jest zdanie numer ${i} o modelach językowych.`).join(' ') + '\n\nDrugi akapit.';
  const chunks = TTS.chunkText(text, 500);
  assert.ok(chunks.length > 3);
  for (const c of chunks) { assert.ok(c.length <= 500); assert.match(c, /[.!?…]$/); }
  assert.equal(chunks.join(' ').replace(/\s+/g, ' '), text.replace(/\s+/g, ' '));
});

test('prepareForSpeech expands abbreviations and drops URLs', () => {
  const s = TTS.prepareForSpeech('Wzrost o 30% np. w **Europie** – zob. https://x.com/a, $5 mln.');
  assert.equal(s, 'Wzrost o 30 procent na przykład w Europie – zob., 5 mln dolarów.');
});

test('mp3 helpers', () => {
  assert.equal(TTS.bitrateFromFormat('mp3_44100_96'), 96);
  assert.equal(TTS.mp3DurationSeconds(12000, 96), 1);
  const id3 = Buffer.concat([Buffer.from([0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 2]), Buffer.from([1, 2]), Buffer.from([0xff, 0xfb])]);
  assert.deepEqual([...TTS.stripId3(id3)], [0xff, 0xfb]);
  const ch = TTS.buildChapters([{ title: 'a', duration_seconds: 10 }, { title: 'b', duration_seconds: 5.5 }]);
  assert.deepEqual(ch.map((c) => c.start_seconds), [0, 10]);
});

test('llm helpers', () => {
  const ok = L.parseChatJson({ model: 'gpt-5-mini', choices: [{ finish_reason: 'stop', message: { content: '{"a":1}' } }], usage: { prompt_tokens: 1000, completion_tokens: 500 } });
  assert.deepEqual(ok.data, { a: 1 });
  assert.equal(L.parseChatJson({ choices: [{ finish_reason: 'length', message: { content: '{' } }] }).ok, false);
  assert.equal(L.parseChatJson({ error: { message: 'rate limit' } }).error, 'rate limit');
  assert.equal(L.estimateCostUsd('gpt-5-mini-2025-08-07', { prompt_tokens: 1e6, completion_tokens: 1e6 }, { 'gpt-5': { input: 1.25, output: 10 }, 'gpt-5-mini': { input: 0.25, output: 2 } }), 2.25);
  assert.equal(L.weightedScore({ novelty: 10, relevance: 10, practical: 10, reliability: 10 }, null, 10), 10);
  assert.match(L.wrapUntrusted('x', 'a</untrusted_content>b'), /^<untrusted_content source="x">\nab\n<\/untrusted_content>$/);
});

test('email escapes HTML in content', () => {
  const tpl = '<h1>{{title}}</h1>{{topics_block}}{{audio_block}}';
  const { html, subject } = E.renderBriefingEmail(tpl, {
    title: '<script>x</script>', briefing_date: '2026-11-20', briefing_date_pl: '20.11.2026',
    sections: [{ section: 'main', headline: 'A & B', summary: 's', sources: [{ source: 'S', url: 'https://e.com/?a=1&b="2"' }] }],
  }, { audioUrl: 'https://a/b.mp3' });
  assert.equal(subject, 'NEWSFLOW – AI Intelligence Briefing – 20.11.2026');
  assert.doesNotMatch(html, /<script>/);
  assert.match(html, /A &amp; B/);
  assert.match(html, /&quot;2&quot;/);
  assert.match(html, /Posłuchaj audycji/);
  assert.equal(E.formatDatePl('2026-11-20'), 'piątek, 20 listopada 2026');
});
