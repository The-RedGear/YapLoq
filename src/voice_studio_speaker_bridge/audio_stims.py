"""Local sound libraries. Selection is captured at queue admission, never replay."""
from io import BytesIO
import math
from pathlib import Path
import random
import re
import wave

from .models import VoiceAlias
from .multi_voice import normalized_voice_name

EXTENSIONS = {'.wav', '.mp3', '.ogg', '.flac'}


def has_viewer(data):
    return any(str(data.get(key) or '').strip() and str(data.get(key)).strip().casefold() not in {'unknown', 'none', 'null'}
               and not re.search(r'%[^%]+%|\{[^}]+\}', str(data.get(key))) for key in ('user', 'displayName', 'userId'))


def validate_libraries(raw, aliases=(), *, legacy=False):
    if not isinstance(raw, dict) or len(raw) > 200:
        raise ValueError('Use at most 200 Audio Stim libraries')
    result, names = {}, set()
    voice_names = {normalized_voice_name(name) for name in aliases}
    if isinstance(aliases, dict):
        voice_names.update(normalized_voice_name(v.public_name) for v in aliases.values() if v.public_name)
    for name, value in raw.items():
        name = str(name).strip()
        key = normalized_voice_name(name)
        if not key or len(name) > 64 or any(c in name for c in '[]\r\n') or key in names or key in voice_names:
            raise ValueError('Stim keywords must be unique and cannot match a voice alias')
        if not isinstance(value, dict):
            raise ValueError('Invalid Audio Stim library')
        files = value.get('files', [])
        if not isinstance(files, list) or len(files) > 1000:
            raise ValueError('Use at most 1000 sound files per stim')
        words = value.get('censor_words', [])
        if not isinstance(words, list):
            raise ValueError('Censor words must be a list')
        entries = []
        for entry in files:
            if not isinstance(entry, dict):
                raise ValueError('Invalid sound entry')
            path = str(entry.get('path', '')).strip()
            volume, weight = float(entry.get('volume', 1)), float(entry.get('weight', 1))
            if not path or Path(path).suffix.lower() not in EXTENSIONS:
                raise ValueError('Audio Stims support WAV, MP3, OGG and FLAC files')
            enabled = bool(entry.get('enabled', True))
            if legacy and math.isfinite(volume) and math.isfinite(weight) and 0 <= volume <= 2 and 0 <= weight <= 10000:
                enabled = enabled and weight > 0
                volume, weight = min(1, volume), max(1, min(100, weight))
            if not math.isfinite(volume) or not 0 <= volume <= 1 or not math.isfinite(weight) or not 1 <= weight <= 100:
                raise ValueError('Sound volume must be 0–100% and random weight 1–100')
            entries.append(dict(path=path, volume=volume, weight=weight, enabled=enabled))
        names.add(key)
        appearance = VoiceAlias(name, icon_id=value.get('icon_id', 'mdi:waveform'), color=value.get('color', '#B6A3FF'))
        mode = value.get('playback_mode', 'sound')
        seconds = float(value.get('pause_seconds', 1))
        if mode not in {'sound', 'pause', 'pause_without_user', 'pause_with_user'} or not math.isfinite(seconds) or not .1 <= seconds <= 60:
            raise ValueError('Choose a playback mode and a pause from 0.1 to 60 seconds')
        result[name] = dict(enabled=bool(value.get('enabled', True)), files=entries,
                            icon_id=appearance.icon_id, color=appearance.color,
                            output_device=str(value.get('output_device', '')),
                            playback_mode=mode, pause_seconds=seconds,
                            action=str(value.get('action', '')).strip()[:256],
                            replay_actions=bool(value.get('replay_actions', False)),
                            allow_without_user=bool(value.get('allow_without_user', False)),
                            censor_words=[str(w).strip()[:120] for w in words if str(w).strip()][:100])
    return result


def resolve_stim(settings, name, viewer=None):
    library = next(((n, v) for n, v in settings.audio_stims.items() if normalized_voice_name(n) == normalized_voice_name(name)), None)
    if library is None or not library[1]['enabled']:
        return None
    label, config = library
    output = config.get('output_device', '')
    if output == '[Same as TTS output]':
        output = settings.output_device or '[Default]'
    mode = config.get('playback_mode', 'sound')
    viewer_available = has_viewer(viewer or {})
    pause = mode == 'pause' or (mode == 'pause_without_user' and not viewer_available) or (mode == 'pause_with_user' and viewer_available)
    if pause:
        metadata = dict(name=label, file='', action=config['action'], replay_actions=config['replay_actions'],
                        allow_without_user=config.get('allow_without_user', False), pause_seconds=config.get('pause_seconds', 1))
        return VoiceAlias(label, provider='audio-stim', voice_id='', volume=1, output_device=output, icon_id=config.get('icon_id', 'mdi:waveform'), color=config.get('color', '#B6A3FF'), audio_stim=metadata)
    available = [entry for entry in config['files'] if entry['enabled'] and entry['weight'] > 0 and Path(entry['path']).is_file()]
    if not available:
        raise ValueError(f'Audio Stim [{label}] has no available enabled sounds')
    chosen = random.choices(available, weights=[e['weight'] for e in available], k=1)[0]
    if Path(chosen['path']).stat().st_size > 64 * 1024 * 1024:
        raise ValueError('Audio Stim file exceeds 64 MB')
    metadata = dict(name=label, file=chosen['path'], action=config['action'], replay_actions=config['replay_actions'], allow_without_user=config.get('allow_without_user', False))
    return VoiceAlias(label, provider='audio-stim', voice_id=chosen['path'], volume=chosen['volume'], output_device=output,
                      icon_id=config.get('icon_id', 'mdi:waveform'), color=config.get('color', '#B6A3FF'), audio_stim=metadata)


def replace_censored_words(text, settings):
    terms = {}
    if settings.profanity_enabled:
        for rule in settings.profanity_rules:
            if rule['enabled'] and rule['action'] == 'stim':
                name = rule['replacement'].strip()
                forms = [rule['word']] + (rule['variants'] if rule['match_variants'] else [])
                for word in forms:
                    if word:
                        terms[word.casefold()] = name
    for name, library in settings.audio_stims.items():
        if library['enabled']:
            for word in library['censor_words']:
                if word.casefold() in terms and terms[word.casefold()].casefold() != name.casefold():
                    raise ValueError('A censored word is assigned to more than one Audio Stim')
                terms[word.casefold()] = name
    if not terms:
        return text
    pattern = re.compile(r'(?<!\w)(?:' + '|'.join(re.escape(t) for t in sorted(terms, key=len, reverse=True)) + r')(?!\w)', re.I)
    # Do not rewrite voice/stim tags themselves.
    parts = re.split(r'(\[[^\[\]\r\n]*\])', text)
    def replacement(match):
        name = terms[match[0].casefold()]
        library = next((v for n, v in settings.audio_stims.items() if n.casefold() == name.casefold()), None)
        if library is None or not library['enabled']:
            raise ValueError('Censor Audio Stim is missing or disabled')
        return '[' + name + ']'
    return ''.join(part if i % 2 else pattern.sub(replacement, part) for i, part in enumerate(parts))


def render_sound(path):
    import miniaudio
    file = Path(path)
    if not file.is_file() or file.stat().st_size > 64 * 1024 * 1024:
        raise ValueError('Audio Stim file is missing or too large')
    info = miniaudio.get_file_info(str(file))
    if info.duration > 300:
        raise ValueError('Audio Stims must be five minutes or shorter')
    decoded = miniaudio.decode_file(str(file), output_format=miniaudio.SampleFormat.SIGNED16, nchannels=1, sample_rate=44100)
    output = BytesIO()
    with wave.open(output, 'wb') as wav:
        wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(44100); wav.writeframes(decoded.samples.tobytes())
    return output.getvalue()


def render_pause(seconds):
    seconds = float(seconds)
    if not math.isfinite(seconds) or not .1 <= seconds <= 60:
        raise ValueError('Pause must be from 0.1 to 60 seconds')
    output = BytesIO()
    with wave.open(output, 'wb') as wav:
        wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(44100)
        wav.writeframes(bytes(round(seconds * 44100) * 2))
    return output.getvalue()
