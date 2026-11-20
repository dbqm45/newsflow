# TODO

## Koszty audio (ElevenLabs)

- [ ] **Później:** przełączyć audycję na 5 minut i model `eleven_flash_v2_5` (wariant mieszczący się w planie Creator, ~22 USD/mies.):
  ```sql
  update app_config set value = jsonb_set(value, '{audio_target_minutes}', '5') where key = 'pipeline';
  update app_config set value = jsonb_set(value, '{model_id}', '"eleven_flash_v2_5"') where key = 'elevenlabs';
  ```
  Uzasadnienie i porównanie wariantów: `docs/COSTS.md`.

- [ ] **Do decyzji:** audio na żądanie zamiast codziennego generowania (tekst w aplikacji, głos dopiero po kliknięciu Play).
  Opcje: darmowy głos systemowy iOS, ElevenLabs per temat z cache w Supabase Storage, OpenAI TTS. Mierzyć rzeczywiste słuchanie przez `playback_progress`.
