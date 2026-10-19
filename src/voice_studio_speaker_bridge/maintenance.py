"""Portable maintenance files; diagnostics deliberately exclude speech and secrets."""
from __future__ import annotations

import json
import platform
from datetime import datetime, timezone
from pathlib import Path
import shutil
import re
import uuid
import zipfile
import tempfile

from .settings import Settings
from . import __version__

PRESET_KEYS = ("aliases", "pronunciations", "hidden_pronunciations", "routing_rules",
               "voice_playlists", "user_voice_rules", "role_voice_rules", "replacements", "assignment_default_voice")
PROFILE_KEYS = PRESET_KEYS + ("output_device", "preview_output_device", "stream_volume", "preview_volume",
    "max_characters", "max_queue", "max_message_age", "duplicate_window", "per_user_queue_limit",
    "per_user_cooldown", "global_cooldown", "blocked_words", "user_blocklist", "user_allowlist",
    "strip_links", "block_links", "strip_emojis", "ignore_command_messages", "ignore_mention_messages",
    "strip_non_ascii", "block_ascii_art", "normalize_audio", "fade_audio")


class Maintenance:
    def __init__(self, settings: Settings, viewers=None):
        self.settings = settings
        from .viewers import ViewerStore
        self.viewers = viewers if isinstance(viewers, ViewerStore) else ViewerStore(settings.path.parent / 'viewers.json')

    def _folder(self, name: str) -> Path:
        folder = self.settings.path.parent / name
        folder.mkdir(parents=True, exist_ok=True)
        return folder

    def backup(self, *, recovery=False) -> str:
        with self.viewers.lock:
            if not recovery:
                self.settings.reload_if_changed()
                self.settings.save()
                self.viewers.all()  # Refuse to label malformed viewer data a good backup.
            elif not self.settings.path.exists():
                self.settings.save()
            viewer_bytes = self.viewers.path.read_bytes() if self.viewers.path.exists() else b'{"version":1,"viewers":[]}'
            stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
            destination = self._folder('backups') / f'YapLoq-{stamp}.zip'
            temporary = destination.with_suffix('.zip.tmp')
            with zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
                archive.writestr('manifest.json', json.dumps(dict(format='yaploq-backup', version=1)))
                archive.write(self.settings.path, 'settings.json')
                archive.writestr('viewers.json', viewer_bytes)
            temporary.replace(destination)
        return str(destination)

    def restore(self, filename: str) -> None:
        # Only restore files previously created in the app's backup directory.
        if Path(filename).name != filename:
            raise ValueError("Choose a backup from the backup list")
        source = self._folder("backups") / filename
        if not source.is_file() or source.resolve().parent != self._folder('backups').resolve():
            raise ValueError("This backup could not be read")
        try:
            if source.suffix.casefold() == '.zip':
                with zipfile.ZipFile(source) as archive:
                    entries = archive.infolist()
                    names = [entry.filename for entry in entries]
                    if (len(names) != len(set(names)) or set(names) != {'manifest.json', 'settings.json', 'viewers.json'}
                            or any(entry.file_size > 20_000_000 or entry.flag_bits & 1 for entry in entries)):
                        raise ValueError('This backup contains unexpected, duplicate or oversized files')
                    manifest = json.loads(archive.read('manifest.json'))
                    if manifest != dict(format='yaploq-backup', version=1):
                        raise ValueError('This backup version is not supported')
                    files = {name: archive.read(name) for name in ('settings.json', 'viewers.json')}
            elif source.suffix.casefold() == '.json':
                if source.stat().st_size > 20_000_000:
                    raise ValueError('Settings backup is oversized')
                files = {'settings.json': source.read_bytes()}
            else:
                raise ValueError('Choose a YapLoq backup ZIP or legacy settings JSON')
            raw = json.loads(files['settings.json'].decode('utf-8-sig'))
            if not isinstance(raw, dict) or not isinstance(raw.get('aliases', {}), dict):
                raise ValueError('Settings backup is invalid')
            if any(not name.strip() or any(ord(character) < 32 for character in name) or not isinstance(alias, dict)
                   for name, alias in raw.get('aliases', {}).items()):
                raise ValueError('Settings backup contains an invalid voice alias')
            from .automations import validate_rules
            validate_rules(raw.get('automations', []))
            from .viewers import ViewerStore
            with tempfile.TemporaryDirectory(prefix='restore-check-', dir=self.settings.path.parent) as stage:
                for name, payload in files.items():
                    Path(stage, name).write_bytes(payload)
                candidate = Settings(Path(stage, 'settings.json'))
                if not candidate._loaded_mtime_ns:
                    raise ValueError('Settings backup could not be loaded')
                if 'viewers.json' in files:
                    ViewerStore(Path(stage, 'viewers.json')).all()
        except (OSError, zipfile.BadZipFile, KeyError, UnicodeError, json.JSONDecodeError) as exc:
            raise ValueError('This backup is damaged or could not be read') from exc
        with self.viewers.lock:
            self.backup(recovery=True)  # Preserve even damaged current files for recovery.
            targets = {self.settings.path if name == 'settings.json' else self.viewers.path: payload for name, payload in files.items()}
            originals = {path: path.read_bytes() if path.exists() else None for path in targets}
            try:
                for path, payload in targets.items():
                    temp = path.with_suffix('.restore.tmp');temp.write_bytes(payload);temp.replace(path)
            except OSError:
                for path, payload in originals.items():
                    if payload is None:
                        path.unlink(missing_ok=True)
                    else:
                        temp = path.with_suffix('.rollback.tmp');temp.write_bytes(payload);temp.replace(path)
                raise
            self.viewers._cache = None
            self.viewers._stamp = None
            self.settings.load()

    def backups(self) -> list[str]:
        for legacy in self._folder("backups").glob("VoxRelay-*.json"):
            renamed = legacy.with_name("YapLoq-" + legacy.name.removeprefix("VoxRelay-"))
            if not renamed.exists():
                shutil.copy2(legacy, renamed)
        return sorted((path.name for path in self._folder('backups').glob('YapLoq-*') if path.suffix.casefold() in {'.json', '.zip'}), reverse=True)

    def profiles(self) -> list[str]:
        return sorted((path.stem.removeprefix("profile-") for path in self._folder("profiles").glob("profile-*.json")), key=str.casefold)

    def _profile_path(self, name: str) -> Path:
        name = name.strip()
        if not re.fullmatch(r"[\w .-]{1,64}", name) or name.endswith("."):
            raise ValueError("Use 1–64 letters, numbers, spaces, hyphens or underscores for the profile name")
        return self._folder("profiles") / f"profile-{name}.json"

    def save_profile(self, name: str) -> str:
        self.settings.reload_if_changed()
        self.settings.save()
        data = json.loads(self.settings.path.read_text(encoding="utf-8-sig"))
        destination = self._profile_path(name)
        temporary = destination.with_suffix(".tmp")
        temporary.write_text(json.dumps({key: data.get(key) for key in PROFILE_KEYS}, indent=2), encoding="utf-8")
        temporary.replace(destination)
        return str(destination)

    def load_profile(self, name: str) -> None:
        source = self._profile_path(name)
        values = json.loads(source.read_text(encoding="utf-8"))
        if not isinstance(values, dict):
            raise ValueError("This profile could not be read")
        self.settings.reload_if_changed()
        self.settings.save()
        current = json.loads(self.settings.path.read_text(encoding="utf-8"))
        current.update({key: value for key, value in values.items() if key in PROFILE_KEYS})
        temp = self.settings.path.with_name(f"profile-check-{uuid.uuid4().hex}.json")
        try:
            temp.write_text(json.dumps(current, indent=2), encoding="utf-8")
            candidate = Settings(temp)
            if not candidate._loaded_mtime_ns:
                raise ValueError("This profile contains invalid settings")
            self.backup()
            temp.replace(self.settings.path)
            self.settings.load()
        finally:
            temp.unlink(missing_ok=True)

    def reset(self, confirmation: str) -> str:
        if confirmation != "RESET":
            raise ValueError("Reset must be confirmed in Settings")
        backup = self.backup()
        defaults = Settings(self.settings.path.with_name(f"defaults-{uuid.uuid4().hex}.json"))
        defaults.path = self.settings.path
        defaults.save()
        self.settings.load()
        return backup

    @staticmethod
    def check_updates() -> dict:
        from .updates import release_info
        try:
            from .channel import is_preview
            return release_info(is_preview())
        except Exception:
            return {"checked": False, "message": "Could not check GitHub Releases. Check your connection and try again."}

    def diagnostics(self, state: dict, events: list[dict]) -> str:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
        destination = self._folder("exports") / f"YapLoq-diagnostics-{stamp}.zip"
        safe = {
            "app": "YapLoq", "version": __version__, "python": platform.python_version(),
            "system": platform.system(), "release": platform.release(),
            "queueLength": state.get("queueLength", 0), "paused": state.get("paused", False),
            "pollyEnabled": self.settings.polly_enabled,
            "aliasCount": len(self.settings.aliases), "recoveryNotice": self.settings.recovery_notice,
            "events": [{"time": item["time"], "source": item["source"], "event": item["event"]}
                       for item in events],
        }
        with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("diagnostics.json", json.dumps(safe, indent=2))
        return str(destination)

    def export_presets(self) -> str:
        self.settings.reload_if_changed()
        data = json.loads(self.settings.path.read_text(encoding="utf-8-sig"))
        stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
        destination = self._folder("exports") / f"YapLoq-presets-{stamp}.json"
        # Presets exclude provider credentials and local/network configuration.
        payload = {"format": "YapLoq-presets", "version": 1,
                   "settings": {key: data.get(key) for key in PRESET_KEYS}}
        destination.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        return str(destination)

    def export_streamerbot(self, alias: str) -> str:
        from .streamerbot_export import export_actions
        self.settings.reload_if_changed()
        voice = str(alias or "").strip()
        folded = voice.casefold()
        special = folded in {"random", "*"} or folded.startswith(("group:", "playlist:"))
        if voice and not special and voice not in self.settings.aliases:
            raise ValueError("Choose an existing voice, Random, or a playlist")
        if folded in {"random", "*"}:
            if not any(a.enabled for a in self.settings.aliases.values()):
                raise ValueError("Turn on at least one voice in the Voices tab before exporting random Speak")
        if folded.startswith("playlist:"):
            wanted = voice.split(":", 1)[1].strip()
            match = next((n for n in self.settings.voice_playlists if n.casefold() == wanted.casefold()), None)
            if match is None:
                raise ValueError(f"Voice playlist not found: {wanted}")
            members = [m for m in self.settings.voice_playlists[match] if m in self.settings.aliases]
            if not members:
                raise ValueError(f"Playlist has no valid voices: {match}")
            voice = f"playlist:{match}"
        destination = self._folder("exports") / "YapLoq-actions.sb"
        destination.write_text(export_actions(self.settings.udp_port, voice), encoding="utf-8")
        return str(destination)

    def export_viewer_command(self, platform: str = '') -> str:
        from .streamerbot_export import export_viewer_commands
        self.settings.reload_if_changed()
        destination = self._folder('exports') / 'YapLoq-viewer-command.sb'
        destination.write_text(export_viewer_commands(self.settings.udp_port, platform), encoding='utf-8')
        return str(destination)

    def export_complete_streamerbot(self, platform='', preset='complete') -> str:
        from .streamerbot_export import export_complete_pack
        self.settings.reload_if_changed()
        destination = self._folder('exports') / 'YapLoq-complete-pack.sb'
        destination.write_text(export_complete_pack(self.settings.udp_port, platform,
                               [alias.name for alias in self.settings.aliases.values() if alias.enabled],
                               self.settings.voice_playlists.keys(), self.profiles(), preset,
                               groups=[alias.group for alias in self.settings.aliases.values() if alias.enabled and alias.group]), encoding='utf-8')
        return str(destination)

    def export_streamerbot_voices(self, aliases) -> str:
        from .streamerbot_export import export_selected_voices
        self.settings.reload_if_changed()
        if not isinstance(aliases, list) or not aliases or any(not isinstance(name, str) or name not in self.settings.aliases for name in aliases):
            raise ValueError('Select existing saved voices to export')
        code = export_selected_voices(self.settings.udp_port, aliases, list(self.settings.aliases))
        destination = self._folder('exports') / 'YapLoq-voices.sb'
        destination.write_text(code, encoding='utf-8')
        return str(destination)

    @staticmethod
    def preview_speakerbot(data: dict) -> dict:
        """Read alias metadata only. Never read Speaker.bot's credential databases."""
        if not isinstance(data.get("aliases"), list):
            raise ValueError("Choose Speaker.bot's data/voicealiases.dat file")
        aliases, skipped = {}, []
        for entry in data["aliases"]:
            name = str(entry.get("name", "")).strip()
            voices = entry.get("voices") or []
            if not name or not voices:
                continue
            voice = voices[0]
            match = re.fullmatch(r"Amazon Polly - .+ - (.+) \((standard|neural|long-form|generative)\)", str(voice.get("name", "")))
            if not match:
                skipped.append({"name": name, "reason": "This voice engine is not installed in YapLoq."})
                continue
            aliases[name] = {"provider": "polly", "voice_id": match[1], "model": match[2],
                             "volume": max(0, min(2, float(voice.get("volume", 1)))), "speed": 1,
                             "group": "Imported"}
        return {"format": "YapLoq-presets", "version": 1, "settings": {"aliases": aliases},
                "skipped": skipped,
                "note": "Audio devices and engine-specific rate/pitch need review. Multi-voice aliases import their first supported voice only. AWS credentials are configured separately."}

    def import_presets(self, payload: dict) -> dict:
        if payload.get("format") not in {"YapLoq-presets", "VoxRelay-presets"} or payload.get("version") != 1:
            raise ValueError("Choose a YapLoq preset file")
        values = payload.get("settings")
        if not isinstance(values, dict):
            raise ValueError("Preset settings must be an object")
        for key, value in values.items():
            if key not in PRESET_KEYS:
                raise ValueError(f"Unsupported preset field: {key}")
            expected = list if key in {"hidden_pronunciations", "routing_rules"} else dict
            if value is not None and not isinstance(value, expected):
                raise ValueError(f"Invalid preset field: {key}")
        # Validate alias values before saving anything.
        from .models import VoiceAlias
        aliases = {}
        for name, value in (values.get("aliases") or {}).items():
            if not isinstance(name, str) or not name.strip() or not isinstance(value, dict):
                raise ValueError("Every alias needs a name and voice settings")
            aliases[name] = VoiceAlias.from_dict(name, value)
        self.backup()
        for key, value in values.items():
            if key == "aliases":
                self.settings.aliases.update(aliases)
            elif key in {"routing_rules", "hidden_pronunciations"}:
                setattr(self.settings, key, value or [])
            else:
                getattr(self.settings, key).update(value or {})
        self.settings.save()
        return {"aliasesImported": len(aliases)}
