# Asset prompts

Everything in Kart Clash is already playable without these: models, maps and UI are
built in code, sounds and music are synthesised in code, and the 2D art (icons,
splash and store graphics) is generated at full resolution by `tools/make_art.py`.

What I couldn't produce here are hand-made 3D models, recorded or produced music and
voice, and painted key art. The prompts below are for those. They're written for
text-to-3D, text-to-image and text-to-music tools. Use a tool whose licence lets you
ship the output commercially, and don't use other games' names or characters in the
prompts.

**Shared style line.** Add it to every visual prompt:

> Original stylised low-poly game art, chunky rounded shapes, flat colours with soft
> gradients, bright saturated palette (orange #FF7A1A, navy #141B33, teal #19C3B1,
> gold #FFD23F), clean silhouettes, readable from far away, no text, no logos.

## 3D models (export as `.glb`, Y-up, 1 unit = 1 m, under 5k triangles each)

| Asset | Prompt | Where it goes |
|---|---|---|
| Kart body | "Small open-wheel battle go-kart, wedge-shaped fibreglass body with a raised nose, roll bar behind the seat, four fat wheels as separate objects, mount points on both sides and on the hood, neutral grey body so it can be tinted, 2.4 m long, 1.6 m wide" | Replaces the boxes in `scripts/kart/kart_model.gd`. Keep the wheels separate so they can spin and steer. |
| Driver | "Cartoon kart driver in a round full-face helmet with a visor, chunky gloves gripping a steering wheel, seated pose, helmet tintable, 0.9 m tall seated" | Child of the kart model |
| Rocket pods | "Pair of side-mounted twin rocket pods, rounded tubes with orange tips, metal brackets" | `WeaponMount` rocket rig |
| Twin gun | "Twin rotary mini-gun turret for a go-kart hood, two six-barrel spinners on a swivel base, barrels as a separate object" | `WeaponMount` machine-gun rig |
| Mine rack | "Rear rack holding three round pink proximity mines with blinking caps" | `WeaponMount` mine rig |
| Shield emitter | "Short antenna mast with a glowing cyan orb on top, metal coil base" | `WeaponMount` shield rig |
| Weapon crate | "Floating weapon crate, rounded cube with glowing seams and a question-mark emblem, sci-fi toy look" | `scripts/combat/weapon_crate.gd` |
| Scrapyard props | "Set of junkyard props: stacked tyres, rusty shipping container, crushed car wreck, wooden crates, traffic cone, low-poly pine tree" | `scripts/arena/arena.gd` |
| Harbor props | "Set of frozen harbour props: wooden dock with bollards, small fishing boat stuck in ice, striped lighthouse, ice blocks, snowman, snowy pine" | `scripts/arena/frost_harbor.gd` |
| Rooftop props | "Set of neon city rooftop props: AC unit, roof vent, antenna mast with red light, billboard frame with blank glowing panel, holographic plinth" | `scripts/arena/neon_rooftop.gd` |
| Temple props | "Set of jungle temple ruins props: broken stone column, giant carved stone head (original design), fallen column, palm tree, fern bush" | `scripts/arena/temple_ruins.gd` |

## 2D art (PNG; sizes are the minimum)

| Asset | Size | Prompt |
|---|---|---|
| Key art / store hero | 3840×2160 | "Three colourful battle go-karts drifting in a junkyard arena at sunset, one firing a homing rocket, sparks and dust, dynamic low camera, empty space at the top for a logo" |
| Logo | 2048×1024, transparent | "Bold chunky game logo reading KART CLASH, italic heavy letters, orange fill with navy outline and gold highlight, slight 3D bevel" (or keep the generated title) |
| Map thumbnails | 1024×1024 each | "Isometric overview of a walled kart battle arena: (1) sunset scrapyard, (2) frozen harbour with an ice pond and two docks, (3) neon city rooftop at night with boost pads, (4) jungle temple with a stepped pyramid" |
| Weapon icons | 512×512 each, transparent | "Round badge icon of a (homing rocket / twin mini-gun / pink proximity mine / bubble shield), flat vector, thick outline" |
| Phone screenshots frame | 1242×2688 | Use real in-game screenshots; frame them with the key art colours |

## Audio (OGG Vorbis, 44.1 kHz; loops should loop seamlessly)

| Asset | Length | Prompt |
|---|---|---|
| Menu music | 60–90 s loop | "Upbeat arcade menu loop, 104 BPM, funky bass, bright synth arpeggios, light drums, playful, no vocals" |
| Scrapyard music | 90 s loop | "High-energy arcade racing loop, 128 BPM, distorted synth bass, punchy drums, rock-tinged lead, no vocals" |
| Harbor music | 90 s loop | "Cool wintry arcade loop, 118 BPM, bell-like plucks, warm pads, crisp hi-hats, no vocals" |
| Rooftop music | 90 s loop | "Synthwave battle loop, 132 BPM, pulsing saw bass, neon arpeggios, gated snare, no vocals" |
| Temple music | 90 s loop | "Jungle adventure arcade loop, 112 BPM, marimba and tom grooves, flute-like lead, no vocals" |
| Victory / defeat stings | 3–5 s | "Short triumphant fanfare" / "short comedic losing jingle" |
| SFX pack | short | Engine idle and rev loop, drift squeal, boost whoosh, rocket launch and explosion, mini-gun burst, mine drop and beep, shield hum, crate pickup chime, kart bump, UI click, countdown beeps and GO |
| Announcer (optional) | short | "Energetic arcade announcer: 3, 2, 1, GO!; Wrecked!; Double wreck!; Team Blaze wins!; Time's up!" |

## Where to put files

- `.glb` models: `assets/models/`. Godot imports them automatically. Replace the matching
  code-built mesh with `load("res://assets/models/<name>.glb").instantiate()`.
- Music: `assets/music/<map id>.ogg`. In `scripts/audio/music.gd`, `play()` could load the
  `.ogg` when it exists and fall back to the synthesised track.
- SFX: `assets/sfx/`. `scripts/combat/sfx.gd` maps sound names to generated streams, so
  swap in loaded streams there.
- Icons and splash: overwrite the PNGs in `assets/icons/` and `assets/splash/` (same sizes),
  or change `tools/make_art.py` and run it again.
