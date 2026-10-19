# Streamer.Bot setup

## Import actions

1. Enable the listener under **Streamer.Bot > Connection** in YapLoq.
2. Open **Import pack** and click **Copy import code**.
3. In Streamer.Bot, choose **Import > Import String** and paste.
4. Use the imported commands, or add a chat trigger for automatic speech.

The same import works with Twitch, YouTube and Kick. Use one speech handler per
input to avoid duplicate audio. Importing does not run actions automatically.

Choose **Speak - Chat command** for command triggers, **Speak - Channel point
reward** for redemptions, or **Speak - Chat message** for ordinary chat.

`!voice Voice name` selects your voice; `!voice reset` restores the default.
These commands are available to VIPs and moderators. The broadcaster retains access.

Moderator controls include `!ylsay message`, `!ylplay`, `!ylpause`, `!ylskip`,
`!ylpauseafter`, `!ylclear` (waiting speech), and `!ylstop` (stop and clear).
Use `!ylsay [Voice name] message` to choose a voice or combine voices.

To add voices later, select them in **Voices** and choose **Export voices**.
Import the copied code into Streamer.Bot to add actions alongside your existing voices.

## Voice assignments

Under **Voices > Assignments**, enter a username and choose a voice. Matching
ignores capitalization. Role defaults are available for moderators, VIPs,
broadcasters and subscribers, with custom groups where the event supplies them.
An explicitly selected voice overrides an assignment.

## Multiple voices

Use voice names in brackets, for example:

```text
[Plankton] Hello! [Spongebob] Hi!
```

Each part becomes a separate queue entry and plays in message order. Unknown or
unavailable voices are reported instead of silently changing the requested voice.

## Run Streamer.Bot actions from YapLoq

In **Streamer.Bot > Actions**, choose an event and add the actions or delays you
want to run. Search your connected Streamer.Bot actions by name. Steps run in
saved order. For strict completion ordering inside Streamer.Bot, use a blocking
queue there.

Under **Queue**, use **Queue started (first audio ready)** for a new queue,
or **Message added to active queue** for new inputs joining an existing queue.
**Message added to queue** runs for every input, including the first.
Splitting one input into voices or sentences does not repeat these admission events.

## Troubleshooting

- Check **Connection** for listener errors and rejected requests.
- Check **Queue** for generation or playback failures.
- If speech plays twice, check for duplicate chat triggers or older speech actions.
- If a voice assignment is ignored, check whether the speech action selects an
  explicit voice.
- Restart YapLoq after changing its listener port.

Keep item-specific controls connected to YapLoq events so they receive the item
ID. Use destructive controls, such as clearing history or loading a saved app
profile, only on deliberate admin triggers.
