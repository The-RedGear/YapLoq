# YapLoq — Remaining feature list

Updated October 18, 2026 against the initial v0.5.0 release.

Source: the supplied YapLoq_Redesign_Codex_Files_NEW (1).zip, especially 01_PRODUCT_SPEC.md and 03_ACCEPTANCE_CHECKLIST.md, plus decisions made afterward in this conversation. This is a remaining-work list, not a new product specification.

Completed work has been removed. “Partial” means an existing implementation needs the specific remaining work described. “Verify” means capability exists or has been claimed, but the requested behavior is not established end to end; do not rebuild it without checking.

## Decisions that override the original brief

These are settled constraints, not unfinished tasks:

- Sidebar: Dashboard, Voices, Queue, Services, Streamer.Bot, Settings.
- Queue and History share one chronological list. Newest admission is first; status changes and replays never promote an existing recording. Explicit manual moves are respected.
- Dashboard keeps a compact queue/recent-speech list, including previous voices, replay buttons and context actions.
- Voice icons may come from any supported Icônes collection, rather than only MDI.
- Alias color applies to voice-list selection, player artwork/background and Dashboard composer controls. The voice editor's Save button and provider-profile selection retain app purple. Recent-speech replay buttons retain app purple.
- Saved-alias selection controls use the alias icon and its own highlight color consistently; default, playlist and random selectors retain standard app styling.
- Update controls use the app's purple styling. Only the main title-bar download icon turns green when an update exists.
- Use one normal installed executable location when applying updates.

## 1. Dashboard

- [ ] Search the voice selector directly. The icon-bearing picker exists; quick text search still needs completion or verification.
- [ ] Verify that Dashboard, Queue and player reconcile the same speech IDs through rapid generation, completion and replay. The reported disappearing/reordering bugs have been fixed; do not list those fixes as new features.
- [ ] Preserve Dashboard input, selection and relevant view state across navigation and restart where appropriate.

## 2. Voices: editing and organization

- [ ] Bulk voice management: select several aliases and apply supported shared actions without losing per-voice settings.
- [ ] Provider-aware editor controls: show only capabilities supported by the selected provider; cover supported pitch/style options rather than presenting ineffective controls. Partial: provider/model/speed/volume controls already exist.
- [ ] Contextual Configure service shortcut from the alias editor, returning to the same edit context.
- [ ] Protect unsaved edits when closing an editor or switching context.
- [ ] Undo for practical reversible operations such as removing an alias.
- [ ] Independent preview playback that does not interrupt or join live speech. Partial: a separate preview output exists; a separate concurrent playback path still needs verification/completion.

## 3. Playlists

Partial: named playlists reference aliases, support basic random selection, and can be used in speech and automation. Do not recreate basic playlist creation or random pools.

- [ ] Sequential rotation.
- [ ] Weighted random selection.
- [ ] Optional prevention of consecutive repeats.
- [ ] Explicit member ordering and convenient playlist duplication.
- [ ] Clear behavior for empty playlists and missing, disabled or unavailable voices.
- [ ] Define selection scope: per message versus a persistent viewer assignment.
- [ ] Preserve references when aliases or playlists are renamed or removed.

## 4. Viewer voice assignments

Partial: Voices > Assignments combines stable platform/user-ID preferences, conditional rules, legacy name/role defaults and a configurable fallback voice. Viewers support searching, alias/playlist preferences, reset, rename-safe identities, availability warnings, and message context assignment. Assignments are saved atomically in data/viewers.json with a previous-version .bak copy. Structured GetViewers, GetViewerVoice and SetViewerVoice requests are implemented for trusted integrations. Rules/default voice remain in settings.json; existing data is retained.

- [x] Opt-in public voice names and audience restrictions; private by default, with permissions rechecked on speech.
- [x] Viewer !voice name, !voice random, !voice reset and list commands, plus an importable Streamer.Bot forwarding action.
- [x] Platform-specific Streamer.Bot command/speech templates and viewer success, reset, list and failure events with reply/identity arguments for configurable response actions.
- [ ] External Streamer.Bot command-trigger and chat-reply validation. Reply actions must be configured by the user; imports do not attach chat triggers automatically.
- [x] Configuration backup ZIPs include settings, actions and viewer assignments; validated restore creates a pre-restore recovery bundle and rolls back files on write failure. Legacy settings-only JSON remains readable and leaves viewers untouched.
- [ ] Add stable platform/user-ID fields to exported legacy VSPEAK workflows. Existing name-only packets still use legacy routing; JSON/HTTP/WebSocket requests can supply stable identity now.

## 5. Voice routing and pronunciation

Partial: routing and global pronunciation already exist and have the requested homes.

Voice selection is now verified and documented: explicit request, saved viewer preference, conditional rule, legacy name/role fallback, configured default, first available enabled alias. Priority rules are independent. Streamer.Bot exports offer Use assignments for automatic voice selection; old explicit exports retain their explicit voice.
- [ ] Explain “Why this voice?” in message details.
- [ ] Per-voice pronunciation overrides in addition to the existing global dictionary.
- [ ] Ensure alias edits affect future requests without unexpectedly changing playing or already-resolved queued speech.

## 6. Queue and message tools

Partial: the unified list, statuses, replay, manual ordering, audio actions and context menus already exist.

- [x] Search speech by voice, message, viewer, platform, source and error; filter by active, completed, failed or skipped/cancelled status without changing chronological order.
- [x] Read-only message details with full text, voice, status, source, viewer, time and recorded failure reason.
- [ ] Explain selected-voice resolution in message details, and retain pre-admission rejection records (which do not currently create queue entries).
- [x] Change an ungenerated Queued message's voice from Queue toolbar/right-click, preserving its ID, timestamp, position, text and viewer identity. Saved aliases and playing speech remain unchanged. Generating/prepared/replayed/current/completed items are protected.
- [ ] Verify priority controls remain understandable and accessible in the combined list.
- [ ] Retain selection and scroll during sustained input, history refresh, manual moves and replay.
- [ ] Verify completed, skipped, cancelled and failed requests remain distinguishable, with history/cache retention independent of waiting speech.

## 7. Persistent player

Partial: persistent controls, progress, seeking, audio save and Queue shortcut already exist.

- [ ] Convenient volume/mute and output selection in the media bar, opening the canonical audio settings for advanced configuration.
- [ ] Verify emergency-stop behavior is clear alongside the separate “stop after current” control.
- [ ] Complete the independent preview behavior described under Voices.

## 8. Services

Partial: provider overview/quick links, connection editors, tests and masked credentials are implemented.

- [ ] Provider capability, usage, quota and cost information where a provider actually supplies it. Avoid fabricated balances or availability claims.
- [ ] Accurate actionable service errors for authentication, quota, timeout and provider outages.
- [ ] Verify connection indicators distinguish configured credentials from a successful service connection.
- [ ] Audit remaining credential helper text for the old “leave blank to keep” instructions now that saved credentials load masked.

## 9. Streamer.Bot

Partial: connection configuration, action export, message sources, payload helpers and lifecycle actions already exist.

- [ ] Visual argument mapping and richer custom payload configuration beyond the implemented event placeholders and JSON argument editor.
- [ ] Viewer voice commands and SetViewerVoice integration from section 4.
- [ ] Complete the external Streamer.Bot end-to-end setup test and extend request accounting to HTTP/WebSocket if needed. UDP listener health, bind errors, request counters and a speech-free local listener test are implemented.
- [ ] Distinguish request receipt/acceptance from generation and playback completion.
- [ ] Useful failure feedback and reconnect/retry controls where the transport supports them.
- [ ] Keep common setup simple, with advanced controls available separately.

## 10. Settings and overall usability

Partial: audio settings, tray behavior, backups, diagnostics, updates and the main page organization already exist.

- [ ] Compact/comfortable density options and supported UI scaling preferences.
- [ ] Broader keyboard shortcuts; Ctrl+Shift+S emergency stop already exists.
- [ ] Ctrl+K command/search palette, if it materially reduces navigation.
- [ ] Remember window/editor sizes and positions.
- [ ] Preserve subsection, filter, selection and appropriate scroll state.
- [x] Global title-bar Save/Ctrl+S tracks page drafts, preserves them across navigation/refresh, validates before committing and retains failed edits. Local editor/record confirmations remain explicit.
- [ ] Warn before exiting with unsaved page drafts and verify all editor cancellation paths.
- [ ] Inline editing and small popovers for simple frequent tasks where useful.
- [ ] Verify keyboard focus, accessible labels, screen-reader behavior and physical high-DPI/mixed-monitor layouts.
- [ ] Verify remaining controls have consistent icons, tooltips and discoverable alternatives to right-click menus.

## 11. Added after the original list

### Streamer.Bot action/sub-action workspace — first version implemented

Actions is now the default Streamer.Bot tab, with existing settings under Connection. The workspace supports named/enabled automations, multiple event triggers, field conditions, ordered Run action/Delay steps, remote action discovery and search, argument templates, duplication, manual reordering and stop/continue error behavior. Saving migrates existing hooks with a settings backup and preserves queue-session semantics.

The workspace now has resizable action/trigger/sub-action panes, first-action guidance and context menus. The sub-action picker loads automatically, caches the catalogue in the app data folder, and filters names/IDs as you type with a bounded result list. Saved automation definitions remain in the data-folder settings file.

Remaining from the broader automation design:

- [ ] Drag-and-drop ordering in addition to the working up/down controls.
- [ ] Configurable per-automation execution queues, concurrency and ignore-while-busy modes. The first version serializes runs.
- [ ] Confirmed remote-action completion where Streamer.Bot provides it; current HTTP dispatch confirmation is not remote completion.
- [ ] Retry policies with clear limits and backoff.
- [ ] Detailed per-run/step history and a deliberate test-run interface. Failures currently appear in the existing event inspector and logs.
- [ ] Visual argument mapping beyond the current JSON key/value editor, and richer conditions/branching if needed.
- [ ] Expose additional connection/provider/application events as they are implemented by YapLoq; do not show triggers that never fire.

### Generate upcoming speech ahead of playback — core implemented locally

- Waiting speech is prepared during active playback, reuses its cached recording, and changes Generating/Ready status on its existing entry. Playback order still follows the queue and explicit manual moves. Paused playback does not start look-ahead requests. At most two pending preparations are retained after manual reorders; provider requests retain the existing global two-request bound, including uncancellable skipped requests.
- [ ] Provider-specific limits and rate-limit handling beyond the conservative global bound; avoid overwhelming services or increasing paid usage unnecessarily.
- [ ] Respect manual moves, skip, remove, clear and voice changes; cancel pending work where possible and discard stale results safely.
- [ ] Bound prepared-audio memory/cache usage, reuse generated audio, and handle individual generation failures without stalling the queue.
- [x] Automated playback test verifies multi-voice segment order while generating ahead. Physical high-volume testing remains above.

### Multiple voices in one input — new feature

- [x] Parse inputs such as: [Plankton] Hello! [Spongebob] Hi, Plankton! into ordered speech entries.
- [x] Shared Dashboard/Streamer.Bot implementation, prefix text using the selected/resolved voice, empty text skipped, literal opening brackets escaped with a backslash, and unknown tags rejected.
- [x] Validate every segment before enqueueing any; total character/queue/user limits and one cooldown per input. Viewer tags obey public names and permissions. Plain text only for multi-voice inputs; maximum 20 tags.
- [ ] Physical end-to-end Streamer.Bot multi-voice testing under live input load.

### Reliable high-volume input — follow-up

- [ ] Extend burst checks to concurrent playback, provider failures, and a real Streamer.Bot sender. Real UDP-to-queue checks now verify received/accepted/rejected counts and completion of admitted messages with simulated audio.
- [ ] Verify skip, clear, ordering and responsiveness during heavy generation and playback.

### Safe alias changes — follow-up

- [ ] Warn about affected playlists, routing, viewer preferences and exported actions before renaming/deleting an alias.
- [ ] Repair internal references and offer a clear repair/re-export path for external Streamer.Bot actions.

### Updates — remaining verification only

The update window, GitHub release checks, startup checks, repeatable manual checks, patch notes, green availability icon and in-place installation are addressed.

- [ ] Rehearse a real released-version-to-newer-version update, including settings retention, restart, interrupted download and rollback.
- [ ] Verify stable/preview channel behavior and communicate how an existing development preview moves to the public release.
- [ ] Signed Windows distribution, when a signing identity is available.

### Release and recovery follow-up

- [ ] Real hardware checks: audio disconnect/reconnect, OBS disconnect and volume restoration, tray restore after Explorer restart, and Windows restart/shutdown.
- [ ] Verify generated Streamer.Bot actions across supported versions.

## Suggested work order

This orders the remaining list; it does not replace its requirements.

1. Protect unsaved page/editor drafts on exit or context changes, following the completed global Save workflow.
2. Reference-safe alias rename/delete: warn about affected playlists, assignments, rules and exported actions; repair internal references.
3. Finish external Streamer.Bot/high-volume and multi-voice validation, including skip/clear/manual moves during generate-ahead playback. Core assignments, public voice commands and multi-voice splitting are implemented.
4. Explain voice selection in message details and retain pre-admission rejection feedback. Queue search/details and waiting-message voice changes are implemented.
5. Advanced playlists and independent preview playback.
6. Keyboard/state/density improvements, provider metadata, update rehearsal and broader physical testing.

## Maintenance rule

Remove a task only when its stated behavior is addressed. For partial features, retain only the unfinished part. Track verification separately from new functionality. Keep later user decisions above the original brief when they conflict.
