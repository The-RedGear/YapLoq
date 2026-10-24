# YapLoq user guide

For YapLoq 0.6.5 on Windows 10/11, 64-bit.

## Queue and replay

Split messages appear as one expandable entry on the Queue page, newest messages first. Expand a message to see its voices, sounds and pauses in playback order. The group uses the first voice alias's icon and color, even if a sound comes first. Sound-only groups use a neutral folder.

Select a completed message and choose **Replay** to play the whole message again. Audio Stims use their original sound files, not cached copies; keep those files available for replay. If part of a message is missing, YapLoq reports the problem rather than replaying only part of it.

Upcoming speech generates in the background, with up to two provider requests at a time. Clips can finish generating out of order, but always play in message order. Pausing stops new generation requests; requests already sent to a provider may finish.

## Audio Stims

Audio Stims uses a searchable keyword list, like Voices. Choose **Add stim**, **Edit**, or double-click a keyword to open its editor. The popup has the same color swatches and icon codes as aliases, with volume and weight sliders for each sound. Playback, Streamer.bot and word-replacement settings stay inside that editor. Cancel leaves the original keyword unchanged.

**Playback** can use a library sound, always pause instead of a sound, or pause only when viewer information is present or missing. Set a pause from 0.1 to 60 seconds. Pauses stay in queue order and do not change the current voice. If Streamer.bot supplies the sound, choose the appropriate pause behavior and its action. Actions without viewer information still require the separate opt-in checkbox.

**Test random** previews a weighted pick from the current library, including unsaved file/volume/weight edits. It never runs Streamer.bot actions. The optional action dropdown loads automatically and filters as you type; selecting an action keeps its ID so renames do not break the connection.

Select a keyword, then use **Output for this keyword** to choose its device, Windows default, or **Same as TTS output**. Each keyword keeps its own routing, including previews. Changes apply live; Save keeps them after restarting. Sound-only inputs do not run speech queue/avatar hooks; their own Audio Stim hooks still work.

Open **Audio Stims**, add a keyword such as `Fart`, then add sound files or a folder. Type `[Fart]` inside a speech message to play a sound at that point. Speech afterward keeps the same voice until another voice tag changes it.

Each file has volume from 0 (muted) to 100 (maximum) and random weight from 1 to 100. Higher weights are selected more often; uncheck a file to exclude it. Keep one enabled file to always use that sound. Folder selection adds its current files; add the folder again to pick up new files. Supported formats: WAV, MP3, OGG and FLAC, up to 64 MB and five minutes per file.

Use **Preview** to check the selected sound. Optional replacement words play the stim instead of speaking those words. The Censor editor also offers an **Audio Stim** replacement. Inline stims use plain text, not SSML.

Detached punctuation immediately after a sound is skipped, so a censored word followed by `?` does not make the next clip start with a stray question mark. Punctuation within the remaining speech is preserved.

An optional Streamer.bot action runs when sound playback starts. Select it from the searchable dropdown or enter its exact name or ID. It receives the original viewer's `userName`, `displayName`, `userId`, platform and profile image when supplied, plus `ttsStim`, `ttsSoundFile` and `ttsMessageId`. Actions require viewer information unless **Allow without viewer information** is enabled. Previews never run actions; replays only run them when explicitly enabled. Streamer.bot connection failures do not stop audio playback.

## First launch

1. Download **YapLoq-Windows-x64-update.zip** from the
   [latest release](https://github.com/The-RedGear/YapLoq/releases/latest).
2. Extract the entire folder and run **YapLoq.exe**. Keep `_internal` beside it.
   You do not need to install Python.
3. Open **Services** and enable a speech service. Windows voices work without an
   account; other services may need credentials or a local server.
4. Fill in the required fields and use **Test connection and load voices**.
5. Open **Voices**, add an alias, choose its service and voice, then test it.
6. On **Dashboard**, choose your alias, enter a message and click **Speak message**.

If speech is silent, check the selected audio output in **Settings** and use the
output test. Cloud services may charge for generated speech.

## Find your way around

| Page | What it's for |
| --- | --- |
| Dashboard | Speak a message and replay recent speech. |
| Voices | Manage aliases, assignments, playlists, pronunciation and censorship. |
| Queue | View waiting speech and history together; manage messages and filters. |
| Services | Connect speech providers and load their voices. |
| Streamer.Bot | Set up actions, copy the import pack and configure connections. |
| Settings | Choose audio devices, speech-input options, profiles, backups and diagnostics. |

Right-click lists and queue entries for the actions available there.

## Services and connection status

Enable the service you want to use, then enter its connection details. The test
button stays disabled until the required fields are filled.

- **Disconnected:** the service is enabled but has not connected successfully.
- **Connecting:** a connection test is running; shown in yellow.
- **Connected:** the connection succeeded; shown in green.

Enabled services stay in the status dropdown even when a connection fails.
If a test reports a partial result, read its message before assuming that voices
are ready to use.

Credentials are masked by default. Use the show/hide control to check them;
changing visibility does not change the credential or require a save.

For Amazon Polly, provide an AWS access key and secret, or an AWS profile.
Temporary credentials may also need a session token. Choose the correct region.
VoiceStudio needs the address of your running local server.

## Saving changes

Use **Save** beside the connection-status dropdown, or press **Ctrl+S**.

The button turns purple and glows when there are unsaved changes. Valid settings
usually take effect as you edit, but Save keeps them for the next launch.
Connection ports and queue-recovery changes require Save and a restart.

After a save attempt, a short message appears to the left of Save:

- **Saved** or **All changes saved:** nothing remains pending.
- **Not saved — click for details:** open it to read the full reason and use
  **Copy details**.

The message flashes briefly, then fades. Right-click Save and choose
**Last save details** to reopen the result later. A failed save keeps your edits
and the button's glow; correct the reported issue and save again.

Right-click Save for **Discard unsaved changes**. Closing the app with pending
edits offers **Save**, **Discard** or **Cancel**. A successful exit save closes
the app; a failure keeps the prompt open with its reason.

Voice and assignment editors may also have an **Apply** or **Save** confirmation
for the record you're editing.

## Voices, assignments and multiple voices

An alias gives a provider voice a friendly name, icon and color. You can adjust
its supported voice settings and organize voices into groups or playlists.
The **ON** checkbox includes a voice in the enabled/random pool. Chat voice tags
use enabled voices by default.

For a smaller random selection, create a named playlist under **Voices → Playlists**.
Use its exported Streamer.Bot action, or the `playlist:Name` selector in a custom
integration.

Under **Voices → Assignments**, enter a username and choose a special voice.
Names match without regard to capitalization and work across platforms.
Only special assignments appear here; ordinary viewers using the default voice
are not added automatically.

Use **Roles & rules** for broadcaster, moderator, VIP, subscriber and custom-group
defaults. The fallback voice is on the Assignments page. Role/group matching
depends on the information Streamer.Bot sends with the event.

Edit, reset or delete an assignment from its controls or right-click menu.
Deleting it does not delete the viewer's speech history.
[More about assignments](ASSIGNMENTS.md).

To switch voices within one input, use alias names in brackets:

```text
[Plankton] Hello! [Spongebob] Hi, Plankton!
```

Each part gets its own clip and plays in message order. Use full alias names
when a shortened name is ambiguous. An explicit voice selection overrides the
normal assignment for that part.

Unrecognized or ambiguous brackets, such as `[laughter]` or a misspelled name,
stay in the text and use the current voice (or your default before any voice
switch). They do not reject the message. Known disabled or restricted voices
still follow their access rules.

Under **Settings → Speech input**, you can also enable sentence splitting.
It is off by default and can add pauses and provider requests. Splitting keeps
the voices and playback order, with at most 50 resulting clips per input.
SSML is kept intact.

## Queue, history and playback

Queue and history share one page. New inputs appear at the top, with older entries
below. Status changes and replaying a recording do not move an existing row.
Pending speech still follows its scheduled playback order.

Statuses identify generating, queued, playing and failed speech. On Dashboard,
completed entries remain in recent speech without a repeated “Finished” label.
A larger window reveals more recent entries.

Use a row's right-click menu to inspect the message, replay or save available
audio, change an ungenerated voice, remove a pending item, or move it up/down.
Replays use the existing recording rather than generating the text again.

Playback controls have different purposes:

- **Pause audio:** pause immediately and resume from the same position.
- **Pause after current:** let the current sound finish, then pause. The small
  square beside the player's transport controls is this stop-after-current
  control, not an immediate stop.
- **Clear waiting:** remove pending speech without stopping the current sound.
- **Stop and clear:** stop the current sound and clear pending speech.

Save recordings you want to keep. History and cached audio follow the retention
setting; audio that has expired cannot be replayed.

## Filters and speech options

Open **Queue → Rules → Filters → Chat prefixes** for:

- **Remove !command**
- **Remove @mention**

These remove matching tokens, not the rest of the message. For example,
`!say Hello @viewer welcome back` becomes `Hello welcome back`.
An input with nothing left after filtering produces no speech.

Other filters handle links, excessive capitals, repeated characters, symbols and
emoji. Pronunciation and censorship controls are under **Voices**.

Queue controls also include limits, cooldowns, duplicate protection and message
expiry. Zero disables the optional limits that support it.
Queue recovery is opt-in and restarts paused; interrupted audio may restart from
the beginning.

## Streamer.Bot setup

1. In **Streamer.Bot → Connection**, enable the UDP listener and check its port.
   Save and restart after changing listener settings.
2. Open **Import pack** and click **Copy import code**.
3. In Streamer.Bot, choose **Import → Import String** and paste.

One import supports Twitch, YouTube and Kick. Choose the speech action that
matches your trigger:

| Action | Use it for |
| --- | --- |
| Speak - Chat command | A speech command such as `!ylsay`. |
| Speak - Channel point reward | A redemption with viewer-entered text. |
| Speak - Chat message | Ordinary chat messages. |

Use only one speech handler per input to avoid duplicate audio. The first two
actions use `%rawInput%`; the chat-message action uses `%message%`. The supplied
actions already handle this—do not append both fields to one payload.

The pack includes `!voice Voice name` and `!voice reset` for VIPs and moderators,
with broadcaster access. Moderator speech and playback commands include
`!ylsay`, `!ylplay`, `!ylpause`, `!ylskip`, `!ylpauseafter`, `!ylclear`
and `!ylstop`. For example:

```text
!ylsay [Plankton] Hello! [Spongebob] Hi!
```

To export additional voice actions later, select voices and choose
**Export voices**. You do not need a chat command for every voice.

### Run actions from YapLoq events

Under **Streamer.Bot → Actions**, add an action, name it, choose its triggers
and add sub-actions or delays. Type in the action picker to filter Streamer.Bot
actions, or open its dropdown. Renames follow the saved action ID; a deleted
target needs a replacement.

Steps dispatch in saved order. If you need to wait for an action to finish
inside Streamer.Bot, configure its queue accordingly.

The **Queue** trigger category includes:

| Trigger | When it runs |
| --- | --- |
| Queue started (first audio ready) | Once when the first audio in a new queue is ready. |
| Message added to queue | Once for every accepted input, including the first. |
| Message added to active queue | Once when an input joins an existing queue; never for the first input of a new queue. |

An existing queue can be playing, generating or waiting. Splitting one input into
voices or sentences does not repeat the message-added events.

[Full Streamer.Bot setup](STREAMERBOT.md).

## Audio and advanced speech

Settings provides separate stream and preview devices and volumes, plus optional
normalization and fades. A voice can override its stream output.

Optional OBS ducking lowers a selected OBS input during speech and restores its
volume afterward. Choose the music or desktop-audio input, not the TTS input.
A forced shutdown or power loss can prevent volume restoration.

Use **Advanced SSML** only with a supported voice/provider and a complete
`<speak>…</speak>` document. Supported tags vary by engine; malformed XML or
unsupported options are rejected. VoiceStudio style instructions are separate
from SSML.

## Profiles, backups and updates

Profiles let you switch voices, rules, dictionaries, filters and audio preferences
without replacing provider credentials or network ports. Save pending settings
before creating a profile. Already queued speech keeps its chosen voice.

Settings also provides backups, restore and preset import/export. Backups include
settings, actions and viewer assignments. Keep backups private: they may contain
encrypted credentials.

For a Speaker.bot alias import, select `voicealiases.dat` and review the preview.
Only supported aliases are imported; configure service credentials separately.

The `data` folder beside the app contains settings, history and runtime files.
Windows-encrypted credentials are tied to your Windows account and computer.
If you move to another computer, expect to enter service credentials again.
Do not replace or delete `data` when manually updating the app.

Use the download icon beside the version number to check for updates and read
release notes. It turns green when an update is available. You can check manually
again without a cooldown. Follow the update window's download and restart steps.
Development previews use their own update channel and data folder.

## If something isn't working

- **No sound:** check the service, selected voice, audio output, volume and queue status.
- **A voice is missing:** enable its service, complete the required fields and test/load voices.
- **Speech plays twice:** check for duplicate Streamer.Bot triggers or multiple speech handlers.
- **An assignment is ignored:** check the username, role information and any explicit voice/tag.
- **Save stays glowing:** click the save result or open **Last save details** for the reason.
- **An action target was removed:** choose its replacement in the sub-action editor.

Open **Settings → Diagnostics** for events, logs and diagnostic export.
Keep credentials and private chat data out of public bug reports.

[Release notes](RELEASE_NOTES.md) · [Roadmap](ROADMAP.md) · [Legal notes](LEGAL.md)
