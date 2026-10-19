# YapLoq 0.6.0

More control over who speaks, smoother multi-voice messages, and a simpler
Streamer.bot setup.

## What's new

- **Viewer and role assignments.** Give a username its own voice, choose voices
  for moderators, VIPs, broadcasters and subscribers, or use custom groups.
- **Multiple voices in one message.** Switch with `[Voice name]` tags. Speech
  generates ahead of playback, with an optional setting to split long messages
  into sentence-sized clips.
- **One Streamer.bot import.** Use the same pack for Twitch, YouTube and Kick.
  It includes voice selection, moderator controls and separate speech actions
  for chat commands, channel-point rewards and ordinary chat.
- **Live settings and one Save button.** Valid settings take effect as you edit.
  Save keeps your changes; unsaved-change prompts protect your drafts.
- **More flexible automations.** Build ordered actions with delays and choose
  from grouped YapLoq event triggers.

## Fixes and improvements

- Commands and mentions are removed without discarding the valid speech around them.
- Replayed audio keeps its place in the combined queue and history.
- Enabled services stay visible when disconnected, with clearer connection states.
- Amazon Polly voices load correctly in the packaged app.
- Credentials stay masked until revealed, without triggering unsaved changes.
- Backups include settings, actions and viewer assignments.
- A shorter project page and a tidier repository.

## Install or update

Download **YapLoq-Windows-x64-update.zip**, extract the whole folder and run
**YapLoq.exe**. Keep `_internal` beside it. Python is not required.

Existing stable installations can check for this release using the download
icon beside the version number. The development preview uses a separate update
channel and data folder.

## Before you start

Windows 10/11, 64-bit. The app is unsigned, so Windows may show a SmartScreen
warning. Cloud speech services may charge for usage; use only voices you have
permission to use.

[User guide](https://github.com/The-RedGear/YapLoq/blob/main/docs/USER_GUIDE.md) ·
[Streamer.bot setup](https://github.com/The-RedGear/YapLoq/blob/main/docs/STREAMERBOT.md)
