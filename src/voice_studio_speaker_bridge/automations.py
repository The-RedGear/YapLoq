"""Validated, data-only Streamer.Bot automation definitions and legacy projection."""
from copy import deepcopy
import math
import uuid
from urllib.request import urlopen
import json

from .protocol import SpeakerBotProtocol

LEGACY = {
    'streamerbot_queued_action': ('Queue started (first audio ready)', 'queued'),
    'streamerbot_queue_added_action': ('Queue: speech added', 'queueAdded'),
    'streamerbot_playing_action': ('Queue playback started', 'playing'),
    'streamerbot_finished_action': ('Queue finished', 'finished'),
    'streamerbot_received_action': ('Message received', 'received'),
    'streamerbot_generating_action': ('Generation started', 'generating'),
    'streamerbot_generated_action': ('Audio generated', 'generated'),
    'streamerbot_error_action': ('Message failed', 'itemError'),
    'streamerbot_cancelled_action': ('Message cancelled', 'itemCancelled'),
}
EVENT_LABELS = dict(received='Message received', generating='Generation started', textqueued='Audio ready',
                    queueadded='Message added to queue', queueextended='Message added to active queue', engineprocessed='Audio generated', playing='Playback started',
                    finished='Message finished', cancelled='Message cancelled or skipped', deleted='Message deleted',
                    error='Message failed', startedspeaking='Speech session started', stoppedspeaking='Speech session stopped',
                    profileactivated='Profile activated', voicechanged='Queued voice changed')
CATALOG = [dict(source=source, event=event, label=EVENT_LABELS.get(event, event))
           for source, events in SpeakerBotProtocol.EVENTS.items() for event in events
           if source == 'texttospeech' and event != 'deleted']
CATALOG.append(dict(source='integration', event='error', label='OBS integration failed'))
CATALOG += [dict(source='viewer', event=event, label=label) for event, label in (
    ('commandreceived', 'Viewer voice command received'), ('voiceassigned', 'Viewer voice set successfully'),
    ('voicereset', 'Viewer voice reset successfully'), ('voiceslisted', 'Viewer requested available voices'),
    ('commandfailed', 'Viewer voice command failed'))]
CATALOG += [dict(source='legacy', event=value[1], label=value[0]) for value in LEGACY.values()]
CATALOG += [dict(source='audiostim', event=event, label='Audio Stim ' + label) for event, label in
            [('playing', 'started'), ('finished', 'finished'), ('error', 'failed'), ('cancelled', 'cancelled')]]
FIELDS = ('alias', 'source', 'user', 'voiceName', 'engineName', 'id', 'text', 'integration', 'platform', 'userId', 'reason', 'publicVoice')


def effective_rules(settings):
    if settings.automations_migrated:
        return deepcopy(settings.automations)
    result = deepcopy(settings.automations)
    for key, (label, event) in LEGACY.items():
        action = str(getattr(settings, key, '')).strip()
        if not action:
            continue
        steps = []
        if key == 'streamerbot_finished_action' and settings.streamerbot_finished_delay:
            steps.append(dict(type='delay', seconds=settings.streamerbot_finished_delay, enabled=True))
        steps.append(dict(type='action', action=action, enabled=True, args={}))
        result.append(dict(id='legacy-' + key, name=label, enabled=settings.streamerbot_actions_enabled,
                           legacyKey=key, triggers=[dict(source='legacy', event=event)],
                           conditions=[], steps=steps, onError='stop'))
    return result


def validate_rules(raw):
    if not isinstance(raw, list):
        raise ValueError('Automations must be a list')
    allowed = {(item['source'], item['event']) for item in CATALOG}
    ids, result = set(), []
    for value in raw:
        if not isinstance(value, dict):
            raise ValueError('Each automation must be an object')
        rule = deepcopy(value)
        rule['id'] = str(rule.get('id') or uuid.uuid4())
        if rule['id'] in ids:
            raise ValueError('Automation IDs must be unique')
        ids.add(rule['id'])
        rule['name'] = str(rule.get('name', '')).strip()
        if not rule['name']:
            raise ValueError('Give every automation a name')
        rule['enabled'] = bool(rule.get('enabled', True))
        triggers = rule.get('triggers', [])
        if not isinstance(triggers, list) or not triggers:
            raise ValueError('Choose at least one trigger')
        for trigger in triggers:
            if not isinstance(trigger, dict) or (trigger.get('source'), trigger.get('event')) not in allowed:
                raise ValueError('Choose an available YapLoq event')
        triggers = [dict(source=t['source'], event=t['event']) for t in triggers]
        rule['triggers'] = triggers
        key = rule.get('legacyKey')
        if key:
            if key not in LEGACY:
                raise ValueError('Choose a supported queue-session trigger')
        if any(t['source'] == 'legacy' for t in triggers):
            # Session triggers reuse the proven lifecycle state machine.
            keys = [k for k, v in LEGACY.items() if triggers == [dict(source='legacy', event=v[1])]]
            if not keys:
                raise ValueError('Use a single queue-session trigger per automation, or choose per-message events')
            rule['legacyKey'] = keys[0]
        else:
            # Once edited to ordinary events this is a normal action, not a
            # legacy lifecycle hook. Keep its ID, name, conditions and steps.
            rule.pop('legacyKey', None)
        conditions = rule.setdefault('conditions', [])
        if not isinstance(conditions, list):
            raise ValueError('Conditions must be a list')
        for condition in conditions:
            if not isinstance(condition, dict) or condition.get('field') not in FIELDS or condition.get('op') not in ('equals', 'contains', 'notEquals'):
                raise ValueError('Choose a supported condition field and comparison')
            condition['value'] = str(condition.get('value', ''))
        steps = rule.setdefault('steps', [])
        if not isinstance(steps, list) or not steps:
            raise ValueError('Add at least one sub-action')
        for step in steps:
            if not isinstance(step, dict):
                raise ValueError('Each sub-action must be an object')
            step['enabled'] = bool(step.get('enabled', True))
            if step.get('type') == 'delay':
                try:
                    seconds = float(step.get('seconds', 0))
                except (ValueError, TypeError):
                    raise ValueError('Delay must be a number of seconds') from None
                if not math.isfinite(seconds) or seconds < 0 or seconds > 86400:
                    raise ValueError('Delay must be between 0 and 86400 seconds')
                step['seconds'] = seconds
            elif step.get('type') == 'action':
                step['action'] = str(step.get('action', '')).strip()
                if not step['action']:
                    raise ValueError('Select a Streamer.Bot action or enter its name/ID')
                args = step.setdefault('args', {})
                if not isinstance(args, dict) or any(not isinstance(k, str) or not isinstance(v, (str, int, float, bool, type(None))) for k, v in args.items()):
                    raise ValueError('Arguments must be a JSON object with simple values')
            else:
                raise ValueError('Choose Run action or Delay')
        if rule.setdefault('onError', 'stop') not in ('stop', 'continue'):
            raise ValueError('Choose Stop or Continue after a failure')
        result.append(rule)
    return result


def matches_conditions(rule, data):
    for condition in rule.get('conditions', []):
        actual = str(data.get(condition['field'], '')).casefold()
        wanted = condition['value'].casefold()
        op = condition['op']
        if (op == 'equals' and actual != wanted or op == 'notEquals' and actual == wanted
                or op == 'contains' and wanted not in actual):
            return False
    return True


def remote_actions(settings):
    request_url = settings.streamerbot_http_url.rstrip('/') + '/GetActions'
    with urlopen(request_url, timeout=3) as response:
        raw = json.loads(response.read(2_000_000))
    actions = raw.get('actions')
    if not isinstance(actions, list):
        raise ValueError('Streamer.Bot did not return an action list. Enable its HTTP server.')
    return [dict(id=str(a['id']), name=str(a['name'])) for a in actions
            if isinstance(a, dict) and a.get('id') and a.get('name')]
