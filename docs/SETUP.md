# Konfiguracja krok po kroku

Wszystkie miejsca do uzupełnienia są oznaczone `REPLACE…` / `YOUR-PROJECT-REF`. Żaden klucz nie trafia do repozytorium.

Kolejność: **1 Supabase → 2 OpenAI → 3 ElevenLabs → 4 Gmail → 5 n8n → 6 iOS → 7 pierwsze uruchomienie.**

---

## 1. Supabase (baza, storage, logowanie)

1. Utwórz projekt na <https://supabase.com> (region: Frankfurt `eu-central-1`). Plan Free wystarcza na start.
2. **SQL Editor → New query** → wklej całość `supabase/migrations/20261120000001_init.sql` → *Run*.
   Migracja włącza `pgvector`, tworzy tabele, RLS, funkcje, widoki i prywatny bucket `audio`.
3. Nowe zapytanie → wklej `supabase/seed.sql` → *Run* (kategorie, konfiguracja, źródła startowe).
4. **Authentication → Sign In / Providers → Email**: włącz Email, **wyłącz „Allow new users to sign up”**.
5. **Authentication → Users → Add user → Create new user**: Twój e-mail + silne hasło, zaznacz *Auto Confirm User*.
6. **Właściciel** — SQL Editor:
   ```sql
   insert into public.app_members (user_id, role)
   select id, 'owner' from auth.users where email = 'TWOJ_EMAIL';

   insert into public.user_preferences (user_id, email)
   select id, email from auth.users where email = 'TWOJ_EMAIL';

   -- adres, na który ma przychodzić briefing
   update public.app_config
   set value = jsonb_set(value, '{email_to}', '"TWOJ_EMAIL"')
   where key = 'delivery';
   ```
7. **Project Settings → API Keys** — zanotuj:
   - **Project URL** `https://<ref>.supabase.co` → do n8n (build) i iOS,
   - **Publishable key** `sb_publishable_…` → tylko do aplikacji iOS,
   - **Secret key** `sb_secret_…` → tylko do n8n. Nigdy do aplikacji ani repozytorium.
8. **Kopie zapasowe:** plan Free nie ma automatycznych backupów do przywrócenia z panelu — raz w tygodniu
   `supabase db dump` (CLI) albo plan Pro (codzienne backupy).

## 2. OpenAI

1. <https://platform.openai.com/api-keys> → *Create new secret key* (projekt „newsflow”, uprawnienia: *All* lub *Restricted* z dostępem do Chat Completions i Embeddings).
2. **Settings → Limits**: ustaw *monthly budget* (np. 15 USD) — to druga linia obrony obok limitów w `app_config.limits`.
3. Modele są w `app_config.models` (`gpt-5-mini` analiza, `gpt-5` briefing, `gpt-5-mini` scenariusz, `text-embedding-3-small`).
   Zmienisz je bez ruszania workflow:
   ```sql
   update app_config set value = jsonb_set(value, '{briefing}', '"gpt-5-mini"') where key = 'models';
   ```
   Przy zmianie modelu zaktualizuj też `app_config.pricing_usd_per_1m_tokens` (szacowanie kosztów).

## 3. ElevenLabs (głos)

1. <https://elevenlabs.io> → plan zgodny z budżetem (zob. [COSTS.md](COSTS.md) — 12 min dziennie wymaga ~375 tys. znaków/mies.).
2. **Voice Library** → filtr *Polish*, kategoria *Narrative / News* → odsłuchaj próbki (sprawdź wymowę „OpenAI”, „Hugging Face”, „Anthropic”) → *Add to my voices* → skopiuj **Voice ID**.
3. **Profile → API Keys** → utwórz klucz (uprawnienie: *Text to Speech*).
4. Wpisz głos i limit znaków zgodny z planem:
   ```sql
   update app_config set value = jsonb_set(value, '{voice_id}', '"TWOJ_VOICE_ID"') where key = 'elevenlabs';
   update app_config set value = jsonb_set(value, '{elevenlabs,monthly_characters}', '100000') where key = 'limits';
   ```
   Pozostałe opcje głosu: `config/audio.json`.

## 4. Gmail (newslettery + wysyłka briefingu)

1. **Zalecane:** osobne konto Gmail na newslettery (np. `twojenewsy.ai@gmail.com`). Gmail API nie pozwala ograniczyć dostępu
   OAuth do jednej etykiety — osobne konto oddziela prywatną korespondencję od systemu.
2. Utwórz etykietę **AI-READ** i filtr: *Od: (adresy newsletterów) → Zastosuj etykietę AI-READ*.
3. W n8n credential Gmail (punkt 5) zaloguj się tym kontem. Briefing może być wysyłany z tego konta na Twój główny adres.

## 5. n8n Cloud

### 5.1 Credentials (Overview → Credentials → Create) — nazwy muszą być dokładnie takie:

| Nazwa | Typ | Wartość |
|---|---|---|
| `NEWSFLOW Supabase` | **Custom Auth** | `{"headers": {"apikey": "sb_secret_…"}}` (dla starego klucza `service_role`: `{"headers": {"apikey": "<service_role>", "Authorization": "Bearer <service_role>"}}`) |
| `NEWSFLOW OpenAI` | **OpenAI** | API key z punktu 2 |
| `NEWSFLOW ElevenLabs` | **Header Auth** | Name: `xi-api-key`, Value: klucz z punktu 3 |
| `NEWSFLOW Gmail` | **Gmail OAuth2** | *Sign in with Google* (konto z punktu 4) |
| `NEWSFLOW Transcript API` *(opcjonalnie)* | **Header Auth** | Name: `x-api-key`, Value: klucz dostawcy transkrypcji YouTube (np. Supadata) |

### 5.2 Zbuduj workflow ze swoim adresem Supabase

```bash
npm install
SUPABASE_URL=https://TWOJ-REF.supabase.co npm run build:n8n
```

(Bez Node.js: w plikach `n8n/workflows/*.json` zamień `https://YOUR-PROJECT-REF.supabase.co` na swój adres.)

### 5.3 Import

1. *Workflows → Add workflow → ⋯ → Import from File* — kolejno `WF99`, `WF01` … `WF06`.
2. W każdym workflow otwórz węzły z czerwonym znacznikiem i wybierz credential o tej samej nazwie (n8n dopasowuje po nazwie; jeśli nie — wybierz ręcznie).
3. **Settings** każdego WF01–WF06 → *Error workflow* → `NEWSFLOW WF99 – Error Handler`. Strefa czasowa jest już ustawiona na `Europe/Warsaw`.
4. **WF01 → węzeł „Gmail: AI-READ”**: w polu *Label Names or IDs* wybierz `AI-READ` z listy, następnie *Activate/Enable node* (prawy przycisk → *Deactivate* przełącza).
5. **WF02 → „Transcript API (optional)”** — włącz tylko, jeśli masz dostawcę transkrypcji YouTube (płatny). Odpowiedź musi zawierać pole `content`.

## 6. Aplikacja iOS

Wymagania: Mac z Xcode 16+, iPhone z iOS 17+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
```

```bash
cd ios && cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

Uzupełnij `ios/Config/Secrets.xcconfig`: `SUPABASE_HOST` (bez `https://`), `SUPABASE_PUBLISHABLE_KEY`, `NEWSFLOW_TEAM_ID`
(Xcode → Settings → Accounts → Team ID), `NEWSFLOW_BUNDLE_ID` (unikalny, np. `pl.twojeimie.newsflow`).

```bash
xcodegen generate && open Newsflow.xcodeproj
```

Wybierz swój iPhone jako cel → *Run*. Za pierwszym razem: iPhone → Ustawienia → Ogólne → VPN i urządzenia → zaufaj deweloperowi.
Darmowe Apple ID: instalacja ważna 7 dni (potem ponowny *Run*). Apple Developer Program (99 USD/rok): TestFlight i brak wygasania.

Zaloguj się kontem z punktu 1.5. Link `newsflow://briefing/RRRR-MM-DD` (z e-maila) otwiera aplikację.

> Kod aplikacji nie był kompilowany w środowisku, w którym powstał (brak Xcode). Jeśli pierwsza kompilacja zgłosi błąd —
> zwykle to drobna różnica w API wersji `supabase-swift`; komunikat z Xcode wystarczy do szybkiej poprawki.

## 7. Pierwsze uruchomienie (ręczne, w tej kolejności)

| Krok | Co zrobić | Czego oczekiwać |
|---|---|---|
| 1 | WF01 → *Test workflow* | `sources.last_success_at` uzupełnione; w `content_items` kilkadziesiąt wierszy `pending` |
| 2 | WF02 → *Test workflow* (2–3 razy, paczki po 20) | statusy `extracted` / `incomplete` |
| 3 | WF03 → *Test workflow* (kilka razy) | wiersze w `analyses`, `stories`, `api_usage` |
| 4 | WF04 → *Test workflow* | `daily_briefings` ze statusem `script_ready` |
| 5 | WF05 → *Test workflow* | pliki w Storage → `audio/briefings/…`, status `audio_ready` |
| 6 | WF06 → *Test workflow* | e-mail w skrzynce, status `delivered` |
| 7 | Aplikacja iOS | briefing na ekranie „Dziś”, odtwarzanie, rozdziały |

Potem przełącz WF01–WF06 na **Active**. Przydatne zapytania kontrolne:

```sql
select extraction_status, analysis_status, count(*) from content_items group by 1, 2 order by 1, 2;
select name, last_success_at, error_count, last_error from sources order by error_count desc;
select * from v_cost_daily order by day desc limit 14;
select workflow, status, finished_at, error from pipeline_runs order by finished_at desc limit 20;
```

## Zmiana ustawień bez edycji workflow

| Co | Gdzie |
|---|---|
| Wagi oceny, próg odrzucenia, próg grupowania, długość audycji, liczba tematów | `app_config` → `scoring_weights`, `pipeline` |
| Modele i cennik | `app_config` → `models`, `pricing_usd_per_1m_tokens` |
| Limity kosztów | `app_config` → `limits` |
| Głos | `app_config` → `elevenlabs` |
| Adres e-mail | `app_config` → `delivery.email_to` |
| Źródła | aplikacja iOS (karta Źródła) albo tabela `sources` |
| Prompty | `prompts/*.md` → `npm run build:n8n` → ponowny import WF03/WF04 (podbij `prompt_version` w pierwszej linii) |
