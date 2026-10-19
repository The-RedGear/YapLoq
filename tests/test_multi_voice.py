from concurrent.futures import ThreadPoolExecutor
from unittest.mock import Mock

import pytest

from voice_studio_speaker_bridge.engine import SpeechEngine
from voice_studio_speaker_bridge.events import EventBus
from voice_studio_speaker_bridge.models import VoiceAlias
from voice_studio_speaker_bridge.protocol import SpeakerBotProtocol
from voice_studio_speaker_bridge.settings import Settings
from voice_studio_speaker_bridge.multi_voice import split_voices


@pytest.fixture
def engine(tmp_path):
    value = SpeechEngine(Settings(tmp_path / 'settings.json'), EventBus())
    value.settings.aliases['Other'] = VoiceAlias('Other', public=True, public_name='Public Other')
    value.settings.aliases['EventVoice'].public = True
    yield value
    value.shutdown()


def speak(engine, text, **kw):
    return SpeakerBotProtocol(engine.settings, engine).execute('Speak', dict(message=text, source='Manual', **kw))


def queued(engine):
    return [(job.text, job.alias.name) for job in engine.pending.queue]


@pytest.mark.parametrize('message,split,count', [
    ('Hello', False, 1),
    ('[Other] Hello [EventVoice] Goodbye', False, 2),
    ('First sentence. Second sentence.', True, 2),
    ('[Other] First sentence. Second sentence. [EventVoice] Goodbye.', True, 3),
])
def test_queue_added_fires_once_per_input_in_empty_and_active_queue(engine, message, split, count):
    engine.settings.split_speech_sentences = split
    events = []
    engine.events.subscribe(lambda source, event, data: events.append((event, data)))
    for request_index in range(2):
        before = len([e for e in events if e[0] == 'queueadded'])
        result = speak(engine, message)
        added = [data for event, data in events if event == 'queueadded']
        assert len(added) == before + 1
        assert len(result['speechIds']) == count
        assert added[-1]['id'] == result['speechIds'][0]
        if count > 1:
            assert added[-1]['speechIds'] == result['speechIds']
            assert added[-1]['segmentCount'] == count
        extended = [data for event, data in events if event == 'queueextended']
        assert len(extended) == request_index
        if request_index:
            assert extended[-1]['id'] == result['speechIds'][0]
    assert len([event for event, _ in events if event == 'received']) == 2 * count


def test_active_queue_addition_fires_while_playing_but_not_for_next_new_queue(engine):
    events = []
    engine.events.subscribe(lambda source, event, data: events.append(event))
    speak(engine, 'First')
    current = engine.pending.get_nowait()
    current.status = 'Playing'
    engine._current = current
    speak(engine, '[Other] second [EventVoice] third')
    assert events.count('queueextended') == 1
    while not engine.pending.empty():
        engine.pending.get_nowait()
    engine._current = None
    speak(engine, 'New queue')
    assert events.count('queueextended') == 1
    assert events.count('queueadded') == 3


@pytest.mark.parametrize('text,expected', [
    ('!say [Other] Hello there', [('Hello there', 'Other')]),
    ('@viewer [Other] Hello there', [('Hello there', 'Other')]),
    ('!say @viewer [Other] Hello [EventVoice] @someone [Other] Goodbye',
     [('Hello', 'Other'), ('Goodbye', 'Other')]),
    ('!say Hello @viewer keep reading', [('Hello keep reading', 'EventVoice')]),
])
def test_chat_cleanup_preserves_remaining_speech_before_voice_splitting(engine, text, expected):
    engine.settings.ignore_command_messages = True
    engine.settings.ignore_mention_messages = True
    speak(engine, text)
    assert queued(engine) == expected


def test_chat_cleanup_rejects_only_when_no_speech_remains(engine):
    engine.settings.ignore_command_messages = True
    engine.settings.ignore_mention_messages = True
    with pytest.raises(ValueError, match='empty'):
        speak(engine, '!say @viewer')
    assert queued(engine) == []


def test_segments_prefix_repeats_and_metadata(engine):
    result = speak(engine, 'Intro [Other] Hi [EventVoice] Hello [Other] Again', user='Viewer')
    assert queued(engine) == [('Intro', 'EventVoice'), ('Hi', 'Other'), ('Hello', 'EventVoice'), ('Again', 'Other')]
    assert len(result['speechIds']) == 4 and result['speechId'] == result['speechIds'][0]
    assert [item['voiceName'] for item in result['segments']] == ['EventVoice', 'Other', 'EventVoice', 'Other']
    assert all(job.user == 'Viewer' for job in engine.pending.queue)


def test_invalid_later_tag_or_blocked_segment_publishes_nothing(engine):
    with pytest.raises(ValueError, match='full alias name'):
        speak(engine, '[Other] valid [Missing] invalid')
    assert queued(engine) == [] and engine.events.recent() == []
    engine.settings.max_characters = 12
    with pytest.raises(ValueError, match='character'):
        speak(engine, '[Other] abcdefgh [EventVoice] ijklmnop')
    assert queued(engine) == [] and engine.events.recent() == []


def test_batch_capacity_and_user_limit_are_atomic(engine):
    engine.settings.max_queue = 1
    with pytest.raises(ValueError, match='fit all'):
        speak(engine, '[Other] one [EventVoice] two')
    assert queued(engine) == []
    engine.settings.max_queue = 20
    engine.settings.per_user_queue_limit = 1
    with pytest.raises(ValueError, match='queue limit'):
        speak(engine, '[Other] one [EventVoice] two', user='viewer')
    assert queued(engine) == []


def test_one_input_consumes_cooldown_once_and_failed_input_does_not(engine):
    engine.settings.global_cooldown = 10
    engine.settings.per_user_cooldown = 10
    engine.settings.max_characters = 10
    with pytest.raises(ValueError):
        speak(engine, '[Other] 123456 [EventVoice] 789012', user='viewer')
    engine.settings.max_characters = 100
    speak(engine, '[Other] one [EventVoice] two', user='viewer')
    assert len(queued(engine)) == 2
    with pytest.raises(ValueError, match='cooldown'):
        speak(engine, 'Next', user='viewer')


def test_viewer_tags_use_public_names_and_permissions(engine):
    engine.settings.chat_voice_tags_all_enabled = False
    protocol = SpeakerBotProtocol(engine.settings, engine)
    data = dict(platform='twitch', userId='123', message='[Public Other] Hello [EventVoice] Hi')
    protocol.execute('Speak', data)
    assert queued(engine) == [('Hello', 'Other'), ('Hi', 'EventVoice')]
    assert all(job.user_id == '123' for job in engine.pending.queue)
    engine.settings.aliases['Other'].viewer_access = 'moderators'
    with pytest.raises(ValueError, match='unavailable'):
        protocol.execute('Speak', data)
    assert len(queued(engine)) == 2


def test_legacy_streamerbot_owner_action_can_tag_private_aliases(engine):
    engine.settings.chat_voice_tags_all_enabled = False
    engine.settings.aliases['Other'].public = False
    engine.settings.aliases['EventVoice'].public = False
    protocol = SpeakerBotProtocol(engine.settings, engine)
    protocol.execute('Speak', dict(voice='random', source='Streamer.bot', user='Owner',
                                  message='[Other] first [EventVoice] second'))
    assert queued(engine) == [('first', 'Other'), ('second', 'EventVoice')]
    with pytest.raises(ValueError, match='unavailable'):
        protocol.execute('Speak', dict(platform='twitch', userId='123', message='[Other] not allowed'))


def test_identified_chat_can_split_private_enabled_voices_without_creating_assignment(engine):
    engine.settings.aliases['Other'].public = False
    engine.settings.aliases['EventVoice'].public = False
    speak(engine, '[Other] first [EventVoice] second', platform='twitch', userId='123')
    assert queued(engine) == [('first', 'Other'), ('second', 'EventVoice')]
    assert SpeakerBotProtocol(engine.settings, engine).execute('GetViewers', {})['viewers'] == []
    engine.settings.aliases['Other'].enabled = False
    with pytest.raises(ValueError, match='unavailable'):
        speak(engine, '[Other] first [EventVoice] second', platform='twitch', userId='123')
    assert len(queued(engine)) == 2


def test_chat_tag_access_setting_survives_save_reload(engine):
    engine.settings.chat_voice_tags_all_enabled = False
    engine.settings.save()
    assert Settings(engine.settings.path).chat_voice_tags_all_enabled is False
    engine.settings.chat_voice_tags_all_enabled = True
    engine.settings.save()
    assert Settings(engine.settings.path).chat_voice_tags_all_enabled is True


def test_private_chat_tags_ignore_case_and_punctuation_with_unique_word_prefixes(engine):
    engine.settings.aliases['Sgt. Johnson'] = VoiceAlias('Sgt. Johnson')
    engine.settings.aliases['Spongebob Squarepants'] = VoiceAlias('Spongebob Squarepants')
    speak(engine, '[sgt johnson] One [SPONGEBOB] Two', platform='twitch', userId='123')
    assert queued(engine) == [('One', 'Sgt. Johnson'), ('Two', 'Spongebob Squarepants')]


def test_optional_sentence_clips_preserve_voices_order_and_abbreviations(engine):
    text = '[Other] Dr. Smith is here. Hello! [EventVoice] Last sentence.'
    speak(engine, text)
    assert len(queued(engine)) == 2
    engine.settings.split_speech_sentences = True
    speak(engine, text)
    assert queued(engine)[2:] == [('Dr. Smith is here.', 'Other'), ('Hello!', 'Other'), ('Last sentence.', 'EventVoice')]
    engine.settings.save()
    assert Settings(engine.settings.path).split_speech_sentences is True


def test_sentence_clip_limit_rejects_whole_input(engine):
    engine.settings.split_speech_sentences = True
    with pytest.raises(ValueError, match='50 clips'):
        speak(engine, 'Hello. ' * 51)
    assert queued(engine) == []


def test_short_unique_alias_and_segment_sort_metadata(engine):
    engine.settings.aliases['Spongebob Squarepants'] = VoiceAlias('Spongebob Squarepants')
    speak(engine, '[Other] first [Spongebob] second')
    jobs = list(engine.pending.queue)
    assert jobs[1].alias.name == 'Spongebob Squarepants'
    assert jobs[0].timestamp <= jobs[1].timestamp
    assert [engine._job_dict(job)['segmentIndex'] for job in jobs] == [0, 1]
    engine.settings.aliases['Spongebob Another'] = VoiceAlias('Spongebob Another')
    with pytest.raises(ValueError, match='full alias name'):
        speak(engine, '[Spongebob] ambiguous')


@pytest.mark.parametrize('packet', [
    b'YAPLOQ\nrandom\n[Other] first [Spongebob] second\nOwner\nowner',
    b'YAPLOQ2\n\ntwitch\n123\nViewer\nviewer\nFalse\nFalse\nFalse\n[Other] first [Spongebob] second',
])
def test_real_udp_packet_splits_into_separate_queue_voices(engine, packet):
    import socket
    import threading
    from time import monotonic, sleep
    from voice_studio_speaker_bridge.server import BridgeServers
    engine.settings.aliases['Spongebob Squarepants'] = VoiceAlias('Spongebob Squarepants')
    engine.settings.udp_port = 0
    server = BridgeServers(engine.settings, SpeakerBotProtocol(engine.settings, engine), engine.events)
    server.udp_thread = threading.Thread(target=server._run_udp, daemon=True)
    server.udp_thread.start()
    try:
        deadline = monotonic() + 2
        while server.udp_server is None and monotonic() < deadline:
            sleep(0.01)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
            client.sendto(packet,
                          ('127.0.0.1', server.udp_server.server_address[1]))
        deadline = monotonic() + 2
        while len(queued(engine)) < 2 and monotonic() < deadline:
            sleep(0.01)
        assert queued(engine) == [('first', 'Other'), ('second', 'Spongebob Squarepants')]
    finally:
        server.stop()


def test_concurrent_inputs_do_not_interleave_segments(engine):
    def submit(i):
        speak(engine, f'[Other] {i}a [EventVoice] {i}b')
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(submit, range(4)))
    texts = [text for text, _ in queued(engine)]
    for i in range(4):
        assert texts.index(f'{i}b') == texts.index(f'{i}a') + 1


def test_escaped_brackets_empty_tags_and_ssml(engine):
    assert split_voices(r'Literal \[Other]', 'default', Mock()) == [('Literal [Other]', 'default')]
    with pytest.raises(ValueError, match='text after'):
        speak(engine, '[Other]')
    engine.settings.aliases['Other'].ssml = True
    with pytest.raises(ValueError, match='SSML'):
        speak(engine, '[Other] hello [EventVoice] hi')
    assert queued(engine) == []


def test_generate_ahead_preserves_segment_playback_order(engine):
    from threading import Event
    from time import monotonic, sleep
    playing, release, prepared = Event(), Event(), Event()
    played = []
    engine.audio = Mock(warning='', remaining_seconds=0.1, elapsed_seconds=0.0, duration_seconds=0.1, progress=0.0)
    engine.audio.decode_wav.side_effect = lambda wav, *_a, **_k: (wav, 100)
    def synth(job):
        if job.text == 'second':
            prepared.set()
        return job.text.encode()
    def play(pcm, **_kw):
        played.append(pcm.decode())
        if pcm == b'first':
            playing.set()
            release.wait(3)
        return True
    engine._synthesize = synth
    engine.audio.play.side_effect = play
    speak(engine, '[Other] first [EventVoice] second [Other] third')
    engine.start()
    try:
        assert playing.wait(2) and prepared.wait(2)
        assert played == ['first']
    finally:
        release.set()
    deadline = monotonic() + 3
    while len(played) < 3 and monotonic() < deadline:
        sleep(0.01)
    assert played == ['first', 'second', 'third']
