# Configuration backups and recovery

Settings > Backups creates a YapLoq ZIP containing settings.json and viewers.json. Settings include voice aliases and appearance, assignments/rules, playlists, pronunciation, service configuration and YapLoq Streamer.Bot action definitions. Viewer preferences retain their stable platform/user IDs.

The ZIP does not include audio history/cache, queue contents, logs, executables, or actions installed in Streamer.Bot itself. Keep backups private: they contain viewer information and service configuration. Encrypted Windows credentials remain protected by the original Windows account/machine; reconnect services when moving to another PC. Preset export remains the credential-free sharing option.

To restore a ZIP from another installation, copy it into the app data folder's backups directory and refresh the backup list. Choose it under Settings > Backups and confirm. YapLoq validates every included file before changing live data, creates a recovery ZIP of the previous files, and replaces settings and viewer assignments together. A handled file-write failure rolls both files back. Restart YapLoq after restoring so all listeners and integrations use restored configuration.

Legacy YapLoq/VoxRelay JSON backups remain readable. They replace settings only; current viewer assignments are left unchanged. The confirmation identifies this difference.

Only the three expected archive members (manifest.json, settings.json and viewers.json) are accepted. Unexpected paths/files, duplicate entries, encrypted ZIPs, unsupported versions, oversized members and invalid viewer/action data are rejected. Archives are never extracted into the live data folder. If current viewer data is damaged, a valid backup can still restore it; the pre-restore recovery ZIP retains the damaged original for inspection.

The application keeps the pre-restore recovery ZIP under backups. An unexpected power loss during replacement is not guaranteed to roll back automatically; use that recovery copy if needed. Backups are not deleted automatically by this feature.
