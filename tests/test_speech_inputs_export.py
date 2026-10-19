import base64
import gzip
import json

from voice_studio_speaker_bridge.streamerbot_export import export_complete_pack, export_speech_inputs


def unpack(code):
    return json.loads(gzip.decompress(base64.b64decode(code)[4:]))


def test_three_speech_inputs_are_additive_and_send_only_one_text_field():
    pack = unpack(export_speech_inputs(6670))
    full = unpack(export_complete_pack(6670))
    actions = pack['data']['actions']
    assert len(actions) == 3
    assert pack['data']['commands'] == []
    assert pack['meta']['autoRunAction'] is None
    assert pack['data']['queues'] == full['data']['queues']
    full_actions = {a['id']: a for a in full['data']['actions']}
    for action in actions:
        assert not action['triggers']
        assert action['actions'] == full_actions[action['id']]['actions']
        payload = action['actions'][0]['payload']
        assert payload.count('%rawInput%') + payload.count('%message%') == 1
        expected = '%message%' if action['name'].endswith('Chat message') else '%rawInput%'
        assert payload.endswith(expected)
        assert action['actions'][0]['port'] == 6670
