import base64
import gzip
import json
from pathlib import Path

import pytest

from voice_studio_speaker_bridge.streamerbot_export import export_complete_pack, export_selected_voices
from voice_studio_speaker_bridge.settings import Settings
from voice_studio_speaker_bridge.models import VoiceAlias
from voice_studio_speaker_bridge.maintenance import Maintenance


def unpack(code):
    return json.loads(gzip.decompress(base64.b64decode(code)[4:]))


def test_expansion_contains_only_selected_voices_with_same_ids_category_and_queue():
    full = unpack(export_complete_pack(6670, aliases=['Old', 'New one', 'New two']))
    selected = unpack(export_selected_voices(6670, ['New two', 'New one', 'New one']))
    actions = selected['data']['actions']
    assert len(actions) == 2
    by_name = {action['name']: action for action in full['data']['actions']}
    for action in actions:
        assert action == by_name[action['name']]
        assert action['group'] == 'YapLoq / Voices'
        assert not action['triggers'] and not action['alwaysRun']
        assert '%userType%' in action['actions'][0]['payload']
    assert selected['data']['queues'] == full['data']['queues']
    assert selected['meta']['autoRunAction'] is None
    assert selected['data']['commands'] == []
    assert not any(action['name'] == '[YL] - Speak - Old' for action in actions)
    assert selected == unpack(export_selected_voices(6670, ['New one', 'New two']))


@pytest.mark.parametrize('names', [None, [], 'Voice', [''], [1], ['One\nTwo']])
def test_invalid_selection_rejected(names):
    with pytest.raises(ValueError):
        export_selected_voices(6670, names)


def test_export_preserves_settings_and_handles_single_disabled_and_unknown_voice(tmp_path):
    settings = Settings(tmp_path / 'settings.json')
    settings.aliases['New'] = VoiceAlias('New', enabled=False)
    settings.save()
    before = settings.path.read_bytes()
    maintenance = Maintenance(settings)
    path = Path(maintenance.export_streamerbot_voices(['New']))
    assert path.parent == tmp_path / 'exports'
    assert len(unpack(path.read_text())['data']['actions']) == 1
    assert settings.path.read_bytes() == before
    with pytest.raises(ValueError):
        maintenance.export_streamerbot_voices(['Missing'])
    assert settings.path.read_bytes() == before
