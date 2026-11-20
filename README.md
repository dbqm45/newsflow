# NEWSFLOW Personal 0.1

Osobisty, polskojęzyczny „Spotify dla informacji o AI”. System sam zbiera materiały
(RSS, blogi, Medium, YouTube, Reddit, podcasty, newslettery z Gmaila), ocenia je jak redaktor,
grupuje w wydarzenia, codziennie o 07:00 przygotowuje briefing, generuje ~12-minutową audycję
i o 08:00 wysyła e-mail. Słuchasz i czytasz w natywnej aplikacji iOS: odtwarzanie w tle,
ekran blokady, rozdziały, tempo, kolejka.

```
 Źródła ──► n8n Cloud ──────────────────────────────► Supabase (Postgres + Storage)
            WF01 zbieranie ─► WF02 ekstrakcja ─►            ▲            │
            WF03 redaktor AI (OpenAI) ─► WF04 briefing ─►   │            ▼
            WF05 audio (ElevenLabs) ─► WF06 e-mail (Gmail)  │     Aplikacja iOS (SwiftUI)
                                                            └──── oceny, zapisane, postęp
```

## Co jest w repozytorium

| Ścieżka | Zawartość |
|---|---|
| `supabase/migrations/…_init.sql` | Pełny schemat: tabele, indeksy, RLS, funkcje RPC, widoki, prywatny bucket `audio` |
| `supabase/seed.sql` | Kategorie (AI + 15 podkategorii), konfiguracja (wagi, modele, limity), ~18 źródeł startowych |
| `n8n/workflows/*.json` | 7 gotowych workflow do importu (WF01–WF06 + WF99 obsługa błędów) |
| `n8n/src/` | Źródła logiki węzłów Code (biblioteki + kod) — z nich generowane są JSON-y |
| `prompts/` | Prompty redakcyjne: analiza materiału, briefing dnia, scenariusz audycji |
| `schemas/` | Schematy JSON odpowiedzi AI (OpenAI Structured Outputs, tryb strict) |
| `config/audio.json` | Konfiguracja i dobór głosu ElevenLabs |
| `email/briefing.html` | Szablon e-maila (`email/sample-briefing.html` — podgląd z danymi testowymi) |
| `ios/` | Aplikacja iOS 17+ (SwiftUI, XcodeGen, supabase-swift) |
| `supabase/functions/tts-preview/` | Edge Function dla ekranu „Porównanie głosów” (OpenAI TTS / ElevenLabs, cache, limity) |
| `docs/` | [Architektura](docs/ARCHITECTURE.md) · [Konfiguracja krok po kroku](docs/SETUP.md) · [Testy i odbiór](docs/TESTING.md) · [Koszty](docs/COSTS.md) |

## Szybki start

1. **Supabase** — utwórz projekt, wklej w SQL Editor `supabase/migrations/20261120000001_init.sql`, potem `supabase/seed.sql`.
2. **n8n Cloud** — utwórz 4 credentials (Supabase, OpenAI, ElevenLabs, Gmail), zbuduj workflow ze swoim adresem Supabase
   i zaimportuj pliki z `n8n/workflows/`:
   ```bash
   SUPABASE_URL=https://TWOJ-REF.supabase.co npm run build:n8n
   ```
3. **iOS** — `cd ios && cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig`, uzupełnij, `xcodegen generate`, uruchom w Xcode.

Szczegóły, z miejscami na każdy klucz: **[docs/SETUP.md](docs/SETUP.md)**.

## Rozwój i testy lokalne

```bash
npm install
npm test               # 19 testów: biblioteki + symulacja przepływu WF01→WF06 na danych testowych
npm run validate:sql   # migracja + seed + test dymny RLS/RPC na lokalnym PostgreSQL 16 z pgvector
```

Logikę węzłów Code edytuj w `n8n/src/`, nie w n8n — potem `npm run build:n8n` i ponowny import.

## Zasady projektu

- Najpierw jakość i użyteczność dla jednej osoby, potem skalowanie.
- Treści z sieci, maili i transkrypcji to **niezaufane dane** — prompty nigdy nie wykonują zawartych w nich poleceń.
- Fakty oddzielone od opinii, prognoz i deklaracji marketingowych; zawsze link do oryginału.
- Zero kluczy w kodzie: credentials w n8n, publishable key w lokalnym `Secrets.xcconfig` (gitignored).
- Audycje oznaczone jako generowane przez AI (w nagraniu, w aplikacji i w e-mailu).
