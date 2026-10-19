from concurrent.futures import ThreadPoolExecutor
import json
from unittest.mock import Mock

import pytest

from voice_studio_speaker_bridge.models import SpeechJob, VoiceAlias
from voice_studio_speaker_bridge.protocol import SpeakerBotProtocol
from voice_studio_speaker_bridge.settings import Settings
from voice_studio_speaker_bridge.viewers import ViewerStore, identity


@pytest.fixture
def protocol(tmp_path):
    settings = Settings(tmp_path / 'settings.json')
    settings.aliases['Other'] = VoiceAlias('Other')
    settings.voice_playlists = {'Pool': ['Other']}
    engine = Mock()
    engine.enqueue.side_effect = lambda text, alias, **kw: SpeechJob(text, alias)
    return SpeakerBotProtocol(settings, engine)


def assign(protocol, **changes):
    return protocol.execute('SetViewerVoice', dict(platform='twitch', userId='123', displayName='Same name', voice='Other', **changes))


def test_assignment_persists_in_data_and_reloads(protocol):
    assign(protocol)
    path = protocol.settings.path.parent / 'viewers.json'
    assert path.is_file()
    store = ViewerStore(path)
    assert store.get('twitch', '123')['voice'] == 'Other'
    assert protocol.execute('GetViewerVoice', dict(platform='twitch', userId='123'))['assignmentOrigin'] == 'Viewer preference'


def test_correct_identity_moves_assignment_atomically_without_overwriting(protocol):
    assign(protocol)
    protocol.execute('SetViewerVoice', dict(platform='twitch', userId='456', voice='Other', originalIdentity=dict(platform='twitch', userId='123')))
    assert protocol.viewers.get('twitch', '123') is None
    assert protocol.viewers.get('twitch', '456')['voice'] == 'Other'
    assign(protocol)
    before = protocol.viewers.path.read_bytes()
    with pytest.raises(ValueError, match='already exists'):
        protocol.execute('SetViewerVoice', dict(platform='twitch', userId='456', voice='', originalIdentity=dict(platform='twitch', userId='123')))
    assert protocol.viewers.path.read_bytes() == before


def test_identical_names_different_ids_platforms_and_id_case_do_not_merge(protocol):
    for platform, user_id in [('twitch', '123'), ('twitch', '456'), ('youtube', '123'), ('youtube', 'AbC'), ('youtube', 'abc')]:
        protocol.execute('SetViewerVoice', dict(platform=platform, userId=user_id, displayName='Same name', voice='Other'))
    assert len(protocol.execute('GetViewers', {})['viewers']) == 5


def test_renamed_viewer_keeps_assignment(protocol):
    assign(protocol)
    protocol.execute('Speak', dict(platform='twitch', userId='123', user='New name', message='Hi'))
    assert protocol.engine.enqueue.call_args.args[1].name == 'Other'
    assert protocol.viewers.get('twitch', '123')['displayName'] == 'New name'


def test_explicit_voice_overrides_viewer_preference(protocol):
    assign(protocol)
    protocol.execute('Speak', dict(platform='twitch', userId='123', message='Hi', voice='EventVoice'))
    assert protocol.engine.enqueue.call_args.args[1].name == 'EventVoice'


def test_reset_uses_existing_routing_default(protocol):
    assign(protocol)
    protocol.execute('SetViewerVoice', dict(platform='twitch', userId='123', voice=''))
    protocol.settings.user_voice_rules['name'] = 'EventVoice'
    protocol.execute('Speak', dict(platform='twitch', userId='123', user='name', message='Hi'))
    assert protocol.engine.enqueue.call_args.args[1].name == 'EventVoice'
    assert protocol.viewers.get('twitch', '123')['voice'] == ''
    assert protocol.execute('GetViewers', {})['viewers'] == []


def test_default_speech_does_not_create_assignment_records(protocol):
    protocol.execute('Speak', dict(platform='twitch', userId='123', user='Default viewer', message='Hi'))
    assert protocol.viewers.all() == []
    assert protocol.execute('GetViewers', {})['viewers'] == []


def test_delete_assignment_keeps_backup_and_default_speech_does_not_recreate_it(protocol):
    assign(protocol)
    assert protocol.execute('DeleteViewerVoice', dict(platform='twitch', userId='123'))['deleted']
    assert protocol.viewers.get('twitch', '123') is None
    assert json.loads(protocol.viewers.path.with_suffix('.json.bak').read_text())['viewers'][0]['voice'] == 'Other'
    protocol.execute('Speak', dict(platform='twitch', userId='123', message='Hi'))
    assert protocol.execute('GetViewers', {})['viewers'] == []
    assert not protocol.execute('DeleteViewerVoice', dict(platform='twitch', userId='123'))['deleted']


def test_role_flags_and_structured_custom_groups_choose_defaults(protocol):
    protocol.settings.role_voice_rules = {'vip': 'Other', 'moderator': 'EventVoice', 'group:special guests': 'Other'}
    protocol.execute('Speak', dict(message='Hi', isVip=True))
    assert protocol.engine.enqueue.call_args.args[1].name == 'Other'
    protocol.execute('Speak', dict(message='Hi', isVip=True, isModerator=True))
    assert protocol.engine.enqueue.call_args.args[1].name == 'EventVoice'
    protocol.execute('Speak', dict(message='Hi', isModerator=True, groups=['Special Guests']))
    assert protocol.engine.enqueue.call_args.args[1].name == 'Other'
    protocol.execute('Speak', dict(message='Hi', isModerator=True, groups='Special Guests'))
    assert protocol.engine.enqueue.call_args.args[1].name == 'EventVoice'


def test_playlist_assignment_uses_enabled_members(protocol):
    protocol.settings.voice_playlists['Pool'] += ['Missing', 'EventVoice']
    protocol.settings.aliases['EventVoice'].enabled = False
    protocol.execute('SetViewerVoice', dict(platform='twitch', userId='123', voice='playlist:Pool'))
    protocol.execute('Speak', dict(platform='twitch', userId='123', message='Hi'))
    assert protocol.engine.enqueue.call_args.args[1].name == 'Other'


def test_missing_assignment_is_visible_and_falls_back_without_erasing_it(protocol):
    assign(protocol)
    del protocol.settings.aliases['Other']
    entry = protocol.execute('GetViewerVoice', dict(platform='twitch', userId='123'))
    assert not entry['available'] and entry['warning']
    protocol.execute('Speak', dict(platform='twitch', userId='123', message='Hi'))
    assert protocol.engine.enqueue.call_args.args[1].name == 'EventVoice'
    assert protocol.viewers.get('twitch', '123')['voice'] == 'Other'


@pytest.mark.parametrize('data', [dict(platform='twitch'), dict(userId='123'), dict(platform='twitch', userId='%userId%'), dict(platform='bad/platform', userId='123')])
def test_invalid_identity_is_rejected_without_creating_file(protocol, data):
    with pytest.raises(ValueError):
        protocol.execute('SetViewerVoice', dict(data, voice='Other'))
    assert not protocol.viewers.path.exists()


def test_unavailable_target_does_not_overwrite_assignment(protocol):
    assign(protocol)
    with pytest.raises(ValueError):
        protocol.execute('SetViewerVoice', dict(platform='twitch', userId='123', voice='Missing'))
    assert protocol.viewers.get('twitch', '123')['voice'] == 'Other'


def test_corrupt_file_is_not_overwritten(protocol):
    protocol.viewers.path.write_text('broken', encoding='utf-8')
    with pytest.raises(ValueError, match='could not be read'):
        assign(protocol)
    assert protocol.viewers.path.read_text() == 'broken'


def test_repeated_messages_do_not_rewrite_file_and_updates_have_backup(protocol):
    assign(protocol)
    before = protocol.viewers.path.stat().st_mtime_ns
    assign(protocol)
    assert protocol.viewers.path.stat().st_mtime_ns == before
    protocol.execute('SetViewerVoice', dict(platform='twitch', userId='123', voice='EventVoice'))
    assert json.loads(protocol.viewers.path.with_suffix('.json.bak').read_text())['viewers'][0]['voice'] == 'Other'


def test_concurrent_assignments_do_not_lose_entries(protocol):
    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(lambda value: protocol.execute('SetViewerVoice', dict(platform='twitch', userId=str(value), voice='Other')), range(1, 26)))
    assert len(protocol.viewers.all()) == 25


def test_user_object_identity_and_message_metadata(protocol):
    data = dict(platform='youtube', user=dict(id='AbC', name='Viewer'), voice='Other', message='Hi')
    assert identity(data) == ('youtube', 'AbC')
    protocol.execute('Speak', data)
    assert protocol.engine.enqueue.call_args.kwargs['user_id'] == 'AbC'
    assert protocol.engine.enqueue.call_args.kwargs['platform'] == 'youtube'


def test_partial_identity_preserves_legacy_speech_but_is_not_saved(protocol):
    protocol.execute('Speak', dict(platform='twitch', user='Viewer', voice='EventVoice', message='Hi'))
    assert protocol.engine.enqueue.call_args.args[1].name == 'EventVoice'
    assert protocol.viewers.all() == []


def test_assignments_precedence_and_independent_priority(protocol):
    assign(protocol)
    protocol.settings.aliases['RuleVoice'] = VoiceAlias('RuleVoice')
    protocol.settings.routing_rules = [dict(field='source', value='chat', alias='RuleVoice', priority=25)]
    request = dict(platform='twitch', userId='123', source='chat', message='Hi')
    protocol.execute('Speak', dict(request, voice='EventVoice'))
    assert protocol.engine.enqueue.call_args.args[1].name == 'EventVoice'
    assert protocol.engine.enqueue.call_args.kwargs['priority'] == 25
    protocol.execute('Speak', request)
    assert protocol.engine.enqueue.call_args.args[1].name == 'Other'
    assert protocol.engine.enqueue.call_args.kwargs['priority'] == 25
    protocol.execute('SetViewerVoice', dict(platform='twitch', userId='123', voice=''))
    protocol.execute('Speak', request)
    assert protocol.engine.enqueue.call_args.args[1].name == 'RuleVoice'


def test_priority_only_rule_does_not_block_later_voice_rule(protocol):
    protocol.settings.routing_rules = [dict(field='source', value='chat', alias='', priority=40),
                                       dict(field='source', value='chat', alias='Other', priority=5)]
    protocol.execute('Speak', dict(source='chat', message='Hi'))
    assert protocol.engine.enqueue.call_args.args[1].name == 'Other'
    assert protocol.engine.enqueue.call_args.kwargs['priority'] == 40


def test_voice_only_rule_does_not_block_later_priority_rule(protocol):
    protocol.settings.routing_rules = [dict(field='source', value='chat', alias='Other'),
                                       dict(field='source', value='chat', alias='', priority=60)]
    protocol.execute('Speak', dict(source='chat', message='Hi'))
    assert protocol.engine.enqueue.call_args.args[1].name == 'Other'
    assert protocol.engine.enqueue.call_args.kwargs['priority'] == 60


def test_configured_default_persists_and_missing_default_falls_back(protocol):
    protocol.settings.assignment_default_voice = 'Other'
    protocol.settings.save()
    assert Settings(protocol.settings.path).assignment_default_voice == 'Other'
    protocol.execute('Speak', dict(message='Hi'))
    assert protocol.engine.enqueue.call_args.args[1].name == 'Other'
    protocol.settings.assignment_default_voice = 'Missing'
    protocol.execute('Speak', dict(message='Hi'))
    assert protocol.engine.enqueue.call_args.args[1].name == 'EventVoice'


def test_explicit_invalid_voice_is_not_silently_replaced_by_assignment(protocol):
    assign(protocol)
    with pytest.raises(ValueError, match='Voice alias not found'):
        protocol.execute('Speak', dict(platform='twitch', userId='123', voice='Missing', message='Hi'))
    protocol.engine.enqueue.assert_not_called()


def test_unavailable_rule_uses_configured_default(protocol):
    protocol.settings.assignment_default_voice = 'Other'
    protocol.settings.routing_rules = [dict(field='source', value='chat', alias='Missing', priority=15)]
    protocol.execute('Speak', dict(source='chat', message='Hi'))
    assert protocol.engine.enqueue.call_args.args[1].name == 'Other'
    assert protocol.engine.enqueue.call_args.kwargs['priority'] == 15


def test_streamerbot_json_user_object_type_preserves_stable_identity(protocol):
    user = json.dumps(dict(id='123', type='twitch', name='New name', login='newlogin', badges=[]))
    assign(protocol)
    protocol.execute('Speak', dict(user=user, message='Hi'))
    assert protocol.engine.enqueue.call_args.args[1].name == 'Other'
    assert protocol.engine.enqueue.call_args.kwargs['user_id'] == '123'
