# FLOWLINE

A one-thumb, portrait, endless timing game where **your vertical scroll is the
simulation clock**.

---

## What FLOWLINE is

You drag your thumb up a feed. Except the feed is a single continuous world, and
what your thumb is actually dragging is *time*. Mechanisms — gates, rings,
pendulums, crushers — run on that clock. Stop your thumb and the world stops
mid-swing. Crawl and it creeps. Flick and it lurches forward. Drag downward and
the last few seconds run backwards, and you get to try again.

There is no menu before gameplay, no lives, no failure screen, no account, and
no permissions.

## Core mechanic

The controller maintains **two clocks**, both driven by one gesture:

| Quantity | Driven by | Meaning |
| --- | --- | --- |
| `gameTime` | scroll **velocity** → smoothed, curved, clamped `timeScale` | drives every obstacle mechanism |
| `flowPosition` | scroll **displacement** | the Spark's progress through the world |

Both freeze together when your thumb stops, and both reverse together on a
downward drag, so it reads as one unified time you are physically dragging.

The game lives in the *ratio* between them. Because velocity → `timeScale` is
non-linear and clamped (a floor of 0.15×, a soft ceiling of 1.6×, and a
flick-only ceiling of 3.6×) while displacement → position is linear, you control
how much the world moves per unit of ground you cover. A slow controlled drag
lets a gate cycle several times while you barely advance. A flick shoots you
through before it can close.

> **Design note.** An earlier single-clock design — where the Spark's position
> was also a pure function of `gameTime` — does not work as a game. A uniform
> time scale scales the player and the obstacles equally, so every outcome is
> fixed the moment you enter a segment and no amount of scrolling can change it.
> The two-clock model is what turns a scrubber over a fixed animation into
> something you can play. `TimeController` documents this in detail, and the
> distinction is directly covered by `test/time_controller_test.dart`.

## Architecture

```
lib/
  core/            math, deterministic RNG, design tokens, GameBalanceConfig, feature flags
  models/          profile, run stats, score events, replay, game mode
  game/
    time/          ScrollTracker, TimeController        <- the two clocks
    rewind/        Rewindable, snapshots, circular RewindBuffer
    components/    Spark, LanePath
    obstacles/     8 families + pooled factory
    segments/      Segment, SegmentPool, SegmentManager
    generation/    GenerationRules, ProceduralGenerator
    scoring/       ScoringSystem
    difficulty/    AdaptiveDifficulty
    effects/       particles, camera shake, EffectsManager
    flowline_game.dart   orchestrator (sequences systems; owns no rules)
  render/          RenderContext, WorldPainter
  services/        audio, haptics, leaderboard, monetization, platform services
  analytics/       AnalyticsService + local implementation
  repositories/    ProfileRepository (shared_preferences + in-memory)
  themes/          GameTheme, ThemeCatalog
  settings/        GameSettings
  ui/              GameScreen, gesture layer, HUD, hints, menu, debug tools
```

Three properties hold everything together:

**Analytic obstacles.** Almost every mechanism's state is a pure function of
`gameTime` — a gate's opening is `f(t, params)`. So rewind is nearly free, and
the snapshot buffer only has to store the three genuinely stateful things
(a released orbiter, a triggered domino chain, the scoring tallies). That is why
30 Hz snapshots over four seconds cost a few kilobytes instead of megabytes.

**Nothing allocates in the loop.** Obstacles and segments come from pools,
particles live in a fixed array, snapshots are flat `Float64List`s, `Paint`
objects are owned by the render context, and the update loop reuses its
containers. Steady-state gameplay should produce a flat allocation graph.

**Injection everywhere.** No singletons. `FlowlineApp` is the composition root;
every system takes its config and collaborators as constructor arguments, which
is why the whole game can be simulated headlessly in tests without a device.

## Requirements

- Flutter **3.19+** (Dart SDK 3.3+, null safety)
- Android SDK 21+ (compile against 34)
- Xcode 15+, iOS 13+
- One runtime dependency: `shared_preferences`

## Installation

```bash
git clone <your-remote> flowline
cd flowline

# Generate the native host projects. The repo ships the two native files that
# actually needed customising (portrait lock, zero permissions); this command
# fills in everything else from the standard template.
flutter create --org com.example --project-name flowline --platforms=android,ios .

flutter pub get
```

`flutter create` will not overwrite `android/app/src/main/AndroidManifest.xml`
or `ios/Runner/Info.plist` if they already exist. If it does replace them,
restore them from git — they are what enforce portrait-only and no permissions.

## Running Android

```bash
flutter devices
flutter run -d <android-device-id>            # debug, with debug HUD and panel
flutter run -d <android-device-id> --profile  # for honest frame timings
```

Always measure performance in `--profile`, never in debug: the debug build's
assertions and unoptimised rendering will lie to you by 20-40%.

## Running iOS

```bash
open ios/Runner.xcworkspace          # set your team + bundle id once
flutter run -d <iphone-id>
flutter run -d "iPhone 15 Pro"       # simulator
```

## Running in the browser (Replit)

The project ships a Replit configuration (`.replit`, `replit.nix`,
`scripts/replit_run.sh`) that builds the game for web and serves it. Press Run;
the first build takes several minutes, later ones seconds. Haptics, orientation
lock and true device frame pacing do not exist on web — everything else does.
Full instructions and failure modes are in `docs/REPLIT.md`.

## Running tests

```bash
flutter test                                    # everything
flutter test test/time_controller_test.dart     # one suite
flutter test --coverage
```

The suite covers the time controller (including frame-rate independence at 30
vs 120 fps), the rewind buffer, ~30,000 generated segments checked against
playability invariants, scoring and combo rules, adaptive difficulty, profile
persistence, and a headless two-minute session plus a widget launch test.

## Debug controls

Debug tooling is gated behind `FeatureFlags`, and those flags are themselves
forced off outside `kDebugMode` — there is no build in which a shipped binary
can show them.

- **Debug HUD** (top-left): fps, frame time, time scale, scroll velocity, game
  time, flow position, rewind buffer depth, active/pooled counts, segment id,
  segment seed, run seed, difficulty tier, skill score.
- **Debug panel** (menu → bottom): skip segment, trigger auto-rewind, regenerate
  ahead, freeze, show collision shapes, restart current seed, time-scale slider,
  forced difficulty tier, forced obstacle family, mode switching.

## Adding a new obstacle

1. Add a value to `ObstacleFamily`, and mark it `isDemanding` / `isRecovery` if
   it belongs in either bucket.
2. Create `lib/game/obstacles/your_family.dart` extending `Obstacle`. Implement
   `sample()` (clearance in world units, precision in 0..1) and `render()`.
   Override `captureState`/`restoreState` **only** if your obstacle has state
   that is not a function of `gameTime`.
3. Register the constructor in `ObstacleFactory._construct`.
4. Add a weight row for it in `GenerationRules._weights`.
5. Add a `case` to `ProceduralGenerator._configure` for band height and params.

The generator invariant tests will immediately tell you if your parameters can
produce impossible geometry.

## Adding a new theme

Add a `GameTheme` to `ThemeCatalog`, append its id to `ThemeCatalog.all` and to
the default `unlockedThemes` list in `PlayerProfile`. Nothing else changes —
themes control colour and bloom only, never geometry or timing.

## Changing difficulty balance

Three knobs, in increasing order of bluntness:

- **Feel** — `GameBalanceConfig`. One file, every number that changes how the
  game feels. See `docs/TUNING.md`.
- **Pacing** — `GenerationRules`: the per-tier weight table, repeat limits,
  demanding-family cooldown, recovery cadence.
- **Adaptation** — `AdaptiveDifficulty`: skill rise/fall rates, tier bands, and
  how much tolerance a struggling player is quietly given.

## Building release binaries

```bash
# Android
flutter build appbundle --release      # Play Store
flutter build apk --release --split-per-abi

# iOS
flutter build ipa --release
```

Signing setup, bundle identifiers and minimum OS versions are documented in
`docs/BUILD.md`. No credentials are committed to this repo.

## Known limitations

These are deliberate MVP boundaries, not oversights.

- **No audio files ship.** `SilentAudioService` implements the full cue
  interface and logs in debug, so every cue site is verifiable, but you will
  hear nothing until you implement a real backend. See `assets/audio/README.md`.
- **The build is unverified on device.** This repository was authored without a
  Flutter toolchain available. Run `flutter analyze` and `flutter test` first;
  expect to fix a small number of mechanical issues before the first launch.
- **Bouncer diverges from the original brief.** The spec described a spring
  surface that deflects the Spark. Lateral deflection needs a second control
  axis the game does not have, so it is implemented as a puck rebounding across
  the corridor — the hazard is the moving object rather than the gap, which
  makes it feel distinct without adding a verb.
- **Leaderboards and Game Center / Play Games are interfaces only.** The local
  implementation deliberately returns `null` for percentile rather than
  inventing a number.
- **Monetization is disabled.** `RewardedAdService` and `PurchaseService` exist
  and are wired to no-op implementations behind feature flags.
- **Replay recording is off.** The models and recorder exist and are tested;
  deterministic playback is not implemented yet.
- **Adaptive difficulty is not persisted mid-run**, only the resulting skill
  score at session end.
- **Haptics on Android** use Flutter's generic feedback constants, which vary in
  character across OEMs far more than on iOS.
