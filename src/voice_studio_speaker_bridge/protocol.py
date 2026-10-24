from __future__ import annotations

from typing import TYPE_CHECKING
import random
import uuid
from dataclasses import replace

from .settings import Settings
from . import __version__
from .viewers import ViewerStore, identity
from .public_voices import eligible_voices, public_label, viewer_roles
from .multi_voice import split_voices, normalized_voice_name, sentence_clips, strip_chat_tokens


import json


def _parse_streamerbot_user(value) -> tuple[str, str]:
    """Normalize Streamer.bot %user% / %userName% into (display, login).

    Some Streamer.bot variable paths stringify a whole user object into JSON
    (badges, login, name, ...). That must never be used as the viewer key.
    """
    if value is None:
        return "", ""
    if isinstance(value, dict):
        display = str(
            value.get("name")
            or value.get("displayName")
            or value.get("display_name")
            or ""
        ).strip()
        login = str(
            value.get("login")
            or value.get("userName")
            or value.get("user_name")
            or value.get("userLogin")
            or ""
        ).strip()
        return display, login
    text = str(value).strip()
    if not text:
        return "", ""
    if text.startswith("%") and text.endswith("%") and len(text) > 2:
        return "", ""
    if text.startswith("{") and ('"login"' in text or '"badges"' in text or "'login'" in text):
        try:
            parsed = json.loads(text)
        except Exception:
            return "", ""
        if isinstance(parsed, dict):
            return _parse_streamerbot_user(parsed)
        return "", ""
    return text, text



if TYPE_CHECKING:
    from .engine import SpeechEngine


class SpeakerBotProtocol:
    EVENTS = {
        "application": ["startedspeaking", "stoppedspeaking"],
        "texttospeech": ["received", "generating", "textqueued", "queueadded", "queueextended", "engineprocessed", "playing", "finished", "cancelled", "deleted", "error", "voicechanged"],
        "voicegate": ["profileactivated"],
        "viewer": ["commandreceived", "voiceassigned", "voicereset", "voiceslisted", "commandfailed"],
        "audiostim": ['playing', 'finished', 'error', 'cancelled'],
    }

    def __init__(self, settings: Settings, engine: "SpeechEngine"):
        self.settings = settings
        self.engine = engine
        self.viewers = ViewerStore(settings.path.parent / 'viewers.json')

    def _viewer_choices(self, selector: str):
        if selector.casefold().startswith('playlist:'):
            name = selector.split(':', 1)[1].strip()
            members = next((voices for key, voices in self.settings.voice_playlists.items() if key.casefold() == name.casefold()), None)
            if members is None:
                raise ValueError('Assigned playlist no longer exists')
            choices = [self.settings.get_alias(str(member)) for member in members]
            choices = [voice for voice in choices if voice and voice.enabled]
        elif selector.casefold() in {'random', '*'}:
            choices = [voice for voice in self.settings.aliases.values() if voice.enabled]
        elif selector.casefold().startswith('group:'):
            group = selector.split(':', 1)[1].strip().casefold()
            choices = [voice for voice in self.settings.aliases.values() if voice.enabled and voice.group.casefold() == group]
        else:
            alias = self.settings.get_alias(selector)
            choices = [alias] if alias and alias.enabled else []
        if not choices:
            raise ValueError('Assigned voice is missing, disabled, or its playlist has no enabled voices')
        return choices

    def _viewer_info(self, entry: dict) -> dict:
        result = dict(entry)
        result['assignmentOrigin'] = 'Viewer preference' if entry.get('voice') else 'Rules / default voice'
        result['available'] = True
        result['warning'] = ''
        if entry.get('voice'):
            try:
                self._viewer_choices(entry['voice'])
                if entry.get('assignmentSource') == 'command':
                    result['assignmentOrigin'] = 'Viewer command'
                if entry.get('assignmentSource') == 'viewer':
                    result['assignmentOrigin'] = 'Viewer command'
                    alias = self.settings.aliases.get(entry['voice'])
                    if alias is None or not alias.public or not public_label(alias):
                        raise ValueError('This voice is no longer public')
            except ValueError as exc:
                result['available'] = False
                result['warning'] = str(exc)
        return result

    def resolve_alias(self, alias_name: str):
        """Resolve a speak voice name to a VoiceAlias.

        Special selectors:
        - ``random`` / ``*`` — any alias with Voices ON checked
        - ``group:Name`` — ON aliases in that group field
        - ``playlist:Name`` — aliases listed in a Rules voice playlist (playlist is the pool)
        Explicit alias names still work when disabled (for testing).
        """
        key = str(alias_name or "").strip()
        if not key:
            raise ValueError("Voice alias is required")
        folded = key.casefold()
        if folded in {"random", "*"}:
            choices = [alias for alias in self.settings.aliases.values() if alias.enabled]
            if not choices:
                raise ValueError("No enabled voices available for random selection")
            return random.choice(choices)
        if folded.startswith("playlist:"):
            wanted = key.split(":", 1)[1].strip()
            if not wanted:
                raise ValueError("Playlist selector needs a name after playlist:")
            members = None
            for name, voices in (self.settings.voice_playlists or {}).items():
                if str(name).casefold() == wanted.casefold():
                    members = list(voices or [])
                    break
            if members is None:
                raise ValueError(f"Voice playlist not found: {wanted}")
            choices = []
            for member in members:
                alias = self.settings.aliases.get(str(member))
                if alias is not None:
                    choices.append(alias)
            if not choices:
                raise ValueError(f"Playlist has no valid voices: {wanted}")
            return random.choice(choices)
        if folded.startswith("group:"):
            group = key.split(":", 1)[1].strip().casefold()
            choices = [
                alias
                for alias in self.settings.aliases.values()
                if alias.enabled and alias.group.casefold() == group
            ]
            if not choices:
                raise ValueError(f"Voice group not found or has no enabled voices: {group}")
            return random.choice(choices)
        alias = self.settings.get_alias(key)
        if alias is None:
            raise ValueError(f"Voice alias not found: {key}")
        return alias

    def execute(self, request: str, data: dict) -> dict:
        native_voice_command = request.casefold() == 'assignvoicecommand'
        if request.casefold() != 'viewervoicecommand' and not native_voice_command:
            return self._execute(request, data)
        words = str(data.get('message') or '').strip().split(maxsplit=1)
        if not native_voice_command and (not words or words[0].casefold() != '!voice'):
            return dict(handled=False)
        display, login = _parse_streamerbot_user(data.get('user', data.get('displayName', '')))
        context = dict(id=str(uuid.uuid4()), source='Streamer.bot', user=display or login,
                       platform='', userId='', command='!voice', alias='', publicVoice='', reply='', error='', reason='')
        try:
            context['platform'], context['userId'] = identity(data)
        except ValueError:
            pass
        self.engine.events.emit('viewer', 'commandreceived', context)
        try:
            result = self._execute(request, data)
        except (ValueError, OSError) as exc:
            # Never include raw chat input or private alias names in the result event.
            message = str(exc) if isinstance(exc, ValueError) else 'Could not save your voice. Please try again.'
            context.update(error=message, reply=message, reason=('disabled' if not native_voice_command and not self.settings.viewer_commands_enabled else
                           'identity' if not context['userId'] else 'storage' if isinstance(exc, OSError) else 'unavailable'))
            self.engine.events.emit('viewer', 'commandfailed', context)
            raise
        action = result.get('action')
        event = {'assigned': 'voiceassigned', 'reset': 'voicereset', 'list': 'voiceslisted'}.get(action)
        if event:
            context.update(reply=result.get('reply', ''), publicVoice=result.get('voice', ''),
                           operation=action, voices=result.get('voices', []))
            if action == 'assigned':
                if native_voice_command:
                    context['alias'] = result.get('voice', '')
                else:
                    context['alias'] = self.viewers.get(context['platform'], context['userId']).get('voice', '')
            self.engine.events.emit('viewer', event, context)
        return dict(result, requestId=context['id'])

    def _execute(self, request: str, data: dict) -> dict:
        normalized = request.lower()
        if normalized == 'assignvoicecommand':
            self.settings.reload_if_changed()
            if not viewer_roles(data).intersection({'vip', 'moderator', 'broadcaster'}):
                raise ValueError('Only VIPs, moderators and the broadcaster can choose a voice.')
            display, login = _parse_streamerbot_user(data.get('userName') or data.get('user') or '')
            username = login or display
            identity(dict(username=username))
            argument = str(data.get('message') or '').strip()
            if argument in ('%ylArgs%', '%rawInput%'):
                argument = ''
            if not argument or argument.casefold() == 'list':
                names = [alias.name for alias in self.settings.aliases.values() if alias.enabled]
                return dict(handled=True, action='list', voices=names, reply=('Available voices: ' + ', '.join(names))[:400])
            selector = argument
            if argument.casefold() == 'reset':
                selector = ''
            else:
                matches = [alias.name for alias in self.settings.aliases.values() if alias.enabled and normalized_voice_name(alias.name) == normalized_voice_name(argument)]
                if len(matches) == 1:
                    selector = matches[0]
                elif argument.casefold() == 'random':
                    selector = 'random'
                self._viewer_choices(selector)
            with self.viewers.lock:
                self.viewers.update(dict(username=username, displayName=username, login=username, voice=selector), assign=True, assignment_source='command')
                if not selector:
                    try:
                        key = identity(data)
                    except ValueError:
                        key = None
                    if key and self.viewers.get(*key):
                        self.viewers.update(dict(platform=key[0], userId=key[1], voice=''), assign=True)
            return dict(handled=True, action='assigned' if selector else 'reset', voice=selector,
                        reply=('Your voice is now ' + selector + '.') if selector else 'Your voice now follows the default voice rules.')
        if normalized in {'getpublicvoices', 'viewervoicecommand'}:
            self.settings.reload_if_changed()
            choices = eligible_voices(self.settings, data)
            if normalized == 'getpublicvoices':
                return dict(enabled=self.settings.viewer_commands_enabled, voices=[public_label(alias) for alias in choices])
            if not self.settings.viewer_commands_enabled:
                raise ValueError('Viewer voice commands are disabled. Enable them in Voices > Assignments > Viewer commands.')
            message = str(data.get('message') or '').strip()
            words = message.split(maxsplit=1)
            if not words or words[0].casefold() != '!voice':
                return dict(handled=False)
            platform, user_id = identity(data)
            argument = words[1].strip() if len(words) > 1 else ''
            if not argument or argument.casefold() == 'list':
                names = [public_label(alias) for alias in choices]
                reply = 'Available voices: ' + ', '.join(names)
                if len(reply) > 400:
                    reply = reply[:397] + '...'
                return dict(handled=True, action='list', voices=names, reply=reply if names else 'No public voices are available for you yet.')
            if argument.casefold() == 'reset':
                self.viewers.update(dict(platform=platform, userId=user_id, voice=''), assign=True, assignment_source='viewer')
                return dict(handled=True, action='reset', reply='Your voice now follows assignment rules and the default voice.')
            if argument.casefold() == 'random':
                alias = random.choice(choices) if choices else None
            else:
                alias = next((voice for voice in choices if public_label(voice).casefold() == argument.casefold()), None)
            if alias is None:
                raise ValueError('That voice is unavailable for you. Use !voice to see available public voices.')
            display, login = _parse_streamerbot_user(data.get('user', data.get('displayName', '')))
            self.viewers.update(dict(platform=platform, userId=user_id, displayName=display, login=login, voice=alias.name),
                                assign=True, assignment_source='viewer')
            return dict(handled=True, action='assigned', voice=public_label(alias), reply='Your voice is now ' + public_label(alias) + '.')
        if normalized in {'getviewers', 'getviewervoice', 'setviewervoice', 'deleteviewervoice'}:
            self.settings.reload_if_changed()
            if normalized == 'getviewers':
                return dict(viewers=[self._viewer_info(entry) for entry in self.viewers.all() if entry.get('voice')],
                            defaultVoice=self.settings.assignment_default_voice,
                            voices=[voice.name for voice in self.settings.aliases.values() if voice.enabled] +
                                   ['playlist:' + name for name in self.settings.voice_playlists] + ['random'])
            platform, user_id = identity(data)
            if normalized == 'deleteviewervoice':
                return dict(deleted=self.viewers.delete(data), platform=platform, userId=user_id)
            if normalized == 'setviewervoice':
                selector = str(data.get('voice') or '').strip()
                if selector:
                    self._viewer_choices(selector)
                entry = self.viewers.update(dict(data, platform=platform, userId=user_id, voice=selector), assign=True)
            else:
                entry = self.viewers.get(platform, user_id) or dict(platform=platform, userId=user_id, displayName='', login='', voice='')
            return self._viewer_info(entry)
        if normalized == 'assignandspeak':
            username = str(data.get('userName') or data.get('user') or '').strip()
            self.execute('SetViewerVoice', dict(username=username, login=username, displayName=username, voice=data.get('voice', '')))
            return self.execute('Speak', dict(data, voice=''))
        if normalized in {'skipandresume', 'clearandresume'}:
            if normalized == 'skipandresume':
                self.engine.stop_current()
            else:
                self.engine.clear_all()
            self.engine.resume()
            return {}
        if normalized == "speak":
            self.settings.reload_if_changed()
            text = str(data.get("message", "")).strip()
            alias_name = str(data.get("voice", "")).strip()
            display_a, login_a = _parse_streamerbot_user(data.get("user", data.get("displayName", "")))
            display_b, login_b = _parse_streamerbot_user(
                data.get("userName", data.get("userLogin", data.get("login", "")))
            )
            # Prefer real display/login pairs; never keep JSON blobs.
            user_display = display_a or display_b
            user_login = login_b or login_a
            if user_display and user_display == user_login and display_a and login_b and display_a != login_b:
                user_display, user_login = display_a, login_b
            user = user_display or user_login
            viewer_key = None
            try:
                viewer_key = identity(data)
            except ValueError:
                pass  # Name-only legacy speech does not create a stable identity.
            saved_viewer = self.viewers.get(*viewer_key) if viewer_key else None
            # An explicit username assignment takes precedence over legacy ID records.
            saved_viewer = self.viewers.by_username(user_login or user_display) or saved_viewer
            viewer_voice = None
            if not alias_name and saved_viewer and saved_viewer.get('voice'):
                try:
                    if saved_viewer.get('assignmentSource') == 'viewer':
                        viewer_voice = next((voice for voice in eligible_voices(self.settings, data) if voice.name == saved_viewer['voice']), None)
                    else:
                        viewer_voice = random.choice(self._viewer_choices(saved_viewer['voice']))
                except ValueError:
                    pass  # Retain the assignment, but use routing/default until repaired.
            # Prefer login for allowlist/blocklist when both are known.
            moderation_user = user_login or user_display or user
            role = str(data.get("role", "")).strip().casefold()
            # Role may also arrive as part of a Streamer.bot user object.
            # Never reuse `text` here — that variable is the spoken message.
            if not role:
                for raw in (data.get("user"), data.get("userName")):
                    if isinstance(raw, dict) and raw.get("role") is not None:
                        role = str(raw.get("role")).strip().casefold()
                        break
                    raw_text = str(raw or "").strip()
                    if raw_text.startswith("{") and '"role"' in raw_text:
                        try:
                            parsed = json.loads(raw_text)
                            if isinstance(parsed, dict) and parsed.get("role") is not None:
                                role = str(parsed.get("role")).strip().casefold()
                                break
                        except Exception:
                            pass
            source = str(data.get("source", "Streamer.bot")).strip()
            priority = int(data.get("priority", 0))
            explicit_voice = alias_name
            user_keys = tuple(dict.fromkeys(value.casefold() for value in (user_login, user_display, user) if value))
            priority_matched = False
            routed_voice = ''
            roles = viewer_roles(data)
            for rule in self.settings.routing_rules:
                if rule.get("enabled", True) is False:
                    continue
                field = str(rule.get("field", ""))
                rule_value = str(rule.get("value", "")).casefold()
                if field == "user":
                    matched = bool(rule_value) and rule_value in user_keys
                elif field == 'role':
                    matched = rule_value.strip() in roles
                else:
                    actual = {"role": role, "source": source, "event": str(data.get("event", ""))}.get(field)
                    matched = actual is not None and actual.casefold() == rule_value
                if matched:
                    if not routed_voice:
                        routed_voice = str(rule.get('alias') or '').strip()
                    if not priority_matched and 'priority' in rule:
                        priority = int(rule.get('priority', priority))
                        priority_matched = True
                    if routed_voice and priority_matched:
                        break
            rule_alias = None
            for key in user_keys:
                rule_alias = self.settings.user_voice_rules.get(key)
                if rule_alias:
                    break
            if not rule_alias:
                roles = viewer_roles(data)
                groups = data.get('groups', [])
                groups = {value.strip().casefold() for value in groups if isinstance(value, str)} if isinstance(groups, list) else set()
                for key, selector in self.settings.role_voice_rules.items():
                    if key.startswith('group:') and key[6:].casefold() in groups:
                        rule_alias = selector
                        break
                if not rule_alias:
                    for candidate in ('broadcaster', 'moderator', 'vip', 'subscriber', role):
                        if candidate in roles and self.settings.role_voice_rules.get(candidate):
                            rule_alias = self.settings.role_voice_rules[candidate]
                            break
            if explicit_voice:
                alias = self.resolve_alias(explicit_voice)
            elif viewer_voice is not None:
                alias = viewer_voice
            else:
                alias = None
                for selector in (routed_voice, rule_alias, self.settings.assignment_default_voice):
                    if not selector:
                        continue
                    try:
                        alias = random.choice(self._viewer_choices(selector))
                        break
                    except ValueError:
                        continue  # Retain stale selectors for repair, then try the next fallback.
                if alias is None:
                    alias = next((voice for voice in self.settings.aliases.values() if voice.enabled), None)
                if alias is None:
                    raise ValueError('No enabled voice is available. Choose a default in Voices > Assignments.')
            alias_name = alias.name
            overrides = {}
            if "speed" in data:
                overrides["speed"] = float(data["speed"])
            if "volume" in data:
                overrides["volume"] = float(data["volume"])
            if "ssml" in data:
                overrides["ssml"] = bool(data["ssml"])
            if str(data.get("instruct", "")).strip():
                overrides["instruct"] = str(data["instruct"]).strip()
            if overrides:
                alias = replace(alias, **overrides)
            metadata = dict(platform=viewer_key[0], user_id=viewer_key[1], display_name=user) if viewer_key else {}
            metadata.update(message_id=str(data.get('messageId') or uuid.uuid4())[:128],
                            avatar_url=str(data.get('userProfileImageUrl') or data.get('profileImageUrl') or '')[:2048])
            if priority:
                metadata['priority'] = priority
            if viewer_key and saved_viewer and saved_viewer.get('voice') and saved_viewer.get('platform') != 'username':
                self.viewers.update(dict(platform=viewer_key[0], userId=viewer_key[1], displayName=user_display, login=user_login))
            def tagged_alias(name):
                from .audio_stims import resolve_stim
                stim = resolve_stim(self.settings, name, dict(user=moderation_user, displayName=user, userId=metadata.get('user_id', '')))
                if stim is not None:
                    return stim
                all_enabled = bool(viewer_key and self.settings.chat_voice_tags_all_enabled)
                restricted = bool(viewer_key and not all_enabled)
                candidates = list(eligible_voices(self.settings, data)) if restricted else [voice for voice in self.settings.aliases.values() if not viewer_key or voice.enabled]
                label = public_label if restricted else lambda voice: voice.name
                if restricted:
                    selected = next((voice for voice in candidates
                                     if public_label(voice).casefold() == name.casefold()), None)
                else:
                    selected = self.settings.get_alias(name)
                    if all_enabled and selected and not selected.enabled:
                        selected = None
                    if all_enabled and selected is None:
                        public_matches = [voice for voice in candidates if public_label(voice).casefold() == name.casefold()]
                        if len(public_matches) == 1:
                            selected = public_matches[0]
                if selected is None:
                    matches = [voice for voice in candidates if label(voice).casefold().startswith(name.casefold() + ' ')]
                    if len(matches) == 1:
                        selected = matches[0]
                if selected is None:
                    normalized_name = normalized_voice_name(name)
                    exact = [voice for voice in candidates if normalized_voice_name(label(voice)) == normalized_name]
                    partial = [voice for voice in candidates if len(normalized_name) >= 2 and normalized_voice_name(label(voice)).startswith(normalized_name + ' ')]
                    matches = exact or partial
                    if len(matches) == 1:
                        selected = matches[0]
                if selected is None:
                    # Unknown/ambiguous brackets are ordinary speech, not an
                    # invalid request. Known but inaccessible voices still obey
                    # their enabled state and viewer permissions.
                    normalized_name = normalized_voice_name(name)
                    known = [voice for voice in self.settings.aliases.values()
                             if any(normalized_voice_name(value) == normalized_name or
                                    (len(normalized_name) >= 2 and
                                     normalized_voice_name(value).startswith(normalized_name + ' '))
                                    for value in (voice.name, public_label(voice)))]
                    if not known or len(known) > 1:
                        return None
                    raise ValueError('A voice tag is unavailable. Check its name, enabled state and chat voice-tag access setting.')
                return replace(selected, **overrides) if overrides else selected
            # Strip prefixes before splitting: a command-only intro must not
            # become an empty segment that rejects otherwise valid speech.
            if not alias.ssml:
                text = strip_chat_tokens(text, self.settings)
                from .audio_stims import replace_censored_words
                text = replace_censored_words(text, self.settings)
            segments = split_voices(text, alias, tagged_alias)
            if len(segments) > 1 and any(voice.ssml for _, voice in segments):
                raise ValueError('Multi-voice input currently supports plain text, not SSML')
            if self.settings.split_speech_sentences:
                segments = [(clip, voice) for segment, voice in segments for clip in ([segment] if voice.ssml else sentence_clips(segment))]
                if len(segments) > 50:
                    raise ValueError('Sentence splitting allows at most 50 clips per input. Shorten the message or turn it off.')
            if len(segments) == 1:
                segment_text, segment_alias = segments[0]
                job = self.engine.enqueue(segment_text, segment_alias, source=source, user=moderation_user, **metadata)
                jobs = [job]
            else:
                jobs = self.engine.enqueue_many(segments, source=source, user=moderation_user, **metadata)
                job = jobs[0]
            return {
                "speechId": job.speech_id,
                "speechIds": [item.speech_id for item in jobs],
                "segments": [dict(speechId=item.speech_id, text=item.text, voiceName=item.alias.name) for item in jobs],
                "text": text,
                "voiceName": job.alias.name,
                "pitch": 0.0,
                "volume": job.alias.volume,
                "rate": job.alias.speed,
            }
        if normalized == "stop":
            self.engine.stop_current()
            return {}
        if normalized == "pause":
            self.engine.pause()
            return {}
        if normalized == "seek":
            return self.engine.seek(float(data.get("seconds", 0)), str(data.get("speechId", "")))
        if normalized == "pauseaftercurrent":
            self.engine.pause_after_current()
            return {}
        if normalized == "clearall":
            self.engine.clear_all()
            return {}
        if normalized == "resume":
            self.engine.resume()
            return {}
        if normalized == "clear":
            self.engine.clear()
            return {}
        if normalized in {"enable", "on"}:
            self.engine.enable()
            return {}
        if normalized in {"disable", "off"}:
            self.engine.disable()
            return {}
        if normalized == "getinfo":
            return {
                "instanceId": "45402e66-303c-43a4-bb1c-4ba721bb0569",
                "name": "Speaker.bot",
                "version": "0.1.6",
                "os": "windows",
                "apiVersion": 2,
                "bridgeName": "YapLoq",
                "bridgeVersion": __version__,
            }
        if normalized == "getevents":
            return {"events": self.EVENTS}
        if normalized == "getaliases":
            self.settings.reload_if_changed()
            return {
                "aliases": [
                    {"id": index, "name": name, "voiceCount": 1}
                    for index, name in enumerate(sorted(self.settings.aliases), 1)
                ]
            }
        if normalized == "getstate":
            return self.engine.state()
        if normalized == "loadprofile":
            from .maintenance import Maintenance
            name = str(data.get("profile", ""))
            Maintenance(self.settings).load_profile(name)
            return {"profile": name}
        if normalized == "gethistory":
            return {"history": self.engine.history_items()}
        if normalized == "clearhistory":
            self.engine.clear_history()
            return {}
        if normalized == "savehistoryaudio":
            return {"path": self.engine.save_history_audio(str(data.get("speechId", "")))}
        if normalized == "replayhistory":
            job = self.engine.replay_history(str(data.get("speechId", "")))
            return {"speechId": job.speech_id}
        if normalized == "removespeech":
            return {"removed": self.engine.remove(str(data.get("speechId", "")))}
        if normalized == 'changespeechvoice':
            return self.engine.change_waiting_voice(str(data.get('speechId', '')), str(data.get('voice', '')).strip())
        if normalized == "movespeech":
            direction = -1 if str(data.get("direction", "up")).lower() == "up" else 1
            return {"moved": self.engine.move(str(data.get("speechId", "")), direction)}
        if normalized == "reorderspeech":
            return {"moved": self.engine.move_before(str(data.get("speechId", "")), str(data.get("beforeId", "")))}
        if normalized == "commands":
            return {"commands": [
                "Speak", "Stop", "Pause", "Seek", "PauseAfterCurrent", "Resume", "Clear", "ClearAll", "Enable", "Disable",
                "GetInfo", "GetEvents", "GetAliases", "GetState", "GetHistory", "ClearHistory", "SaveHistoryAudio", "ReplayHistory",
                "RemoveSpeech", "MoveSpeech", "ReorderSpeech", "ChangeSpeechVoice", "LoadProfile", "Subscribe", "Unsubscribe", "Commands",
            ]}
        if normalized in {"events", "mode", "getvoicegateprofiles", "activatevoicegateprofile"}:
            return {}
        raise ValueError(f"Unsupported request: {request}")
