# Global Save

The title-bar Save button sits immediately left of connection status. It saves pending page settings across the app, regardless of which page is visible. Ctrl+S invokes the same operation. Pending changes turn the button purple with a subtle static glow; its label stays Save. It remains clickable when clean and confirms that all changes are saved without unnecessary writes. Tracking is driven by input events, not by the playback polling timer.

Covered sections include app/audio/OBS settings, service configuration and masked credentials, Streamer.Bot connection, Actions, voice On/Off toggles, rules/profanity, pronunciation edits, default assignment voice and viewer-command settings. Drafts survive page navigation and voice/settings refreshes. Reverting an edit clears its pending indicator.

Save commits grid edits, stages the changed sections in memory, validates Actions through a read-only backend endpoint, and writes the settings file once after validation succeeds. Action changes also receive a pre-save configuration backup. A validation failure identifies the section, leaves settings unchanged and keeps the drafts pending. Credential drafts are retained if saving fails. Ports/listener changes still require restarting YapLoq.

Page-level Save controls are hidden. Editor/record confirmations remain local: saving an alias or sub-action dialog, applying a viewer record, and changing a queued message finish that specific edit. Audio downloads, creating a profile, backup/restore and explicit secret-clearing actions are not the global settings save. Profiles are labeled Create profile to distinguish them.

Valid page settings apply in memory after a short editing debounce, without writing settings.json. Save makes them permanent. Invalid sections retain their last valid active values while their draft remains editable. Provider and OBS tests wait for live application rather than requiring Save. Live application affects future requests/playback; it does not regenerate speech already resolved or playing.

Right-click the title-bar Save button for Discard unsaved changes: controls return to the saved values and the backend's temporary overlay is cleared. Saving or discarding is serialized after any in-flight live request. Unrelated backend record saves exclude the temporary settings overlay, so creating an alias cannot accidentally persist unsaved settings. The overlay is session-only and is absent after restarting.

Exceptions: listener ports/bindings, listener enablement and queue recovery need Save and restart. History retention requires Save because it can delete old audio/history. Action definitions and voice On/Off record edits retain their existing explicit confirmation/save flow; they are not runtime settings overlays. Local alias/sub-action editors still confirm their individual records. The port/recovery and retention controls explain these exceptions in their tooltips.

Pending edits are held in memory, not an on-disk draft file. Exiting with pending page changes offers Save, Discard and Cancel. Save uses the global validation flow; invalid edits prevent exit. Discard exits without writing those drafts, and Cancel keeps them open. Minimizing/hiding to the tray does not prompt.

Alias, playlist, pronunciation, profanity and sub-action editors also protect changed drafts when closed, including their Cancel/X/Escape paths. Save uses that editor's existing validation and confirmation; invalid edits stay open. Switching pages retains page drafts without prompting. These prompts do not protect against force-ending the process or losing power.
