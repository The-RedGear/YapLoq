"""Viewer-facing choices; metadata must come from a trusted integration event."""
from collections import Counter
import json


def viewer_roles(data):
    user = data.get('user')
    if isinstance(user, str) and user.lstrip().startswith('{'):
        try:
            user = json.loads(user)
        except ValueError:
            user = {}
    user = user if isinstance(user, dict) else {}
    result = set()
    for source in (data, user):
        role = str(source.get('role') or '').strip().casefold()
        result.add({'mod': 'moderator', 'sub': 'subscriber'}.get(role, role))
        for flag, role_name in [('isModerator', 'moderator'), ('isBroadcaster', 'broadcaster'),
                                ('isVip', 'vip'), ('isSubscribed', 'subscriber'), ('subscribed', 'subscriber')]:
            if source.get(flag) is True:
                result.add(role_name)
        for badge in source.get('badges', []) if isinstance(source.get('badges'), list) else []:
            if isinstance(badge, dict):
                result.add(str(badge.get('name') or '').casefold())
    return result


def public_label(alias):
    name = alias.public_name or alias.name
    if len(name) > 64 or any(ord(c) < 32 for c in name) or name.casefold() in {'random', 'reset', 'list'} or name.startswith('!'):
        return ''
    return name


def eligible_voices(settings, data):
    roles = viewer_roles(data)
    choices = []
    for alias in settings.aliases.values():
        if not alias.enabled or not alias.public or not public_label(alias):
            continue
        audience = alias.viewer_access
        allowed = audience == 'everyone' or 'broadcaster' in roles
        if 'moderator' in roles and audience in {'subscribers', 'vips', 'moderators'}:
            allowed = True
        if audience == 'subscribers' and 'subscriber' in roles or audience == 'vips' and 'vip' in roles:
            allowed = True
        if allowed:
            choices.append(alias)
    counts = Counter(public_label(alias).casefold() for alias in choices)
    return sorted((alias for alias in choices if counts[public_label(alias).casefold()] == 1), key=lambda alias: public_label(alias).casefold())
