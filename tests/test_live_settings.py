import json
import os
from concurrent.futures import ThreadPoolExecutor

import pytest

from voice_studio_speaker_bridge.settings import Settings
from voice_studio_speaker_bridge.protocol import SpeakerBotProtocol
from voice_studio_speaker_bridge.models import VoiceAlias
from unittest.mock import Mock


def test_runtime_settings_apply_reset_and_save_without_disk_leaks(tmp_path):
    settings = Settings(tmp_path / 'settings.json')
    settings.save()
    original = settings.path.read_bytes()
    draft = json.loads(original)
    draft.update(split_speech_sentences=True, max_queue=17, udp_port=12345)
    result = settings.apply_runtime(draft)
    assert settings.split_speech_sentences and settings.max_queue == 17
    assert settings.udp_port != 12345 and 'udp_port' in result['restartRequired']
    assert settings.path.read_bytes() == original
    assert Settings(settings.path).split_speech_sentences is False
    settings.aliases['New'] = VoiceAlias('New')
    settings.save()  # A confirmed record operation must not save the settings draft.
    persisted = Settings(settings.path)
    assert 'New' in persisted.aliases and persisted.split_speech_sentences is False
    assert settings.split_speech_sentences is True
    settings.apply_runtime(None)
    assert settings.split_speech_sentences is False and settings.max_queue == persisted.max_queue


def test_invalid_draft_retains_last_valid_active_values(tmp_path):
    settings = Settings(tmp_path / 'settings.json')
    settings.apply_runtime({'max_queue': 19})
    with pytest.raises(ValueError, match='Invalid live settings'):
        settings.apply_runtime({'max_queue': 'invalid'})
    assert settings.max_queue == 19 and not settings.path.exists()


def test_destructive_retention_changes_wait_for_save(tmp_path):
    settings = Settings(tmp_path / 'settings.json')
    original = settings.history_limit
    result = settings.apply_runtime({'history_limit': 1})
    assert settings.history_limit == original and result['saveRequired'] == ['history_limit']


def test_saved_file_changes_preserve_unsaved_overlay_until_reset(tmp_path):
    settings = Settings(tmp_path / 'settings.json')
    settings.save()
    settings.apply_runtime({'max_queue': 19})
    saved = Settings(settings.path)
    saved.split_speech_sentences = True
    saved.save()
    settings.reload_if_changed()
    assert settings.max_queue == 19 and settings.split_speech_sentences
    settings.apply_runtime(None)
    assert settings.max_queue == saved.max_queue


@pytest.mark.parametrize('atomic', [True, False])
def test_same_timestamp_save_is_detected_without_losing_live_draft(tmp_path, atomic):
    settings = Settings(tmp_path / 'settings.json')
    settings.assignment_default_voice = 'Voice A'
    settings.save()
    settings.apply_runtime({'max_queue': 19})
    before = settings.path.stat()
    contents = settings.path.read_text(encoding='utf-8').replace('Voice A', 'Voice B')
    if atomic:
        replacement = settings.path.with_suffix('.replacement')
        replacement.write_text(contents, encoding='utf-8')
        os.utime(replacement, ns=(before.st_atime_ns, before.st_mtime_ns))
        replacement.replace(settings.path)
    else:
        # Also cover in-place writes with unchanged timestamps but different sizes.
        settings.path.write_text(contents + ' ', encoding='utf-8')
        os.utime(settings.path, ns=(before.st_atime_ns, before.st_mtime_ns))
    assert settings.path.stat().st_mtime_ns == before.st_mtime_ns
    assert settings.reload_if_changed()
    assert settings.assignment_default_voice == 'Voice B'
    assert settings.max_queue == 19
    assert not settings.reload_if_changed()
    settings.apply_runtime(None)
    assert settings.max_queue == Settings(settings.path).max_queue


def test_live_sentence_setting_affects_future_requests_without_save(tmp_path):
    from voice_studio_speaker_bridge.engine import SpeechEngine
    from voice_studio_speaker_bridge.events import EventBus
    settings = Settings(tmp_path / 'settings.json')
    engine = SpeechEngine(settings, EventBus())
    try:
        protocol = SpeakerBotProtocol(settings, engine)
        settings.apply_runtime({'split_speech_sentences': True})
        result = protocol.execute('Speak', {'message': 'First sentence. Second sentence.'})
        assert len(result['speechIds']) == 2
        assert not settings.path.exists()
    finally:
        engine.shutdown()


def test_thread_local_save_does_not_hide_live_values_from_other_threads(tmp_path):
    settings = Settings(tmp_path / 'settings.json')
    settings.apply_runtime({'max_queue': 19})
    with ThreadPoolExecutor(max_workers=2) as pool:
        assert list(pool.map(lambda _: settings.max_queue, range(30))) == [19] * 30
