# YapLoq

<img src="assets/YapLoq-icon.png" width="96" alt="YapLoq logo">

Give your stream a voice.

YapLoq brings text-to-speech, custom voices and Streamer.bot controls together
in a Windows app. Let viewers speak with their own voices, turn a message into
a conversation between characters, or keep things simple with one voice for chat.

**[Download for Windows](https://github.com/The-RedGear/YapLoq/releases/latest)** ·
[Getting started](docs/USER_GUIDE.md) · [Streamer.bot setup](docs/STREAMERBOT.md)

## Made for your stream

- Connect Windows voices or a supported speech service, including VoiceStudio,
  Amazon Polly, ElevenLabs, Azure and Google Cloud TTS.
- Create voices with their own names, colors and icons, and assign them to
  viewers or roles.
- Use `[Voice name]` tags to switch voices within a message.
- Manage speech and replay recordings from one queue.
- Bring chat commands, channel-point rewards and playback events into your
  Streamer.bot setup.
- Choose what gets spoken with pronunciation rules, text filters and cooldowns.

## Get started

1. Download **YapLoq-Windows-x64-update.zip** from the latest release.
2. Extract the whole folder and run **YapLoq.exe**. Keep `_internal` beside it.
3. Connect a service under **Services**, then add a voice under **Voices**.
4. For Streamer.bot, copy the import code from **Streamer.Bot → Import pack**.

No Python installation is needed. Future updates are available from the download
icon beside the version number.

YapLoq runs on 64-bit Windows 10 and 11. The app is unsigned, so Windows may show
a SmartScreen warning. Cloud speech services may charge for usage.

## Help and feedback

Found a bug or have an idea? [Open an issue](https://github.com/The-RedGear/YapLoq/issues).
Please leave credentials and private chat information out of reports.

[User guide](docs/USER_GUIDE.md) · [Supported services](docs/PROVIDERS.md) ·
[What's new](docs/RELEASE_NOTES.md) · [Roadmap](docs/ROADMAP.md)

## For developers

Source setup, tests and build instructions are in
[Contributing](.github/CONTRIBUTING.md).

## License

[MIT](LICENSE). See [third-party notices](docs/THIRD_PARTY_NOTICES.md) and
[legal notes](docs/LEGAL.md). Use only voices you have permission to use.
YapLoq is an independent project and is not affiliated with Streamer.bot or the
speech providers it supports.
