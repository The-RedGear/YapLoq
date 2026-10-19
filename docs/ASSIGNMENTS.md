# Assignments

Assignments is for special viewer voices only. Default-voice chat does not create records. Edit supports correcting a platform ID without overwriting another identity. Reset returns to role/default selection and hides the row; Delete removes the stored record with a previous-file backup. Neither operation deletes speech history.

The fallback selector is inline, not a separate page. Roles & rules shows role/group defaults first, with advanced conditional rules collapsed. Existing legacy username rules remain stored and effective for compatibility, but are hidden from the role editor.

Built-in role defaults match broadcaster, moderator, VIP and subscriber flags supplied by a trusted integration. Custom group rules use a case-insensitive `groups` array on a structured Speak request, for example:

```json
{"request":"Speak","platform":"twitch","userId":"123","user":"Example","message":"Hello","groups":["Special Guests"],"isVip":true}
```

Streamer.Bot must supply its actual group memberships; YapLoq does not fetch or infer them. The compact YAPLOQ2 UDP template does not carry custom groups; use a structured JSON Speak payload for those. If several group rules match, the first configured match wins. Otherwise built-in role precedence is Broadcaster, Moderator, VIP, Subscriber. Explicit voices, saved viewer assignments and conditional voice rules still precede these defaults. A stale group/role voice falls back normally.

Chat [Voice] tags can use every enabled alias by default. Matching ignores case, tolerates punctuation/spacing differences, and allows a unique word-prefix such as [Spongebob]. Ambiguous names are rejected; no approximate guess chooses a different voice. Public-only restrictions remain available under Settings > Speech input & integration templates. Existing !voice integration requests remain compatible, but have no dedicated Assignments tab.

Optional sentence generation is in the same Settings section and is off by default. Plain-text sentences become separate audio clips/queue entries; voice, identity, chronological admission and playback order are retained. Common abbreviations are kept intact, but this is conservative punctuation-based segmentation rather than a language parser. SSML stays whole. Inputs over 50 resulting clips are rejected before any are queued. Splitting adds provider calls and can introduce pauses or costs; it does not guarantee a faster first clip for every provider.
