// NEWSFLOW — renderowanie e-maila z briefingiem (szablon: email/briefing.html)

function escapeHtml(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function fillTemplate(tpl, vars) {
  return tpl.replace(/\{\{(\w+)\}\}/g, (m, k) => (vars[k] == null ? '' : String(vars[k])));
}

function formatDatePl(isoDate) {
  const months = ['stycznia', 'lutego', 'marca', 'kwietnia', 'maja', 'czerwca', 'lipca', 'sierpnia', 'września', 'października', 'listopada', 'grudnia'];
  const days = ['niedziela', 'poniedziałek', 'wtorek', 'środa', 'czwartek', 'piątek', 'sobota'];
  const d = new Date(isoDate + 'T12:00:00Z');
  return `${days[d.getUTCDay()]}, ${d.getUTCDate()} ${months[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
}

function formatDuration(sec) {
  if (!sec) return '';
  const m = Math.floor(sec / 60), s = Math.round(sec % 60);
  return `${m}:${String(s).padStart(2, '0')}`;
}

function sourcesHtml(sources) {
  if (!sources || !sources.length) return '';
  return '<div style="margin-top:8px;font-size:13px;line-height:1.7;">Źródła: ' + sources.map((s) =>
    `<a href="${escapeHtml(s.url)}" style="color:#4f46e5;text-decoration:none;">${escapeHtml(s.source || s.title)}</a>`).join(' · ') + '</div>';
}

function topicHtml(t, n) {
  const row = (label, text) => text ? `<div style="margin-top:8px;font-size:14px;line-height:1.55;color:#3f3f46;"><b>${label}:</b> ${escapeHtml(text)}</div>` : '';
  return `<tr><td style="padding:16px 28px 4px;">
    <div style="font-size:12px;color:#a1a1aa;">${n}. ${escapeHtml(t.subcategory || '')}</div>
    <div style="font-size:17px;font-weight:700;line-height:1.35;margin-top:2px;">${escapeHtml(t.headline)}</div>
    <div style="margin-top:6px;font-size:15px;line-height:1.6;color:#27272a;">${escapeHtml(t.summary)}</div>
    ${row('Dlaczego to ważne', t.why_it_matters)}
    ${row('Zastosowanie w praktyce', t.practical_use)}
    ${row('Uwaga – rozbieżności', t.discrepancies)}
    ${sourcesHtml(t.sources)}
  </td></tr>`;
}

function renderBriefingEmail(tpl, b, opts) {
  opts = opts || {};
  const sections = b.sections || [];
  const headline = sections.find((s) => s.section === 'headline');
  const others = sections.filter((s) => s !== headline);
  const stats = b.stats || {};
  const audioBlock = opts.audioUrl
    ? `<tr><td style="padding:20px 28px 0;"><a href="${escapeHtml(opts.audioUrl)}" style="display:block;background:#4f46e5;color:#fff;text-decoration:none;border-radius:10px;padding:14px 18px;font-weight:600;font-size:16px;">▶ Posłuchaj audycji${b.audio_duration_seconds ? ' (' + formatDuration(b.audio_duration_seconds) + ')' : ''}</a>
       <div style="font-size:12px;color:#71717a;margin-top:6px;">Link ważny ${opts.signedUrlDays || 7} dni. W aplikacji NEWSFLOW nagranie jest zawsze dostępne.</div></td></tr>`
    : '';
  const notice = opts.notice
    ? `<tr><td style="padding:16px 28px 0;"><div style="background:#fef3c7;border-radius:10px;padding:12px 14px;font-size:14px;color:#92400e;">${escapeHtml(opts.notice)}</div></td></tr>`
    : '';
  const headlineBlock = headline
    ? `<tr><td style="padding:12px 28px 16px;"><div style="border-left:4px solid #6366f1;background:#eef2ff;border-radius:8px;padding:14px 16px;">
        <div style="font-size:12px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:#4f46e5;">Najważniejsza informacja dnia</div>
        <div style="font-size:19px;font-weight:700;line-height:1.35;margin-top:4px;">${escapeHtml(headline.headline)}</div>
        <div style="margin-top:6px;font-size:15px;line-height:1.6;">${escapeHtml(headline.summary)}</div>
        ${headline.why_it_matters ? `<div style="margin-top:8px;font-size:14px;line-height:1.55;"><b>Dlaczego to ważne:</b> ${escapeHtml(headline.why_it_matters)}</div>` : ''}
        ${headline.practical_use ? `<div style="margin-top:8px;font-size:14px;line-height:1.55;"><b>Zastosowanie:</b> ${escapeHtml(headline.practical_use)}</div>` : ''}
        ${sourcesHtml(headline.sources)}</div></td></tr>`
    : '';
  const trends = b.trends
    ? `<tr><td style="padding:16px 28px 0;"><div style="font-size:13px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:#6366f1;">Trendy i wnioski</div>
       <div style="margin-top:6px;font-size:15px;line-height:1.6;">${escapeHtml(b.trends)}</div></td></tr>`
    : '';
  const subject = `NEWSFLOW – AI Intelligence Briefing – ${b.briefing_date_pl || b.briefing_date}`;
  const html = fillTemplate(tpl, {
    subject: escapeHtml(subject),
    preheader: escapeHtml((headline && headline.headline) || b.summary || ''),
    title: escapeHtml(b.title),
    date_long: escapeHtml(formatDatePl(b.briefing_date)),
    lead: escapeHtml(b.summary || ''),
    audio_block: audioBlock,
    notice_block: notice,
    headline_block: headlineBlock,
    topics_block: others.map((t, i) => topicHtml(t, i + 1)).join('\n') || '<tr><td style="padding:16px 28px;color:#71717a;">Brak dodatkowych tematów.</td></tr>',
    trends_block: trends,
    stats_analyzed: stats.analyzed ?? b.items_analyzed ?? 0,
    stats_rejected: stats.rejected ?? b.items_rejected ?? 0,
    stats_incomplete: stats.incomplete ?? 0,
    stats_collected: stats.collected ?? b.items_considered ?? 0,
    briefing_link: escapeHtml(opts.briefingLink || '#'),
  });
  return { subject, html };
}

/* @exports — wszystko poniżej jest usuwane przez build.mjs */
module.exports = { escapeHtml, fillTemplate, formatDatePl, formatDuration, renderBriefingEmail };
