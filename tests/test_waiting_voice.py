from unittest.mock import Mock

import pytest

from voice_studio_speaker_bridge.engine import SpeechEngine
from voice_studio_speaker_bridge.events import EventBus
from voice_studio_speaker_bridge.models import VoiceAlias
from voice_studio_speaker_bridge.protocol import SpeakerBotProtocol
from voice_studio_speaker_bridge.settings import Settings


@pytest.fixture
def engine(tmp_path):
    value = SpeechEngine(Settings(tmp_path / 'settings.json'), EventBus())
    value.settings.aliases['Other'] = VoiceAlias('Other', speed=1.2, color='#87C9AF')
    yield value
    value.shutdown()


def test_changes_one_waiting_entry_preserving_identity_order_and_saved_alias(engine):
    first = engine.enqueue('First', engine.settings.aliases['EventVoice'])
    job = engine.enqueue('Second', engine.settings.aliases['EventVoice'], user='viewer', platform='twitch', user_id='123')
    original = engine.settings.aliases['Other'].to_dict()
    timestamp, age = job.timestamp, job.enqueued_at
    result = SpeakerBotProtocol(engine.settings, engine).execute('ChangeSpeechVoice', dict(speechId=job.speech_id, voice='Other'))
    assert result['id'] == job.speech_id and result['alias'] == 'Other'
    assert list(engine.pending.queue) == [first, job]
    assert job.text == 'Second' and job.timestamp == timestamp and job.enqueued_at == age
    assert job.user_id == '123' and job.alias.speed == 1.2
    assert job.alias is not engine.settings.aliases['Other']
    assert engine.settings.aliases['Other'].to_dict() == original
    assert engine.events.recent()[0]['event'] == 'voicechanged'
    assert engine.events.recent()[0]['data']['previousAlias'] == 'EventVoice'


@pytest.mark.parametrize('status', ['Generating', 'Ready', 'Playing', 'Error', 'Cancelled'])
def test_cannot_change_started_or_terminal_jobs(engine, status):
    job = engine.enqueue('First', engine.settings.aliases['EventVoice'])
    job.status = status
    with pytest.raises(ValueError):
        engine.change_waiting_voice(job.speech_id, 'Other')
    assert job.alias.name == 'EventVoice'


def test_generation_claim_current_and_replay_are_protected(engine):
    job = engine.enqueue('First', engine.settings.aliases['EventVoice'])
    job.generation_started = True
    with pytest.raises(ValueError):
        engine.change_waiting_voice(job.speech_id, 'Other')
    job.generation_started = False
    job.replay_recording = True
    with pytest.raises(ValueError):
        engine.change_waiting_voice(job.speech_id, 'Other')
    engine.pending.get_nowait()
    engine._current = job
    with pytest.raises(ValueError, match='no longer waiting'):
        engine.change_waiting_voice(job.speech_id, 'Other')
    engine._current = None


def test_missing_disabled_or_incompatible_alias_is_rejected(engine):
    job = engine.enqueue('First', engine.settings.aliases['EventVoice'])
    with pytest.raises(ValueError, match='enabled'):
        engine.change_waiting_voice(job.speech_id, 'Missing')
    engine.settings.aliases['Other'].enabled = False
    with pytest.raises(ValueError, match='enabled'):
        engine.change_waiting_voice(job.speech_id, 'Other')
    engine.settings.aliases['Other'].enabled = True
    engine.settings.aliases['Other'].ssml = True
    with pytest.raises(ValueError, match='mode'):
        engine.change_waiting_voice(job.speech_id, 'Other')
    assert job.alias.name == 'EventVoice'


def test_change_is_persisted_without_cooldown_or_new_admission(engine):
    job = engine.enqueue('First', engine.settings.aliases['EventVoice'])
    before = engine._last_global_request
    engine.change_waiting_voice(job.speech_id, 'Other')
    assert engine._last_global_request == before
    assert engine.pending.qsize() == 1
    received = [item for item in engine.events.recent() if item['event'] == 'received']
    assert len(received) == 1
    engine._save_queue = Mock(wraps=engine._save_queue)
    engine.change_waiting_voice(job.speech_id, 'EventVoice')
    engine._save_queue.assert_called_once()
