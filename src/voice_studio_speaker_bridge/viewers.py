"""Stable viewer identities and assignments, stored beside the app settings."""
from __future__ import annotations

import json
from pathlib import Path
import re
import shutil
from threading import RLock


def identity(data: dict) -> tuple[str, str]:
    raw = data.get('user')
    if isinstance(raw, str) and raw.lstrip().startswith('{'):
        try:
            raw = json.loads(raw)
        except ValueError:
            raw = None
    raw = raw if isinstance(raw, dict) else {}
    kind = str(raw.get('type') or '').strip().casefold()
    inferred_platform = kind if kind in {'twitch', 'youtube', 'kick', 'discord', 'tiktok', 'facebook', 'trovo'} else ''
    platform = str(data.get('platform') or raw.get('platform') or inferred_platform).strip().casefold()
    user_id = str(data.get('userId') or raw.get('id') or raw.get('userId') or '').strip()
    if not re.fullmatch(r'[a-z0-9][a-z0-9_-]{0,31}', platform):
        raise ValueError('Provide the viewer platform, such as twitch or youtube')
    if not user_id or len(user_id) > 128 or any(ord(c) < 32 for c in user_id) or user_id.startswith('%'):
        raise ValueError('Provide a stable platform userId, not a display name or placeholder')
    return platform, user_id


class ViewerStore:
    def __init__(self, path: Path):
        self.path = path
        self.lock = RLock()
        self._cache = None
        self._stamp = None

    def _read(self) -> dict:
        try:
            stamp = self.path.stat().st_mtime_ns
            if self._cache is not None and stamp == self._stamp:
                return self._cache
            payload = json.loads(self.path.read_text(encoding='utf-8-sig'))
        except FileNotFoundError:
            self._cache, self._stamp = None, None
            return {}
        except (OSError, ValueError) as exc:
            raise ValueError('Viewer data could not be read. Restore viewers.json from its .bak copy.') from exc
        if not isinstance(payload, dict) or payload.get('version') != 1 or not isinstance(payload.get('viewers'), list):
            raise ValueError('Viewer data format is not supported; the file was not changed')
        result = {}
        for entry in payload['viewers']:
            if not isinstance(entry, dict):
                raise ValueError('Viewer data contains an invalid entry; the file was not changed')
            key = identity(entry)
            if key in result or not all(isinstance(entry.get(field, ''), str) for field in ('displayName', 'login', 'voice')):
                raise ValueError('Viewer data contains an invalid or duplicate entry; the file was not changed')
            result[key] = dict(entry)
        self._cache, self._stamp = result, stamp
        return result

    def all(self) -> list[dict]:
        with self.lock:
            return sorted((dict(entry) for entry in self._read().values()), key=lambda v: (v.get('displayName', '').casefold(), v['platform'], v['userId']))

    def get(self, platform: str, user_id: str) -> dict | None:
        with self.lock:
            entry = self._read().get((platform, user_id))
            return dict(entry) if entry else None

    def update(self, data: dict, *, assign: bool = False, assignment_source: str = 'admin') -> dict:
        platform, user_id = identity(data)
        with self.lock:
            records = self._read()
            original = identity(data['originalIdentity']) if assign and data.get('originalIdentity') else (platform, user_id)
            if original != (platform, user_id):
                if original not in records:
                    raise ValueError('The original viewer no longer exists. Refresh before editing.')
                if (platform, user_id) in records:
                    raise ValueError('That viewer ID already exists. Edit its existing assignment instead.')
            previous = records.get((platform, user_id))
            entry = dict(previous or records.get(original) or dict(platform=platform, userId=user_id, displayName='', login='', voice=''))
            entry.update(platform=platform, userId=user_id)
            for field in ('displayName', 'login'):
                value = str(data.get(field) or '').strip()
                if value:
                    if len(value) > 128 or any(ord(c) < 32 for c in value):
                        raise ValueError('Viewer names must be a single line of at most 128 characters')
                    entry[field] = value
            if assign:
                entry['voice'] = str(data.get('voice') or '').strip()
                entry['assignmentSource'] = assignment_source
            # Repeat messages do not rewrite the file. Only identities, names
            # or assignments changing require a durable write.
            if entry != previous:
                records = dict(records)
                if original != (platform, user_id):
                    del records[original]
                records[(platform, user_id)] = entry
                self.path.parent.mkdir(parents=True, exist_ok=True)
                temporary = self.path.with_suffix('.tmp')
                temporary.write_text(json.dumps(dict(version=1, viewers=list(records.values())), indent=2), encoding='utf-8')
                if self.path.exists():
                    shutil.copy2(self.path, self.path.with_suffix('.json.bak'))
                temporary.replace(self.path)
                self._cache, self._stamp = records, self.path.stat().st_mtime_ns
            return dict(entry)

    def delete(self, data: dict) -> bool:
        key = identity(data)
        with self.lock:
            records = dict(self._read())
            if key not in records:
                return False
            del records[key]
            temporary = self.path.with_suffix('.tmp')
            temporary.write_text(json.dumps(dict(version=1, viewers=list(records.values())), indent=2), encoding='utf-8')
            shutil.copy2(self.path, self.path.with_suffix('.json.bak'))
            temporary.replace(self.path)
            self._cache, self._stamp = records, self.path.stat().st_mtime_ns
            return True
