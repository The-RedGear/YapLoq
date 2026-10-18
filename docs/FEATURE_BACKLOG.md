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

Partial: username-based voice rules already exist. The original stable-identity viewer workspace remains unfinished.

- [ ] Searchable viewer list under Voices, keyed by platform and stable user ID, with display names for presentation.
- [ ] Assign a saved alias or playlist as a viewer's default.
- [ ] Persist assignments and provide reset to channel default.
- [ ] Handle changed display names and identical display names without confusing viewers.
- [ ] Show assignment origin and handle deleted/unavailable voices.
- [ ] Context action on a message to set that viewer's default voice.
- [ ] Public voice names and permission restrictions so viewers cannot select private or restricted voices.
- [ ] Streamer.Bot chat workflows such as !voice name, !voice random and !voice reset.
- [ ] Structured SetViewerVoice request with validation, persistence and useful success/failure feedback.

## 5. Voice routing and pronunciation

Partial: routing and global pronunciation already exist and have the requested homes.

- [ ] Document and verify voice-selection precedence: explicit request, saved viewer preference, matching rule, default, available fallback. Existing behavior must be checked before changing it.
- [ ] Explain “Why this voice?” in message details.
- [ ] Per-voice pronunciation overrides in addition to the existing global dictionary.
- [ ] Ensure alias edits affect future requests without unexpectedly changing playing or already-resolved queued speech.

## 6. Queue and message tools

Partial: the unified list, statuses, replay, manual ordering, audio actions and context menus already exist.

- [ ] Search and filter speech by useful fields such as voice, status, source and message.
- [ ] Message details with failure/rejection reasons and the selected-voice explanation.
- [ ] Change a waiting message's voice without modifying the saved alias or interrupting playing speech.
- [ ] Contextual viewer-default assignment, using the same persisted assignments as Voices.
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
- [ ] Consistent unsaved-edit protection across editors.
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

### Generate upcoming speech ahead of playback — new feature

- [ ] Generate waiting speech while the current recording plays, so the next audio is ready sooner.
- [ ] Use bounded generation concurrency with provider-specific limits and rate-limit handling; avoid overwhelming services or increasing paid usage unnecessarily.
- [ ] Preserve the intended playback order regardless of which generation finishes first. Generation status must not move rows.
- [ ] Show Generating, Ready, Playing and terminal statuses on each existing queue entry.
- [ ] Respect manual moves, skip, remove, clear and voice changes; cancel pending work where possible and discard stale results safely.
- [ ] Bound prepared-audio memory/cache usage, reuse generated audio, and handle individual generation failures without stalling the queue.
- [ ] Verify playback remains responsive and multi-voice input segments keep their spoken order when generated ahead.

### Multiple voices in one input — new feature

- [ ] Parse inputs such as: [Plankton] Hello! [Spongebob] Hi, Plankton!
- [ ] Create one speech entry for each named alias segment.
- [ ] Preserve segment playback order even if generation completes out of order.
- [ ] Define behavior for text before the first tag, empty segments, literal brackets and unknown aliases.
- [ ] Apply the same behavior to the intended Dashboard and Streamer.Bot entry points.
- [ ] Keep rejection feedback and queue limits understandable when one request expands into several entries.

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

1. Finish external Streamer.Bot/high-volume validation and add bounded generation ahead of playback. Standard-app control restrictions, callback-log verification, UDP input accounting and local listener diagnostics are addressed.
2. Viewer assignments, public voice permissions and Streamer.Bot voice commands.
3. Multi-voice input with guaranteed segment order.
4. Queue search/details, waiting-message voice changes and reference-safe alias edits.
5. Advanced playlists and independent preview playback.
6. Keyboard/state/density improvements, provider metadata and broader physical testing.

## Maintenance rule

Remove a task only when its stated behavior is addressed. For partial features, retain only the unfinished part. Track verification separately from new functionality. Keep later user decisions above the original brief when they conflict.
