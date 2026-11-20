// NEWSFLOW — parser RSS 2.0 / Atom / YouTube / Reddit / podcastów (bez zależności).
// Wymaga: text.cjs (decodeEntities, stripCdata, htmlToText)

function _tag(block, name) {
  const re = new RegExp(`<${name}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/${name}>`, 'i');
  const m = block.match(re);
  return m ? decodeEntities(stripCdata(m[1])).trim() : null;
}
function _rawTag(block, name) {
  const re = new RegExp(`<${name}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/${name}>`, 'i');
  const m = block.match(re);
  return m ? stripCdata(m[1]).trim() : null;
}
function _attr(block, tagName, attr, where) {
  const re = new RegExp(`<${tagName}\\b[^>]*>`, 'gi');
  const tags = block.match(re) || [];
  for (const t of tags) {
    if (where && !where(t)) continue;
    const m = t.match(new RegExp(`\\b${attr}=["']([^"']*)["']`, 'i'));
    if (m) return decodeEntities(m[1]);
  }
  return null;
}
function _date(s) {
  if (!s) return null;
  const d = new Date(s);
  return isNaN(d.getTime()) ? null : d.toISOString();
}
function _duration(s) {
  if (!s) return null;
  if (/^\d+$/.test(s)) return parseInt(s, 10);
  const p = s.split(':').map(Number);
  if (p.some(isNaN)) return null;
  return p.reduce((acc, v) => acc * 60 + v, 0);
}

function parseFeed(xml, opts) {
  opts = opts || {};
  const maxItems = opts.maxItems || 30;
  xml = String(xml || '');
  const isAtom = /<feed\b[^>]*xmlns=["']http:\/\/www\.w3\.org\/2005\/Atom["']/i.test(xml) || (/<entry\b/i.test(xml) && !/<item\b/i.test(xml));
  const blocks = xml.match(isAtom ? /<entry\b[\s\S]*?<\/entry>/gi : /<item\b[\s\S]*?<\/item>/gi) || [];
  const items = [];
  for (const b of blocks.slice(0, maxItems)) {
    let url, externalId, description, content, author, published, mediaUrl = null, transcriptUrl = null, duration = null;
    const title = htmlToText(_tag(b, 'title') || '');
    if (isAtom) {
      url = _attr(b, 'link', 'href', (t) => !/rel=["'](?!alternate)/i.test(t)) || _attr(b, 'link', 'href');
      externalId = _tag(b, 'yt:videoId') || _tag(b, 'id');
      const rawContent = _rawTag(b, 'content');
      content = rawContent ? htmlToText(decodeEntities(rawContent)) : null;
      description = htmlToText(_tag(b, 'media:description') || _tag(b, 'summary') || '');
      author = _tag(b, 'name');
      published = _tag(b, 'published') || _tag(b, 'updated');
    } else {
      url = _tag(b, 'link') || _attr(b, 'link', 'href');
      externalId = _tag(b, 'guid') || url;
      const rawContent = _rawTag(b, 'content:encoded');
      content = rawContent ? htmlToText(decodeEntities(rawContent)) : null;
      description = htmlToText(decodeEntities(_rawTag(b, 'description') || _rawTag(b, 'itunes:summary') || ''));
      author = _tag(b, 'dc:creator') || _tag(b, 'author') || _tag(b, 'itunes:author');
      published = _tag(b, 'pubDate') || _tag(b, 'dc:date');
      mediaUrl = _attr(b, 'enclosure', 'url');
      transcriptUrl = _attr(b, 'podcast:transcript', 'url', (t) => /text\/(plain|html|vtt)|application\/(x-subrip|srt)/i.test(t)) ||
        _attr(b, 'podcast:transcript', 'url');
      duration = _duration(_tag(b, 'itunes:duration'));
    }
    if (!url || !title) continue;
    items.push({
      external_id: externalId ? String(externalId).slice(0, 500) : null,
      title: title.slice(0, 500),
      url: url.trim(),
      author: author ? author.slice(0, 200) : null,
      published_at: _date(published),
      description: description ? description.slice(0, 5000) : null,
      content: content || null,
      media_url: mediaUrl,
      transcript_url: transcriptUrl,
      duration_seconds: duration,
    });
  }
  return { format: isAtom ? 'atom' : 'rss', items };
}

/* @exports — wszystko poniżej jest usuwane przez build.mjs */
const t = require('./text.cjs');
Object.assign(globalThis, t);
module.exports = { parseFeed };
