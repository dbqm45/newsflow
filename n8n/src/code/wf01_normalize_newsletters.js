//@lib text
// Wejście: wiadomości z węzła Gmail (etykieta AI-READ). Jeśli węzeł Gmail jest wyłączony,
// dostajemy tu wiersz źródła — wtedy nic nie robimy.
const src = $('Get Gmail source').first().json;
const msgs = $input.all().map((i) => i.json)
  .filter((m) => m && m.id && m.subject !== undefined && (m.html || m.text || m.textAsHtml));
if (!msgs.length) return [];

const SKIP_LINK = /unsubscribe|wypisz|manage.*preferences|mailto:|list-manage|\/open\?|pixel|tracking|view.*browser|privacy|facebook\.com|twitter\.com\/intent|linkedin\.com\/share/i;
const rows = msgs.map((m) => {
  const htmlText = htmlToText(m.html || m.textAsHtml || '');
  const text = wordCount(m.text) > wordCount(htmlText) * 0.7 ? String(m.text) : htmlText;
  const links = [];
  const re = /href=["'](https?:\/\/[^"']+)["']/gi;
  let mm;
  while ((mm = re.exec(m.html || '')) && links.length < 40) {
    const u = decodeEntities(mm[1]);
    if (!SKIP_LINK.test(u) && !links.includes(u)) links.push(u);
  }
  const from = m.from && (m.from.text || (m.from.value && m.from.value[0] && (m.from.value[0].name || m.from.value[0].address)));
  const d = m.date ? new Date(m.date) : new Date();
  return {
    source_id: src.id,
    external_id: String(m.id),
    title: String(m.subject || '(bez tematu)').slice(0, 500),
    original_url: 'https://mail.google.com/mail/u/0/#all/' + (m.threadId || m.id),
    author: from ? String(from).slice(0, 200) : null,
    published_at: isNaN(d.getTime()) ? null : d.toISOString(),
    description: text.slice(0, 500),
    original_content: truncate(text, 60000),
    content_hash: sha256('gmail:' + (m.messageId || m.id)),
    language: null,
    visibility: 'private',
    word_count: wordCount(text),
    extraction_status: 'extracted',
    metadata: { gmail_id: m.id, links, newsletter: true },
  };
});
return [{ json: { rows, count: rows.length } }];
