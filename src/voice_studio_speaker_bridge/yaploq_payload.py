"""One tagged, line-based transport. Message text is always the final field."""
from __future__ import annotations
import re


def speech_payload(voice='', platform='%userType%', message='%message%', command='speak'):
    return '\r\n'.join(['YAPLOQ', 'command:' + command, voice, platform, '%userId%', '%userName%',
                        '%broadcastUserId%', '%userGroups%', '%isSubscribed%|%userIsSponsor%', '%isVip%', '%isModerator%', message])


def control_payload(command, *arguments):
    return '\r\n'.join(['YAPLOQ', 'command:' + command, *arguments])


def parse_payload(raw: str):
    parts = raw.replace('\r\n', '\n').split('\n')
    if len(parts) < 2 or parts[0].strip().upper() != 'YAPLOQ' or not parts[1].startswith('command:'):
        raise ValueError('Use YAPLOQ followed by command:function')
    command = parts[1][8:].strip().casefold()
    arguments = parts[2:]
    if command in {'speak', 'viewer', 'assignandspeak', 'voice'}:
        if len(arguments) < 10:
            raise ValueError('Speech payload is incomplete. Copy a fresh action from the Streamer.Bot tab.')
        voice, platform, user_id, username, owner, groups, subscribed, vip, moderator = arguments[:9]
        platform = platform.strip().casefold()
        if not re.fullmatch(r'[a-z0-9][a-z0-9_-]{0,31}', platform):
            platform = ''
        membership = subscribed.split('|', 1)
        subscribed = membership[1] if platform == 'youtube' and len(membership) == 2 else membership[0]
        data = dict(voice=voice.strip(), platform=platform, userId=user_id.strip(),
                    user=username.strip(), userName=username.strip(),
                    isBroadcaster=bool(owner.strip() and not owner.strip().startswith('%') and owner.strip() == user_id.strip()),
                    groups=[name.strip() for name in groups.split(',') if name.strip() and not name.strip().startswith('%')][:100],
                    isSubscribed=subscribed.strip().casefold() == 'true', isVip=vip.strip().casefold() == 'true',
                    isModerator=moderator.strip().casefold() == 'true', message='\n'.join(arguments[9:]), source='Streamer.bot')
        return {'speak': 'Speak', 'viewer': 'ViewerVoiceCommand', 'assignandspeak': 'AssignAndSpeak', 'voice': 'AssignVoiceCommand'}[command], data
    simple = {'pause': 'Pause', 'pauseaftercurrent': 'PauseAfterCurrent', 'resume': 'Resume',
              'skip': 'Stop', 'clear': 'Clear', 'clearall': 'ClearAll', 'enable': 'Enable', 'disable': 'Disable',
              'clearhistory': 'ClearHistory', 'skipresume': 'SkipAndResume', 'clearresume': 'ClearAndResume'}
    if command in simple:
        if any(value.strip() for value in arguments):
            raise ValueError('This command does not take arguments')
        return simple[command], {}
    signatures = {
        'assign': ('SetViewerVoice', ('username', 'voice')),
        'reset': ('SetViewerVoice', ('username',)), 'deleteassignment': ('DeleteViewerVoice', ('username',)),
        'remove': ('RemoveSpeech', ('speechId',)), 'moveup': ('MoveSpeech', ('speechId',)),
        'movedown': ('MoveSpeech', ('speechId',)), 'changevoice': ('ChangeSpeechVoice', ('speechId', 'voice')),
        'replay': ('ReplayHistory', ('speechId',)), 'saveaudio': ('SaveHistoryAudio', ('speechId',)),
        'seek': ('Seek', ('speechId', 'seconds')), 'loadprofile': ('LoadProfile', ('profile',))}
    if command not in signatures:
        raise ValueError('Unknown YapLoq function. Copy a supported action from the Streamer.Bot tab.')
    request, names = signatures[command]
    if len(arguments) != len(names) or any(not value.strip() or value.strip().startswith('%') for value in arguments):
        raise ValueError('Provide ' + ', '.join(names) + ' before running this action.')
    data = dict(zip(names, (value.strip() for value in arguments)))
    if command == 'reset':
        data['voice'] = ''
    if command in {'moveup', 'movedown'}:
        data['direction'] = 'up' if command == 'moveup' else 'down'
    if 'username' in data:
        data.update(login=data['username'], displayName=data['username'])
    return request, data
