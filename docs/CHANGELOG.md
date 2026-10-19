# Changelog

## 0.6.3

- Save feedback briefly flashes and fades; full messages can be opened and copied, including after the notice disappears.
- Existing migrated actions can change triggers without being recreated.
- Queue triggers share one menu, with a separate once-per-input event for additions to an already active queue.

## 0.6.2

- Streamer.Bot action pickers load cached lists correctly, follow renamed actions by ID and flag deleted targets.
- Save results appear beside the Save button briefly, including validation failures.
- The main-window exit guard is registered after its functions are loaded.

## 0.6.1 — Hotfix

- Saving during exit closes the app after success; failures remain visible in the prompt without discarding drafts.
- Queue-added actions run once per message input, not once per generated clip.
- Action names update immediately in the list; new names and empty fields use focus-aware placeholders.
- Saved settings are detected reliably even when rapid Windows saves share a timestamp, without losing unsaved live changes.

## 0.6.0 — Assignments, multi-voice speech and live settings

- Redesigned Assignments with special viewer voices, edit/delete, role/group defaults and an inline fallback voice.
- Multi-voice chat tags, tolerant unambiguous alias matching, generate-ahead playback and optional sentence clips.
- Stable queue/history ordering, search, message details and changing an ungenerated queued voice.
- Global Save/Ctrl+S, live settings, Discard and unsaved-change protection for page/editor drafts.
- Configuration backup bundles include viewer assignments, with validated restore and recovery copies.
- Streamer.Bot automation improvements, categorized triggers and separate assignment-aware chat/command templates.
- One Streamer.Bot import for multistream setups, with selected-voice exports for expanding your voice library.
- Ready-made VIP/mod voice selection and moderator-only playback commands. Shared speech commands support bracketed voice names.
- Separate speech actions for chat commands, channel point rewards and chat messages. Command and mention cleanup preserves valid multi-voice speech.
- Consistent custom popup styling and corrected credential Show/Hide tracking.
- Fixed packaged Amazon Polly endpoint/service data; packaged-runtime checks now validate AWS models and certificates offline.
- Dashboard UI checks no longer presume the build runner's monitor size.

## 0.5.0 — Initial YapLoq release

- Six-page desktop interface: Dashboard, Voices, Queue, Services, Streamer.Bot and Settings.
- Custom voice icons from Icônes, alias colors, favorites, playlists and routing.
- Unified queue and history with stable order, recording replay and context actions.
- Dashboard recent speech stays visible through playback completion.
- Masked service credentials with show/hide controls.
- In-app GitHub release checks, patch notes, verified update downloads and restart installation.

### Earlier development work

- Applies the supplied YapLoq microphone and wordmark to the title bar,
  sidebar, About panel, Windows executable/window icons, tray and README banner.
  Original vector masters and reproducible icon exports are included.

- History media-bar playback uses the selected recording without copying or
  regenerating it. Missing recordings are hidden; History and cache share one limit.
- Whole-row History selection, wrapped playlist rows and rounded frames.
- Collapsible profanity rules with per-word toggles, variants, replacement
  alternatives, remove/block actions, and words hidden by default.
- Sliders with exact-value entry for limits and cooldowns.
- Smoother playback progress, seeking, responsive polling, collapsible setup guides,
  rounded control states and locally bundled Poppins typography.

Adds Speaker.bot-compatible cloud TTS engines: ElevenLabs, Azure Speech,
Google Cloud TTS, IBM Watson, UberDuck, TTS.Monster, Acapela, and CereProc.
Each engine has a Services page. Secrets use the same Windows DPAPI protection
as Polly.

Also in this preview:

- Streamer.bot UDP speak identity handling (display vs login; reject `%user%` JSON blobs)
- Allowlist / protocol hardening for speak requests
- Voices **ON** toggles for the global `random` Speak pool; Streamer.bot export can use Random
- **Rules → Voice playlists** for named pools (`playlist:Name`) usable in Speak, routing, and export
- Playground multi-line script layout, pill scrollbars, VoiceStudio and Streamer.bot UI cleanup
- Packaging copies `LICENSE`, notices, `LEGAL.md`, and `docs/` into the Windows zip

The build is **unsigned**. Cloud TTS is billed by each provider. Native Streamer.bot
imports and live OBS/device/DPI checks remain release gates; see `ROADMAP.md` and
`docs/RELEASE_NOTES.md`.

## 0.4.0 preview

Adds queue safeguards, active-audio pause, paused recovery, ordered routing,
profiles, Windows voices, SSML, OBS ducking, output controls, data maintenance,
voice search/favorites, event diagnostics and native Streamer.bot action exports.

Fixes interrupted settings writes, long skip delays, duplicate lifecycle
registration, tests contaminating the live queue, unnecessary history refreshes,
incorrect alias-profile selection, missing editable dropdown controls, silent
playback failures, custom-port startup checks and a UDP shutdown race.

The preview is unsigned. Native Streamer.bot imports and live OBS/device/DPI
checks remain release gates; see ROADMAP.md. The existing 0.3 installation is
unchanged by this build.
