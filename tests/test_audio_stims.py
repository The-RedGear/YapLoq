from io import BytesIO
from pathlib import Path
from time import monotonic, sleep
from unittest.mock import Mock, patch
import wave

import pytest

from voice_studio_speaker_bridge.audio_stims import validate_libraries, render_sound
from voice_studio_speaker_bridge.engine import SpeechEngine
from voice_studio_speaker_bridge.events import EventBus
from voice_studio_speaker_bridge.models import VoiceAlias
from voice_studio_speaker_bridge.protocol import SpeakerBotProtocol
from voice_studio_speaker_bridge.settings import Settings
from voice_studio_speaker_bridge.streamerbot import StreamerBotActions


@pytest.fixture
def setup(tmp_path):
    output=BytesIO()
    with wave.open(output, 'wb') as wav:
        wav.setparams((1,2,44100,0,'NONE','not compressed')); wav.writeframes(bytes(8820))
    path=tmp_path/'fart.wav'; path.write_bytes(output.getvalue())
    settings=Settings(tmp_path/'settings.json')
    settings.aliases['Wallace']=VoiceAlias('Wallace')
    settings.aliases['Plankton']=VoiceAlias('Plankton')
    settings.audio_stims=validate_libraries({'Fart':dict(files=[dict(path=str(path))], action='[CE] - Fart [Attack]', censor_words=['stinky'])}, settings.aliases)
    engine=SpeechEngine(settings,EventBus())
    yield engine, path, output.getvalue()
    engine.shutdown()


def submit(engine, text, **extra):
    return SpeakerBotProtocol(engine.settings, engine).execute('Speak',dict(message=text, platform='twitch',userId='123',user='ExampleViewer',userProfileImageUrl='https://example.test/viewer.png',messageId='input-1', **extra))


def wait_until(check):
    deadline=monotonic()+3
    while not check() and monotonic()<deadline: sleep(.01)
    assert check()


def test_mixed_segments_keep_voice_order_sender_and_one_queue_event(setup):
    engine, path, _=setup
    result=submit(engine,'[Wallace] First [Fart] second [Plankton] Third [Fart] fourth')
    jobs=list(engine.pending.queue)
    assert [(j.text,j.alias.name) for j in jobs]==[('First','Wallace'),('[Fart]','Fart'),('second','Wallace'),('Third','Plankton'),('[Fart]','Fart'),('fourth','Plankton')]
    assert all(j.message_id=='input-1' and j.user_id=='123' and j.avatar_url.endswith('viewer.png') for j in jobs)
    assert len(result['speechIds'])==6
    assert len([e for e in engine.events.recent() if e['event']=='queueadded'])==1


def test_weighted_selection_and_disabled_files(setup):
    engine, path, _=setup
    library=engine.settings.audio_stims['Fart']
    library['files'] += [dict(path=str(path),volume=.5,weight=3,enabled=True),dict(path=str(path),volume=1,weight=100,enabled=False)]
    with patch('voice_studio_speaker_bridge.audio_stims.random.choices', side_effect=lambda seq,weights,k:[seq[1]]) as choose:
        submit(engine,'[Fart]')
    assert choose.call_args.kwargs['weights']==[1,3]
    assert engine.pending.queue[0].alias.volume==.5


def test_missing_library_is_atomic_and_sender_blocklist_applies(setup):
    engine,path,_=setup
    path.unlink()
    with pytest.raises(ValueError,match='no available'): submit(engine,'[Wallace] First [Fart]')
    assert engine.pending.empty()
    engine.settings.user_blocklist=['ExampleViewer']
    path.write_bytes(b'x')
    with pytest.raises(ValueError,match='blocked'): submit(engine,'[Fart]')
    assert engine.pending.empty()


def test_censor_replacement_splits_without_changing_voice(setup):
    engine,_,_=setup
    submit(engine,'[Wallace] That is STINKY!')
    assert [(j.text,j.alias.name) for j in engine.pending.queue]==[('That is','Wallace'),('[Fart]','Fart'),('!','Wallace')]


def test_settings_roundtrip_and_alias_collisions(setup):
    engine,path,_=setup
    engine.settings.save()
    loaded=Settings(engine.settings.path)
    assert loaded.audio_stims['Fart']['files'][0]['path']==str(path)
    with pytest.raises(ValueError,match='voice alias'):
        validate_libraries({'Wallace':dict(files=[])},engine.settings.aliases)
    for value in [float('nan'),-1,10001]:
        with pytest.raises(ValueError): validate_libraries({'Test':dict(files=[dict(path=str(path),weight=value)])})


def test_local_decoder_produces_real_wav(setup):
    _,path,_=setup
    decoded=render_sound(path)
    with wave.open(BytesIO(decoded),'rb') as wav: assert wav.getframerate()==44100 and wav.getnchannels()==1


def test_hooks_fire_at_playback_with_native_viewer_arguments_not_admission_or_replay(setup):
    engine,path,wav=setup
    runner=StreamerBotActions(engine.settings,engine.events)
    calls=[]; runner._post_action=lambda action,args:calls.append((action,args))
    played=[]
    engine._synthesize=lambda job:wav
    engine.audio=Mock(warning='',remaining_seconds=0,elapsed_seconds=0,duration_seconds=0,progress=0)
    engine.audio.decode_wav=lambda *a,**k:(b'pcm',100)
    def play(pcm, **kwargs):
        played.append(engine._current.alias.name)
        if kwargs.get('on_started'): kwargs['on_started']()
        return True
    engine.audio.play.side_effect=play
    submit(engine,'[Wallace] Hello [Fart] Goodbye')
    assert runner.stim_pending.empty() and calls==[]
    runner.start();engine.start()
    try:
        wait_until(lambda:len(engine.history)==3 and len(calls)==1)
        assert played==['Wallace','Fart','Wallace']
        action,args=calls[0]
        assert action=='[CE] - Fart [Attack]'
        assert args['userName']=='ExampleViewer' and args['userId']=='123' and args['userType']=='twitch'
        assert args['userProfileImageUrl']=='https://example.test/viewer.png' and args['ttsMessageId']=='input-1'
        stim=next(row for row in engine.history if row['provider']=='audio-stim')
        engine.replay_history(stim['id'])
        wait_until(lambda:len(played)==4)
        sleep(.1)
        assert len(calls)==1
    finally: runner.shutdown()


def test_preview_and_cancelled_sound_never_queue_hook(setup):
    engine,_,_=setup
    runner=StreamerBotActions(engine.settings,engine.events)
    submit(engine,'[Fart]')
    job=engine.pending.queue[0]
    data=engine._event_data(job)
    runner._on_event('audiostim','cancelled',data)
    runner._on_event('audiostim','playing',dict(data,source='Audio Stim preview'))
    assert runner.stim_pending.empty()


def test_censor_rules_and_sentence_splitting_preserve_sound_segments(setup):
    engine,_,_=setup
    engine.settings.split_speech_sentences=True
    engine.settings.profanity_enabled=True
    engine.settings.profanity_rules=[dict(word='smelly', variants=['smellier'], enabled=True, match_variants=True, action='stim', replacement='Fart')]
    submit(engine,'[Wallace] Hello. This is smellier. [Fart] Goodbye.')
    jobs=list(engine.pending.queue)
    assert [j.alias.name for j in jobs]==['Wallace','Wallace','Fart','Wallace','Fart','Wallace']
    assert len([e for e in engine.events.recent() if e['event']=='queueadded'])==1


def test_playback_hook_not_called_if_cancelled_or_device_fails():
    from threading import Event
    import miniaudio
    from voice_studio_speaker_bridge.audio import AudioPlayer
    player=AudioPlayer(); hook=Mock(); cancelled=Event();cancelled.set()
    assert not player.play(bytes(100),cancel_event=cancelled,on_started=hook)
    with patch('voice_studio_speaker_bridge.audio.miniaudio.PlaybackDevice',side_effect=miniaudio.MiniaudioError('test failure')):
        assert not player.play(bytes(100),on_started=hook)
    hook.assert_not_called()


def test_replay_hook_is_explicitly_opt_in(setup):
    engine,_,_=setup
    submit(engine,'[Fart]')
    runner=StreamerBotActions(engine.settings,engine.events)
    data=engine._event_data(engine.pending.queue[0]);data['replay']=True
    runner._on_event('audiostim','playing',data)
    assert runner.stim_pending.empty()
    data['stim']['replay_actions']=True
    runner._on_event('audiostim','playing',data)
    assert runner.stim_pending.get_nowait()[0]=='[CE] - Fart [Attack]'


@pytest.mark.parametrize('output,expected',[('', 'TTS device'),('Sound effects device','Sound effects device'),('[Default]','')])
@pytest.mark.parametrize('preview',[False,True])
def test_stim_output_is_independent_and_saved(setup,output,expected,preview):
    engine,_,wav=setup
    engine.settings.output_device='TTS device'
    engine.settings.preview_output_device='Headphones'
    engine.settings.audio_stim_output_device=output
    engine.settings.save()
    assert Settings(engine.settings.path).audio_stim_output_device==output
    engine._synthesize=lambda job:wav
    engine.audio=Mock(warning='',remaining_seconds=0,elapsed_seconds=0,duration_seconds=0,progress=0)
    engine.audio.decode_wav=lambda *a,**k:(b'pcm',100)
    played=[]
    def play(pcm,**kwargs):
        played.append((engine._current.alias.name,engine.audio.output_device))
        return True
    engine.audio.play.side_effect=play
    submit(engine,'[Wallace] Before [Fart] after')
    if preview:
        next(job for job in engine.pending.queue if job.alias.audio_stim).source='Audio Stim preview'
    engine.start()
    wait_until(lambda:len(engine.history)==3)
    assert played==[('Wallace','TTS device'),('Fart',expected),('Wallace','TTS device')]


def test_stim_output_applies_live_without_saving(setup):
    engine,_,_=setup
    engine.settings.save()
    engine.settings.apply_runtime({'audio_stim_output_device':'Sound effects device'})
    assert engine.settings.audio_stim_output_device=='Sound effects device'
    assert Settings(engine.settings.path).audio_stim_output_device==''


def test_random_preview_endpoint_uses_weights_and_never_attaches_actions(setup):
    import json
    from threading import Thread
    from urllib.request import Request,urlopen
    from voice_studio_speaker_bridge.server import BridgeServers
    engine,path,_=setup
    engine.settings.http_address='127.0.0.1';engine.settings.http_port=0
    servers=BridgeServers(engine.settings,SpeakerBotProtocol(engine.settings,engine),engine.events)
    thread=Thread(target=servers._run_http,daemon=True);thread.start()
    try:
        wait_until(lambda:servers.http_server is not None)
        library=dict(engine.settings.audio_stims['Fart'])
        library['files']=[dict(path=str(path),volume=.3,weight=2,enabled=True),dict(path=str(path),volume=1,weight=1,enabled=False)]
        request=Request(f'http://127.0.0.1:{servers.http_server.server_port}/api/stims/preview',data=json.dumps(dict(keyword='Fart',library=library,output_device='Selected device')).encode(),headers={'Content-Type':'application/json'})
        with patch('voice_studio_speaker_bridge.audio_stims.random.choices',side_effect=lambda seq,weights,k:[seq[0]]) as choose:
            with urlopen(request,timeout=3) as response: result=json.load(response)
        assert result['ok'] and result['result']['file']==str(path)
        assert choose.call_args.kwargs['weights']==[2]
        job=engine.pending.queue[0]
        assert job.alias.volume==.3 and job.alias.audio_stim['action']=='' and 'preview' in job.source.lower()
        assert job.alias.output_device=='Selected device'
        assert job.alias.name=='Fart' and job.text=='[Fart]' and job.alias.audio_stim['name']=='Fart'
    finally:servers.stop();thread.join(3)


def test_stim_only_input_never_dispatches_speech_queue_hooks(setup):
    engine,_,_=setup
    runner=StreamerBotActions(engine.settings,engine.events)
    submit(engine,'[Fart]')
    job=engine.pending.queue[0];data=engine._event_data(job)
    for event in ('received','queueadded','textqueued','playing','finished'):
        runner._on_event('texttospeech',event,data)
    assert runner.pending.empty() and not runner.active_speech_ids
    assert not runner.batch_queued_announced and not runner.batch_is_playing
    runner._on_event('audiostim','playing',data)
    assert runner.stim_pending.get_nowait()[0]=='[CE] - Fart [Attack]'


def test_sound_first_mixed_input_still_announces_one_speech_queue_addition(setup):
    engine,_,_=setup
    submit(engine,'[Fart] [Wallace] Hello')
    event=next(e for e in engine.events.recent() if e['event']=='queueadded')
    assert event['data']['alias']=='Wallace' and not event['data']['stim']


def test_queue_finish_waits_for_middle_and_trailing_stims(setup):
    engine,_,_=setup
    engine.settings.streamerbot_actions_enabled=True
    engine.settings.streamerbot_finished_action='Queue finish'
    engine.settings.streamerbot_finished_delay=0
    runner=StreamerBotActions(engine.settings,engine.events)
    submit(engine,'[Wallace] Before [Fart] after [Fart]')
    jobs=list(engine.pending.queue)
    for job in jobs[:-1]:
        runner._on_event('texttospeech','finished',engine._event_data(job))
        assert runner.pending.empty()
    runner._on_event('texttospeech','finished',engine._event_data(jobs[-1]))
    action,args=runner.pending.get_nowait()
    assert action=='Queue finish' and args['ttsState']=='finished'
    assert not runner.active_speech_ids and not runner.active_stim_ids


@pytest.mark.parametrize('identity',[{}, {'user':'%userName%','userId':'%userId%'}, {'user':'  '}])
def test_stim_action_requires_viewer_unless_opted_in(setup,identity):
    engine,_,_=setup
    runner=StreamerBotActions(engine.settings,engine.events)
    submit(engine,'[Fart]')
    data=engine._event_data(engine.pending.queue[0]);data.update(user='',displayName='',userId='');data.update(identity)
    runner._on_event('audiostim','playing',data)
    assert runner.stim_pending.empty()
    data['stim']['allow_without_user']=True
    runner._on_event('audiostim','playing',data)
    assert runner.stim_pending.get_nowait()[0]=='[CE] - Fart [Attack]'


def test_numeric_limits_and_old_library_migration(setup):
    _,path,_=setup
    for volume,weight in [(1.01,1),(1,0),(1,101)]:
        with pytest.raises(ValueError): validate_libraries({'Sound':dict(files=[dict(path=str(path),volume=volume,weight=weight)])})
    old={'Sound':dict(files=[dict(path=str(path),volume=.4,weight=0),dict(path=str(path),volume=2,weight=1000)])}
    files=validate_libraries(old,legacy=True)['Sound']['files']
    assert files[0]['volume']==.4 and files[0]['weight']==1 and not files[0]['enabled']
    assert files[1]['volume']==1 and files[1]['weight']==100


def test_pause_keyword_needs_no_file_and_keeps_queue_order(setup):
    engine,_,_=setup
    config=engine.settings.audio_stims['Fart'];config.update(playback_mode='pause',pause_seconds=.25,files=[])
    submit(engine,'[Wallace] Before [Fart] after')
    jobs=list(engine.pending.queue)
    assert [j.alias.name for j in jobs]==['Wallace','Fart','Wallace']
    assert jobs[1].alias.audio_stim['pause_seconds']==.25
    with wave.open(BytesIO(engine._synthesize(jobs[1])),'rb') as wav:
        assert wav.getnframes()/wav.getframerate()==.25
        assert set(wav.readframes(wav.getnframes()))=={0}


@pytest.mark.parametrize('viewer,pause',[({},True),({'user':'%userName%'},True),({'user':'ExampleViewer'},False)])
def test_pause_only_without_viewer(setup,viewer,pause):
    from voice_studio_speaker_bridge.audio_stims import resolve_stim
    engine,_,_=setup
    engine.settings.audio_stims['Fart'].update(playback_mode='pause_without_user',pause_seconds=2)
    alias=resolve_stim(engine.settings,'Fart',viewer)
    assert bool(alias.audio_stim.get('pause_seconds'))==pause


def test_pause_duration_validation(setup):
    for seconds in [0,-1,61,float('nan')]:
        with pytest.raises(ValueError):validate_libraries({'Pause':dict(playback_mode='pause',pause_seconds=seconds)})


@pytest.mark.parametrize('device,expected',[('[Same as TTS output]','TTS device'),('[Default]','[Default]'),('Effects bus','Effects bus')])
def test_per_keyword_output_overrides_shared_output(setup,device,expected):
    from voice_studio_speaker_bridge.audio_stims import resolve_stim
    engine,_,_=setup
    engine.settings.output_device='TTS device';engine.settings.audio_stim_output_device='Old shared device'
    engine.settings.audio_stims['Fart']['output_device']=device
    alias=resolve_stim(engine.settings,'Fart')
    assert alias.output_device==expected
    engine.settings.save()
    assert Settings(engine.settings.path).audio_stims['Fart']['output_device']==device


@pytest.mark.parametrize('viewer,pause',[({},False),({'user':'ExampleViewer'},True),({'user':'%userName%'},False)])
def test_pause_when_viewer_available(setup,viewer,pause):
    from voice_studio_speaker_bridge.audio_stims import resolve_stim
    engine,_,_=setup
    config=engine.settings.audio_stims['Fart'];config.update(playback_mode='pause_with_user',pause_seconds=2)
    validated=validate_libraries({'Fart':config})
    assert validated['Fart']['playback_mode']=='pause_with_user'
    assert bool(resolve_stim(engine.settings,'Fart',viewer).audio_stim.get('pause_seconds'))==pause
