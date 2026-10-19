# Contributing to YapLoq

Thanks for helping improve YapLoq.

## Before opening an issue

- Search existing issues first.
- Include the YapLoq version and Windows version.
- Explain what you expected and what actually happened.
- Include relevant log lines, but remove usernames, credentials, and private data.

## Pull requests

1. Fork the repository and create a focused branch.
2. Keep unrelated changes out of the pull request.
3. Add or update tests when behavior changes.
4. Run the test suite before submitting.
5. Explain the user-facing effect of the change.

Never commit API keys, passwords, overlay URLs, service-account JSON, settings
files, generated audio, logs, caches, or other users' voice assets.

By submitting a contribution, you confirm that:

1. You have the right to submit the content.
2. Your contribution may be distributed under this repository's MIT License.
3. You will not submit code that intentionally exfiltrates credentials or
   disables the project's safety/attribution notices.

Please follow the [Code of Conduct](CODE_OF_CONDUCT.md). For legal and trademark
boundaries, see [legal notes](../docs/LEGAL.md).

## Build and test

On Windows 10/11 with Python 3.10+ and Windows PowerShell 5.1:

```powershell
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -e ".[google]" pytest pyinstaller cffi
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m PyInstaller --noconfirm YapLoq.spec
```

The portable app is created in `dist/YapLoq`. Build metadata and packaging
helpers live in `tools/`; application UI resources live in `assets/`.

## Release naming

Use `YapLoq X.Y.Z` for release titles and `vX.Y.Z` for tags. Do not append
labels such as "Hotfix" or a reason to the title. Put the changes in the notes.
Publish only after the GitHub test and Windows build jobs pass.
