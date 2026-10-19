import json
from pathlib import Path
import zipfile
from unittest.mock import patch

import pytest

from voice_studio_speaker_bridge.maintenance import Maintenance
from voice_studio_speaker_bridge.settings import Settings
from voice_studio_speaker_bridge.viewers import ViewerStore


@pytest.fixture
def maintenance(tmp_path):
    settings = Settings(tmp_path / 'settings.json')
    settings.save()
    viewers = ViewerStore(tmp_path / 'viewers.json')
    viewers.update(dict(platform='twitch', userId='123', voice='EventVoice'), assign=True)
    return Maintenance(settings, viewers)


def test_complete_backup_restores_settings_actions_and_viewers(maintenance):
    settings = maintenance.settings
    settings.viewer_commands_enabled = True
    settings.automations = [dict(id='one', name='Reply', enabled=True,
        triggers=[dict(source='viewer', event='voiceassigned')],
        steps=[dict(type='action', action='Reply', args={'message': '{ttsReply}'})], conditions=[], onError='stop')]
    settings.save()
    backup = Path(maintenance.backup())
    with zipfile.ZipFile(backup) as archive:
        assert set(archive.namelist()) == {'manifest.json', 'settings.json', 'viewers.json'}
    settings.max_queue = 99
    settings.automations = []
    settings.save()
    maintenance.viewers.update(dict(platform='twitch', userId='123', voice=''), assign=True)
    maintenance.viewers.update(dict(platform='kick', userId='new', voice='EventVoice'), assign=True)
    maintenance.restore(backup.name)
    assert settings.max_queue == 25
    assert settings.automations[0]['name'] == 'Reply' and settings.viewer_commands_enabled
    assert maintenance.viewers.get('twitch', '123')['voice'] == 'EventVoice'
    assert maintenance.viewers.get('kick', 'new') is None
    assert len(maintenance.backups()) == 2


def test_legacy_json_restores_settings_only(maintenance):
    backup = maintenance._folder('backups') / 'YapLoq-legacy.json'
    backup.write_bytes(maintenance.settings.path.read_bytes())
    maintenance.settings.max_queue = 99
    maintenance.settings.save()
    maintenance.viewers.update(dict(platform='kick', userId='keep', voice='EventVoice'), assign=True)
    maintenance.restore(backup.name)
    assert maintenance.settings.max_queue == 25
    assert maintenance.viewers.get('kick', 'keep')['voice'] == 'EventVoice'


@pytest.mark.parametrize('bad_name', ['../settings.json', 'extra.json', 'viewers.json'])
def test_invalid_archive_never_changes_live_files(maintenance, bad_name):
    backup = maintenance._folder('backups') / 'YapLoq-bad.zip'
    before = maintenance.settings.path.read_bytes(), maintenance.viewers.path.read_bytes()
    with zipfile.ZipFile(backup, 'w') as archive:
        archive.writestr('manifest.json', json.dumps(dict(format='yaploq-backup', version=1)))
        archive.writestr('settings.json', before[0])
        if bad_name != 'viewers.json':
            archive.writestr('viewers.json', before[1])
        archive.writestr(bad_name, '{broken')
    with pytest.raises(ValueError):
        maintenance.restore(backup.name)
    assert before == (maintenance.settings.path.read_bytes(), maintenance.viewers.path.read_bytes())
    assert maintenance.backups() == ['YapLoq-bad.zip']


def test_restore_can_recover_current_corrupt_viewer_file(maintenance):
    backup = Path(maintenance.backup())
    maintenance.viewers.path.write_text('{broken')
    maintenance.restore(backup.name)
    assert maintenance.viewers.get('twitch', '123')['voice'] == 'EventVoice'
    recovery = next(name for name in maintenance.backups() if name != backup.name)
    with zipfile.ZipFile(backup.parent / recovery) as archive:
        assert archive.read('viewers.json') == b'{broken'


def test_replace_failure_rolls_back_both_files(maintenance):
    backup = Path(maintenance.backup())
    maintenance.settings.max_queue = 77
    maintenance.settings.save()
    maintenance.viewers.update(dict(platform='twitch', userId='123', voice=''), assign=True)
    before = maintenance.settings.path.read_bytes(), maintenance.viewers.path.read_bytes()
    original = Path.replace
    failed = False
    def replace(path, target):
        nonlocal failed
        if path.name == 'viewers.restore.tmp' and not failed:
            failed = True
            raise OSError('simulated write failure')
        return original(path, target)
    with patch.object(Path, 'replace', replace), pytest.raises(OSError):
        maintenance.restore(backup.name)
    assert before == (maintenance.settings.path.read_bytes(), maintenance.viewers.path.read_bytes())


def test_empty_viewer_snapshot_clears_new_assignments(maintenance):
    maintenance.viewers.path.unlink()
    maintenance.viewers._cache = None
    backup = Path(maintenance.backup())
    maintenance.viewers.update(dict(platform='twitch', userId='new', voice='EventVoice'), assign=True)
    maintenance.restore(backup.name)
    assert maintenance.viewers.all() == []
