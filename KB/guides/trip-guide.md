# Trip guide: phone page that finds where you are and narrates the place's history (Wikipedia + browser TTS)

Ticket: T141 · Last verified: 2026-09-29 by headless Chromium test (fake GPS Sagrada Família + Milan Duomo, 5 widths)

## When to use
A standalone phone page (no Eye, no server) that tells the story of a nearby or named place, in Spanish or English.
Not for pre-rendered narration synced to animation: use /kokoro-narration.

## The path we took
- Wikipedia Action API with `origin=*` (CORS, no key): `generator=geosearch` 1 km + `prop=info|description|coordinates`
  (`colimit=max`, `codistancefrompoint`), ranked by `length / (1 + dist/150)`, events/streets/stations/cities x0.1.
- Story: `prop=extracts&exintro&explaintext`; if < 110 words, add the History/Historia section of the full extract;
  trimmed to 220 words at sentence ends (60-90 s). Text is never generated: only fetched text is shown and read.
- Speech: browser `speechSynthesis` (es-ES / en-GB), one utterance per sentence; mic: `webkitSpeechRecognition` es-ES.
  Kokoro was not used: it needs this machine, and the page must work alone on the phone.
- One file: `~/agents/t141/where/index.html`, dropped to https `/t141/where/` (geolocation needs a secure context).

## Exact commands
```bash
cd ~/agents/t141 && python3 -m http.server 8911 --bind 127.0.0.1 &
PATH=~/.nvm/versions/node/v24.20.0/bin:$PATH node test.cjs http://127.0.0.1:8911/where/   # headless, --mute-audio
drop-link ~/agents/t141/where t141
```

## Pitfalls (measured)
- es.wikipedia "Sagrada Familia" is the religious concept; the basilica is "Templo Expiatorio de la Sagrada Familia".
- Geosearch at the Duomo ranked "Milán" (city) and a funeral article first until the penalty rules; description
  "ciudad de Italia" is matched only at the start (a bare "ciudad" also hit "Catedral de Milán").
- `coordinates` defaults to 10 results: without `colimit=max` pages lose their distance.
- Nested parentheses and "(s." abbreviations cut sentences; spoken text strips parentheses in a loop.

## Links
- Code: ~/agents/t141/where/index.html · Test: ~/agents/t141/test.cjs · Shots: ~/agents/t141/shots/
