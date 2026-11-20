-- =====================================================================
-- NEWSFLOW Personal 0.1 — dane startowe
-- Uruchom PO migracji. Bezpieczne do ponownego uruchomienia.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Konfiguracja
-- ---------------------------------------------------------------------
insert into public.app_config (key, value, description) values
  ('scoring_weights',
   '{"novelty":0.30,"relevance":0.25,"practical":0.20,"reliability":0.15,"corroboration":0.10}',
   'Wagi oceny ważności (suma = 1.0). Popularność NIE jest kryterium.'),
  ('models',
   '{"analysis":"gpt-5-mini","briefing":"gpt-5","script":"gpt-5-mini","embedding":"text-embedding-3-small"}',
   'Modele OpenAI używane w poszczególnych krokach.'),
  ('pricing_usd_per_1m_tokens',
   '{"gpt-5-mini":{"input":0.25,"output":2.0},"gpt-5":{"input":1.25,"output":10.0},"text-embedding-3-small":{"input":0.02,"output":0}}',
   'Cennik do szacowania kosztów. Zaktualizuj wg aktualnego cennika OpenAI.'),
  ('elevenlabs',
   '{"voice_id":"REPLACE_WITH_VOICE_ID","model_id":"eleven_multilingual_v2","output_format":"mp3_44100_96","max_chunk_chars":2500,"usd_per_1k_characters":0.22,"voice_settings":{"stability":0.5,"similarity_boost":0.75,"style":0.15,"use_speaker_boost":true,"speed":1.0}}',
   'Konfiguracja syntezy mowy (patrz config/audio.json).'),
  ('limits',
   '{"openai":{"daily_usd":0.80,"monthly_usd":15.0,"daily_calls":400},"elevenlabs":{"daily_usd":4.0,"monthly_usd":25.0,"monthly_characters":100000}}',
   'Twarde limity kosztów — workflow sprawdzają je przed wywołaniem API. monthly_characters ustaw zgodnie z planem ElevenLabs (Creator = 100k).'),
  ('pipeline',
   '{"extract_batch":20,"analyze_batch":15,"min_words_complete":250,"min_words_partial":80,"max_content_chars":16000,"min_importance":4.5,"story_similarity_threshold":0.82,"story_window_hours":96,"briefing_hours":24,"briefing_min_topics":5,"briefing_max_topics":10,"briefing_candidates":30,"audio_target_minutes":12,"max_item_age_days":4}',
   'Parametry przetwarzania.'),
  ('delivery',
   '{"email_to":"REPLACE_WITH_YOUR_EMAIL","app_url_scheme":"newsflow://","signed_url_days":7}',
   'Dostarczanie briefingu.')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Kategorie
-- ---------------------------------------------------------------------
insert into public.categories (slug, name, description, sort_order) values
  ('ai', 'AI – sztuczna inteligencja', 'Główna kategoria w wersji 0.1', 1)
on conflict (slug) do nothing;

insert into public.categories (slug, name, parent_id, sort_order)
select v.slug, v.name, (select id from public.categories where slug = 'ai'), v.ord
from (values
  ('llm',            'Modele językowe i LLM',             1),
  ('agents',         'Agenci AI',                         2),
  ('automation',     'Automatyzacja',                     3),
  ('tools',          'Narzędzia AI',                      4),
  ('image-video',    'Generowanie obrazu i wideo',        5),
  ('voice-audio',    'Generowanie głosu i audio',         6),
  ('open-source',    'Open source',                       7),
  ('research',       'Badania naukowe',                   8),
  ('startups',       'Startupy AI',                       9),
  ('business',       'AI w biznesie',                    10),
  ('coding',         'AI w programowaniu',               11),
  ('productivity',   'AI w produktywności',              12),
  ('robotics',       'Robotyka i systemy autonomiczne',  13),
  ('infrastructure', 'Infrastruktura i sprzęt AI',       14),
  ('policy-safety',  'Regulacje i bezpieczeństwo AI',    15)
) as v(slug, name, ord)
on conflict (slug) do nothing;

-- ---------------------------------------------------------------------
-- Źródła startowe (zweryfikuj adresy po imporcie — WF01 zapisze błędy
-- w sources.last_error, jeśli któryś feed przestał działać)
-- ---------------------------------------------------------------------
insert into public.sources (name, type, url, language, priority, category_id, configuration, check_interval_minutes)
select v.name, v.type::public.source_type, v.url, v.lang, v.prio,
       (select id from public.categories where slug = 'ai'), v.cfg::jsonb, v.interval_min
from (values
  -- Producenci modeli i laboratoria
  ('OpenAI News',              'rss',     'https://openai.com/news/rss.xml',                               'en', 5, '{}', 120),
  ('Google DeepMind Blog',     'rss',     'https://deepmind.google/blog/rss.xml',                          'en', 5, '{}', 180),
  ('Google AI Blog',           'rss',     'https://blog.google/technology/ai/rss/',                        'en', 4, '{}', 180),
  ('Hugging Face Blog',        'rss',     'https://huggingface.co/blog/feed.xml',                          'en', 4, '{}', 180),
  ('Microsoft Research Blog',  'rss',     'https://www.microsoft.com/en-us/research/feed/',                'en', 3, '{}', 240),
  ('NVIDIA Technical Blog',    'rss',     'https://developer.nvidia.com/blog/feed',                        'en', 3, '{}', 240),
  -- Media i analizy
  ('MIT Technology Review AI', 'rss',     'https://www.technologyreview.com/topic/artificial-intelligence/feed', 'en', 4, '{}', 180),
  ('The Verge AI',             'rss',     'https://www.theverge.com/rss/ai-artificial-intelligence/index.xml', 'en', 3, '{}', 120),
  ('TechCrunch AI',            'rss',     'https://techcrunch.com/category/artificial-intelligence/feed/', 'en', 3, '{}', 120),
  ('Simon Willison',           'blog',    'https://simonwillison.net/atom/everything/',                    'en', 4, '{}', 180),
  ('Import AI (Jack Clark)',   'blog',    'https://importai.substack.com/feed',                            'en', 4, '{}', 360),
  ('Towards Data Science',     'medium',  'https://medium.com/feed/towards-data-science',                  'en', 2, '{}', 360),
  -- Reddit (RSS, bez API)
  ('r/LocalLLaMA',             'reddit',  'https://www.reddit.com/r/LocalLLaMA/top/.rss?t=day',            'en', 3, '{"max_items":10}', 240),
  ('r/MachineLearning',        'reddit',  'https://www.reddit.com/r/MachineLearning/top/.rss?t=day',       'en', 2, '{"max_items":10}', 360),
  -- YouTube (kanał RSS: https://www.youtube.com/feeds/videos.xml?channel_id=...)
  ('Two Minute Papers',        'youtube', 'https://www.youtube.com/feeds/videos.xml?channel_id=UCbfYPyITQ-7l4upoX8nvctg', 'en', 3, '{}', 240),
  ('AI Explained',             'youtube', 'https://www.youtube.com/feeds/videos.xml?channel_id=UCNJ1Ymd5yFuUPtn21xtRbbw', 'en', 4, '{}', 240),
  -- Podcasty
  ('Latent Space',             'podcast', 'https://api.substack.com/feed/podcast/1084089.rss',             'en', 3, '{}', 720)
) as v(name, type, url, lang, prio, cfg, interval_min)
on conflict (type, url) do nothing;

-- Gmail — etykieta AI-READ (prywatne). URL to tylko identyfikator, czytanie robi węzeł Gmail w WF01.
insert into public.sources (name, type, url, language, priority, category_id, visibility, configuration, check_interval_minutes)
values ('Newslettery (Gmail: AI-READ)', 'gmail', 'gmail://label/AI-READ', 'en', 4,
        (select id from public.categories where slug = 'ai'), 'private', '{"label":"AI-READ"}', 180)
on conflict (type, url) do nothing;

-- ---------------------------------------------------------------------
-- Właściciel: po utworzeniu użytkownika w Supabase Auth uruchom:
--   insert into public.app_members (user_id, role)
--   select id, 'owner' from auth.users where email = 'TWOJ_EMAIL';
--   insert into public.user_preferences (user_id, email)
--   select id, email from auth.users where email = 'TWOJ_EMAIL';
-- ---------------------------------------------------------------------
