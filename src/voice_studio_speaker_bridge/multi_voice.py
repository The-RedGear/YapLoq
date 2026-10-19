"""Inline voice tags. Escape a literal opening bracket with a backslash."""
import re

TAG = re.compile(r'(?<!\\)\[([^\[\]\r\n]{1,64})\]')


def split_voices(text, default_alias, resolve):
    matches = list(TAG.finditer(text))
    if not matches:
        return [(text.replace(r'\[', '['), default_alias)]
    if len(matches) > 20:
        raise ValueError('Use at most 20 voice tags per input')
    result = []
    alias, cursor = default_alias, 0
    for match in matches:
        segment = text[cursor:match.start()].replace(r'\[', '[').strip()
        if segment:
            result.append((segment, alias))
        alias = resolve(match[1].strip())
        cursor = match.end()
    segment = text[cursor:].replace(r'\[', '[').strip()
    if segment:
        result.append((segment, alias))
    if not result:
        raise ValueError('Add some text after a voice tag')
    return result
