# DuckTown FSD — self-driving for a FiveM server

This is the FSD (full self-driving) system from **DuckTown**, a private FiveM
zombie-survival server built on the BeyondSurvival (BS19) framework. It lives
inside a larger admin resource (`juno-admin`) that also handles moderation, a
companion NPC, and a token-gated HTTP API — the FSD parts are the subject of
this repo. Private values (server IPs, the owner's license identifier, the API
token) have been replaced with placeholders; the token itself was never in the
code (it loads from a `token.txt` file that is not included).

**Status: the drive has a known unresolved fault.** Under an FSD drive task
the car slows to ~1 m/s and stops. The symptoms, the investigation so far, and
the current leading hypothesis are documented below.

## How it works

Four layers:

1. **The game's own driving brain (base layer).** The client issues
   `TaskVehicleDriveToCoordLongrange` / `TaskVehicleDriveWander` to the
   *player's own ped*. Touching throttle/brake/steering cancels instantly
   (takeover watcher thread).
2. **D1 decision models (supervision).** The client reports context every 3 s
   (speed, engine health, nearby peds, stopped time, distance left). The
   server asks small decision models (Liquid AI d1-2b / d1-omni-2b, served by
   LM Studio on the `/v1/systemone` endpoint) to judge: initial pace
   (careful 25 / normal 35 / fast 50 m/s), blocked situations
   (wait / push through / reroute), danger (flee / keep going / stop), and a
   stuck detector (sustained < 2 m/s with > 30 m to go). Verdicts come back as
   `juno-admin:fsdAdjust` events and are applied by re-issuing the drive task.
   Everything fails open: no model answer = the game brain just drives.
3. **Vision co-pilot.** Every ~6 s the server grabs a screenshot from the
   driver's client (screenshot-basic) and asks a small vision model
   (lfm3-vl-2b) for one word — CONTINUE / SLOW / STOP / PUSH / REROUTE — which
   is applied the same way.
4. **Places + menu + API.** A server-side gazetteer resolves place names
   ("camp", "fort zancudo", …) to coordinates. In game: an ox_lib context
   menu on **F5** (waypoint / place picker / cruise / 3 speeds / stop) and
   `/fsdctl` chat commands. Externally, a token-gated HTTP API can start and
   stop drives remotely.

FSD is **owner-only**, enforced server-side by license identifier (the client
UI is also gated). Everyone else drives manually.

## Known fault: the drive task crawls

Under any FSD drive task, on any vehicle, on flat ground included:

- The car **starts off at a good speed, then slows to ~1 m/s (3–4 km/h on the
  dashboard), stops, and FSD turns off.**
- **Reverse gear reaches full speed.** Manual (human) driving is completely
  fine in the same cars.
- One observation of **fast off-road, slow on-road**.
- Sometimes the car never moves at all despite the task being active.

### Ruled out / tried

- **The FSD code itself, line by line.** `fsdStart`, the `fsdAdjust` handler
  (speed/style `0` = "keep current", re-issues the task with stored values),
  the takeover watcher, and all server verdict paths have been read and are
  correct as written. The core call matches the known-working public
  Bucko_autopilot resource exactly (single Longrange call, style 786603).
- **Driving styles:** 447 → 2883755 (786603 + UseSwitchedOffNodes) →
  1076625579 (+ ForceJoinInRoadDirection) → 1076626091 (+ AllowGoingWrongWay,
  current, untested). No change in the crawl.
- **`SetDriveTaskCruiseSpeed` / `SetDriveTaskMaxSpeed` envelope calls** were
  called after every task issue; removed in the current build (Bucko parity —
  and `SetDriveTaskMaxSpeed` doesn't appear in the Cfx native list; the
  documented ceiling native is `SetDriveTaskMaxCruiseSpeed`). Untested since
  removal.
- **The framework's vehicle systems (bs_vehicles):** its parts/wear system
  defaults unregistered cars to 54–96% part health (engine power multiplier
  floor 0.45 — not a crawl), fuel for found cars is random 10–65% with an
  engine-splutter branch only ≤ 8%. Neither explains ~1 m/s.
- **Other resources:** a full-server grep found no other resource calling
  `SetDriveTaskCruiseSpeed`, `AddRoadNodeSpeedZone`, or
  `SetDriveTaskDrivingStyle`.
- **Zombies/traffic braking:** test drives ran with 0 peds nearby.

### Leading hypothesis (untested)

**bs_vehicles' scroll-wheel throttle** (`resources/[beyond]/bs_vehicles/client/cl_cruise.lua`
in the original — not included here). If enabled on the driver's client
(persistent KVP `bs_wheelthr_on`) with its level scrolled below 0, it injects
`SetControlNormal(0, 72, …)` (brake) every frame while the player isn't
pressing W/S. That fits the observed symptoms: forward crawls (brake drag),
reverse is fast (brake input is reverse throttle at a stop), manual driving
is fine (injection pauses while W is held), FSD "turns off" (the injected
brake can trip the takeover watcher). The current build auto-disables that
feature during FSD drives via bs_vehicles' own settings export and restores
it afterwards — **not yet test-driven**.

### Built, awaiting a test drive

- **Raw-drive bisect:** `juno-admin:rawDrive` issues the bare native task
  with zero FSD machinery (no state, no watcher, no supervision).
- **Companion A/B harness:** `juno-admin:compDrive` gives the companion NPC
  ped the identical drive task in his own car. NPC-fast + player-crawl would
  isolate the fault to the player control layer; NPC-crawl too would clear
  it. (Needs a player connected — FiveM runs ped brains on a nearby client;
  on an empty server nothing animates.)
- **Destination snapping:** goto targets are snapped to the closest vehicle
  node in `fsdStart`.
- The sense/telemetry feed reports the car's gear, RPM, fuel level, engine
  state and entity max speed, plus whether the wheel-throttle is enabled —
  though for reasons unknown the vehicle block has not been appearing in the
  owner's reports (the code is in `buildReport`, pcall-wrapped; possibly
  stale client files).

`RESEARCH.md` is a web-research report on this symptom (Cfx forum threads,
native docs, working autopilot sources) with a ranked cause list and
discriminating experiments.

## Files

- `client.lua` — everything client-side. FSD: search for `FSD` (state table
  ~line 570 onward: `fsdStart`, takeover watcher, `fsdGo`/`fsdWaypoint`/
  `fsdCruise` handlers, F5 menu, `fsdAdjust`, raw-drive + companion-drive
  test harnesses). Telemetry: `buildReport`.
- `server.lua` — API routes (`doFsd` ~line 400), FSD sessions + supervision
  triggers + D1/vision calls (~lines 550–800), the gazetteer, owner check.
- `fxmanifest.lua` — resource manifest (ox_lib is a dependency for the menu).

Environment: FXServer build 38781, ox_lib 3.24.0 (pinned), BS19 v1.1.0
framework, screenshot-basic for the vision frames.
