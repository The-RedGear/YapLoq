from threading import Event, Lock
from time import monotonic, sleep
from unittest.mock import Mock

import pytest

from voice_studio_speaker_bridge.engine import SpeechEngine
from voice_studio_speaker_bridge.events import EventBus
from voice_studio_speaker_bridge.settings import Settings


def wait_for(predicate, timeout=2):
    deadline = monotonic() + timeout
    while monotonic() < deadline:
        if predicate():
            return
        sleep(0.01)
    assert predicate()


@pytest.fixture
def engine(tmp_path):
    value = SpeechEngine(Settings(tmp_path / 'settings.json'), EventBus())
    value.audio = Mock(warning='', remaining_seconds=0.1, elapsed_seconds=0.0, duration_seconds=0.1, progress=0.0)
    value.audio.decode_wav.side_effect = lambda wav, *_a, **_k: (wav, 100)
    value.audio.play.return_value = True
    yield value
    value.shutdown()


def test_prepares_during_playback_without_reordering_or_regenerating(engine):
    playing, release = Event(), Event()
    synthesized, played = [], []
    def synth(job):
        synthesized.append(job.text)
        return job.text.encode()
    def play(pcm, **_kwargs):
        played.append(pcm.decode())
        if pcm == b'first':
            playing.set()
            release.wait(3)
        return True
    engine._synthesize = synth
    engine.audio.play.side_effect = play
    alias = engine.settings.aliases['EventVoice']
    jobs = [engine.enqueue(text, alias) for text in ('first', 'second', 'third')]
    engine.start()
    try:
        assert playing.wait(2)
        assert jobs[1].generation_done.wait(2)
        assert jobs[1].status == 'Ready'
        assert jobs[2].generation_done.wait(2)
        assert sorted(synthesized) == ['first', 'second', 'third']
        with engine.pending.mutex:
            assert list(engine.pending.queue) == jobs[1:]
        # A manual reorder is honored, even though the other entry is ready.
        assert engine.move(jobs[2].speech_id, -1)
        release.set()
        wait_for(lambda: len(engine.history) == 3)
        assert played == ['first', 'third', 'second']
        assert sorted(synthesized) == ['first', 'second', 'third']
    finally:
        release.set()


def test_remove_during_preparation_discards_result_and_continues(engine):
    playing, release_play, generating, release_generation = (Event() for _ in range(4))
    played = []
    def synth(job):
        if job.text == 'removed':
            generating.set()
            release_generation.wait(3)
        return job.text.encode()
    def play(pcm, **_kwargs):
        played.append(pcm.decode())
        if pcm == b'first':
            playing.set()
            release_play.wait(3)
        return True
    engine._synthesize = synth
    engine.audio.play.side_effect = play
    alias = engine.settings.aliases['EventVoice']
    engine.enqueue('first', alias)
    removed = engine.enqueue('removed', alias)
    engine.enqueue('last', alias)
    engine.start()
    try:
        assert playing.wait(2) and generating.wait(2)
        assert engine.remove(removed.speech_id)
        release_generation.set()
        release_play.set()
        wait_for(lambda: len(engine.history) == 2)
        assert played == ['first', 'last']
        assert removed.status == 'Removed'
    finally:
        release_generation.set()
        release_play.set()


def test_preparation_failure_does_not_stall_following_speech(engine):
    playing, release = Event(), Event()
    played = []
    def synth(job):
        if job.text == 'bad':
            raise RuntimeError('Provider unavailable')
        return job.text.encode()
    def play(pcm, **_kwargs):
        played.append(pcm.decode())
        if pcm == b'first':
            playing.set()
            release.wait(3)
        return True
    engine._synthesize = synth
    engine.audio.play.side_effect = play
    alias = engine.settings.aliases['EventVoice']
    engine.enqueue('first', alias)
    bad = engine.enqueue('bad', alias)
    engine.enqueue('last', alias)
    engine.start()
    try:
        assert playing.wait(2) and bad.generation_done.wait(2)
        assert bad.status == 'Error'
        release.set()
        wait_for(lambda: len(engine.history) == 2)
        assert played == ['first', 'last']
        assert bad.error == 'Provider unavailable'
    finally:
        release.set()


def test_pause_does_not_start_preparing_paid_requests(engine):
    alias = engine.settings.aliases['EventVoice']
    job = engine.enqueue('waiting', alias)
    engine._synthesize = Mock(return_value=b'audio')
    engine.pause()
    engine.start()
    sleep(0.15)
    engine._synthesize.assert_not_called()
    assert not job.generation_started


def test_generates_all_waiting_speech_while_first_is_still_generating(engine):
    first_started, release_first = Event(), Event()
    lock = Lock()
    active = 0
    peak = 0
    generated, played = [], []
    def synth(job):
        nonlocal active, peak
        with lock:
            active += 1
            peak = max(peak, active)
        try:
            if job.text == 'first':
                first_started.set()
                release_first.wait(4)
            generated.append(job.text)
            return job.text.encode()
        finally:
            with lock:
                active -= 1
    engine._synthesize = synth
    engine.audio.play.side_effect = lambda pcm, **kwargs: played.append(pcm.decode()) or True
    texts = ['first', 'second', 'third', 'fourth', 'fifth', 'sixth']
    jobs = [engine.enqueue(text, engine.settings.aliases['EventVoice']) for text in texts]
    engine.start()
    try:
        assert first_started.wait(2)
        assert jobs[-1].generation_done.wait(2)
        assert all(job.generation_done.is_set() for job in jobs[1:])
        assert not jobs[0].generation_done.is_set() and played == []
        assert peak == 2  # Full look-ahead without unbounded provider concurrency.
        release_first.set()
        wait_for(lambda: len(engine.history) == len(texts))
        assert played == texts
        assert sorted(generated) == sorted(texts)
    finally:
        release_first.set()
