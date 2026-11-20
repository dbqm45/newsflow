-- Aplikacja pokazuje tekst audycji (scenariusz) w odtwarzaczu — dodajemy kolumnę script do widoku v_briefings.
-- "create or replace view" pozwala dopisać kolumnę na końcu bez zmiany pozostałych.
create or replace view public.v_briefings with (security_invoker = true) as
select
  b.id, b.briefing_date, b.edition, b.title, b.summary, b.text_content, b.sections, b.trends, b.stats, b.chapters,
  b.status, b.items_considered, b.items_analyzed, b.items_rejected, b.created_at, b.email_sent_at,
  b.audio_asset_id,
  aa.storage_path     as audio_path,
  aa.duration_seconds as audio_duration_seconds,
  (select pp.position_seconds from public.playback_progress pp
    where pp.audio_asset_id = b.audio_asset_id and pp.user_id = auth.uid()) as my_position_seconds,
  exists (select 1 from public.saved_items sv
    where sv.briefing_id = b.id and sv.user_id = auth.uid()) as is_saved,
  b.script
from public.daily_briefings b
left join public.audio_assets aa on aa.id = b.audio_asset_id and aa.status = 'ready';
