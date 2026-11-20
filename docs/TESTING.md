# Testy i odbiór (Etap 6)

## 1. Testy automatyczne (lokalnie, bez kluczy API)

```bash
npm install
npm test
```

19 testów (`n8n/test/`):

- **biblioteki** — SHA-256 zgodny z `node:crypto` (także UTF-8), kanoniczne URL-e, HTML→tekst, ekstrakcja artykułu,
  napisy VTT, parser RSS/Atom/YouTube/podcast, dzielenie tekstu pod TTS, normalizacja mowy, nagłówki ID3, koszty tokenów, e-mail (escapowanie HTML);
- **wszystkie workflow** — poprawne połączenia, kompilujący się kod węzłów Code, brak niewstawionych znaczników i sekretów;
- **symulacja przepływu** WF01 → WF06 na danych testowych (atrapy `$input`, `$()`, `$now`, binarne MP3):
  odrzucanie starych pozycji, prywatne newslettery, routing ekstrakcji, oznaczanie niekompletnych, odrzucanie
  materiałów spoza AI i o niskiej ważności, filtrowanie halucynowanych `story_id`, wymuszenie ujawnienia głosu AI,
  limit znaków ElevenLabs, sklejanie MP3 i rozdziały z czasami, e-mail z audio / bez audio / alert o braku briefingu.

Podgląd wygenerowanego e-maila: `email/sample-briefing.html`.

```bash
npm run validate:sql
```

Migracja + seed (dwukrotnie — idempotentność) + test dymny na PostgreSQL 16 z pgvector i atrapą schematów `auth`/`storage`:
kolejka ekstrakcji/analizy, zbiorcze zapisy, grupowanie dwóch materiałów w jedno wydarzenie, ocena potwierdzenia,
kandydaci do briefingu, budżet, **RLS** (obcy użytkownik nic nie widzi, właściciel widzi), oceny, zapisane, postęp odsłuchu.

Testy aplikacji iOS: Xcode → *Product → Test* (`NewsflowTests`: dekodowanie odpowiedzi PostgREST, daty, adresy feedów, formatowanie).

## 2. Test „na żywo” — pierwszy dzień

Wykonaj kroki z [SETUP.md → Pierwsze uruchomienie](SETUP.md#7-pierwsze-uruchomienie-ręczne-w-tej-kolejności) i sprawdź:

- [ ] żadne źródło nie ma `error_count > 0` (inaczej popraw URL w karcie Źródła),
- [ ] w `content_items` ≤ 10% `failed`,
- [ ] 5 losowych analiz: streszczenie zgodne z oryginałem, bez dopisanych faktów, deklaracje oznaczone jako deklaracje,
- [ ] grupowanie: `select title, item_count, source_count from stories order by source_count desc limit 10;` — czy grupy są sensowne,
- [ ] briefing: 5–10 tematów, brak powtórzeń, najważniejszy temat faktycznie najważniejszy,
- [ ] audio: naturalne tempo, poprawna wymowa nazw, przejścia między tematami, zdanie o AI w intro,
- [ ] e-mail: działają linki do źródeł i do odsłuchu, temat `NEWSFLOW – AI Intelligence Briefing – DD.MM.RRRR`,
- [ ] aplikacja: odtwarzanie w tle i z ekranu blokady, zmiana tempa, przeskok rozdziałów, wznowienie od miejsca przerwania.

## 3. Okres testowy (14–30 dni) — dziennik

Codziennie 2 minuty: oceń briefing 👍/👎 i 3–5 materiałów w aplikacji. Raz w tygodniu uruchom:

```sql
-- 1. Kompletność zbierania: nowe materiały per źródło (czy żadne źródło nie "umilkło")
select s.name, count(ci.*) as items_7d, max(ci.collected_at) as last_item
from sources s left join content_items ci on ci.source_id = s.id and ci.collected_at > now() - interval '7 days'
where s.active group by s.name order by items_7d;

-- 2. Jakość ekstrakcji
select s.type, ci.extraction_status, count(*) from content_items ci join sources s on s.id = ci.source_id
where ci.collected_at > now() - interval '7 days' group by 1, 2 order by 1, 2;

-- 3. Rozkład ocen i odrzuceń (czy próg min_importance jest dobry)
select width_bucket(importance_score, 1, 10, 9) as bucket, count(*),
       count(*) filter (where is_relevant) as kept
from analyses where created_at > now() - interval '7 days' group by 1 order by 1;

-- 4. Powtórzenia: te same wydarzenia w kolejnych briefingach
select st.title, count(*) as briefings from briefing_stories bs join stories st on st.id = bs.story_id
join daily_briefings db on db.id = bs.briefing_id where db.briefing_date > current_date - 7
group by st.title having count(*) > 1;

-- 5. Punktualność
select briefing_date, created_at at time zone 'Europe/Warsaw' as ready_at,
       email_sent_at at time zone 'Europe/Warsaw' as sent_at, status
from daily_briefings order by briefing_date desc limit 14;

-- 6. Twoje oceny vs ocena systemu (czy wagi pasują do Ciebie)
select f.rating, round(avg(a.importance_score), 2), count(*) from user_feedback f
join analyses a on a.content_item_id = f.content_item_id group by f.rating;

-- 7. Koszt dzienny
select * from v_cost_daily order by day desc limit 14;

-- 8. Próby prompt injection wykryte w treściach
select ci.title, s.name from analyses a join content_items ci on ci.id = a.content_item_id
join sources s on s.id = ci.source_id where (a.raw_response->>'injection_detected')::boolean;
```

## 4. Kryteria sukcesu 0.1 (z planu) — jak sprawdzić

| Kryterium | Dowód |
|---|---|
| Automatycznie pobiera nowe materiały | zapytanie 1, `sources.last_success_at` |
| Przechowuje w Supabase | `content_items`, `analyses` |
| Analizuje i przypisuje kategorie | `content_categories`, `analyses.subcategory_slug` |
| Wykrywa powtórzenia | unikalny `content_hash` + `stories.item_count > 1` + zapytanie 4 |
| Wybiera najważniejsze | briefing vs Twoje oceny (zapytanie 6) |
| Poprawne polskie streszczenia | przegląd 5 losowych analiz tygodniowo |
| Briefing tekstowy | `daily_briefings`, e-mail |
| Audycja audio | `audio_assets`, aplikacja |
| E-mail z linkiem do odsłuchu | skrzynka, `email_sent_at` |
| Historia materiałów i nagrań | Biblioteka w aplikacji |
| Ocenianie przydatności | `user_feedback` |
| Kontrola kosztów | `v_cost_daily`, `app_config.limits` |

## 5. Strojenie po teście

| Objaw | Co zmienić |
|---|---|
| Za dużo słabych tematów | podnieś `pipeline.min_importance` (np. 5,5) |
| Różne wydarzenia sklejane w jedno | podnieś `story_similarity_threshold` (0,86) |
| To samo wydarzenie rozbite na kilka | obniż próg (0,78) |
| Ciągle te same źródła na górze | zmień `sources.priority`, oceniaj 👎 |
| Streszczenia zbyt ogólne | dopracuj `prompts/analyze_item.md`, podbij `prompt_version` |
| Audycja brzmi jak czytanie listy | dopracuj `prompts/audio_script.md` (przejścia, długość rozdziałów) |
| Briefing gotowy za późno | przesuń WF04/WF05 wcześniej (cron w węźle Schedule) |
