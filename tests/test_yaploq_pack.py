import base64
import gzip
import json

import pytest

from voice_studio_speaker_bridge.streamerbot_export import export_complete_pack
from voice_studio_speaker_bridge.yaploq_payload import parse_payload, speech_payload, control_payload


def unpack(code):
    return json.loads(gzip.decompress(base64.b64decode(code)[4:]))


def fill(payload):
    values = dict(userType='twitch', commandSource='twitch', userId='123', userName='Viewer', broadcastUserId='123',
                  userGroups='Guests, VIP Club', isSubscribed='False', isVip='True', isModerator='True',
                  message='[Voice] First line\nSecond line', rawInput='Hello', ttsAlias='Voice', ttsId='item-123',
                  ttsProfile='Streaming', ttsSeconds='3', ylArgs='Voice')
    for key, value in values.items():
        payload = payload.replace('%' + key + '%', value)
    return payload


def test_complete_pack_one_tag_queue_names_ids_and_no_auto_run():
    pack = unpack(export_complete_pack(6670, 'twitch', ['Voice', 'Other'], ['Cast'], ['Streaming']))
    assert pack['meta']['autoRunAction'] is None
    assert pack['data']['queues'][0]['name'] == 'Yaploq'
    actions = pack['data']['actions']
    assert len(actions) >= 28
    assert len({action['id'] for action in actions}) == len(actions)
    assert len({action['name'] for action in actions}) == len(actions)
    for action in actions:
        assert action['name'].startswith('[YL] - ')
        assert action['queue'] == pack['data']['queues'][0]['id']
        assert all(trigger['type'] == 401 for trigger in action['triggers']) and not action['alwaysRun']
        for step in action['actions']:
            assert step['port'] == 6670 and step['payload'].startswith('YAPLOQ\r\ncommand:')
            assert all(tag not in step['payload'] for tag in ['YAPLOQ2', 'YAPLOQVOICE', 'VSPEAK', 'VCONTROL', 'YAPLOQMETA'])
            parse_payload(fill(step['payload']))
    assert pack == unpack(export_complete_pack(6670, 'twitch', ['Voice', 'Other'], ['Cast'], ['Streaming']))


def test_speech_metadata_and_multiline_text_stay_separate():
    request, data = parse_payload(fill(speech_payload()))
    assert request == 'Speak' and data['isBroadcaster'] and data['isVip'] and data['isModerator']
    assert data['groups'] == ['Guests', 'VIP Club']
    assert data['message'] == '[Voice] First line\nSecond line'
    assert data['voice'] == ''


@pytest.mark.parametrize('platform,user_id,owner,subscriber,sponsor,expected', [
    ('twitch', '123', '123', 'True', '%userIsSponsor%', True),
    ('YouTube', 'UC-channel', 'UC-owner', 'True', 'False', False),
    ('youtube', 'UC-channel', 'UC-owner', 'False', 'True', True),
    ('kick', '456', '456', 'True', '%userIsSponsor%', True)])
def test_one_payload_detects_each_event_platform(platform, user_id, owner, subscriber, sponsor, expected):
    payload = speech_payload().replace('%userType%', platform).replace('%userId%', user_id).replace('%broadcastUserId%', owner)
    payload = payload.replace('%userName%', 'Viewer').replace('%isSubscribed%', subscriber).replace('%userIsSponsor%', sponsor).replace('%message%', 'Hello')
    request, data = parse_payload(payload)
    assert request == 'Speak' and data['platform'] == platform.casefold()
    assert data['isSubscribed'] is expected
    assert data['isBroadcaster'] is (user_id == owner)
    assert data['groups'] == [] and not data['isVip'] and not data['isModerator']


def test_complete_pack_ignores_old_platform_selector_and_is_always_universal():
    assert export_complete_pack(6670, 'twitch') == export_complete_pack(6670, 'youtube') == export_complete_pack(6670)
    for action in unpack(export_complete_pack(6670))['data']['actions']:
        if 'command:speak\r\n' in action['actions'][0]['payload']:
            assert '%userType%' in action['actions'][0]['payload']
        assert not action['name'].endswith((' - Twitch', ' - Youtube', ' - Kick'))


@pytest.mark.parametrize('command,args,expected', [('pause', [], 'Pause'), ('moveup', ['123'], 'MoveSpeech'),
    ('reset', ['Viewer'], 'SetViewerVoice'), ('assign', ['Viewer', 'Voice'], 'SetViewerVoice'),
    ('skipresume', [], 'SkipAndResume'), ('clearresume', [], 'ClearAndResume')])
def test_controls(command, args, expected):
    assert parse_payload(control_payload(command, *args))[0] == expected


@pytest.mark.parametrize('payload', ['YAPLOQ\ncommand:unknown', 'YAPLOQ\ncommand:remove\n%ttsId%',
    'YAPLOQ\ncommand:speak', 'YAPLOQ\ncommand:pause\nunexpected', 'YAPLOQ\ncommand:assign\nViewer'])
def test_incomplete_or_unknown_commands_are_rejected(payload):
    with pytest.raises(ValueError):
        parse_payload(payload)


def test_essentials_is_smaller_and_does_not_include_destructive_admin_tools():
    pack = unpack(export_complete_pack(6670, preset='essentials'))
    assert not any('command:loadprofile' in action['actions'][0]['payload'] or 'command:clearhistory' in action['actions'][0]['payload'] for action in pack['data']['actions'])


def test_maintenance_pack_stays_in_data_and_includes_saved_enabled_choices(tmp_path):
    from voice_studio_speaker_bridge.settings import Settings
    from voice_studio_speaker_bridge.models import VoiceAlias
    from voice_studio_speaker_bridge.maintenance import Maintenance
    settings = Settings(tmp_path / 'settings.json')
    settings.aliases['Cast voice'] = VoiceAlias('Cast voice', group='Cartoons')
    settings.aliases['Disabled voice'] = VoiceAlias('Disabled voice', enabled=False)
    settings.voice_playlists = {'Cast': ['Cast voice']}
    settings.save()
    maintenance = Maintenance(settings)
    maintenance.save_profile('Streaming')
    path = maintenance.export_complete_streamerbot('twitch')
    from pathlib import Path
    assert Path(path).parent == tmp_path / 'exports'
    names = {action['name'] for action in unpack(Path(path).read_text())['data']['actions']}
    assert '[YL] - Speak - Cast voice' in names
    assert '[YL] - Speak - Disabled voice' not in names
    assert '[YL] - Speak voice group - Cartoons' in names
    assert '[YL] - Speak playlist - Cast' in names
    assert '[YL] - Load profile - Streaming' in names
