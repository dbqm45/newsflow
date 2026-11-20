-- =====================================================================
-- NEWSFLOW Personal 0.1 — schemat bazy danych (Supabase / PostgreSQL)
-- =====================================================================
-- Zasady:
--  * Materiały źródłowe, analizy, nagrania i dane użytkownika są w
--    osobnych tabelach (łatwa rozbudowa do platformy wieloużytkownikowej).
--  * n8n pisze do bazy kluczem "secret" (rola service_role, omija RLS).
--  * Aplikacja iOS loguje się jako zwykły użytkownik (rola authenticated)
--    i widzi dane tylko jeśli jest w tabeli app_members.
--  * Treści z newsletterów (Gmail) mają visibility = 'private'.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;
create extension if not exists vector   with schema extensions;
create extension if not exists pg_trgm  with schema extensions;

-- ---------------------------------------------------------------------
-- Typy wyliczeniowe
-- ---------------------------------------------------------------------
create type public.source_type as enum (
  'rss', 'youtube', 'medium', 'blog', 'web', 'podcast', 'reddit', 'gmail', 'x', 'linkedin'
);
create type public.visibility as enum ('public', 'private');
create type public.extraction_status as enum (
  'pending', 'processing', 'extracted', 'incomplete', 'failed', 'skipped'
);
create type public.analysis_status as enum (
  'pending', 'processing', 'analyzed', 'rejected', 'failed', 'skipped'
);
create type public.briefing_status as enum (
  'draft', 'script_ready', 'audio_generating', 'audio_ready', 'audio_failed',
  'delivered', 'delivered_text_only', 'failed'
);
create type public.asset_status as enum ('pending', 'generating', 'ready', 'failed');

-- ---------------------------------------------------------------------
-- Funkcje pomocnicze
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------
-- Członkowie (w 0.1: jedna osoba — właściciel)
-- ---------------------------------------------------------------------
create table public.app_members (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  role       text not null default 'owner' check (role in ('owner', 'member')),
  created_at timestamptz not null default now()
);

create or replace function public.is_member()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (select 1 from public.app_members where user_id = auth.uid());
$$;

-- ---------------------------------------------------------------------
-- Konfiguracja systemu (wagi, limity, modele) — edytowalna bez deployu
-- ---------------------------------------------------------------------
create table public.app_config (
  key         text primary key,
  value       jsonb not null,
  description text,
  updated_at  timestamptz not null default now()
);
create trigger trg_app_config_updated before update on public.app_config
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- Kategorie i podkategorie
-- ---------------------------------------------------------------------
create table public.categories (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique check (slug ~ '^[a-z0-9-]+$'),
  name        text not null,
  parent_id   uuid references public.categories (id) on delete restrict,
  description text,
  active      boolean not null default true,
  sort_order  int not null default 100,
  created_at  timestamptz not null default now()
);
create index idx_categories_parent on public.categories (parent_id);

-- ---------------------------------------------------------------------
-- Źródła
-- ---------------------------------------------------------------------
create table public.sources (
  id                     uuid primary key default gen_random_uuid(),
  name                   text not null,
  type                   public.source_type not null,
  url                    text not null,
  language               text not null default 'en',
  priority               smallint not null default 3 check (priority between 1 and 5),
  category_id            uuid references public.categories (id) on delete set null,
  active                 boolean not null default true,
  visibility             public.visibility not null default 'public',
  configuration          jsonb not null default '{}'::jsonb,
  check_interval_minutes int not null default 180 check (check_interval_minutes >= 15),
  last_checked_at        timestamptz,
  last_success_at        timestamptz,
  last_error             text,
  error_count            int not null default 0,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (type, url)
);
create index idx_sources_active on public.sources (active, type);
create trigger trg_sources_updated before update on public.sources
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- Zebrane materiały (surowe)
-- ---------------------------------------------------------------------
create table public.content_items (
  id                  uuid primary key default gen_random_uuid(),
  source_id           uuid not null references public.sources (id) on delete cascade,
  external_id         text,
  title               text not null,
  original_url        text not null,
  author              text,
  published_at        timestamptz,
  collected_at        timestamptz not null default now(),
  description         text,
  original_content    text,
  transcript          text,
  content_hash        text not null unique,
  language            text,
  word_count          int,
  visibility          public.visibility not null default 'public',
  extraction_status   public.extraction_status not null default 'pending',
  extraction_error    text,
  extraction_attempts smallint not null default 0,
  analysis_status     public.analysis_status not null default 'pending',
  analysis_error      text,
  analysis_attempts   smallint not null default 0,
  claimed_at          timestamptz,
  metadata            jsonb not null default '{}'::jsonb,
  updated_at          timestamptz not null default now()
);
-- Deduplikacja: content_hash = sha256(kanoniczny URL). external_id tylko pomocniczo.
create index idx_content_items_source_external
  on public.content_items (source_id, external_id) where external_id is not null;
create index idx_content_items_extraction on public.content_items (extraction_status, collected_at);
create index idx_content_items_analysis   on public.content_items (analysis_status, collected_at);
create index idx_content_items_published  on public.content_items (published_at desc);
create index idx_content_items_source     on public.content_items (source_id, published_at desc);
create index idx_content_items_title_trgm on public.content_items using gin (title extensions.gin_trgm_ops);
create trigger trg_content_items_updated before update on public.content_items
  for each row execute function public.set_updated_at();

create table public.content_categories (
  content_item_id uuid not null references public.content_items (id) on delete cascade,
  category_id     uuid not null references public.categories (id) on delete cascade,
  confidence      real not null default 1 check (confidence between 0 and 1),
  primary key (content_item_id, category_id)
);
create index idx_content_categories_cat on public.content_categories (category_id);

-- ---------------------------------------------------------------------
-- Analizy AI (jedna aktualna analiza na materiał)
-- ---------------------------------------------------------------------
create table public.analyses (
  id                uuid primary key default gen_random_uuid(),
  content_item_id   uuid not null unique references public.content_items (id) on delete cascade,
  is_relevant       boolean not null,
  reject_reason     text,
  title_pl          text,
  summary           text,
  key_points        jsonb not null default '[]'::jsonb,
  practical_value   text,
  why_it_matters    text,
  claims            jsonb not null default '[]'::jsonb,  -- [{text, type: fact|opinion|forecast|marketing}]
  entities          jsonb not null default '[]'::jsonb,
  completeness      text not null default 'complete' check (completeness in ('complete', 'partial', 'insufficient')),
  source_language   text,
  novelty_score     smallint check (novelty_score between 1 and 10),
  relevance_score   smallint check (relevance_score between 1 and 10),
  practical_score   smallint check (practical_score between 1 and 10),
  reliability_score smallint check (reliability_score between 1 and 10),
  importance_score  numeric(4, 2),
  subcategory_slug  text,
  analysis_model    text not null,
  prompt_version    text not null,
  tokens_input      int,
  tokens_output     int,
  cost_usd          numeric(10, 6),
  embedding         extensions.vector(1536),
  raw_response      jsonb,
  created_at        timestamptz not null default now()
);
create index idx_analyses_created on public.analyses (created_at desc);
create index idx_analyses_importance on public.analyses (importance_score desc);
create index idx_analyses_embedding on public.analyses
  using hnsw (embedding extensions.vector_cosine_ops);

-- Synchronizacja content_categories z wynikiem analizy (kategoria główna + podkategorie)
create or replace function public.sync_content_categories()
returns trigger language plpgsql
set search_path = public
as $$
begin
  delete from public.content_categories where content_item_id = new.content_item_id;
  if new.is_relevant then
    insert into public.content_categories (content_item_id, category_id, confidence)
    select new.content_item_id, c.id,
           case when c.slug = 'ai' then 1
                when c.slug = new.subcategory_slug then coalesce((new.raw_response->>'subcategory_confidence')::real, 0.8)
                else 0.5 end
    from public.categories c
    where c.slug = 'ai' or c.slug = new.subcategory_slug
       or c.slug in (select jsonb_array_elements_text(coalesce(new.raw_response->'secondary_subcategories', '[]'::jsonb)))
    on conflict do nothing;
  end if;
  return new;
end $$;
create trigger trg_analyses_categories after insert or update of is_relevant, subcategory_slug, raw_response
  on public.analyses for each row execute function public.sync_content_categories();

-- ---------------------------------------------------------------------
-- Wydarzenia (grupy materiałów o tym samym wydarzeniu)
-- ---------------------------------------------------------------------
create table public.stories (
  id                  uuid primary key default gen_random_uuid(),
  title               text not null,
  summary             text,
  category_id         uuid references public.categories (id) on delete set null,
  subcategory_slug    text,
  importance_score    numeric(4, 2),
  reliability_score   numeric(4, 2),
  corroboration_score numeric(4, 2),
  item_count          int not null default 0,
  source_count        int not null default 0,
  first_seen_at       timestamptz not null default now(),
  last_updated_at     timestamptz not null default now()
);
create index idx_stories_updated on public.stories (last_updated_at desc);
create index idx_stories_importance on public.stories (importance_score desc);

create table public.story_items (
  story_id        uuid not null references public.stories (id) on delete cascade,
  content_item_id uuid not null unique references public.content_items (id) on delete cascade,
  similarity      real,
  added_at        timestamptz not null default now(),
  primary key (story_id, content_item_id)
);

-- ---------------------------------------------------------------------
-- Nagrania
-- ---------------------------------------------------------------------
create table public.audio_assets (
  id               uuid primary key default gen_random_uuid(),
  kind             text not null check (kind in ('briefing_full', 'briefing_chapter', 'story', 'item')),
  content_item_id  uuid references public.content_items (id) on delete set null,
  story_id         uuid references public.stories (id) on delete set null,
  briefing_id      uuid,  -- FK dodany niżej (zależność cykliczna)
  chapter_index    smallint,
  title            text,
  storage_path     text not null unique,
  duration_seconds numeric(8, 2),
  size_bytes       bigint,
  voice_id         text,
  model_id         text,
  language         text not null default 'pl',
  characters       int,
  cost_usd         numeric(10, 6),
  ai_generated     boolean not null default true,
  status           public.asset_status not null default 'pending',
  error            text,
  metadata         jsonb not null default '{}'::jsonb,
  generated_at     timestamptz not null default now()
);
create index idx_audio_assets_briefing on public.audio_assets (briefing_id, kind, chapter_index);

-- ---------------------------------------------------------------------
-- Codzienne briefingi
-- ---------------------------------------------------------------------
create table public.daily_briefings (
  id                uuid primary key default gen_random_uuid(),
  briefing_date     date not null,
  edition           text not null default 'ai-daily',
  title             text not null,
  summary           text,
  text_content      text,                       -- pełny tekst (markdown)
  sections          jsonb not null default '[]'::jsonb,  -- tematy dla e-maila i aplikacji
  trends            text,                       -- trendy i wnioski dnia
  stats             jsonb not null default '{}'::jsonb,
  script            jsonb,                      -- scenariusz audio z rozdziałami
  chapters          jsonb not null default '[]'::jsonb,  -- [{index,title,start_seconds,duration_seconds,audio_asset_id}]
  headline_story_id uuid references public.stories (id) on delete set null,
  audio_asset_id    uuid references public.audio_assets (id) on delete set null,
  status            public.briefing_status not null default 'draft',
  items_considered  int,
  items_analyzed    int,
  items_rejected    int,
  analysis_model    text,
  cost_usd          numeric(10, 6),
  error             text,
  email_sent_at     timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (briefing_date, edition)
);
create index idx_daily_briefings_date on public.daily_briefings (briefing_date desc);
create trigger trg_daily_briefings_updated before update on public.daily_briefings
  for each row execute function public.set_updated_at();

alter table public.audio_assets
  add constraint audio_assets_briefing_fk
  foreign key (briefing_id) references public.daily_briefings (id) on delete cascade;

create table public.briefing_stories (
  briefing_id    uuid not null references public.daily_briefings (id) on delete cascade,
  story_id       uuid not null references public.stories (id) on delete cascade,
  position       smallint not null,
  section        text not null check (section in ('headline', 'main', 'tools', 'trends', 'brief')),
  why_it_matters text,
  primary key (briefing_id, story_id)
);
create index idx_briefing_stories_story on public.briefing_stories (story_id);

-- ---------------------------------------------------------------------
-- Dane użytkownika (oddzielone od treści)
-- ---------------------------------------------------------------------
create table public.user_feedback (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  content_item_id uuid references public.content_items (id) on delete cascade,
  story_id        uuid references public.stories (id) on delete cascade,
  briefing_id     uuid references public.daily_briefings (id) on delete cascade,
  rating          smallint not null check (rating in (-1, 1)),
  feedback_type   text not null default 'thumbs'
                  check (feedback_type in ('thumbs', 'not_relevant', 'already_known', 'too_long', 'inaccurate', 'great')),
  comment         text,
  created_at      timestamptz not null default now(),
  check (num_nonnulls(content_item_id, story_id, briefing_id) = 1)
);
create unique index uq_feedback_item  on public.user_feedback (user_id, content_item_id) where content_item_id is not null;
create unique index uq_feedback_story on public.user_feedback (user_id, story_id) where story_id is not null;
create unique index uq_feedback_brief on public.user_feedback (user_id, briefing_id) where briefing_id is not null;

create table public.user_preferences (
  user_id                  uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  language                 text not null default 'pl',
  briefing_time            time not null default '08:00',
  timezone                 text not null default 'Europe/Warsaw',
  preferred_categories     text[] not null default array['ai'],
  preferred_sources        uuid[] not null default '{}',
  preferred_audio_length   smallint not null default 12 check (preferred_audio_length between 3 and 40),
  preferred_voice          text,
  playback_rate            numeric(3, 2) not null default 1.0 check (playback_rate between 0.5 and 3.0),
  interests                text[] not null default '{}',
  email                    text,
  updated_at               timestamptz not null default now()
);
create trigger trg_user_preferences_updated before update on public.user_preferences
  for each row execute function public.set_updated_at();

create table public.saved_items (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  content_item_id uuid references public.content_items (id) on delete cascade,
  story_id        uuid references public.stories (id) on delete cascade,
  briefing_id     uuid references public.daily_briefings (id) on delete cascade,
  created_at      timestamptz not null default now(),
  check (num_nonnulls(content_item_id, story_id, briefing_id) = 1)
);
create unique index uq_saved_item  on public.saved_items (user_id, content_item_id) where content_item_id is not null;
create unique index uq_saved_story on public.saved_items (user_id, story_id) where story_id is not null;
create unique index uq_saved_brief on public.saved_items (user_id, briefing_id) where briefing_id is not null;

create table public.playback_progress (
  user_id          uuid not null default auth.uid() references auth.users (id) on delete cascade,
  audio_asset_id   uuid not null references public.audio_assets (id) on delete cascade,
  position_seconds numeric(8, 2) not null default 0,
  completed        boolean not null default false,
  updated_at       timestamptz not null default now(),
  primary key (user_id, audio_asset_id)
);
create trigger trg_playback_progress_updated before update on public.playback_progress
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- Koszty i dziennik wykonania
-- ---------------------------------------------------------------------
create table public.api_usage (
  id              bigint generated always as identity primary key,
  created_at      timestamptz not null default now(),
  workflow        text not null,
  provider        text not null check (provider in ('openai', 'elevenlabs', 'transcription', 'x', 'other')),
  operation       text not null,
  model           text,
  tokens_input    int,
  tokens_output   int,
  characters      int,
  cost_usd        numeric(10, 6) not null default 0,
  content_item_id uuid references public.content_items (id) on delete set null,
  briefing_id     uuid references public.daily_briefings (id) on delete set null,
  metadata        jsonb not null default '{}'::jsonb
);
create index idx_api_usage_created on public.api_usage (provider, created_at desc);

create table public.pipeline_runs (
  id           bigint generated always as identity primary key,
  workflow     text not null,
  execution_id text,
  status       text not null check (status in ('success', 'partial', 'error', 'skipped')),
  started_at   timestamptz,
  finished_at  timestamptz not null default now(),
  stats        jsonb not null default '{}'::jsonb,
  error        text
);
create index idx_pipeline_runs_wf on public.pipeline_runs (workflow, finished_at desc);

-- =====================================================================
-- FUNKCJE (RPC) — wywoływane przez n8n (service_role) i aplikację
-- =====================================================================

-- Konfiguracja jako jeden obiekt JSON
create or replace function public.get_config()
returns jsonb language sql stable
set search_path = public
as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from public.app_config;
$$;

-- Źródła do sprawdzenia (zgodnie z check_interval_minutes)
create or replace function public.get_sources_due(p_types public.source_type[] default null, p_force boolean default false)
returns setof public.sources language sql stable
set search_path = public
as $$
  select s.* from public.sources s
  where s.active
    and (p_types is null or s.type = any (p_types))
    and (p_force or s.last_checked_at is null
         or s.last_checked_at + make_interval(mins => s.check_interval_minutes) <= now() + interval '5 minutes')
  order by s.priority desc, s.last_checked_at nulls first;
$$;

create or replace function public.mark_source_checked(p_source_id uuid, p_ok boolean, p_error text default null)
returns void language sql volatile
set search_path = public
as $$
  update public.sources set
    last_checked_at = now(),
    last_success_at = case when p_ok then now() else last_success_at end,
    last_error      = case when p_ok then null else left(p_error, 2000) end,
    error_count     = case when p_ok then 0 else error_count + 1 end
  where id = p_source_id;
$$;

-- Pobiera paczkę materiałów do ekstrakcji (blokada przed podwójnym przetwarzaniem)
create or replace function public.claim_items_for_extraction(p_limit int default 20)
returns table (
  id uuid, source_id uuid, source_type public.source_type, source_name text, source_config jsonb,
  title text, original_url text, description text, original_content text, transcript text,
  metadata jsonb, extraction_attempts smallint
)
language plpgsql volatile
set search_path = public
as $$
begin
  return query
  with picked as (
    select ci.id from public.content_items ci
    where (ci.extraction_status = 'pending'
           or (ci.extraction_status = 'processing' and ci.claimed_at < now() - interval '1 hour')
           or (ci.extraction_status = 'failed' and ci.extraction_attempts < 3
               and ci.updated_at < now() - interval '2 hours'))
    order by ci.collected_at
    limit p_limit
    for update skip locked
  ), upd as (
    update public.content_items ci set
      extraction_status = 'processing',
      extraction_attempts = ci.extraction_attempts + 1,
      claimed_at = now()
    from picked where ci.id = picked.id
    returning ci.*
  )
  select u.id, u.source_id, s.type, s.name, s.configuration, u.title, u.original_url, u.description,
         u.original_content, u.transcript, u.metadata, u.extraction_attempts
  from upd u join public.sources s on s.id = u.source_id;
end $$;

-- Pobiera paczkę materiałów do analizy AI
create or replace function public.claim_items_for_analysis(p_limit int default 15)
returns table (
  id uuid, source_name text, source_type public.source_type, source_priority smallint,
  title text, original_url text, author text, published_at timestamptz, language text,
  description text, content text, word_count int, extraction_status public.extraction_status
)
language plpgsql volatile
set search_path = public
as $$
begin
  return query
  with picked as (
    select ci.id from public.content_items ci
    where ci.extraction_status in ('extracted')
      and (ci.analysis_status = 'pending'
           or (ci.analysis_status = 'processing' and ci.claimed_at < now() - interval '1 hour')
           or (ci.analysis_status = 'failed' and ci.analysis_attempts < 3
               and ci.updated_at < now() - interval '1 hour'))
    order by ci.published_at desc nulls last
    limit p_limit
    for update skip locked
  ), upd as (
    update public.content_items ci set
      analysis_status = 'processing',
      analysis_attempts = ci.analysis_attempts + 1,
      claimed_at = now()
    from picked where ci.id = picked.id
    returning ci.*
  )
  select u.id, s.name, s.type, s.priority, u.title, u.original_url, u.author, u.published_at,
         u.language, u.description,
         coalesce(nullif(u.transcript, ''), u.original_content, u.description) as content,
         u.word_count, u.extraction_status
  from upd u join public.sources s on s.id = u.source_id;
end $$;

-- Zbiorczy zapis wyników ekstrakcji: [{id, status, original_content?, transcript?, word_count?, language?, error?, metadata?}]
create or replace function public.apply_extraction_results(p_results jsonb)
returns int language plpgsql volatile
set search_path = public
as $$
declare n int;
begin
  update public.content_items ci set
    extraction_status = (r->>'status')::public.extraction_status,
    original_content  = coalesce(r->>'original_content', ci.original_content),
    transcript        = coalesce(r->>'transcript', ci.transcript),
    word_count        = coalesce((r->>'word_count')::int, ci.word_count),
    language          = coalesce(r->>'language', ci.language),
    extraction_error  = r->>'error',
    metadata          = ci.metadata || coalesce(r->'metadata', '{}'::jsonb),
    analysis_status   = case when (r->>'status') in ('incomplete', 'failed', 'skipped')
                             then 'skipped'::public.analysis_status else ci.analysis_status end,
    claimed_at        = null
  from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) r
  where ci.id = (r->>'id')::uuid;
  get diagnostics n = row_count;
  return n;
end $$;

-- Zbiorczy zapis statusów analizy: [{id, status, error?}]
create or replace function public.apply_analysis_status(p_rows jsonb)
returns int language plpgsql volatile
set search_path = public
as $$
declare n int;
begin
  update public.content_items ci set
    analysis_status = (r->>'status')::public.analysis_status,
    analysis_error  = r->>'error',
    claimed_at      = null
  from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r
  where ci.id = (r->>'id')::uuid;
  get diagnostics n = row_count;
  return n;
end $$;

-- Ważona ocena wg wag z app_config.scoring_weights
create or replace function public.weighted_score(
  p_novelty numeric, p_relevance numeric, p_practical numeric, p_reliability numeric, p_corroboration numeric
) returns numeric language sql stable
set search_path = public
as $$
  with w as (
    select coalesce((select value from public.app_config where key = 'scoring_weights'),
      '{"novelty":0.30,"relevance":0.25,"practical":0.20,"reliability":0.15,"corroboration":0.10}'::jsonb) as v
  )
  select round((
      coalesce(p_novelty, 1)       * (v->>'novelty')::numeric
    + coalesce(p_relevance, 1)     * (v->>'relevance')::numeric
    + coalesce(p_practical, 1)     * (v->>'practical')::numeric
    + coalesce(p_reliability, 1)   * (v->>'reliability')::numeric
    + coalesce(p_corroboration, 1) * (v->>'corroboration')::numeric
  ), 2) from w;
$$;

-- Przelicza statystyki i ocenę wydarzenia
create or replace function public.refresh_story(p_story_id uuid)
returns void language plpgsql volatile
set search_path = public
as $$
declare
  v_items int; v_sources int; v_corr numeric; v_rel numeric;
  v_nov numeric; v_relev numeric; v_prac numeric;
  v_best record;
begin
  select count(*), count(distinct ci.source_id),
         avg(a.reliability_score), max(a.novelty_score), max(a.relevance_score), max(a.practical_score)
    into v_items, v_sources, v_rel, v_nov, v_relev, v_prac
  from public.story_items si
  join public.content_items ci on ci.id = si.content_item_id
  join public.analyses a on a.content_item_id = si.content_item_id
  where si.story_id = p_story_id and a.is_relevant;

  -- 1 źródło = 2 pkt, każde kolejne niezależne źródło +2 (max 10).
  v_corr := least(10, 2 * greatest(v_sources, 1));

  select a.title_pl, a.summary, a.subcategory_slug into v_best
  from public.story_items si
  join public.analyses a on a.content_item_id = si.content_item_id
  where si.story_id = p_story_id and a.is_relevant
  order by a.importance_score desc nulls last, a.created_at
  limit 1;

  update public.stories set
    item_count          = coalesce(v_items, 0),
    source_count        = coalesce(v_sources, 0),
    corroboration_score = v_corr,
    reliability_score   = round(v_rel, 2),
    importance_score    = public.weighted_score(v_nov, v_relev, v_prac, v_rel, v_corr),
    title               = coalesce(v_best.title_pl, title),
    summary             = coalesce(v_best.summary, summary),
    subcategory_slug    = coalesce(v_best.subcategory_slug, subcategory_slug),
    last_updated_at     = now()
  where id = p_story_id;
end $$;

-- Przypisuje przeanalizowany materiał do istniejącego lub nowego wydarzenia
-- (najbliższy sąsiad po embeddingu w oknie czasowym).
create or replace function public.assign_item_to_story(
  p_content_item_id uuid,
  p_embedding       extensions.vector(1536),
  p_threshold       float default 0.82,
  p_window_hours    int default 96
) returns uuid
language plpgsql volatile
set search_path = public, extensions
as $$
declare
  v_story uuid; v_sim float; v_title text; v_summary text; v_sub text; v_cat uuid;
begin
  update public.analyses set embedding = p_embedding where content_item_id = p_content_item_id;

  select si.story_id, 1 - (a.embedding <=> p_embedding)
    into v_story, v_sim
  from public.analyses a
  join public.story_items si on si.content_item_id = a.content_item_id
  where a.embedding is not null
    and a.content_item_id <> p_content_item_id
    and a.is_relevant
    and a.created_at > now() - make_interval(hours => p_window_hours)
  order by a.embedding <=> p_embedding
  limit 1;

  if v_story is null or v_sim < p_threshold then
    select a.title_pl, a.summary, a.subcategory_slug into v_title, v_summary, v_sub
    from public.analyses a where a.content_item_id = p_content_item_id;
    select id into v_cat from public.categories where slug = 'ai';
    insert into public.stories (title, summary, subcategory_slug, category_id)
    values (coalesce(v_title, '(bez tytułu)'), v_summary, v_sub, v_cat)
    returning id into v_story;
    v_sim := 1;
  end if;

  insert into public.story_items (story_id, content_item_id, similarity)
  values (v_story, p_content_item_id, v_sim)
  on conflict (content_item_id) do update set story_id = excluded.story_id, similarity = excluded.similarity;

  perform public.refresh_story(v_story);
  return v_story;
end $$;

-- Kandydaci do briefingu: wydarzenia z ostatnich p_hours, z bonusem z ocen użytkownika
create or replace function public.get_briefing_candidates(p_hours int default 24, p_limit int default 30)
returns table (
  story_id uuid, title text, summary text, subcategory_slug text,
  importance_score numeric, adjusted_score numeric, reliability_score numeric,
  source_count int, item_count int, items jsonb
)
language sql stable
set search_path = public
as $$
  with recent as (
    select st.* from public.stories st
    where st.last_updated_at > now() - make_interval(hours => p_hours)
      and st.item_count > 0
      -- nie powtarzaj wydarzeń z wczorajszego briefingu, chyba że doszły nowe materiały
      and not exists (
        select 1 from public.briefing_stories bs
        join public.daily_briefings db on db.id = bs.briefing_id
        where bs.story_id = st.id
          and db.created_at > now() - interval '7 days'
          and db.created_at > (select max(si.added_at) from public.story_items si where si.story_id = st.id)
      )
  ),
  fb as (  -- preferencje: średnia ocena per podkategoria i źródło (ostatnie 60 dni)
    select a.subcategory_slug, ci.source_id, avg(f.rating)::numeric as r
    from public.user_feedback f
    join public.content_items ci on ci.id = f.content_item_id
    join public.analyses a on a.content_item_id = ci.id
    where f.created_at > now() - interval '60 days'
    group by grouping sets ((a.subcategory_slug), (ci.source_id))
  )
  select r.id, r.title, r.summary, r.subcategory_slug, r.importance_score,
         round(r.importance_score
               + coalesce((select fb.r from fb where fb.subcategory_slug = r.subcategory_slug and fb.source_id is null), 0) * 0.5
               + coalesce((select avg(fb.r) from fb
                           join public.story_items si on si.story_id = r.id
                           join public.content_items ci on ci.id = si.content_item_id
                           where fb.source_id = ci.source_id), 0) * 0.3, 2) as adjusted_score,
         r.reliability_score, r.source_count, r.item_count,
         (select jsonb_agg(jsonb_build_object(
                    'content_item_id', ci.id,
                    'title', coalesce(a.title_pl, ci.title),
                    'source', s.name,
                    'url', ci.original_url,
                    'published_at', ci.published_at,
                    'summary', a.summary,
                    'key_points', a.key_points,
                    'practical_value', a.practical_value,
                    'claims', a.claims,
                    'reliability', a.reliability_score
                  ) order by a.importance_score desc)
          from public.story_items si
          join public.content_items ci on ci.id = si.content_item_id
          join public.sources s on s.id = ci.source_id
          join public.analyses a on a.content_item_id = ci.id
          where si.story_id = r.id and a.is_relevant) as items
  from recent r
  order by adjusted_score desc nulls last
  limit p_limit;
$$;

-- Statystyki do briefingu
create or replace function public.briefing_stats(p_hours int default 24)
returns jsonb language sql stable
set search_path = public
as $$
  select jsonb_build_object(
    'collected', (select count(*) from public.content_items where collected_at > now() - make_interval(hours => p_hours)),
    'analyzed',  (select count(*) from public.analyses where created_at > now() - make_interval(hours => p_hours)),
    'rejected',  (select count(*) from public.analyses where created_at > now() - make_interval(hours => p_hours) and not is_relevant),
    'incomplete',(select count(*) from public.content_items where collected_at > now() - make_interval(hours => p_hours) and extraction_status = 'incomplete'),
    'stories',   (select count(*) from public.stories where last_updated_at > now() - make_interval(hours => p_hours))
  );
$$;

-- Kontrola budżetu: czy wolno wywołać dostawcę (limity w app_config.limits)
create or replace function public.check_budget(p_provider text)
returns jsonb language sql stable
set search_path = public
as $$
  with lim as (
    select coalesce((select value from public.app_config where key = 'limits'), '{}'::jsonb) -> p_provider as l
  ), usage as (
    select
      coalesce(sum(cost_usd) filter (where created_at >= date_trunc('day', now() at time zone 'Europe/Warsaw') at time zone 'Europe/Warsaw'), 0) as day_usd,
      coalesce(sum(cost_usd) filter (where created_at >= date_trunc('month', now() at time zone 'Europe/Warsaw') at time zone 'Europe/Warsaw'), 0) as month_usd,
      coalesce(sum(characters) filter (where created_at >= date_trunc('month', now() at time zone 'Europe/Warsaw') at time zone 'Europe/Warsaw'), 0) as month_chars,
      count(*) filter (where created_at >= date_trunc('day', now() at time zone 'Europe/Warsaw') at time zone 'Europe/Warsaw') as day_calls
    from public.api_usage where provider = p_provider
  )
  select jsonb_build_object(
    'provider', p_provider,
    'day_usd', u.day_usd, 'month_usd', u.month_usd, 'month_characters', u.month_chars, 'day_calls', u.day_calls,
    'limits', lim.l,
    'allowed',
      (lim.l is null) or (
            u.day_usd     < coalesce((lim.l->>'daily_usd')::numeric, 1e9)
        and u.month_usd   < coalesce((lim.l->>'monthly_usd')::numeric, 1e9)
        and u.month_chars < coalesce((lim.l->>'monthly_characters')::numeric, 1e12)
        and u.day_calls   < coalesce((lim.l->>'daily_calls')::numeric, 1e9))
  ) from usage u, lim;
$$;

-- ---------------------------------------------------------------------
-- RPC dla aplikacji (security invoker => działają w ramach RLS użytkownika)
-- ---------------------------------------------------------------------
-- Ocena materiału: p_rating = 1 (przydatne), -1 (nieprzydatne), 0 (usuń ocenę)
create or replace function public.set_feedback(p_content_item_id uuid, p_rating int, p_feedback_type text default 'thumbs')
returns void language plpgsql security invoker
set search_path = public
as $$
begin
  delete from public.user_feedback where user_id = auth.uid() and content_item_id = p_content_item_id;
  if p_rating in (-1, 1) then
    insert into public.user_feedback (content_item_id, rating, feedback_type)
    values (p_content_item_id, p_rating, coalesce(p_feedback_type, 'thumbs'));
  end if;
end $$;

create or replace function public.set_briefing_feedback(p_briefing_id uuid, p_rating int)
returns void language plpgsql security invoker
set search_path = public
as $$
begin
  delete from public.user_feedback where user_id = auth.uid() and briefing_id = p_briefing_id;
  if p_rating in (-1, 1) then
    insert into public.user_feedback (briefing_id, rating) values (p_briefing_id, p_rating);
  end if;
end $$;

-- Zapisz / usuń z zapisanych. Zwraca nowy stan.
create or replace function public.toggle_saved(p_content_item_id uuid default null, p_briefing_id uuid default null)
returns boolean language plpgsql security invoker
set search_path = public
as $$
declare v_deleted int;
begin
  delete from public.saved_items
  where user_id = auth.uid()
    and ((p_content_item_id is not null and content_item_id = p_content_item_id)
      or (p_briefing_id is not null and briefing_id = p_briefing_id));
  get diagnostics v_deleted = row_count;
  if v_deleted > 0 then return false; end if;
  insert into public.saved_items (content_item_id, briefing_id) values (p_content_item_id, p_briefing_id);
  return true;
end $$;

create or replace function public.save_progress(p_audio_asset_id uuid, p_position_seconds numeric, p_completed boolean default false)
returns void language sql security invoker
set search_path = public
as $$
  insert into public.playback_progress (user_id, audio_asset_id, position_seconds, completed)
  values (auth.uid(), p_audio_asset_id, greatest(p_position_seconds, 0), p_completed)
  on conflict (user_id, audio_asset_id) do update
    set position_seconds = excluded.position_seconds,
        completed = public.playback_progress.completed or excluded.completed;
$$;

grant execute on function public.set_feedback(uuid, int, text) to authenticated;
grant execute on function public.set_briefing_feedback(uuid, int) to authenticated;
grant execute on function public.toggle_saved(uuid, uuid) to authenticated;
grant execute on function public.save_progress(uuid, numeric, boolean) to authenticated;
revoke execute on function public.set_feedback(uuid, int, text) from anon;
revoke execute on function public.set_briefing_feedback(uuid, int) from anon;
revoke execute on function public.toggle_saved(uuid, uuid) from anon;
revoke execute on function public.save_progress(uuid, numeric, boolean) from anon;

-- =====================================================================
-- WIDOKI dla aplikacji (security_invoker => obowiązuje RLS wołającego)
-- =====================================================================
create view public.v_feed with (security_invoker = true) as
select
  ci.id,
  coalesce(a.title_pl, ci.title)        as title,
  ci.title                              as original_title,
  ci.original_url,
  ci.author,
  ci.published_at,
  ci.collected_at,
  ci.visibility,
  ci.extraction_status,
  ci.analysis_status,
  s.id                                  as source_id,
  s.name                                as source_name,
  s.type                                as source_type,
  a.summary,
  a.key_points,
  a.practical_value,
  a.why_it_matters,
  a.claims,
  a.completeness,
  a.source_language,
  a.importance_score,
  a.reliability_score,
  a.subcategory_slug,
  c.name                                as subcategory_name,
  si.story_id,
  st.item_count                         as story_item_count,
  st.source_count                       as story_source_count,
  (select f.rating from public.user_feedback f
    where f.content_item_id = ci.id and f.user_id = auth.uid()) as my_rating,
  exists (select 1 from public.saved_items sv
    where sv.content_item_id = ci.id and sv.user_id = auth.uid()) as is_saved
from public.content_items ci
join public.sources s on s.id = ci.source_id
left join public.analyses a on a.content_item_id = ci.id
left join public.categories c on c.slug = a.subcategory_slug
left join public.story_items si on si.content_item_id = ci.id
left join public.stories st on st.id = si.story_id;

create view public.v_briefings with (security_invoker = true) as
select
  b.id, b.briefing_date, b.edition, b.title, b.summary, b.text_content, b.sections, b.trends, b.stats, b.chapters,
  b.status, b.items_considered, b.items_analyzed, b.items_rejected, b.created_at, b.email_sent_at,
  b.audio_asset_id,
  aa.storage_path     as audio_path,
  aa.duration_seconds as audio_duration_seconds,
  (select pp.position_seconds from public.playback_progress pp
    where pp.audio_asset_id = b.audio_asset_id and pp.user_id = auth.uid()) as my_position_seconds,
  exists (select 1 from public.saved_items sv
    where sv.briefing_id = b.id and sv.user_id = auth.uid()) as is_saved
from public.daily_briefings b
left join public.audio_assets aa on aa.id = b.audio_asset_id and aa.status = 'ready';

create view public.v_cost_daily with (security_invoker = true) as
select (created_at at time zone 'Europe/Warsaw')::date as day, provider,
       count(*) as calls, sum(cost_usd) as cost_usd,
       sum(tokens_input) as tokens_input, sum(tokens_output) as tokens_output, sum(characters) as characters
from public.api_usage
group by 1, 2;

-- =====================================================================
-- RLS
-- =====================================================================
alter table public.app_members        enable row level security;
alter table public.app_config         enable row level security;
alter table public.categories         enable row level security;
alter table public.sources            enable row level security;
alter table public.content_items      enable row level security;
alter table public.content_categories enable row level security;
alter table public.analyses           enable row level security;
alter table public.stories            enable row level security;
alter table public.story_items        enable row level security;
alter table public.audio_assets       enable row level security;
alter table public.daily_briefings    enable row level security;
alter table public.briefing_stories   enable row level security;
alter table public.user_feedback      enable row level security;
alter table public.user_preferences   enable row level security;
alter table public.saved_items        enable row level security;
alter table public.playback_progress  enable row level security;
alter table public.api_usage          enable row level security;
alter table public.pipeline_runs      enable row level security;

-- Odczyt treści — tylko członkowie
create policy members_read on public.app_members        for select to authenticated using (user_id = auth.uid());
create policy members_read on public.app_config         for select to authenticated using (public.is_member());
create policy members_read on public.categories         for select to authenticated using (public.is_member());
create policy members_read on public.sources            for select to authenticated using (public.is_member());
create policy members_read on public.content_items      for select to authenticated using (public.is_member());
create policy members_read on public.content_categories for select to authenticated using (public.is_member());
create policy members_read on public.analyses           for select to authenticated using (public.is_member());
create policy members_read on public.stories            for select to authenticated using (public.is_member());
create policy members_read on public.story_items        for select to authenticated using (public.is_member());
create policy members_read on public.audio_assets       for select to authenticated using (public.is_member());
create policy members_read on public.daily_briefings    for select to authenticated using (public.is_member());
create policy members_read on public.briefing_stories   for select to authenticated using (public.is_member());
create policy members_read on public.api_usage          for select to authenticated using (public.is_member());
create policy members_read on public.pipeline_runs      for select to authenticated using (public.is_member());

-- Zarządzanie źródłami z aplikacji (bez Gmail/X/LinkedIn — te tylko przez n8n/SQL)
create policy owner_insert_sources on public.sources for insert to authenticated
  with check (public.is_member() and type not in ('gmail', 'x', 'linkedin'));
create policy owner_update_sources on public.sources for update to authenticated
  using (public.is_member()) with check (public.is_member());
create policy owner_delete_sources on public.sources for delete to authenticated
  using (public.is_member() and type not in ('gmail'));

-- Dane osobiste — tylko własne wiersze
create policy own_rows on public.user_feedback for all to authenticated
  using (user_id = auth.uid() and public.is_member()) with check (user_id = auth.uid() and public.is_member());
create policy own_rows on public.user_preferences for all to authenticated
  using (user_id = auth.uid() and public.is_member()) with check (user_id = auth.uid() and public.is_member());
create policy own_rows on public.saved_items for all to authenticated
  using (user_id = auth.uid() and public.is_member()) with check (user_id = auth.uid() and public.is_member());
create policy own_rows on public.playback_progress for all to authenticated
  using (user_id = auth.uid() and public.is_member()) with check (user_id = auth.uid() and public.is_member());

-- Funkcje wewnętrzne pipeline'u: tylko service_role
revoke execute on function public.claim_items_for_extraction(int) from public, anon, authenticated;
revoke execute on function public.claim_items_for_analysis(int)   from public, anon, authenticated;
revoke execute on function public.assign_item_to_story(uuid, extensions.vector, float, int) from public, anon, authenticated;
revoke execute on function public.refresh_story(uuid)             from public, anon, authenticated;
revoke execute on function public.mark_source_checked(uuid, boolean, text) from public, anon, authenticated;
revoke execute on function public.get_sources_due(public.source_type[], boolean) from public, anon, authenticated;
revoke execute on function public.get_briefing_candidates(int, int) from public, anon, authenticated;
revoke execute on function public.check_budget(text)              from public, anon, authenticated;
revoke execute on function public.get_config()                    from public, anon, authenticated;
revoke execute on function public.apply_extraction_results(jsonb) from public, anon, authenticated;
revoke execute on function public.apply_analysis_status(jsonb)    from public, anon, authenticated;
grant execute on function public.apply_extraction_results(jsonb) to service_role;
grant execute on function public.apply_analysis_status(jsonb)    to service_role;
grant execute on function public.claim_items_for_extraction(int) to service_role;
grant execute on function public.claim_items_for_analysis(int)   to service_role;
grant execute on function public.assign_item_to_story(uuid, extensions.vector, float, int) to service_role;
grant execute on function public.refresh_story(uuid)             to service_role;
grant execute on function public.mark_source_checked(uuid, boolean, text) to service_role;
grant execute on function public.get_sources_due(public.source_type[], boolean) to service_role;
grant execute on function public.get_briefing_candidates(int, int) to service_role;
grant execute on function public.check_budget(text)              to service_role;
grant execute on function public.get_config()                    to service_role;

-- Anon nie ma czego szukać w tej bazie
revoke all on all tables in schema public from anon;

-- =====================================================================
-- STORAGE: prywatny bucket na nagrania
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('audio', 'audio', false, 52428800, array['audio/mpeg'])
on conflict (id) do nothing;

create policy "members read audio" on storage.objects for select to authenticated
  using (bucket_id = 'audio' and public.is_member());
