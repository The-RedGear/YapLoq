from __future__ import annotations

import json
import logging
import re
from queue import Empty, Full, Queue
from threading import Event, RLock, Thread, Timer
from urllib.request import Request, urlopen

from .events import EventBus
from .settings import Settings
from .automations import matches_conditions, validate_rules


class StreamerBotActions:
    """Run optional Streamer.bot actions for TTS lifecycle events."""

    EVENT_SETTINGS = {
        "textqueued": ("queued", "streamerbot_queued_action"),
        "queueadded": ("queueAdded", "streamerbot_queue_added_action"),
        "playing": ("playing", "streamerbot_playing_action"),
        "finished": ("finished", "streamerbot_finished_action"),
        "cancelled": ("cancelled", "streamerbot_finished_action"),
        "error": ("error", "streamerbot_finished_action"),
    }
    EXTRA_EVENT_SETTINGS = {
        "received": ("received", "streamerbot_received_action"),
        "generating": ("generating", "streamerbot_generating_action"),
        "engineprocessed": ("generated", "streamerbot_generated_action"),
        "error": ("itemError", "streamerbot_error_action"),
        "cancelled": ("itemCancelled", "streamerbot_cancelled_action"),
    }

    def __init__(self, settings: Settings, events: EventBus):
        self.settings = settings
        self.events = events
        self.pending: Queue[tuple[str, dict] | None] = Queue()
        self.stim_pending = Queue(maxsize=128)
        self.stim_thread = Thread(target=self._run_stims, name='Audio Stim hooks', daemon=True)
        self.stop_event = Event()
        self.state_lock = RLock()
        self.finish_timer: Timer | None = None
        self.finish_generation = 0
        self.active_speech_ids: set[str] = set()
        self.active_stim_ids: set[str] = set()
        self.speech_session_seen = False
        self.batch_is_playing = False
        self.batch_queued_announced = False
        self.thread = Thread(target=self._run, name="Streamer.bot actions", daemon=True)
        events.subscribe(self._on_event)

    def start(self) -> None:
        if not self.thread.is_alive():
            self.thread.start()
        if not self.stim_thread.is_alive():
            self.stim_thread.start()

    def shutdown(self) -> None:
        if self.settings.automations_migrated:
            self.stop_event.set()
        finish = None
        with self.state_lock:
            if self.finish_timer is not None:
                finish = self.finish_timer.args[:2]
                self.finish_timer.cancel()
                self.finish_timer = None
        if finish:
            self.pending.put(finish)
        self.pending.put(None)
        if self.thread.is_alive():
            self.thread.join(timeout=7)
        self.stop_event.set()
        if self.stim_thread.is_alive():
            self.stim_thread.join(timeout=4)

    def _on_event(self, source: str, event_type: str, data: dict) -> None:
        if data.get('automationOrigin'):
            return
        # Sounds have their own hooks; they must not start/finish the speech
        # session or run avatar/puppet speech automation.
        if source.casefold() == 'texttospeech' and data.get('stim'):
            speech_id = str(data.get('id', ''))
            with self.state_lock:
                if event_type == 'received':
                    self.active_stim_ids.add(speech_id)
                    if self.finish_timer is not None:
                        self.speech_session_seen = True
                    self._cancel_finished_timer()
                elif event_type in {'finished', 'cancelled', 'error'}:
                    self.active_stim_ids.discard(speech_id)
                    if self.speech_session_seen and not self.active_speech_ids and not self.active_stim_ids:
                        self.speech_session_seen = False
                        self.batch_is_playing = False
                        self.batch_queued_announced = False
                        self.settings.reload_if_changed()
                        action = self._configured_action('streamerbot_finished_action') if self._actions_enabled() else None
                        if action:
                            self._schedule_finished(action, self._arguments('finished', data))
            if event_type == 'textqueued':
                self.events.acknowledge_action(str(data.get('id', '')))
            return
        if source == 'audiostim':
            stim = data.get('stim') or {}
            if 'preview' in str(data.get('source', '')).casefold() or (data.get('replay') and not stim.get('replay_actions')):
                return
            if event_type == 'playing' and stim.get('action') and (stim.get('allow_without_user') or self._has_viewer(data)):
                arguments = self._arguments(event_type, data)
                arguments.update(userName=data.get('user', ''), user=data.get('displayName') or data.get('user', ''),
                                 displayName=data.get('displayName') or data.get('user', ''), userId=data.get('userId', ''),
                                 userType=data.get('platform', ''), platform=data.get('platform', ''),
                                 userProfileImageUrl=data.get('userProfileImageUrl', ''), profileImageUrl=data.get('userProfileImageUrl', ''),
                                 targetUserName=data.get('user', ''), targetUser=data.get('displayName') or data.get('user', ''),
                                 targetUserProfileImageUrl=data.get('userProfileImageUrl', ''), rawInput=data.get('user', ''))
                try:
                    self.stim_pending.put_nowait((stim['action'], arguments))
                except Full:
                    self.events.emit('integration', 'error', dict(integration='Audio Stim hook backlog', automationOrigin=True))
        self.settings.reload_if_changed()
        for rule in self.settings.automations:
            if (rule.get('enabled', True) and not rule.get('legacyKey')
                    and any(t.get('source') == source and t.get('event') == event_type for t in rule.get('triggers', []))
                    and matches_conditions(rule, data)):
                self.pending.put((rule, self._arguments(event_type, data)))
        if source == "integrationtest":
            self.settings.reload_if_changed()
            mapped = self.EXTRA_EVENT_SETTINGS.get(event_type) or self.EVENT_SETTINGS.get(event_type)
            if mapped and self._actions_enabled():
                action = self._configured_action(mapped[1])
                if action:
                    self.pending.put((action, self._arguments(mapped[0], data)))
            return
        if source.casefold() != "texttospeech":
            return
        self.settings.reload_if_changed()
        extra = self.EXTRA_EVENT_SETTINGS.get(event_type)
        if extra and self._actions_enabled():
            action = self._configured_action(extra[1])
            if action:
                self.pending.put((action, self._arguments(extra[0], data)))
        if event_type == "received" and self._actions_enabled():
            with self.state_lock:
                self.active_speech_ids.add(str(data.get("id", "")))
                self.speech_session_seen = True
            self._cancel_finished_timer()
            return
        mapped = self.EVENT_SETTINGS.get(event_type.casefold())
        if mapped is None:
            return
        self.settings.reload_if_changed()
        if not self._actions_enabled():
            if event_type == "textqueued":
                self.events.acknowledge_action(str(data.get("id", "")))
            return
        state, setting_name = mapped
        speech_id = str(data.get("id", ""))
        if state == "queueAdded":
            with self.state_lock:
                if speech_id:
                    self.active_speech_ids.add(speech_id)
            self._cancel_finished_timer()
        elif state == "queued":
            with self.state_lock:
                if speech_id:
                    self.active_speech_ids.add(speech_id)
                if self.batch_queued_announced:
                    self.events.acknowledge_action(speech_id)
                    return
                self.batch_queued_announced = True
            self._cancel_finished_timer()
        elif state == "playing":
            self._cancel_finished_timer()
            with self.state_lock:
                if self.batch_is_playing:
                    return
                self.batch_is_playing = True
        elif state in {"finished", "cancelled", "error"}:
            with self.state_lock:
                if speech_id:
                    self.active_speech_ids.discard(speech_id)
                queue_is_idle = not self.active_speech_ids and not self.active_stim_ids
                if queue_is_idle:
                    self.speech_session_seen = False
                    self.batch_is_playing = False
                    self.batch_queued_announced = False
            if not queue_is_idle:
                return
        action = self._configured_action(setting_name)
        if not action and state == "queued":
            self.events.acknowledge_action(speech_id)
        if action:
            arguments = self._arguments(state, data)
            if state in {"finished", "cancelled", "error"}:
                self._schedule_finished(action, arguments)
            else:
                if state == "playing":
                    self._cancel_finished_timer()
                self.pending.put((action, arguments))

    def _schedule_finished(self, action: str, arguments: dict) -> None:
        delay = 0.0 if isinstance(action, dict) else max(0.0, min(10.0, float(self.settings.streamerbot_finished_delay)))
        self._cancel_finished_timer()
        if delay <= 0:
            self.pending.put((action, arguments))
            return
        with self.state_lock:
            generation = self.finish_generation
            timer = Timer(delay, self._release_finished, args=(action, arguments, generation))
            timer.daemon = True
            self.finish_timer = timer
        timer.start()

    def _release_finished(self, action: str, arguments: dict, generation: int) -> None:
        with self.state_lock:
            if generation != self.finish_generation or self.active_speech_ids or self.active_stim_ids:
                return
            self.finish_timer = None
        if not self.stop_event.is_set():
            self.pending.put((action, arguments))

    def _cancel_finished_timer(self) -> None:
        with self.state_lock:
            self.finish_generation += 1
            if self.finish_timer is not None:
                self.finish_timer.cancel()
                self.finish_timer = None

    @staticmethod
    def _has_viewer(data):
        from .audio_stims import has_viewer
        return has_viewer(data)

    @staticmethod
    def _arguments(state: str, data: dict) -> dict:
        return {
            "ttsState": state,
            "ttsId": str(data.get("id", "")),
            "ttsText": str(data.get("text", "")),
            "ttsAlias": str(data.get("alias", "")),
            "ttsVoice": str(data.get("voiceName", "")),
            "ttsSource": str(data.get("source", "")),
            "ttsUser": str(data.get("user", "")),
            "ttsDuration": float(data.get("duration", 0.0) or 0.0),
            "ttsEngine": str(data.get('engineName', '')),
            "ttsError": str(data.get('error', data.get('message', ''))),
            "ttsIntegration": str(data.get('integration', '')),
            "ttsPlatform": str(data.get('platform', '')),
            "ttsUserId": str(data.get('userId', '')),
            "ttsPublicVoice": str(data.get('publicVoice', '')),
            "ttsReply": str(data.get('reply', '')),
            "ttsReason": str(data.get('reason', '')),
            "ttsStim": str((data.get('stim') or {}).get('name', '')),
            "ttsSoundFile": str((data.get('stim') or {}).get('file', '')),
            "ttsMessageId": str(data.get('messageId', '')),
            "ttsDisplayName": str(data.get('displayName', '')),
            "ttsUserProfileImageUrl": str(data.get('userProfileImageUrl', '')),
        }

    def _run_stims(self):
        while not self.stop_event.is_set():
            try:
                action, arguments = self.stim_pending.get(timeout=0.1)
            except Empty:
                continue
            try:
                self._post_action(action, arguments)
            except Exception:
                logging.exception('Audio Stim action dispatch failed')
                self.events.emit('integration', 'error', dict(integration='Audio Stim action', id=arguments.get('ttsId', ''), automationOrigin=True))
            finally:
                self.stim_pending.task_done()

    def _actions_enabled(self):
        if self.settings.automations_migrated:
            return any(rule.get('enabled', True) and rule.get('legacyKey') for rule in self.settings.automations)
        return self.settings.streamerbot_actions_enabled

    def _configured_action(self, key):
        if self.settings.automations_migrated:
            rules = [rule for rule in self.settings.automations if rule.get('legacyKey') == key and rule.get('enabled', True)]
            return dict(legacyKey=key, rules=rules) if rules else ''
        return str(getattr(self.settings, key, '')).strip()

    def _run_steps(self, rule, arguments):
        if 'rules' in rule:
            for child in rule['rules']:
                self._run_steps(child, arguments)
            return
        rule = validate_rules([rule])[0]
        data = dict(alias=arguments.get('ttsAlias'), source=arguments.get('ttsSource'), user=arguments.get('ttsUser'),
                    voiceName=arguments.get('ttsVoice'), engineName=arguments.get('ttsEngine'),
                    id=arguments.get('ttsId'), text=arguments.get('ttsText'), integration=arguments.get('ttsIntegration'),
                    platform=arguments.get('ttsPlatform'), userId=arguments.get('ttsUserId'),
                    reason=arguments.get('ttsReason'), publicVoice=arguments.get('ttsPublicVoice'))
        if not matches_conditions(rule, data):
            return
        for step in rule['steps']:
            if self.stop_event.is_set():
                return
            if not step.get('enabled', True):
                continue
            if rule.get('legacyKey') == 'streamerbot_finished_action' and (self.active_speech_ids or self.active_stim_ids):
                return
            try:
                if step['type'] == 'delay':
                    if self.stop_event.wait(step['seconds']):
                        return
                else:
                    args = dict(arguments)
                    for key, value in step.get('args', {}).items():
                        if isinstance(value, str):
                            value = re.sub(r'\{(tts\w+)\}', lambda match: str(arguments.get(match[1], match[0])), value)
                        args[key] = value
                    self._post_action(step['action'], args)
            except Exception:
                self.events.emit('automation', 'failed', {'automationId': rule['id'], 'step': rule['steps'].index(step) + 1, 'automationOrigin': True})
                if rule['onError'] != 'continue':
                    raise

    def _run(self) -> None:
        while not self.stop_event.is_set():
            try:
                item = self.pending.get(timeout=0.5)
            except Empty:
                continue
            if item is None:
                self.pending.task_done()
                break
            action, arguments = item
            delivered = False
            try:
                with self.state_lock:
                    generic = isinstance(action, dict) and not action.get('legacyKey')
                    if not generic and arguments.get("ttsState") in {"finished", "cancelled", "error"} and (self.active_speech_ids or self.active_stim_ids):
                        continue
                    if not generic and arguments.get("ttsState") in {"queued", "playing"} and arguments.get("ttsId") != "lifecycle-test" and arguments.get("ttsId") not in self.active_speech_ids:
                        continue
                if isinstance(action, dict):
                    self._run_steps(action, arguments)
                    self.events.emit('automation', 'dispatched', {'automationId': action.get('id', action.get('legacyKey', '')), 'automationOrigin': True})
                else:
                    self._post_action(action, arguments)
                delivered = True
            except Exception:
                logging.exception("Could not run Streamer.bot lifecycle action %s", action)
                self.events.emit("integration", "error", {"integration": "Streamer.bot", "id": arguments.get("ttsId", ""), 'automationOrigin': True})
            finally:
                if arguments.get("ttsState") == "queued":
                    self.events.acknowledge_action(str(arguments.get("ttsId", "")), delivered)
                self.pending.task_done()

    def _post_action(self, action: str, arguments: dict) -> None:
        identifier = "id" if self._looks_like_guid(action) else "name"
        body = json.dumps({"action": {identifier: action}, "args": arguments}).encode("utf-8")
        request = Request(
            self.settings.streamerbot_http_url.rstrip("/") + "/DoAction",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(request, timeout=3) as response:
            if response.status not in (200, 204):
                raise OSError(f"Streamer.bot returned HTTP {response.status}")

    @staticmethod
    def _looks_like_guid(value: str) -> bool:
        parts = value.split("-")
        return len(parts) == 5 and [len(part) for part in parts] == [8, 4, 4, 4, 12]
