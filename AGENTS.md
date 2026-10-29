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
- `getBlockIndex()` rebuilds every 0.5 s from `collectionService:GetTagged('block')`, keeping
  only `BasePart`s with `Size == Vector3.one * 3`, keyed by grid position.
- `getPlacedBlock(pos)` (base.lua) is the module-facing wrapper: it takes a **world** position
  and returns `(instance, gridPosition)`. `sides` holds the six `Enum.NormalId * 3` world
  offsets, so `calculatePath` keys its maps in world space and hands back world positions.

**Known constraint:** the tag is applied to more than real blocks — logs, props and map
decoration carry it too, and they are filtered out by the size check. As of the last test,
2834 instances carried the tag and 931 passed the filter. Consequently `findBlock` returns nil
for anything off the 3-stud grid (beds, lucky blocks, iron ore). `bedwars.breakBlock` handles
this by falling back to the instance the caller passed in — keep that fallback if you touch
this area.

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

- Indent with **tabs**; files are **CRLF**. Match the surrounding file exactly when editing —
  replacements that assume `\n` will not match.
- Every module needs a `Tooltip`.
- Modules that depend on executor capabilities gate at the very top:
  ```lua
  if ce then return end
  ```
  This is valid because each module is wrapped in `run(function() … end)`, so the `return` only
  exits that module. `NoClickDelay`, `Reach`, `ProjectileAimbot`, `FastBreak`, `KeepSprint`,
  `Velocity` and `NoSlowdown` currently do this.

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
