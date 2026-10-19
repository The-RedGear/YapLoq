"""Native SBAE exports using Streamer.bot's documented v10 export envelope.

The legacy v0.2.4 action schema is intentional: supported Streamer.bot versions
upgrade that schema on import. No trigger runs automatically on import.
"""
import base64
import gzip
import json
import uuid

from . import __version__


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
    commands = [("Speak", f"YAPLOQ2\r\n{voice}\r\n%commandSource%\r\n%userId%\r\n%userName%\r\n%role%\r\n%isSubscribed%\r\n%isVip%\r\n%isModerator%\r\n%message%")]
    for name, token in (("Pause audio", "pause"), ("Pause after current", "pauseaftercurrent"),
                        ("Resume", "resume"), ("Skip current", "skip"),
                        ("Clear waiting", "clear"), ("Stop and clear", "clearall"),
                        ("Remove item", "remove"), ("Move item up", "moveup"), ("Move item down", "movedown")):
        payload = "VCONTROL\r\n" + token
        if token in {"remove", "moveup", "movedown"}:
            payload += "\r\n%ttsId%"
        commands.append((name, payload))
    actions = []
    for name, payload in commands:
        actions.append({"id": _id("action/"+name), "queue": queue_id, "enabled": True,
            "excludeFromHistory": False, "name": "YapLoq - "+name, "group": "YapLoq",
            "alwaysRun": False, "randomAction": False, "concurrent": True,
            "triggers": [], "actionGroups": [], "collapsedGroups": [],
            "actions": [{"id": _id("subaction/"+name), "weight": 0.0, "type": 2,
                "group": None, "enabled": True, "index": 0, "port": port, "payload": payload}]})
    envelope = {
        "version": 10, "exportedFrom": "0.2.4", "minimumVersion": "0.2.4",
        "meta": {"name": "YapLoq speech and queue controls", "author": "YapLoq",
            "version": __version__, "autoRunAction": None, "minimumVersion": "0.2.4",
            "description": "Speech and queue actions for YapLoq. Attach your own triggers. Speak uses the selected alias, or random among Voices marked On. Item controls use ttsId. Importing can replace existing YapLoq actions with the same names."},
        "data": {"actions": actions, "queues": [{"id": queue_id, "name": "YapLoq commands", "blocking": False}],
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
    action['name'] = 'YapLoq - Viewer voice command' + suffix
    step = action['actions'][0]
    step['id'] = _id('subaction/Viewer voice command/' + platform)
    event_platform = platform or '%commandSource%'
    step['payload'] = ('YAPLOQVOICE\r\n' + event_platform + '\r\n%userId%\r\n%userName%\r\n%role%\r\n'
                       '%isSubscribed%\r\n%isVip%\r\n%isModerator%\r\n!voice %rawInput%')
    speech = json.loads(json.dumps(action))
    speech['id'] = _id('action/Viewer assigned speech/' + platform)
    speech['name'] = 'YapLoq - Speak using viewer assignment' + suffix
    speech['actions'][0]['id'] = _id('subaction/Viewer assigned speech/' + platform)
    speech['actions'][0]['payload'] = ('YAPLOQ2\r\n\r\n' + event_platform + '\r\n%userId%\r\n%userName%\r\n%role%\r\n'
                                     '%isSubscribed%\r\n%isVip%\r\n%isModerator%\r\n%rawInput%')
    chat = json.loads(json.dumps(speech))
    chat['id'] = _id('action/Viewer assigned chat/' + platform)
    chat['name'] = 'YapLoq - Chat using viewer assignment' + suffix
    chat['actions'][0]['id'] = _id('subaction/Viewer assigned chat/' + platform)
    chat['actions'][0]['payload'] = chat['actions'][0]['payload'].replace('%rawInput%', '%message%')
    envelope['data']['actions'] = [action, speech, chat]
    envelope['meta']['name'] = 'YapLoq viewer voice command'
    envelope['meta']['description'] = 'Attach a Command Triggered trigger for a Starts With !voice command to Viewer voice command. Attach your separate speech command (for example !say) to Speak using viewer assignment. For ordinary chat messages, attach Chat using viewer assignment instead; it sends message, not rawInput. Do not attach both speech actions to the same input. Enable viewer commands in YapLoq Assignments only if using !voice. Import does not create or run triggers. Use viewer result events in YapLoq Actions to run your own Streamer.Bot reply actions; ttsReply, ttsPlatform and ttsUserId are supplied.'
    binary = b'SBAE' + gzip.compress(json.dumps(envelope, ensure_ascii=False, separators=(',', ':')).encode('utf-8'), mtime=0)
    return base64.b64encode(binary).decode('ascii')
