# VapeForSolara

Working notes for anyone (human or agent) making changes here. Read this before editing.

## Layout

| Path | What it is |
| --- | --- |
| `VapeForSolara/src/` | The **source**. This is what you edit. |
| `VapeForSolara/src/games/` | Per-place game folders; `bedwars/6872274481 - game/` is the main one. |
| `VapeForSolara/src/libraries/bedwars/` | `construct.lua`, `construct.json`, `compiler.lua`. |
| `VapeBundler/` | The build tool (Node, `helpers/*.js`). |
| `VapeCompiled/` | The **build output**. Generated — do not hand-edit. |
| `src/libraries/bedwars/compiler.lua` | Captures live game metadata into `construct.json` (run inside the executor). |

The output directory is what gets uploaded into the executor's workspace under `newvape/`:

```
newvape/main.lua, loader.lua
newvape/games/<placeId>.lua
newvape/guis/new.lua
newvape/libraries/bedwars/construct.lua
newvape/libraries/bedwars/construct.json
```

## Building

`VapeBundler/config.json` is **not in the repo** (gitignored), so `index.js` cannot be run
directly — it throws on `require('./config.json')`. `helpers/vars.js` also defaults
`DEST_PATH` to an empty string, which silently writes output to the project root. Always set
it explicitly. Run the helpers from `VapeBundler/`:

```bash
cd VapeBundler && node -e "
const fs=require('fs'), path=require('path');
const {VARS}=require('./helpers/vars.js');
VARS.IS_DEV=false;
VARS.DEST_PATH=path.resolve('../VapeCompiled');
const processGame=require('./helpers/processGame.js');
const processLibraries=require('./helpers/processLibraries.js');
const SRC=path.resolve('../VapeForSolara/src');
processLibraries(path.join(SRC,'libraries'));
const GAMES=path.join(SRC,'games');
for (const game of fs.readdirSync(GAMES)) {
  if (game.includes('-')) processGame(path.join(GAMES,game),game);
  else { const b=path.join(GAMES,game); for (const e of fs.readdirSync(b)) processGame(path.join(b,e),e); }
}
"
```

## How a game file is assembled

`helpers/processGame.js` concatenates, **in this order**:

1. `base.lua` — raw, unwrapped.
2. Every file in `Combat/ Blatant/ Render/ Utility/ World/ Inventory/ Legit/`, sorted by name,
   each wrapped as `run(function()` … `end)` **only if the file does not contain the literal
   `run(`**. (`AntiFall.lua`, `Fly.lua`, `Killaura.lua` contain it and are appended raw.)

**Scope consequence:** the wrapper is a chunk-level `run(...)` call placed *after* `base.lua`'s
declarations, so module files still see `base.lua`'s file-scope locals (`lplr`, `entitylib`,
`inputService`, `gameCamera`, `getWool`, `roundPos`, `getPlacedBlock`, `tween`, `color`,
`uipallet`, `prediction`, …). Module-file locals, however, stay private to that file — do not
try to share a helper between two module files by declaring it local in one of them.

`run()` is a `pcall` wrapper that reports `Module failed to load: …`. It only protects
**initialisation**; code running later in a `task.spawn`/`repeat` loop is *not* protected, so an
error there surfaces as a raw console error.

## Cross-chunk globals — `getgenv()`

`construct.lua` is loaded separately, via `loadstring` from `base.lua`:

```lua
local construct = loadstring(downloadFile('newvape/libraries/bedwars/construct.lua'))()
repeat task.wait() until construct ~= nil and construct.loaded
```

It is therefore a **different chunk** and cannot see `base.lua` locals. Anything it needs from
`base.lua` must be exported with `getgenv()` (`collection`, `getItem`, `getSword`, `getTool`,
`getWool`, `getPlacedBlock`, `getBlocksInPoints`, `roundPos`, `switchItem`, `store`, `bedwars`,
`remotes`, `sides`, `Reach`, `HitBoxes`, `InfiniteFly`, `TrapDisabler`, `vapeEvents`).

> If you add a `base.lua` local that `construct.lua` calls, export it. Forgetting this produces
> `attempt to call a nil value` at runtime with no obvious cause.

## `construct.lua` structure

```lua
local ce = ceCheck()          -- true on Solara/Xeno, false on full-featured executors
if not ce then
    run(function() … end)     -- hook the real remotes, real Knit controllers, real stores
    return {loaded = true}    -- ← early return: nothing below runs on a full executor
end

-- from here down: the emulation used on ce executors
```

Everything after that early return is the **emulated** game surface: `bedwars.BlockController`,
`bedwars.SwordController`, `bedwars.ProjectileController`, `bedwars.AppController`,
`bedwars.SoundManager`, `bedwars.BlockCpsController`, `bedwars.Client`, etc. Modules in
`games/bedwars/6872274481 - game/` are written against the **real** API, so these emulations
must stay API-compatible with the decompiled client — same method names, same argument order,
same return shapes.

**Nothing may depend on `require` returning the real game module.** On Solara `require` is a
stand-in, so an emulated surface has to be rebuilt from what the client can observe — tags,
attributes, parts, remotes, attributes on the local player — not from the game's own classes.
The decompiled source in `ReplicatedStorage.rbxts_include…block-engine` is the specification to
copy the *behaviour* from; calling into it is not an option.

Metadata (`ItemMeta`, `ProjectileMeta`, `QueueMeta`, `ShopItems`, `AppLayers`, `UILayers`,
`SoundList`, `CombatConstant`, …) is loaded from `construct.json` into `meta` near the top.
Regenerate that file with `compiler.lua` running in a live match; it is large (~1.7 MB).

## Block model

- Blocks are **3 studs**, and the API works in **two coordinate spaces**:
  - *grid* = world / 3, integer. `getBlockPosition(390, 24, 453)` is `(130, 8, 151)`.
  - *world* = grid * 3. `getWorldPosition(130, 8, 151)` is `(390, 24, 453)`.

  The real engine's store, every `blockRef.blockPosition`, the block selector's
  `placementPosition`, and therefore all module code use **grid**. Positions used for
  raycasts, magnitudes and `hitPosition` use **world**. Verified against the live client:
  `getBlockPosition(part.Position)` on a 3-stud block returns `part.Position / 3`.
- `roundBlockPos(pos)` converts world → grid (no multiply). `findBlock(pos)` takes grid and
  indexes the store directly, so never round a value twice.
- **The store is incremental, not rebuilt.** It is a port of `basic-block-store` +
  `client-block-engine.startBlockReplication`: every tagged part is registered once into
  `blocks[cell] = part` (one entry per cell it covers) plus `blockRoots[part] = rootCell`, and
  it is kept in step by `GetInstanceAddedSignal('block')`, a `Size` connection (the server
  re-cuts a merged part when a neighbour is placed) and `AncestryChanged`. Do **not** put a
  periodic `GetTagged` scan back: it allocates per cell, goes blind between rebuilds, and was
  the source of both the lag and the stale answers.
- The store exposes the real surface — `getBlockAt`, `getBlockData` (the `Workspace.BlockData`
  folder entry, not the part), `getBlocksInRegion3`, `getAllBlocks`, `getAllBlockPositions`,
  `setBlock`, `setBlockRootPosition`, `getBlockRootPosition`, `removeBlockInstance`.
  `bedwars.BlockController` likewise keeps `getBlockPosition` / `getWorldPosition` /
  `snapPosition` / `getStore` / `getHandlerRegistry` (with `getContainedPositions` and
  `getBlockMeta`) / `getAnimationController` (`PLACE_BLOCK` is 0, `BREAK_BLOCK` is 1) /
  `getCharacter` / `getBlockInstanceFromChild` / `isAllowedPlacement` / `calculateBlockDamage`.
- **Placement goes through `isAllowedPlacement` first.** The emulated gate rejects an occupied
  cell, a cell with a placement already in flight (`pendingPlacements`, the stand-in for the
  local block the real placer creates before it sends) and a cell inside the player's head.
  The old 20/s throttle is gone; do not re-add one — the gate is the rate limit.
- `mouseBlockInfo` must be present and consistent: `target.blockRef.blockPosition` is the cell
  being built **against** (grid), `hitPosition` is a world point on the face that touches the
  new cell, `hitNormal` is that face, and `placementPosition` is the new cell (grid).
- **Blocks are merged, so never key the store by instance centre.** The game collapses runs of
  identical blocks into one greedy part (attribute `GreedyBlock`): one `grass` part can cover
  30×6×9 studs, and a bed is a 3×3×3 `MeshPart`. In a live match ~2275 parts tagged `block`
  cover ~103k cells. Filtering by `Size == Vector3.one * 3` (which the index used to do) hides
  most of the map — that is what made Breaker work on beds and nothing else.
- `bedwars.breakBlock` targets the part's **nearest cell to the player**, not the part's own
  position. On a merged part the centre cell is surrounded by the rest of the same part, so
  `calculatePath` never finds an air neighbour and the breaker silently gives up — that is why
  Breaker only ever reached beds and single blocks.
- `BlockController:isBlockBreakable` is not "true": the engine rejects a `NoBreak` part, and the
  game hooks the check to cancel `Team<N>NoBreak` (your own bed — verified live: every bed part
  carries `Team<N>NoBreak` matching its `TeamId`, and the local player's `Team` attribute is the
  same number) and `Player<UserId>NoBreak` (blocks you may not break).
- One break swing at a time. `bedwars.breakBlock` is called at the module's update rate, so a
  fresh animation track per call stacks up and the arm keeps swinging after the target leaves
  range; the emulation keeps a single swing and stops both the player and the viewmodel track.
- `getPlacedBlock(pos)` (base.lua) is the module-facing wrapper: it takes a **world** position
  and returns `(instance, gridPosition)`. `sides` holds the six `Enum.NormalId * 3` world
  offsets, so `calculatePath` keys its maps in world space and hands back world positions.

- **Never raycast for a block without skipping `gamecore_GameQueryIgnore`.** The game parents
  its own visuals into Workspace (the block highlight box, break effects, lobby props) and
  marks each with that attribute so its queries step over them
  (`GameQueryUtil:isQueryIgnored`). They are ordinary queryable parts, so a plain
  `workspace:Raycast` lands on the highlight box hovering over the highlighted block — that is
  why the emulated selector used to answer for a different block than the one on screen.
- The emulated selector resolves a **greedy** part (`GreedyBlock` attribute) the way the real
  one does: the cell comes straight from the hit point via `roundBlockPos`, never from walking
  `getContainedPositions` — that walk is thousands of cells on a 30×6×9 part, at click rate.
  Everything else (beds, ore) goes through the nearest contained cell.
- `BlockPlacer:placeBlock(cell, mouseInfo)` takes **grid**. Callers that pass no mouseInfo
  (AutoClicker, Schematica) get one filled in from the player's own highlight: `getMouseInfo(0)`
  is used only when its `placementPosition` is the cell being placed, so the placement carries
  the same target and face the player can see highlighted.

**Only cells are keys.** `findBlock` answers for every cell a part covers, so beds, lucky
blocks and iron ore on the 3-stud grid are found like any other block. `bedwars.breakBlock`
keeps its fallback to the caller's instance only for parts that are not tagged `block` at all —
keep it if you touch this area, and keep the path cache short-lived (`calculatePath` caches for
0.3 s), since a cached path to a block that has since been broken parks the breaker on an
empty cell.

## Module API

```lua
local Thing
Thing = vape.Categories.Blatant:CreateModule({
    Name = 'Thing',
    Function = function(callback) … end,
    Tooltip = '…'
})
Thing:CreateSlider({Name = '…', Min = 1, Max = 30, Default = 30, Suffix = '…'})
Thing:CreateToggle({Name = '…', Default = true, Darker = true, Function = …})
Thing:CreateTwoSlider({Name = 'CPS', Min = 1, Max = 9, DefaultMin = 7, DefaultMax = 7})
Thing:CreateDropdown({Name = '…', List = {'…'}})
Thing:CreateTextList({Name = '…', Function = …})
```

- Indent with **tabs**. Match the surrounding file exactly when editing — replacements that
  assume the wrong line endings will not match. Check before assuming: `construct.lua` is LF.
- **Do not break a method chain across lines** (`bedwars.X` / `:Get(…)` / `:CallServer(…)` on
  separate lines) and do not split a short `a and b or c` over three lines. Keep the chain on
  one statement — hoist the remote into a local if it gets long. `stylua`'s 120-column default
  would re-wrap both, so `stylua --check` reports those deliberate lines and nothing else on an
  otherwise clean file: read its diff, never "fix" it by re-wrapping.
- Every module needs a `Tooltip`.
- Modules that depend on executor capabilities gate at the very top:
  ```lua
  if ce then return end
  ```
  This is valid because each module is wrapped in `run(function() … end)`, so the `return` only
  exits that module. `NoClickDelay`, `Reach`, `ProjectileAimbot`, `FastBreak`, `KeepSprint`,
  `Velocity` and `NoSlowdown` currently do this.

## Emulation coverage

Checked against the live client (`@easy-games.block-engine` and the `TS` controllers) and the
emulated surface in `construct.lua`. A module only belongs in this table once the thing it
patches actually exists on the ce path.

| Module | On ce | Why |
| --- | --- | --- |
| NoClickDelay | works | patches `SwordController.isClickingTooFast`, which the emulation defines and the swing path calls |
| NoSlowdown | works | `SprintController:getMovementStatusModifier()` is emulated with `modifiers` / `addModifier` / `removeModifier` |
| Crosshair | works | no constant to patch, so it sets `ViewmodelController.crosshairImage`, the image the controller shows |
| UI Cleanup | works | hotbar app cannot be required on ce, so the rendered `PlayerGui` is cleaned instead and re-applied every 0.25 s (Roact resets the props it owns) |
| Velocity | works | already has a ce branch: it writes the `ConstantManager_kb*` attributes the real knockback module reads |
| ProjectileAimbot | feasible | the emulation provides `ProjectileController:calculateImportantLaunchValues` / `getLaunchPosition`; still needs `prediction` and `targetinfo` confirmed as globals the module can see |
| FastConsume | feasible | `ClickHold` is emulated, but it builds its bar inside `new()`; the hold has to go through `startClick` before the module's patch means anything |
| FastBreak | redundant | `setCooldown` lowers a cooldown the emulated `breakBlock` does not have — Breaker's Break speed is the throttle |
| KeepSprint | redundant | the constant picks which event clears `blockSprint`, and the emulation only sets it from movement modifiers |
| HitFix | redundant | the emulated `swingSwordAtMouse` already raycasts the way the fixed version does |
| Reach | no | mutates `CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE`, a client-side value the server does not trust |
| DamageIndicator | no | needs the real `DamageIndicator` table via `debug.getupvalue`; the emulation is a no-op function |
| WinEffect | no | needs `getconnections` on the `WinEffectTriggered` listener |
| AutoKit `block_kicker` | no | needs the real `BlockKickerKitController` |

`VapeCompiled/` is generated and updated by the build — never hand-edit or copy files into it.

## Verification

There is **no Luau toolchain in this repo** — no `luau`, `luau-analyze`, or usable `lua` (the
installed `lua` cannot parse `+=`, `//`, `continue`, or generic `for … in table`). Checks are
therefore:

1. Read the edited region back after writing.
2. Rebuild and grep the built artefacts in `VapeCompiled/` to confirm the change shipped.
3. Runtime confirmation has to happen in the executor. When something fails silently, ask for a
   probe rather than guessing — one `pcall`-wrapped print block that reports tag counts,
   `store.hand.toolType`, `isLayerOpen`, `isAlive` and `matchState` has resolved more here than
   any amount of static reasoning.

## Traps already hit (do not re-introduce)

- **Silent no-ops beat crashes.** A periodic `updateStore()` loop or a module's `repeat` loop
  dies permanently on its first error, and the module then does nothing with no error shown.
  Guard anything indexing `bedwars.ItemMeta[itemType]` — the table has **no metatable
  fallback**, so unknown item types return nil, not `{}`.
- **`table index is nil`** — always a `t[nil] = v` write; reads of `t[nil]` are harmless. Check
  lookups keyed by values derived from meta (`breakType`, `abilityId`, …).
- **Dijkstra:** air nodes and block nodes are tracked separately. `distances` only ever holds
  block positions, so writing an air position into `air[…]` makes `distances[node] < cost`
  compare nil against a number. Mark `air[node[2]]` (the parent block), never `air[side]`.
- **`createLocalProjectile`** must destroy its model on *both* impact and expiry; disconnecting
  the Heartbeat connection alone leaves instances in workspace forever.
- **Placement has to be throttled by hand.** The engine wraps every placement in
  `BlockEngine:isAllowedPlacement` and only places at its own cadence. Scaffold calls
  `bedwars.placeBlock` once per expand step per 0.03 s tick, so without the same gate the
  emulation fires dozens of blocking `PlaceBlock` invokes a second the moment placements start
  succeeding. `placeBlock` keeps a 0.05 s floor, remembers cells it filled for 0.5 s (the index
  lags 0.15 s, so a just-filled cell still looks empty), and does every yielding step — item
  switch, remote call — off the caller's thread with the result `pcall`ed.
- **Remote shapes differ.** `PlaceBlock` and `DamageBlock` are `RemoteFunction`s
  (`CallServer` → `InvokeServer`, and the result comes back directly — do not chain `:andThen`
  on it); `SwordHit`, `SwordSwingMiss` and the rest are `RemoteEvent`s. A placement is only
  accepted with `{blockType, position, blockData, mouseBlockInfo}`, where `mouseBlockInfo` is
  `{target = {blockRef, hitPosition, hitNormal}, placementPosition}` — without it the server
  cancels the placement, silently.
- **A missed swing still sends.** The real controller routes hits *and* misses through
  `attackEntity(nil, …)`: a miss plays the swing and fires `SwordSwingMiss`
  (`{weapon, chargeRatio}`, 20 a second server side). Skipping it desyncs the game's own swing
  bookkeeping, so `swingSwordInRegion` must not short-circuit on "no target".
- **`AppController:isAppOpen`** is an emulation: screen GUIs stay mounted while closed, so
  checking existence is not enough — check actual visibility, or `isLayerOpen` reports true
  during normal play and silently disables AutoClicker/TriggerBot/Killaura.
- **Placing a block** requires holding it. `bedwars.placeBlock` switches via `switchItem` before
  sending `PlaceBlock`, and it takes a **world** position.
- **Coordinate space** — sending a world position where the server expects grid (or the store
  keyed by world) makes `DamageBlock` answer `cancelled` and `PlaceBlock` do nothing, with no
  error anywhere. `bedwars.placeBlock` (world in) and `BlockPlacer:placeBlock` (grid in) are the
  two boundaries; everything string compared, cached or sent as a `blockRef` is grid.
- **`getBlocksInPoints`** must walk the store, not the `(2*range)^3` cube it covers: that was
  ~74k lookups per call and Scaffold makes several per 0.03 s tick.
