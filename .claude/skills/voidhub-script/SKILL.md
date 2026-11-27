---
name: voidhub-script
description: Build, test and deliver a complete Roblox executor script (auto farm, auto play, combat, ESP, movement, game hub) on the VoidHub UI library, testing every feature live one by one. Use whenever the user asks for a script, hub, GUI, cheat or feature for a Roblox game, or mentions VoidHub.
---

# VoidHub script builder

A full workflow for building game scripts on the VoidHub UI library. It works for Claude Code and any other AI: read this whole file first, then `llms.txt` for the UI API.

The job is not done when the code is written. It is done when every feature has been tested live in the game, one at a time, and the user has the final `.txt` file.

---

## 0. Hard rules (never break these)

1. **Anti-AFK first.** Before anything else (before exploring, before loading scripts), turn anti-AFK on. Turn it back on after every teleport, rejoin or server hop, because a new place means a new client.
2. **No GitHub, no pushing.** Don't commit, push, open pull requests or upload the script anywhere. Don't load test builds from GitHub raw links. Run the script straight in the client from its source text (the executor tool's content or paste mode), and deliver it as a local `.txt` file.
3. **No persistence.** No `queue_on_teleport`, auto-execute folders or anything that survives a teleport unless the user asks for it.
4. **The name is "VoidHub".** The window `Name`, `Title` and `LoadingTitle` are always `"VoidHub"`.
5. **No comments in the delivered file.** Clean code only.
6. **Never invent game data.** Every remote name, payload, attribute, path or place ID comes from the live game (decompiled code, spied traffic, probes). If something isn't found yet, the feature stays visibly unfinished and you say so.
7. **Honest status.** Never say a feature works unless you watched it work live. "Written but untested" is a valid answer; a fake "done" is not.
8. **Don't stop half way.** If the user is away and asked you to keep testing, keep going: poll the client, fix, retest. Report at milestones.

---

## 1. Session start checklist

Do these in order, every time:

1. **Anti-AFK on** (the executor bridge's anti-AFK tool, or the in-script fallback in section 5).
2. List the connected clients and pick the right one. Multiple clients: set the active one explicitly.
3. Get the game info: `game.PlaceId`, `game.GameId`, place name, `game.JobId`.
4. Get the player state: character location, health, team, leaderstats, visible GUIs.
5. Check the executor's capabilities (`hookmetamethod`, `decompile`, `getgc`, `setthreadidentity`, `firesignal`, screenshots). Some tools are missing on mobile executors; plan around what exists.

If the client disconnects (teleport, kick, crash), poll every 15 to 30 seconds until it's back, then rerun the checklist from step 1.

---

## 2. Read the UI library

- `llms.txt`: every constructor, option, handle and rule. This is the source of truth.
- `Source.lua`: check rare options here before relying on them.
- `Example.lua`: a working demo.
- `Scripts/*.lua`: finished hubs (`TheForge.lua`, `Hoops.lua`). Copy their structure, unload logic and loop style.

Load line inside scripts:

```lua
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/voidhub9-dotcom/VoidHub-UI/main/Source.lua"))()
```

(Loading the UI library itself this way is fine. The rule against GitHub is about your own script and test builds.)

---

## 3. Reverse engineer the game before writing features

Never guess. For each feature the user wants, find out how the game does it.

### 3.1 Map the systems
- List `ReplicatedStorage` remotes grouped by service (many games use folders like `Remotes`, `Events`, `Aero.AeroRemoteServices`, `Knit.Services`, `Packages._Index`).
- List the important workspace folders (mobs, ores, items, characters, balls, NPCs, zones).
- Read the local character's attributes and the folders under it. Watch which ones change while the player acts.
- Find the controllers and modules in `PlayerScripts` and `ReplicatedStorage` (input, movement, combat, UI, data).

### 3.2 Decompile the game's own input code
This is the most reliable source. The keyboard, mobile, gamepad and menu-button modules show the exact remote and payload a real press sends. Copy them exactly, including field names and value types (`{ Shoot = true, Input = "E" }` is not the same as `{ Shoot = true, UseSpace = true }`).

### 3.3 Spy and trace
- Run a remote spy while the player does one manual action, then read the captured calls.
- Trace activity (attributes, GUI, stats, position) for 5 to 10 seconds around that action.
- Decompile the module that fired it and read only the relevant lines.

### 3.4 Probe safely
- Small read-only snippets that return compact values, never whole instances.
- `pcall` around every Roblox call.
- Store long results in `getgenv()` and read them back later instead of blocking one call for minutes.

### 3.5 Traps seen in real games
- **Proxy bodies.** The visible character can be anchored while a separate part (for example `workspace.ProxyCharacter`) does the real physics. Measure position and velocity on the part that moves.
- **Characters outside Player.Character.** Some games keep them in `workspace.Characters.<Name>`.
- **ObjectValues instead of attributes.** The holder of a ball or item may be `obj.Attributes.Character.Value`, not `obj:GetAttribute("Character")`.
- **Held modifiers.** A held key or state (block, guard, aim) changes what another key does. Release it before firing the next action.
- **Server-locked states.** During dribbles, stuns or animations (`CanMove = false`, `Action = "Dribbling"`), input is ignored. Wait for the state to end, fire, then confirm the action really started and retry if not.
- **Camera-relative movement.** Steering by setting a move vector often makes the character spin. Hook the game's move-vector function and return a world-space direction instead.
- **Slot, profile and menu state.** Teleports such as a private gym may need a valid save slot or build. Read the profile data before calling them.
- **Wrong target.** Check team, side or goal attributes rather than "nearest" guesses.

---

## 4. Plan the features

Before coding, write a short table for the user:

| Feature | How the game does it (remote/payload/attribute) | Evidence | Status |
| --- | --- | --- | --- |

Status is one of: found, partly found, unknown. Unknown features are built gated and labelled unfinished in the UI, never faked.

---

## 5. Script layout

```lua
if getgenv().VoidHubGame then pcall(getgenv().VoidHubGame.Unload) end
local Hub = { Running = true, Conns = {}, Log = {} }
getgenv().VoidHubGame = Hub

local Players, RunService, VirtualUser = game:GetService("Players"), game:GetService("RunService"), game:GetService("VirtualUser")
local LP = Players.LocalPlayer
local function conn(c) table.insert(Hub.Conns, c) return c end
local function log(s) table.insert(Hub.Log, 1, os.date("%X ") .. s) if #Hub.Log > 50 then table.remove(Hub.Log) end end

conn(LP.Idled:Connect(function() VirtualUser:CaptureController() VirtualUser:ClickButton2(Vector2.new()) end))

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/voidhub9-dotcom/VoidHub-UI/main/Source.lua"))()
local Window = Library:CreateVoidHubWindow({
    Name = "VoidHub", Title = "VoidHub", LoadingTitle = "VoidHub",
    ToggleUIKeybind = "RightControl",
    ConfigurationSaving = { Enabled = true, FolderName = "VoidHub_<Game>" },
})
Hub.Window = Window
local function F(flag) local f = Window.Flags[flag] return f and f.Value end

task.spawn(function()
    while Hub.Running do
        local ok, err = pcall(function()
        end)
        if not ok then log("loop: " .. tostring(err)) end
        task.wait(0.1)
    end
end)

function Hub.Unload()
    Hub.Running = false
    for _, c in ipairs(Hub.Conns) do pcall(function() c:Disconnect() end) end
    pcall(function() Window:Destroy() end)
    getgenv().VoidHubGame = nil
end
Window:LoadAutoload()
return Hub
```

Structure rules:
- Tabs go by area (Farm, Combat, Movement, Visuals, Misc). Use sub-tabs when a tab gets long; groupboxes hold related options.
- Every feature is a flagged element read through `F("Flag")`, so configs save it. Flags are unique.
- Sliders for every tunable number (range, delay, smoothing, cooldown) with sane defaults.
- A Misc tab with: anti-AFK toggle (on by default), auto rejoin on kick, a live log or status panel, and an Unload button.
- Re-running the script unloads the old copy first. Unload restores every `hookmetamethod`, `BindToRenderStep`, patched module function and created instance.
- Respect Luau's 200-locals limit in big files: group state in tables and use `do ... end` blocks.

---

## 6. Feature engineering rules

- **Reuse the game's flow.** Fire the same remotes in the same order with the same payloads, and wait for the server between steps.
- **Confirm every action.** After firing, check that the game reacted (attribute changed, item gained, animation state, server event). Retry a bounded number of times, then back off and log.
- **Cooldowns** on everything that can spam: attacks, shots, passes, purchases, teleports.
- **Bounded loops.** Every `while` has a timeout; every search has a limit.
- **Validate targets.** Exists, alive, right team, in range, not the local player, finite numbers.
- **Movement.** Prefer walking or steering through the game's own movement; teleport only when the game allows it, and check the server didn't snap you back.
- **Ping.** Read ping from `Stats.Network.ServerStatsItem["Data Ping"]` (fall back to `LocalPlayer:GetNetworkPing()`). Use it for timing and prediction (lead targets by velocity × ping).
- **Hooks.** Save the original before hooking, let your own calls bypass the hook (a flag such as `Timing.ours`), and restore on unload.
- **UI-only features** (ESP, overlays) clean up their drawings and instances when toggled off.
- **Humanize auto features** with optional random delays and mistake chances.

---

## 7. Test every feature live, one by one

This is the core of the skill. Never test everything at once.

### 7.1 Run the script without GitHub
- Run the current local source directly in the client (executor tool content or paste mode). Don't push, and don't load from a raw link.
- After loading, check that `getgenv().VoidHubGame` exists and the window opened. If the load errored, read the console, fix it and rerun.

### 7.2 Test loop for each feature
For feature N:
1. **Anti-AFK still on?** Check.
2. **Baseline:** record the relevant state with the feature off (position, stats, attribute values, inventory, velocity).
3. **Enable only this feature** through `Window.Flags.<Flag>:Set(true)`. Leave everything else off.
4. **Watch:** record attribute changes, remote responses, server events and log lines into a `getgenv()` table for 15 to 90 seconds.
5. **Measure:** compare against the baseline with numbers (items gained per minute, studs moved, hits landed, grades received, success/fail count).
6. **Disable** it and confirm it fully stops (no leftover movement, held keys or loops).
7. **Verdict:** works / partly / fails, with the numbers. If it fails, find the cause from the data (decompile again if needed), fix it, rerun the script from source and retest. Don't move on until it works or the blocker is clearly stated.
8. Log the result in a running test table.

### 7.3 Then test combinations
After every feature works alone, test the ones meant to run together (auto farm plus auto sell, auto play plus sprint). Check that they don't fight each other.

### 7.4 Test in real conditions
- Test where the feature will really be used (live match, real server, private server alone), not only in a lobby.
- If the user asks for a specific mode or place, navigate there with the game's own teleport remotes, then rerun the session checklist (anti-AFK first).
- Keep polling while waiting for matches or teleports; don't give up after one timeout.

### 7.5 Test report format

| # | Feature | Result | Evidence (numbers) | Fixes made |
| --- | --- | --- | --- | --- |

---

## 8. Deliver

- Strip comments, set the hub name to "VoidHub", and check there is no `queue_on_teleport` or other persistence.
- Save the final script as a `.txt` file in the scratchpad or working folder and send it to the user.
- No GitHub push, no upload.
- Final message:
  1. What's in the file.
  2. The test table: which features were verified live, with numbers.
  3. What is untested or blocked, and exactly why.
  4. The shortest next step.

---

## 9. Talking to the user

- Lead with the result.
- Short updates while working ("testing Auto Farm now, results in 60 seconds").
- No lectures, no ban warnings.
- When the user is away, keep testing and summarize when they're back.
