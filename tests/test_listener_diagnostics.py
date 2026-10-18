import json
import socket
import threading
import time
from unittest.mock import Mock

import pytest

from voice_studio_speaker_bridge.events import EventBus
from voice_studio_speaker_bridge.server import BridgeServers
from voice_studio_speaker_bridge.settings import Settings
from voice_studio_speaker_bridge.engine import SpeechEngine
from voice_studio_speaker_bridge.protocol import SpeakerBotProtocol


def wait_for(predicate):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.01)
    raise AssertionError('Listener did not reach expected state')


@pytest.fixture
def listener(tmp_path):
    settings = Settings(tmp_path / 'settings.json')
    settings.enable_udp = True
    settings.udp_address = '127.0.0.1'
    settings.udp_port = 0
    protocol = Mock()
    server = BridgeServers(settings, protocol, EventBus())
    server.udp_thread = threading.Thread(target=server._run_udp, daemon=True)
    server.udp_thread.start()
    wait_for(lambda: server.udp_server is not None)
    try:
        yield server, protocol
    finally:
        server.stop()


def test_probe_checks_actual_listener_without_speech_or_request_counts(listener):
    server, protocol = listener
    assert server.integration_status()['state'] == 'listening'
    server.test_udp_listener()
    wait_for(lambda: server.integration_status()['test'] == 'passed')
    assert server.integration_status()['received'] == 0
    protocol.execute.assert_not_called()


def test_udp_burst_accounts_for_accepted_and_rejected_requests(listener):
    server, protocol = listener
    def execute(command, data):
        if data['message'].startswith('reject'):
            raise ValueError('Speech queue is full (50 items)')
        return {'speechId': data['message']}
    protocol.execute.side_effect = execute
    port = server.integration_status()['activePort']
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
        for index in range(60):
            message = ('reject' if index % 3 == 0 else 'accept') + str(index)
            client.sendto(('VSPEAK\nEventVoice\n' + message).encode(), ('127.0.0.1', port))
    wait_for(lambda: server.integration_status()['accepted'] + server.integration_status()['rejected'] == 60)
    status = server.integration_status()
    assert status['received'] == 60
    assert status['accepted'] == 40
    assert status['rejected'] == 20
    assert status['processing'] == 0
    assert status['lastRejection'] == 'Speech queue is full (50 items)'
    assert status['lastReceivedAt']
    assert protocol.execute.call_count == 60


def test_invalid_packets_are_counted_without_exposing_the_payload(listener):
    server, protocol = listener
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
        client.sendto(b'private malformed message', ('127.0.0.1', server.integration_status()['activePort']))
    wait_for(lambda: server.integration_status()['rejected'] == 1)
    assert 'private malformed' not in json.dumps(server.integration_status())
    protocol.execute.assert_not_called()


def test_bind_conflict_is_visible_and_does_not_claim_to_be_listening(listener):
    first, _ = listener
    settings = first.settings
    settings.udp_port = first.integration_status()['activePort']
    other = BridgeServers(settings, Mock(), EventBus())
    other._run_udp()
    status = other.integration_status()
    assert status['state'] == 'error'
    assert str(settings.udp_port) in status['listenerError']
    assert status['activePort'] is None
    with pytest.raises(ValueError, match='not running'):
        other.test_udp_listener()


def test_real_queue_burst_counts_admission_overflow_and_completion(listener):
    server, _ = listener
    settings = server.settings
    settings.max_queue = 12
    settings.history_limit = 100
    settings.save()
    engine = SpeechEngine(settings, server.events)
    engine._synthesize = lambda job: b'wav'
    engine.audio = Mock(warning='')
    engine.audio.decode_wav.return_value = (b'pcm', 10)
    engine.audio.play.return_value = True
    server.protocol = SpeakerBotProtocol(settings, engine)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
        for index in range(30):
            client.sendto(f'VSPEAK\nEventVoice\nburst {index}'.encode(), ('127.0.0.1', server.integration_status()['activePort']))
    wait_for(lambda: server.integration_status()['accepted'] + server.integration_status()['rejected'] == 30)
    status = server.integration_status()
    assert (status['received'], status['accepted'], status['rejected']) == (30, 12, 18)
    assert 'full' in status['lastRejection']
    engine.start()
    try:
        wait_for(lambda: len(engine.history) == 12)
        assert len({item['id'] for item in engine.history}) == 12
        assert all(item['status'] == 'Finished' for item in engine.history)
        assert engine.pending.empty()
    finally:
        engine.shutdown()
