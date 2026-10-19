import base64
import gzip
import json
import re

from voice_studio_speaker_bridge.streamerbot_export import export_complete_pack, export_selected_voices
from voice_studio_speaker_bridge.streamerbot_commands import CHAT_SOURCES


def unpack(code):
    return json.loads(gzip.decompress(base64.b64decode(code)[4:]))


def match(command, text):
    return any(text.casefold() == token.casefold() or
               (command['location'] == 0 and text.casefold().startswith(token.casefold() + ' '))
               for token in command['command'].splitlines())


def test_native_commands_have_matching_action_triggers_and_explicit_permissions():
    pack = unpack(export_complete_pack(6670, aliases=['Plankton'], playlists=['Cast']))
    commands = pack['data']['commands']
    assert len(commands) >= 13
    references = {trigger['commandId'] for action in pack['data']['actions'] for trigger in action['triggers']}
    assert references == {command['id'] for command in commands}
    for command in commands:
        assert command['grantType'] == 0 and command['permittedGroups']
        assert command['sources'] == CHAT_SOURCES == 2098177
        assert command['ignoreBotAccount'] and command['ignoreInternal']
        assert command['mode'] == 0 and not command['regexExplicitCapture']
        assert all(token.startswith('!') for token in command['command'].splitlines())
        if match(command, '!voice Plankton'):
            assert set(command['permittedGroups']) == {'VIPs', 'Moderators'}
        else:
            assert command['permittedGroups'] == ['Moderators']
    assert sum(bool(match(command, '!ylskip')) for command in commands) == 1
    assert sum(bool(match(command, '!ylplay')) for command in commands) == 1
    assert sum(bool(match(command, '!voice Plankton')) for command in commands) == 1
    assert not any(match(command, '!ylskipanything') or match(command, '!voices') for command in commands)
    say = next(command for command in commands if match(command, '!ylsay hello world'))
    assert say['command'] == '!ylsay' and say['location'] == 0
    action = next(a for a in pack['data']['actions'] if any(t['commandId'] == say['id'] for t in a['triggers']))
    assert action['actions'][0]['payload'].endswith('%rawInput%')
    assert pack['meta']['autoRunAction'] is None


def test_selected_voice_commands_match_full_pack_and_avoid_slug_collisions():
    universe = ['Master Chief', 'Master-Chief', 'Plankton']
    full = unpack(export_complete_pack(6670, aliases=universe))
    selected = unpack(export_selected_voices(6670, ['Master Chief'], universe))
    commands = full['data']['commands']
    assert selected['data']['commands'] == []
    voice_commands = [command for command in commands if command['group'] == 'YapLoq / Voices']
    assert voice_commands == []
    actions = [a for a in full['data']['actions'] if a['group'] == 'YapLoq / Voices']
    assert len(actions) == 3 and all(not a['triggers'] for a in actions)
    assert selected['data']['actions'][0] in actions
