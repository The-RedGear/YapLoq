# Global Save

The title-bar Save button sits immediately left of connection status. It saves pending page settings across the app, regardless of which page is visible. Ctrl+S invokes the same operation. Pending changes turn the button purple with a subtle static glow; its label stays Save. It remains clickable when clean and confirms that all changes are saved without unnecessary writes. Tracking is driven by input events, not by the playback polling timer.

Covered sections include app/audio/OBS settings, service configuration and masked credentials, Streamer.Bot connection, Actions, voice On/Off toggles, rules/profanity, pronunciation edits, default assignment voice and viewer-command settings. Drafts survive page navigation and voice/settings refreshes. Reverting an edit clears its pending indicator.

Save commits grid edits, stages the changed sections in memory, validates Actions through a read-only backend endpoint, and writes the settings file once after validation succeeds. Action changes also receive a pre-save configuration backup. A validation failure identifies the section, leaves settings unchanged and keeps the drafts pending. Credential drafts are retained if saving fails. Ports/listener changes still require restarting YapLoq.

Page-level Save controls are hidden. Editor/record confirmations remain local: saving an alias or sub-action dialog, applying a viewer record, and changing a queued message finish that specific edit. Audio downloads, creating a profile, backup/restore and explicit secret-clearing actions are not the global settings save. Profiles are labeled Create profile to distinguish them.

Service connection tests and voice-loading actions use saved configuration. If the current service has pending changes, Save first; testing no longer silently persists those edits. OBS testing follows the same rule.

Pending edits are held in memory, not an on-disk draft file. Do not exit without saving edits you want to retain.
