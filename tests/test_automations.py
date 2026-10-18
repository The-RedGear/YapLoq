from copy import deepcopy
import threading
import time
from unittest.mock import Mock, patch

import pytest

from voice_studio_speaker_bridge.automations import effective_rules, validate_rules, remote_actions
from voice_studio_speaker_bridge.events import EventBus
from voice_studio_speaker_bridge.settings import Settings
from voice_studio_speaker_bridge.streamerbot import StreamerBotActions


def rule(**overrides):
    result = dict(id='one', name='Talking', enabled=True, triggers=[dict(source='texttospeech', event='playing')],
                  conditions=[], steps=[dict(type='action', action='First', args={'message': '{ttsAlias}: {ttsText}'})], onError='stop')
    result.update(overrides)
    return validate_rules([result])[0]


@pytest.fixture
def runner(tmp_path):
    settings = Settings(tmp_path / 'settings.json')
    return StreamerBotActions(settings, EventBus())


def test_multiple_triggers_filters_and_saved_rule_order(runner):
    first = rule(conditions=[dict(field='alias', op='equals', value='Plankton')])
    second = rule(id='two', triggers=first['triggers'] + [dict(source='texttospeech', event='error')])
    runner.settings.automations = [first, second]
    runner._on_event('texttospeech', 'playing', dict(id='a', alias='Other'))
    assert runner.pending.get_nowait()[0]['id'] == 'two'
    assert runner.pending.empty()
    runner._on_event('texttospeech', 'playing', dict(id='b', alias='Plankton'))
    assert [runner.pending.get_nowait()[0]['id'] for _ in range(2)] == ['one', 'two']


def test_steps_dispatch_in_order_with_delay_and_template_arguments(runner):
    definition = rule(steps=[dict(type='action', action='First', args={'message': '{ttsAlias}: {ttsText}'}),
                            dict(type='delay', seconds=0.02), dict(type='action', action='Second')])
    calls = []
    runner._post_action = lambda action, arguments: calls.append((action, arguments, time.monotonic()))
    runner._run_steps(definition, runner._arguments('playing', dict(alias='Plankton', text='Hello')))
    assert [item[0] for item in calls] == ['First', 'Second']
    assert calls[0][1]['message'] == 'Plankton: Hello'
    assert calls[1][2] - calls[0][2] >= 0.015


def test_delay_is_cancelled_on_shutdown(runner):
    definition = rule(steps=[dict(type='delay', seconds=3600), dict(type='action', action='Never')])
    runner._post_action = Mock()
    thread = threading.Thread(target=runner._run_steps, args=(definition, {}))
    thread.start()
    runner.stop_event.set()
    thread.join(0.5)
    assert not thread.is_alive()
    runner._post_action.assert_not_called()


@pytest.mark.parametrize('behavior, expected', [('stop', ['First']), ('continue', ['First', 'Second'])])
def test_failures_follow_rule_policy(runner, behavior, expected):
    definition = rule(onError=behavior, steps=[dict(type='action', action='First'), dict(type='action', action='Second')])
    calls = []
    def post(action, _):
        calls.append(action)
        if action == 'First':
            raise OSError('offline')
    runner._post_action = post
    if behavior == 'stop':
        with pytest.raises(OSError):
            runner._run_steps(definition, {})
    else:
        runner._run_steps(definition, {})
    assert calls == expected
    assert runner.events.recent()[0]['event'] == 'failed'


def test_legacy_projection_does_not_mutate_and_migration_preserves_session_finish(runner):
    settings = runner.settings
    settings.streamerbot_actions_enabled = True
    settings.streamerbot_queued_action = 'Show avatar'
    settings.streamerbot_finished_action = 'Hide avatar'
    projected = effective_rules(settings)
    assert not settings.automations_migrated
    assert settings.automations == []
    settings.automations = validate_rules(projected)
    settings.automations_migrated = True
    settings.save()
    restored = Settings(settings.path)
    assert restored.automations == settings.automations
    runner._on_event('texttospeech', 'received', {'id': 'first'})
    runner._on_event('texttospeech', 'received', {'id': 'second'})
    runner._on_event('texttospeech', 'textqueued', {'id': 'first'})
    queued, _ = runner.pending.get_nowait()
    assert queued['rules'][0]['steps'][0]['action'] == 'Show avatar'
    runner._on_event('texttospeech', 'finished', {'id': 'first'})
    assert runner.pending.empty()
    runner._on_event('texttospeech', 'finished', {'id': 'second'})
    finished, _ = runner.pending.get_nowait()
    assert finished['rules'][0]['steps'][0]['action'] == 'Hide avatar'
    assert runner.pending.empty()


def test_duplicate_session_rules_keep_saved_order(runner):
    triggers = [dict(source='legacy', event='playing')]
    definitions = validate_rules([rule(triggers=triggers), rule(id='two', triggers=triggers)])
    runner.settings.automations = definitions
    runner.settings.automations_migrated = True
    assert [r['id'] for r in runner._configured_action('streamerbot_playing_action')['rules']] == ['one', 'two']


@pytest.mark.parametrize('seconds', [-1, float('nan'), float('inf'), 'bad'])
def test_invalid_delays_are_rejected(seconds):
    with pytest.raises(ValueError):
        rule(steps=[dict(type='delay', seconds=seconds)])


def test_recursive_failure_events_do_not_trigger_automations(runner):
    runner.settings.automations = [rule(triggers=[dict(source='texttospeech', event='error')])]
    runner._on_event('texttospeech', 'error', {'automationOrigin': True})
    assert runner.pending.empty()


def test_action_discovery_uses_saved_instance_address(runner):
    runner.settings.streamerbot_http_url = 'http://127.0.0.1:9999'
    with patch('voice_studio_speaker_bridge.automations.urlopen') as open_url:
        open_url.return_value.__enter__.return_value.read.return_value = b'{"actions":[{"id":"abc","name":"Hello"}]}'
        assert remote_actions(runner.settings) == [dict(id='abc', name='Hello')]
    assert open_url.call_args.args[0] == 'http://127.0.0.1:9999/GetActions'


def test_live_worker_executes_event_sequence_without_legacy_duplication(runner):
    runner.settings.automations = [rule(steps=[dict(type='action', action='First'),
                                             dict(type='delay', seconds=0.01),
                                             dict(type='action', action='Second')])]
    runner.settings.automations_migrated = True
    calls, done = [], threading.Event()
    def post(action, arguments):
        calls.append(action)
        if action == 'Second':
            done.set()
    runner._post_action = post
    runner.start()
    try:
        runner.events.emit('texttospeech', 'playing', {'id': 'speech', 'alias': 'Plankton'})
        assert done.wait(1)
        assert calls == ['First', 'Second']
    finally:
        runner.shutdown()
