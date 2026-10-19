"""Native command definitions and bindings shared by full and voice-only imports."""
import re
import unicodedata
import uuid

from .yaploq_payload import speech_payload

# Streamer.bot CommandSource flags: Twitch Message, YouTube Message, Kick Message.
CHAT_SOURCES = 1 | 1024 | 2097152


def _id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_OID, 'VoxRelay/' + name))


def _slug(name):
    normalized = unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode().casefold()
    return re.sub(r'[^a-z0-9]+', '-', normalized).strip('-')[:40] or 'voice'


def attach_commands(pack, port, voice_universe=()):
    commands = []
    actions = pack['data']['actions']
    by_name = {action['name'].removeprefix('[YL] - '): action for action in actions}

    def bind(action, tokens, *, arguments=False, groups=('Moderators',), payload=None):
        key = action['id']
        command_id = _id('chat-command/' + key)
        commands.append(dict(id=command_id, name=action['name'], enabled=True, include=True,
                             mode=0, command='\r\n'.join(tokens), regexExplicitCapture=False,
                             location=0 if arguments else 1,
                             ignoreBotAccount=True, ignoreInternal=True, sources=CHAT_SOURCES,
                             persistCounter=False, persistUserCounter=False, caseSensitive=False,
                             globalCooldown=0, userCooldown=0, group=action['group'], grantType=0,
                             permittedUsers=[], permittedGroups=list(groups)))
        action['triggers'] = [dict(commandId=command_id, id=_id('chat-trigger/' + key), type=401,
                                   enabled=True, exclusions=[])]
        if payload is not None:
            action['actions'][0]['payload'] = payload

    for name, tokens in {
        'Pause audio': ['!ylpause'], 'Pause after current': ['!ylpauseafter'],
        'Resume': ['!ylplay', '!ylresume'], 'Skip current': ['!ylskip'],
        'Clear waiting': ['!ylclear'], 'Stop and clear': ['!ylstop'],
        'Skip and resume': ['!ylskipplay'], 'Stop, clear and resume': ['!ylclearplay'],
        'Enable speech': ['!ylenable'], 'Disable speech': ['!yldisable'],
    }.items():
        if name in by_name:
            bind(by_name[name], tokens)
    if 'Speak - Chat command' in by_name:
        bind(by_name['Speak - Chat command'], ['!ylsay'], arguments=True,
             payload=speech_payload('', message='%rawInput%'))
    if 'Speak random voice' in by_name:
        bind(by_name['Speak random voice'], ['!ylrandom'], arguments=True,
             payload=speech_payload('random', message='%rawInput%'))
    if 'Viewer voice command' in by_name:
        action = by_name['Viewer voice command']
        action['name'] = '[YL] - Assign voice'
        bind(action, ['!voice', '!ylvoice'], arguments=True, groups=('VIPs', 'Moderators'),
             payload=speech_payload('', message='%rawInput%', command='voice'))

    # Each action has a stable command ID. Rare slug collisions receive a stable suffix.
    for category, prefix, label in [('Playlists', '!ylplaylist-', 'Speak playlist - '),
                                     ('Voice groups', '!ylgroup-', 'Speak voice group - ')]:
        category_actions = [action for action in actions if action['group'] == 'YapLoq / ' + category]
        universe = list(voice_universe) if category == 'Voices' else [a['name'].removeprefix('[YL] - ' + label) for a in category_actions]
        counts = {}
        for name in set(universe):
            slug = _slug(name)
            counts[slug] = counts.get(slug, 0) + 1
        for action in category_actions:
            name = action['name'].removeprefix('[YL] - ' + label)
            slug = _slug(name)
            if counts.get(slug, 0) > 1:
                slug += '-' + _id('voice-command-name/' + name)[:8]
            payload = action['actions'][0]['payload'].replace('%message%', '%rawInput%')
            bind(action, [prefix + slug], arguments=True, payload=payload)
    pack['data']['commands'] = commands
    pack['minimumVersion'] = '1.0.0'
    pack['meta']['minimumVersion'] = '1.0.0'
    return pack
