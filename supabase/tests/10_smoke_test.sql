-- Test dymny: przepływ materiał -> analiza -> wydarzenie -> kandydaci -> RLS
\set ON_ERROR_STOP on
begin;
insert into auth.users values ('00000000-0000-0000-0000-000000000001', 'owner@example.com'),
                              ('00000000-0000-0000-0000-000000000002', 'stranger@example.com');
insert into public.app_members (user_id) values ('00000000-0000-0000-0000-000000000001');

-- dwa materiały o tym samym wydarzeniu z dwóch źródeł + jeden inny
insert into public.content_items (id, source_id, title, original_url, content_hash, published_at, original_content, extraction_status)
select v.id::uuid, (select id from public.sources where name = v.src), v.title, v.url, md5(v.url), now(), 'tekst', 'extracted'
from (values
  ('10000000-0000-0000-0000-000000000001', 'OpenAI News',  'Model X released', 'https://a.example/x'),
  ('10000000-0000-0000-0000-000000000002', 'The Verge AI', 'OpenAI ships Model X', 'https://b.example/x'),
  ('10000000-0000-0000-0000-000000000003', 'Hugging Face Blog', 'New dataset', 'https://c.example/y')
) v(id, src, title, url);

select count(*) as claimed from public.claim_items_for_analysis(10);
select public.apply_analysis_status('[{"id":"10000000-0000-0000-0000-000000000003","status":"analyzed"}]');
select public.apply_extraction_results('[{"id":"10000000-0000-0000-0000-000000000003","status":"extracted","word_count":321,"metadata":{"x":1}}]');
do $$ begin if (select word_count from public.content_items where id='10000000-0000-0000-0000-000000000003') <> 321
  then raise exception 'apply_extraction_results failed'; end if; end $$;

insert into public.analyses (content_item_id, is_relevant, title_pl, summary, novelty_score, relevance_score,
  practical_score, reliability_score, importance_score, subcategory_slug, analysis_model, prompt_version)
select id, true, 'Tytuł ' || title, 'Streszczenie', 8, 9, 6, 8,
  public.weighted_score(8, 9, 6, 8, 2), 'llm', 'test', 'v1'
from public.content_items;

-- embeddingi: dwa prawie identyczne, trzeci ortogonalny
select public.assign_item_to_story('10000000-0000-0000-0000-000000000001',
  (select ('[' || string_agg(case when i = 1 then '1' else '0' end, ',') || ']') from generate_series(1,1536) i)::extensions.vector);
select public.assign_item_to_story('10000000-0000-0000-0000-000000000002',
  (select ('[' || string_agg(case when i = 1 then '0.99' when i = 2 then '0.05' else '0' end, ',') || ']') from generate_series(1,1536) i)::extensions.vector);
select public.assign_item_to_story('10000000-0000-0000-0000-000000000003',
  (select ('[' || string_agg(case when i = 3 then '1' else '0' end, ',') || ']') from generate_series(1,1536) i)::extensions.vector);

do $$ declare n int; c numeric; begin
  select count(*) into n from public.stories;
  if n <> 2 then raise exception 'expected 2 stories, got %', n; end if;
  select corroboration_score into c from public.stories where source_count = 2;
  if c <> 4 then raise exception 'expected corroboration 4, got %', c; end if;
end $$;

select story_id, title, importance_score, adjusted_score, source_count from public.get_briefing_candidates(24, 10);
select public.briefing_stats(24);
select public.check_budget('openai');
select public.get_config() ? 'models' as has_models;

-- RLS: obcy użytkownik nic nie widzi, właściciel widzi
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
do $$ begin if (select count(*) from public.v_feed) <> 0 then raise exception 'RLS leak'; end if; end $$;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
do $$ begin if (select count(*) from public.v_feed) <> 3 then raise exception 'owner cannot read feed'; end if; end $$;
select public.set_feedback('10000000-0000-0000-0000-000000000001', -1);
select public.set_feedback('10000000-0000-0000-0000-000000000001', 1);
do $$ begin if not public.toggle_saved('10000000-0000-0000-0000-000000000002') then raise exception 'toggle 1'; end if; end $$;
do $$ begin if public.toggle_saved('10000000-0000-0000-0000-000000000002') then raise exception 'toggle 2'; end if; end $$;
do $$ begin if not public.toggle_saved('10000000-0000-0000-0000-000000000001') then raise exception 'toggle 3'; end if; end $$;
reset role;
insert into public.audio_assets (id, kind, storage_path, status) values ('20000000-0000-0000-0000-000000000001', 'briefing_full', 'x/full.mp3', 'ready');
set local role authenticated;
select public.save_progress('20000000-0000-0000-0000-000000000001', 42.5);
select public.save_progress('20000000-0000-0000-0000-000000000001', 50, true);
do $$ begin if (select position_seconds from public.playback_progress) <> 50 then raise exception 'progress'; end if; end $$;
select title, my_rating, is_saved from public.v_feed where my_rating is not null;
reset role;
rollback;
\echo SMOKE TEST OK
