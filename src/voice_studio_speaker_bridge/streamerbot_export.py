"""Native SBAE exports using Streamer.bot's documented v10 export envelope.

The legacy v0.2.4 action schema is intentional: supported Streamer.bot versions
upgrade that schema on import. No trigger runs automatically on import.
"""
import base64
import gzip
import json
import uuid

from . import __version__
from .yaploq_payload import speech_payload, control_payload


def _id(name: str) -> str:
    # Preserve installed action/queue IDs across the rename to avoid duplicate imports.
    return str(uuid.uuid5(uuid.NAMESPACE_OID, "VoxRelay/" + name))


def export_actions(port: int, alias: str) -> str:
    if not 1 <= port <= 65535:
        raise ValueError("UDP port must be between 1 and 65535")
    voice = alias.strip()
    if "\n" in voice or "\r" in voice:
        raise ValueError("Choose a valid voice alias for the Speak action")
    # A blank alias deliberately uses the Assignments resolution pipeline.
    # ``random`` / ``playlist:Name`` / ``group:Name`` are resolved at speak time.
    if voice.casefold().startswith("group:") and not voice.split(":", 1)[1].strip():
        raise ValueError("Group selector needs a group name after group:")
    if voice.casefold().startswith("playlist:") and not voice.split(":", 1)[1].strip():
        raise ValueError("Playlist selector needs a name after playlist:")
    queue_id = _id("command queue")
    commands = [("Speak", speech_payload(voice))]
    for name, token in (("Pause audio", "pause"), ("Pause after current", "pauseaftercurrent"),
                        ("Resume", "resume"), ("Skip current", "skip"),
                        ("Clear waiting", "clear"), ("Stop and clear", "clearall"),
                        ("Remove item", "remove"), ("Move item up", "moveup"), ("Move item down", "movedown")):
        payload = control_payload(token, *(['%ttsId%'] if token in {'remove', 'moveup', 'movedown'} else []))
        commands.append((name, payload))
    actions = []
    for name, payload in commands:
        actions.append({"id": _id("action/"+name), "queue": queue_id, "enabled": True,
            "excludeFromHistory": False, "name": "[YL] - "+name, "group": "YapLoq",
            "alwaysRun": False, "randomAction": False, "concurrent": True,
            "triggers": [], "actionGroups": [], "collapsedGroups": [],
            "actions": [{"id": _id("subaction/"+name), "weight": 0.0, "type": 2,
                "group": None, "enabled": True, "index": 0, "port": port, "payload": payload}]})
    envelope = {
        "version": 10, "exportedFrom": "0.2.4", "minimumVersion": "0.2.4",
        "meta": {"name": "YapLoq speech and queue controls", "author": "YapLoq",
            "version": __version__, "autoRunAction": None, "minimumVersion": "0.2.4",
            "description": "Speech and queue actions for YapLoq. Attach your own triggers. Speak uses the selected alias, or random among Voices marked On. Item controls use ttsId. Importing can replace existing YapLoq actions with the same names."},
        "data": {"actions": actions, "queues": [{"id": queue_id, "name": "Yaploq", "blocking": False}],
            "commands": [], "websocketServers": [], "websocketClients": [], "timers": []}}
    binary = b"SBAE" + gzip.compress(json.dumps(envelope, ensure_ascii=False, separators=(",", ":")).encode("utf-8"), mtime=0)
    return base64.b64encode(binary).decode("ascii")


def export_viewer_commands(port: int, platform: str = '') -> str:
    platform = platform.strip().casefold()
    if platform not in {'', 'twitch', 'youtube', 'kick'}:
        raise ValueError('Choose Twitch, YouTube, Kick, or event platform')
    binary = base64.b64decode(export_actions(port, ''))
    envelope = json.loads(gzip.decompress(binary[4:]))
    action = envelope['data']['actions'][0]
    suffix = ' - ' + platform.title() if platform else ''
    action['id'] = _id('action/Viewer voice command/' + platform)
    action['name'] = '[YL] - Viewer voice command' + suffix
    step = action['actions'][0]
    step['id'] = _id('subaction/Viewer voice command/' + platform)
    event_platform = platform or '%userType%'
    step['payload'] = speech_payload('', event_platform, '!voice %rawInput%', 'viewer')
    speech = json.loads(json.dumps(action))
    speech['id'] = _id('action/Viewer assigned speech/' + platform)
    speech['name'] = '[YL] - Speak using viewer assignment' + suffix
    speech['actions'][0]['id'] = _id('subaction/Viewer assigned speech/' + platform)
    speech['actions'][0]['payload'] = speech_payload('', event_platform, '%rawInput%')
    chat = json.loads(json.dumps(speech))
    chat['id'] = _id('action/Viewer assigned chat/' + platform)
    chat['name'] = '[YL] - Chat using viewer assignment' + suffix
    chat['actions'][0]['id'] = _id('subaction/Viewer assigned chat/' + platform)
    chat['actions'][0]['payload'] = chat['actions'][0]['payload'].replace('%rawInput%', '%message%')
    envelope['data']['actions'] = [action, speech, chat]
    envelope['meta']['name'] = 'YapLoq viewer voice command'
    envelope['meta']['description'] = 'Attach a Command Triggered trigger for a Starts With !voice command to Viewer voice command. Attach your separate speech command (for example !say) to Speak using viewer assignment. For ordinary chat messages, attach Chat using viewer assignment instead; it sends message, not rawInput. Do not attach both speech actions to the same input. Enable viewer commands in YapLoq Assignments only if using !voice. Import does not create or run triggers. Use viewer result events in YapLoq Actions to run your own Streamer.Bot reply actions; ttsReply, ttsPlatform and ttsUserId are supplied.'
    binary = b'SBAE' + gzip.compress(json.dumps(envelope, ensure_ascii=False, separators=(',', ':')).encode('utf-8'), mtime=0)
    return base64.b64encode(binary).decode('ascii')


def export_complete_pack(port: int, platform: str = '', aliases=(), playlists=(), profiles=(), preset='complete', groups=(), command_aliases=None) -> str:
    """All supported remote controls; nothing auto-runs or silently attaches triggers."""
    if preset not in {'complete', 'essentials'}:
        raise ValueError('Choose Complete pack or Essentials')
    envelope = json.loads(gzip.decompress(base64.b64decode(export_actions(port, ''))[4:]))
    # Complete imports are always platform-neutral, including older callers that
    # still supply a platform argument.
    viewer = json.loads(gzip.decompress(base64.b64decode(export_viewer_commands(port, ''))[4:]))
    actions = envelope['data']['actions']
    # Existing IDs are retained when these templates replace earlier exports.
    actions.extend(viewer['data']['actions'][1:])
    actions[-2]['name'] = '[YL] - Speak - Chat command'
    actions[-1]['name'] = '[YL] - Speak - Chat message'
    for action in actions[-2:]:
        # Separate entry points must not replace users' existing speech triggers.
        action['id'] = _id('speech-input/' + action['name'])
        action['actions'][0]['id'] = _id('speech-input-step/' + action['name'])
    queue_id = envelope['data']['queues'][0]['id']
    event_platform = '%userType%'

    def add(name, payload, category='Tools'):
        actions.append(dict(id=_id('pack/' + name), queue=queue_id, enabled=True, excludeFromHistory=False,
                            name='[YL] - ' + name, group='YapLoq / ' + category, alwaysRun=False,
                            randomAction=False, concurrent=True, triggers=[], actionGroups=[], collapsedGroups=[],
                            actions=[dict(id=_id('pack-step/' + name), weight=0.0, type=2, group=None,
                                          enabled=True, index=0, port=port, payload=payload)]))

    add('Speak - Channel point reward', speech_payload('', event_platform, '%rawInput%'), 'Speech')
    add('Speak random voice', speech_payload('random', event_platform), 'Speech')
    add('Skip and resume', control_payload('skipresume'), 'Combined')
    add('Stop, clear and resume', control_payload('clearresume'), 'Combined')
    add('Set viewer voice', control_payload('assign', '%userName%', '%ttsAlias%'), 'Assignments')
    add('Reset viewer voice', control_payload('reset', '%userName%'), 'Assignments')
    add('Assign voice and speak', speech_payload('%ttsAlias%', event_platform, command='assignandspeak'), 'Combined')
    if preset == 'complete':
        for name, command, arguments in [
            ('Delete viewer assignment', 'deleteassignment', ['%userName%']),
            ('Enable speech', 'enable', []), ('Disable speech', 'disable', []),
            ('Replay audio', 'replay', ['%ttsId%']), ('Save audio', 'saveaudio', ['%ttsId%']),
            ('Change queued voice', 'changevoice', ['%ttsId%', '%ttsAlias%']),
            ('Seek audio', 'seek', ['%ttsId%', '%ttsSeconds%']), ('Clear history', 'clearhistory', []),
            ('Load saved profile', 'loadprofile', ['%ttsProfile%'])]:
            add(name, control_payload(command, *arguments))
        actions.append(viewer['data']['actions'][0])
        for alias in sorted(set(aliases), key=str.casefold):
            if not alias or '\n' in alias or '\r' in alias:
                continue
            add('Speak - ' + alias, speech_payload(alias, event_platform), 'Voices')
        for playlist in sorted(set(playlists), key=str.casefold):
            if playlist and '\n' not in playlist and '\r' not in playlist:
                add('Speak playlist - ' + playlist, speech_payload('playlist:' + playlist, event_platform), 'Playlists')
        for group in sorted(set(groups), key=str.casefold):
            if group and '\n' not in group and '\r' not in group:
                add('Speak voice group - ' + group, speech_payload('group:' + group, event_platform), 'Voice groups')
        for profile in sorted(set(profiles), key=str.casefold):
            if profile and '\n' not in profile and '\r' not in profile:
                add('Load profile - ' + profile, control_payload('loadprofile', profile), 'Profiles')
    envelope['meta'].update(name='YapLoq integration' if preset == 'complete' else 'YapLoq essentials',
                            description='Speech, assignments and playback controls for Twitch, YouTube and Kick. Includes VIP/mod voice selection and moderator-only chat controls.')
    from .streamerbot_commands import attach_commands
    attach_commands(envelope, port, aliases if command_aliases is None else command_aliases)
    return base64.b64encode(b'SBAE' + gzip.compress(json.dumps(envelope, ensure_ascii=False, separators=(',', ':')).encode(), mtime=0)).decode()


def export_speech_inputs(port: int) -> str:
    """Add the three speech entry points without replacing existing command bindings."""
    pack = json.loads(gzip.decompress(base64.b64decode(export_complete_pack(port))[4:]))
    names = {'[YL] - Speak - ' + source for source in
             ('Chat command', 'Channel point reward', 'Chat message')}
    pack['data']['actions'] = [a for a in pack['data']['actions'] if a['name'] in names]
    for action in pack['data']['actions']:
        action['triggers'] = []
    pack['data']['commands'] = []
    pack['meta'].update(name='YapLoq speech inputs', description='Speech actions for chat commands, channel point rewards and chat messages.')
    return base64.b64encode(b'SBAE' + gzip.compress(json.dumps(pack, ensure_ascii=False, separators=(',', ':')).encode(), mtime=0)).decode()


def export_selected_voices(port: int, aliases: list[str], all_aliases=None) -> str:
    if not isinstance(aliases, list) or not aliases or any(not isinstance(name, str) or not name.strip() or '\n' in name or '\r' in name for name in aliases):
        raise ValueError('Select at least one saved voice to export')
    names = set(aliases)
    pack = json.loads(gzip.decompress(base64.b64decode(export_complete_pack(port, aliases=aliases, command_aliases=aliases if all_aliases is None else all_aliases))[4:]))
    pack['data']['actions'] = [action for action in pack['data']['actions']
                               if action['group'] == 'YapLoq / Voices' and action['name'][len('[YL] - Speak - '):] in names]
    command_ids = {trigger['commandId'] for action in pack['data']['actions'] for trigger in action['triggers']}
    pack['data']['commands'] = [command for command in pack['data']['commands'] if command['id'] in command_ids]
    pack['meta'].update(name='YapLoq voices', description='Selected voice actions. Import alongside your existing YapLoq actions.')
    return base64.b64encode(b'SBAE' + gzip.compress(json.dumps(pack, ensure_ascii=False, separators=(',', ':')).encode(), mtime=0)).decode()
