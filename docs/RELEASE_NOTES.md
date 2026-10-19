# YapLoq 0.6.0 — Assignments, multi-voice speech and live settings

Voice automation for streamers, with a Windows desktop app and Streamer.Bot integration.

## New in 0.6.0

- Assign special voices to viewers using stable platform/user IDs. Edit/delete assignments, choose role/custom-group defaults, and set the fallback voice inline.
- Use multiple aliases in one input, such as `[Plankton] Hello! [Spongebob] Hi!`. Chat tags support enabled voices, case-insensitive names and unambiguous word-prefixes. Optional sentence-per-clip generation is off by default in Settings.
- Upcoming speech generates ahead of playback. Queue/history remain newest-first without promoting replayed recordings; search, inspect full message details, or change the voice of an ungenerated queued message.
- Valid settings apply live. Save/Ctrl+S keeps changes; right-click Save to discard unsaved edits. Ports/recovery require Save and restart. Destructive retention and action/voice record changes retain explicit Save.
- Unsaved-change prompts protect page and editor drafts. Popup title bars follow the app design; credential visibility toggles no longer mark settings dirty or disable themselves during live validation.
- Configuration backups include settings, actions and viewer assignments, with validation and recovery copies on restore.
- Expanded Streamer.Bot automations and categorized event triggers, plus separate assignment-aware chat and command templates.
- Amazon Polly voices now load in the packaged Windows app: missing AWS endpoint/service data and certificate packaging are fixed and checked before release.

### Integration notes

One Streamer.Bot import works across Twitch, YouTube and Kick, including multistream setups. Ready-made commands include VIP/mod voice selection and moderator-only playback controls. Existing integrations remain compatible.

## What's included

- Dashboard for speaking with your selected voice and replaying recent speech.
- Eleven speech services, including Windows voices, VoiceStudio, Amazon Polly, ElevenLabs, Azure and Google Cloud TTS.
- Voice aliases with custom Icônes icons, colors, favorites, playlists and routing.
- Unified queue and history with generation/playback statuses, manual ordering, recording replay, save audio and right-click actions.
- Streamer.Bot action exports, UDP speech requests and optional playback actions.
- Pronunciation and message filters, profanity rules, queue limits and cooldowns.
- Separate stream/preview audio outputs and optional OBS ducking.
- Encrypted service credentials, masked by default with show/hide controls.
- GitHub release checks, patch notes and verified in-app update downloads with backup and restart installation.

## Download and start

1. Download **YapLoq-Windows-x64-update.zip** from this release.
2. Extract the entire ZIP to a writable folder. Keep `_internal` beside `YapLoq.exe`.
3. Run **YapLoq.exe**. Python is not required.
4. Open **Services**, connect a service, then create and test an alias in **Voices**.
5. Open **Streamer.Bot** for the connection and action export instructions.

The same ZIP is the portable first-time download and the package used by the in-app updater.

## Notes

- Windows 10/11, 64-bit. This build is unsigned; Windows SmartScreen may show a warning.
- Cloud speech usage is billed by each provider. Use voices you own or have permission to use.
- Settings, history and audio remain local. Windows-encrypted credentials must be entered again on another computer or Windows account.
- The separate development preview retains its own data folder and update channel. This release does not automatically migrate preview settings.
- Provider availability, audio hardware and OBS behavior depend on your setup. See the roadmap for ongoing validation and planned improvements.

YapLoq is distributed under the MIT License. See LICENSE, THIRD_PARTY_NOTICES.md and docs/LEGAL.md.
