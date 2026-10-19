from unittest.mock import Mock

import pytest

from voice_studio_speaker_bridge.models import VoiceAlias, SpeechJob
from voice_studio_speaker_bridge.protocol import SpeakerBotProtocol
from voice_studio_speaker_bridge.public_voices import eligible_voices
from voice_studio_speaker_bridge.settings import Settings
from voice_studio_speaker_bridge.events import EventBus


@pytest.fixture
def protocol(tmp_path):
    settings = Settings(tmp_path / 'settings.json')
    settings.viewer_commands_enabled = True
    settings.aliases['Internal'] = VoiceAlias('Internal', public=True, public_name='Friendly voice')
    settings.aliases['Mods'] = VoiceAlias('Mods', public=True, viewer_access='moderators')
    engine = Mock()
    engine.events = EventBus()
    engine.enqueue.side_effect = lambda text, alias, **kw: SpeechJob(text, alias)
    return SpeakerBotProtocol(settings, engine)


def command(protocol, text, **metadata):
    return protocol.execute('ViewerVoiceCommand', dict(platform='twitch', userId='123', message=text, **metadata))


def test_private_by_default_and_opt_in(protocol):
    assert not VoiceAlias('Private').public
    protocol.settings.viewer_commands_enabled = False
    with pytest.raises(ValueError, match='disabled'):
        command(protocol, '!voice Friendly voice')
    assert not protocol.viewers.path.exists()


def test_public_name_selection_and_reset(protocol):
    assert command(protocol, '!voice')['voices'] == ['Friendly voice']
    with pytest.raises(ValueError, match='unavailable'):
        command(protocol, '!voice Internal')
    command(protocol, '!voice FRIENDLY VOICE')
    assert protocol.viewers.get('twitch', '123')['voice'] == 'Internal'
    protocol.execute('Speak', dict(platform='twitch', userId='123', message='Hello'))
    assert protocol.engine.enqueue.call_args.args[1].name == 'Internal'
    command(protocol, '!voice reset')
    assert protocol.viewers.get('twitch', '123')['voice'] == ''


@pytest.mark.parametrize('metadata,allowed', [({}, False), ({'isModerator': 'true'}, False),
    ({'role': 2}, False), ({'role': 'moderator'}, True), ({'isModerator': True}, True),
    ({'role': 'broadcaster'}, True), ({'isSubscribed': True}, False)])
def test_access_uses_trusted_typed_metadata(protocol, metadata, allowed):
    assert ('Mods' in [v.name for v in eligible_voices(protocol.settings, metadata)]) is allowed


def test_random_is_persisted_without_generating_audio(protocol):
    command(protocol, '!voice random')
    assert protocol.viewers.get('twitch', '123')['voice'] == 'Internal'
    protocol.engine.enqueue.assert_not_called()
    assert command(protocol, '!other')['handled'] is False


def test_permission_revocation_falls_back_but_admin_private_voice_works(protocol):
    command(protocol, '!voice Friendly voice')
    protocol.settings.aliases['Internal'].public = False
    protocol.execute('Speak', dict(platform='twitch', userId='123', message='Hello'))
    assert protocol.engine.enqueue.call_args.args[1].name == 'EventVoice'
    protocol.execute('SetViewerVoice', dict(platform='twitch', userId='123', voice='Internal'))
    protocol.execute('Speak', dict(platform='twitch', userId='123', message='Hello'))
    assert protocol.engine.enqueue.call_args.args[1].name == 'Internal'


def test_identity_and_selectors_cannot_bypass_public_access(protocol):
    with pytest.raises(ValueError):
        protocol.execute('ViewerVoiceCommand', dict(message='!voice random'))
    for name in ['Mods', 'group:everyone', 'playlist:Pool', 'EventVoice']:
        with pytest.raises(ValueError, match='unavailable'):
            command(protocol, '!voice ' + name)


def test_duplicate_labels_fail_closed_and_fields_round_trip(protocol):
    alias = protocol.settings.aliases['Internal']
    assert VoiceAlias.from_dict(alias.name, alias.to_dict()).public_name == 'Friendly voice'
    protocol.settings.aliases['Duplicate'] = VoiceAlias('Duplicate', public=True, public_name='friendly voice')
    assert command(protocol, '!voice')['voices'] == []


def test_result_events_are_correlated_and_persist_before_success(protocol):
    observed = []
    protocol.engine.events.subscribe(lambda source, event, data: observed.append((source, event, data)))
    result = command(protocol, '!voice Friendly voice', user='Viewer')
    assert [event for _, event, _ in observed] == ['commandreceived', 'voiceassigned']
    data = observed[-1][2]
    assert data['id'] == observed[0][2]['id'] == result['requestId']
    assert data['platform'] == 'twitch' and data['userId'] == '123'
    assert data['alias'] == 'Internal' and data['publicVoice'] == 'Friendly voice'
    assert data['reply'] == result['reply']
    assert protocol.viewers.get('twitch', '123')['voice'] == 'Internal'
    command(protocol, '!voice reset')
    assert observed[-1][1] == 'voicereset'
    command(protocol, '!voice')
    assert observed[-1][1] == 'voiceslisted'


def test_fail_event_does_not_leak_request_or_modify_assignment(protocol):
    command(protocol, '!voice Friendly voice')
    with pytest.raises(ValueError):
        command(protocol, '!voice private secret text')
    event = protocol.engine.events.recent()[0]
    assert event['event'] == 'commandfailed'
    assert event['data']['reason'] == 'unavailable'
    assert 'secret' not in str(event)
    assert protocol.viewers.get('twitch', '123')['voice'] == 'Internal'


def test_disabled_and_storage_failure_events(protocol):
    protocol.settings.viewer_commands_enabled = False
    with pytest.raises(ValueError):
        command(protocol, '!voice random')
    assert protocol.engine.events.recent()[0]['data']['reason'] == 'disabled'
    protocol.settings.viewer_commands_enabled = True
    protocol.viewers.update = Mock(side_effect=OSError('secret path'))
    with pytest.raises(OSError):
        command(protocol, '!voice random')
    data = protocol.engine.events.recent()[0]['data']
    assert data['reason'] == 'storage' and 'secret' not in str(data)


@pytest.mark.parametrize('platform', ['twitch', 'youtube', 'kick', ''])
def test_platform_templates_include_identity_and_no_auto_triggers(platform):
    import base64
    import gzip
    import json
    from voice_studio_speaker_bridge.streamerbot_export import export_viewer_commands, export_actions
    envelope = json.loads(gzip.decompress(base64.b64decode(export_viewer_commands(6670, platform))[4:]))
    actions = envelope['data']['actions']
    assert len(actions) == 3
    normal = json.loads(gzip.decompress(base64.b64decode(export_actions(6670, ''))[4:]))
    normal_ids = {action['id'] for action in normal['data']['actions']}
    assert len({action['id'] for action in actions}) == 3
    for action in actions:
        assert action['id'] not in normal_ids
        assert action['triggers'] == [] and not action['alwaysRun']
        payload = action['actions'][0]['payload']
        assert (platform or '%userType%') in payload
        assert all(token in payload for token in ['%userId%', '%userName%', '%broadcastUserId%', '%userGroups%', '%isSubscribed%', '%isVip%', '%isModerator%'])
    assert actions[0]['actions'][0]['payload'].endswith('!voice %rawInput%')
    assert actions[1]['actions'][0]['payload'].startswith('YAPLOQ\r\ncommand:speak\r\n\r\n')
    assert actions[1]['actions'][0]['payload'].endswith('%rawInput%')
    assert actions[2]['actions'][0]['payload'].startswith('YAPLOQ\r\ncommand:speak\r\n\r\n')
    assert actions[2]['actions'][0]['payload'].endswith('%message%')
    assert envelope['meta']['autoRunAction'] is None


def test_viewer_events_dispatch_with_reply_arguments_and_platform_conditions(protocol):
    from voice_studio_speaker_bridge.automations import validate_rules
    from voice_studio_speaker_bridge.streamerbot import StreamerBotActions
    runner = StreamerBotActions(protocol.settings, protocol.engine.events)
    protocol.settings.automations = validate_rules([dict(id='reply', name='Viewer reply', enabled=True,
        triggers=[dict(source='viewer', event='voiceassigned')],
        conditions=[dict(field='platform', op='equals', value='twitch')],
        steps=[dict(type='action', action='Reply', args={'message': '{ttsReply}', 'platform': '{ttsPlatform}', 'viewer': '{ttsUserId}'})])])
    result = command(protocol, '!voice Friendly voice')
    rule, arguments = runner.pending.get_nowait()
    sent = []
    runner._post_action = lambda action, args: sent.append((action, args))
    runner._run_steps(rule, arguments)
    assert sent[0][1]['message'] == result['reply']
    assert sent[0][1]['viewer'] == '123' and sent[0][1]['platform'] == 'twitch'
    assert runner.pending.empty()
