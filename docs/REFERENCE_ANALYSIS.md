# Smash Karts: short reference analysis

## How this was done (and its limits)

The REA (reverse-engineer-web) skill was loaded, but its MCP tools are not registered in
this environment and registering them needs a separate approval, and the build container's
network policy blocks direct requests to smashkarts.io. So this is a **light observational
analysis** from public pages (the smashkarts.io landing page and the CrazyGames listing),
not a bundle or runtime analysis. No code or assets were downloaded or extracted; the game
itself (a WebGL build) was not played from this environment.

Each point is marked **[sourced]** (stated on a public page) or **[inferred]** (common to the
genre / commonly observed gameplay, used as a design choice, not verified here).

## Key mechanics

- **Pitch** [sourced]: "Multiplayer kart battle arena. Drive fast. Fire rockets. Make big explosions."
- **Driving** [sourced]: WASD or arrow keys to drive. [inferred] Arcade handling: quick
  acceleration, tight steering, no gears, karts bump each other, ramps and jumps in arenas.
- **Arena** [sourced]: several maps, seasonal variants. [inferred] Compact walled arenas
  with obstacles, ramps and open lanes, sized so a fight is never far away.
- **Pickups** [sourced]: drive over mystery boxes to get a random weapon or power-up.
  [inferred] Boxes respawn after a short delay; you hold one weapon at a time.
- **Weapons** [sourced]: rockets, machine gun, mines (three per pickup), cannonballs,
  spiky-go-round, nuke, static bomb, freeze blaster, invincibility.
- **Combat** [sourced]: Space fires. [inferred] Karts have health; explosions knock karts
  around; a destroyed kart explodes and respawns after a few seconds.
- **Match flow** [sourced]: 3-minute matches. [inferred] Free-for-all, ranked by kills,
  end-of-match leaderboard, then play again.
- **Camera** [inferred]: third-person chase camera behind and above the kart, with
  shake on explosions.
- **UI** [sourced]: kart/character customisation, prize machine, coins/gems (meta-game,
  out of scope here). [inferred] HUD with timer, kill count, current weapon, health,
  leaderboard and kill feed.

## What Kart Clash takes from this

3-minute free-for-all, one arena with ramps and obstacles, random-weapon crates that
respawn, rockets / machine gun / mines, health + respawn, chase camera with shake, kill-based
ranking, and keyboard plus touch controls. All models, names, colours and UI are original.
The meta-game (currency, cosmetics, online play) is deliberately left out of v1.
