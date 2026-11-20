# Koszty i kontrola budżetu

## Szacunek miesięczny (60–80 nowych materiałów dziennie, briefing 12 min)

| Usługa | Plan | Szacunek / mies. | Z czego wynika |
|---|---|---|---|
| n8n Cloud | Starter | ~20–24 EUR | ~1 200 wykonań/mies. (WF01–03 co 2 h + 3 dzienne) — mieści się w limicie 2 500 |
| Supabase | Free | 0 USD | baza < 500 MB, storage < 1 GB (~8 MB audio/dzień ⇒ ~4 miesiące archiwum; potem Pro 25 USD lub czyszczenie starych MP3) |
| OpenAI | pay-as-you-go | 6–14 USD | analiza `gpt-5-mini` ~0,15–0,30 USD/dzień; briefing `gpt-5` + scenariusz `gpt-5-mini` ~0,05–0,12 USD/dzień; embeddingi < 0,01 |
| ElevenLabs | **zależy od długości audycji** | 22–99 USD | 12 min ≈ 12 500 znaków/dzień ≈ **375 tys. znaków/mies.** |
| Gmail | — | 0 | |

### ⚠️ ElevenLabs nie mieści się w budżecie 5–15 USD przy 12 min dziennie

Plan dokumentu zakładał 5–15 USD na ElevenLabs. Przy `eleven_multilingual_v2` (1 kredyt = 1 znak):

| Wariant | Znaki / mies. | Plan ElevenLabs | Koszt |
|---|---|---|---|
| 12 min, multilingual v2 | ~375 tys. | Pro (500k) | ~99 USD |
| 12 min, flash v2.5 (0,5 kredytu/znak) | ~190 tys. kredytów | Pro / Creator + dopłaty | ~50–99 USD |
| **5 min, flash v2.5** | ~80 tys. kredytów | **Creator (100k)** | **~22 USD** |
| 4 min, multilingual v2 | ~95 tys. | Creator (100k) | ~22 USD |

Rekomendacja na okres testowy: **Creator + `audio_target_minutes = 5` + `eleven_flash_v2_5`**, a po 2 tygodniach decyzja,
czy dłuższa audycja jest warta Pro. Zmiana:

```sql
update app_config set value = jsonb_set(value, '{audio_target_minutes}', '5') where key = 'pipeline';
update app_config set value = jsonb_set(value, '{model_id}', '"eleven_flash_v2_5"') where key = 'elevenlabs';
```

Tańsza alternatywa do rozważenia po teście: OpenAI TTS (`gpt-4o-mini-tts`, ~0,015 USD/min ⇒ ~5–6 USD/mies. za 12 min dziennie),
kosztem nieco mniej naturalnej polskiej prozodii. Wymagałoby to podmiany węzła TTS w WF05.

**Realny cel na start:** ~50–60 USD/mies. (n8n 22 + OpenAI 10 + ElevenLabs Creator 22). Cel 20–30 USD jest osiągalny
tylko z krótszą audycją na tańszym TTS lub z self-hosted n8n.

## Mechanizmy kontroli (wbudowane)

1. **Limity twarde** — `app_config.limits` (`daily_usd`, `monthly_usd`, `daily_calls`, `monthly_characters`).
   `check_budget()` jest wołane przed każdym przebiegiem WF03, WF04 i WF05:
   - WF03 po przekroczeniu cicho pomija przebieg (materiały czekają),
   - WF04/WF05 kończą się błędem widocznym w `pipeline_runs`; WF06 wysyła wtedy wersję tekstową lub alert.
2. **Zapis każdego wywołania** — `api_usage` (tokeny, znaki, koszt, materiał/briefing).
3. **Koszt analizy i nagrania** — `analyses.cost_usd`, `audio_assets.cost_usd`, `daily_briefings.cost_usd`.
4. **Widok dzienny** — `v_cost_daily`, w aplikacji: Ustawienia → Stan systemu i koszty.
5. **Limit po stronie dostawców** — ustaw *monthly budget* w OpenAI i limit planu w ElevenLabs.

## Dźwignie, gdy koszty rosną

| Dźwignia | Efekt |
|---|---|
| `pipeline.max_content_chars` 16000 → 8000 | ~-40% tokenów wejściowych analizy |
| wyłącz źródła o niskim priorytecie / `max_items` dla Reddita | mniej materiałów do analizy |
| `models.briefing` → `gpt-5-mini` | ~-80% kosztu briefingu |
| `pipeline.audio_target_minutes` | liniowo koszt ElevenLabs |
| `pipeline.min_importance` ↑ | mniej materiałów w wydarzeniach (nie zmienia kosztu analizy) |
