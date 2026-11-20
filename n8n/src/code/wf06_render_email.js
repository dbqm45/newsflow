//@lib email
const TEMPLATE = TEMPLATE_HTML('briefing');
const SUPABASE_URL = '{{SUPABASE_URL}}';
const cfg = $('Load config').first().json;
const D = cfg.delivery || {};
const d = $('Prepare delivery').first().json;
const sign = $input.first() ? $input.first().json : {};
const date = $now.setZone('Europe/Warsaw').toFormat('yyyy-MM-dd');
const datePl = $now.setZone('Europe/Warsaw').toFormat('dd.MM.yyyy');
if (!D.email_to || /^REPLACE/.test(D.email_to)) throw new Error('Ustaw app_config.delivery.email_to');

if (d.missing) {
  return [{ json: {
    to: D.email_to, briefing_id: null, status: null,
    subject: `NEWSFLOW – briefing ${datePl} nie został przygotowany`,
    html: `<p>Dzisiejszy briefing (${escapeHtml(formatDatePl(date))}) nie został wygenerowany.</p>
           <p>Sprawdź tabelę <code>pipeline_runs</code> w Supabase oraz historię wykonań WF03/WF04 w n8n.</p>`,
  } }];
}
const audioUrl = d.audio_path && sign && sign.signedURL ? SUPABASE_URL + '/storage/v1' + sign.signedURL : null;
const notice = audioUrl ? null
  : 'Nagranie audio nie zostało dziś wygenerowane — poniżej pełna wersja tekstowa. Szczegóły w pipeline_runs (WF05).';
const { subject, html } = renderBriefingEmail(TEMPLATE, { ...d, briefing_date_pl: datePl }, {
  audioUrl, notice, signedUrlDays: D.signed_url_days || 7,
  briefingLink: (D.app_url_scheme || 'newsflow://') + 'briefing/' + d.briefing_date,
});
return [{ json: { to: D.email_to, subject, html, briefing_id: d.id, status: audioUrl ? 'delivered' : 'delivered_text_only' } }];
