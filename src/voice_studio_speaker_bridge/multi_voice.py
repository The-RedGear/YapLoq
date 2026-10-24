"""Inline voice tags. Escape a literal opening bracket with a backslash."""
import re

TAG = re.compile(r'(?<!\\)\[([^\[\]\r\n]{1,64})\]')


def strip_chat_tokens(text, settings):
    """Remove chat-only tokens before they can become empty voice segments."""
    if settings.ignore_command_messages:
        text = re.sub(r'(?<!\S)!\S+', '', text)
    if settings.ignore_mention_messages:
        text = re.sub(r'(?<!\S)@\S+', '', text)
    return text.strip()


def normalized_voice_name(name):
    return ' '.join(''.join(char if char.isalnum() else ' ' for char in name.casefold()).split())


def sentence_clips(text):
    """Conservative plain-text boundaries; leave abbreviations and initials intact."""
    start = 0
    result = []
    for boundary in re.finditer(r'''[.!?。！？]["'”’)]*\s+|\n+''', text):
        end = boundary.end()
        candidate = text[start:end].strip()
        if re.search(r'\b(?:mr|mrs|ms|dr|prof|sr|jr|st|vs|etc|e\.g|i\.e)\.$', candidate, re.I) or re.search(r'\b[A-Z]\.$', candidate):
            continue
        if candidate:
            result.append(candidate)
        start = end
    if text[start:].strip():
        result.append(text[start:].strip())
    return result


def split_voices(text, default_alias, resolve):
    matches = list(TAG.finditer(text))
    if not matches:
        return [(text.replace(r'\[', '['), default_alias)]
    result = []
    alias, cursor = default_alias, 0
    voice_tags = 0
    for match in matches:
        selected = resolve(match[1].strip())
        if selected is None:
            # Ordinary bracketed text (or a typo) is not a voice switch.
            # Leave it in the current segment, including trailing stage cues.
            continue
        voice_tags += 1
        if voice_tags > 20:
            raise ValueError('Use at most 20 voice tags per input')
        segment = text[cursor:match.start()].replace(r'\[', '[').strip()
        if segment:
            result.append((segment, alias))
        if getattr(selected, 'provider', '') == 'audio-stim':
            result.append((match[0], selected))
        else:
            alias = selected
        cursor = match.end()
    segment = text[cursor:].replace(r'\[', '[').strip()
    if segment:
        result.append((segment, alias))
    if not result:
        raise ValueError('Add some text after a voice tag')
    return result
