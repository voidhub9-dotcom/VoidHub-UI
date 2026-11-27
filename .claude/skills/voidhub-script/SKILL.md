---
name: voidhub-script
description: Build a complete Roblox executor script (auto farm, combat, ESP, game-specific hub) on the VoidHub UI library. Use whenever the user asks for a script, hub, GUI or feature for a Roblox game, or mentions VoidHub.
---

# VoidHub script builder

Builds game scripts on the VoidHub UI library from this repo. Works for Claude Code and any other AI: read this file, then `llms.txt` for the full UI API.

## 1. Read the API first

- `llms.txt` — every constructor, option and handle. Treat it as the source of truth; check rare options against `Source.lua`.
- `Example.lua` — a working demo script.
- `Scripts/` — finished hubs (`TheForge.lua`, `Hoops.lua`). Copy their structure.

Load line, always:

```lua
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/voidhub9-dotcom/VoidHub-UI/main/Source.lua"))()
```

## 2. Learn the game before writing features

Never guess remotes, paths or attribute names. With a Roblox MCP/executor bridge:

1. Identify the place (`game.PlaceId`, game info) and which client is active.
2. Find the systems: `ReplicatedStorage` remotes (list services and their children), character attributes, workspace folders.
3. Decompile the client's own input/UI modules (keyboard, mobile, gamepad, menu buttons). They show the exact remote and payload the game sends. Copy those payloads exactly.
4. Spy remotes while the user does one manual action, then reproduce it.
5. Probe values with small read-only snippets that return compact data, and use `pcall` around every Roblox call.

Typical traps (found in real games):
- The visible character model can be anchored while a separate proxy part does the real physics. Measure position on the part that moves.
- Values may live in an `ObjectValue` inside a folder (`ball.Attributes.Character`), not in `:GetAttribute`.
- A held modifier (e.g. HoldG for defense) changes what another key does. Release state before firing actions.
- Server-driven states (dribbling, CanMove=false) ignore input. Wait for the state to end and confirm the action actually started, retrying if needed.
- Movement input is often camera-relative. Hook the move-vector function to steer in world space instead of fighting the camera.

## 3. Script layout

```lua
if getgenv().MyHub then pcall(getgenv().MyHub.Unload) end
local Hub = { Running = true, Conns = {} }
getgenv().MyHub = Hub
local function conn(c) table.insert(Hub.Conns, c) return c end

local Library = loadstring(game:HttpGet(".../Source.lua"))()
local Window = Library:CreateVoidHubWindow({
    Name = "VoidHub", Title = "VoidHub", LoadingTitle = "VoidHub",
    ToggleUIKeybind = "RightControl",
    ConfigurationSaving = { Enabled = true, FolderName = "VoidHub_<Game>" },
})
local function F(flag) local f = Window.Flags[flag] return f and f.Value end

-- tabs > sub-tabs > groupboxes > elements, every option with a unique Flag

-- one main loop: task.spawn(function() while Hub.Running do ... task.wait() end end)

function Hub.Unload()
    Hub.Running = false
    -- restore every hook, metamethod, render step and patched module function
    for _, c in ipairs(Hub.Conns) do pcall(function() c:Disconnect() end) end
    pcall(function() Window:Destroy() end)
    getgenv().MyHub = nil
end
Window:LoadAutoload()
return Hub
```

Rules:
- The hub, window title and loading title are always **"VoidHub"**.
- Re-running the script must unload the previous copy first: restore `hookmetamethod`, `BindToRenderStep` and any patched module functions.
- Every feature is a flagged toggle/slider read through `F("Flag")`, so configs save it.
- Wrap each loop step in `pcall` and send errors to a log, so one failure doesn't kill the loop.
- Cooldowns on every remote spam (shots, passes, steals), and bounded loops with timeouts.
- No persistence: no `queue_on_teleport`, no auto-execute files, nothing that survives a teleport unless the user asks.
- No code comments in the delivered file.
- Use the built-in notifications, config and theme UI; don't rebuild them.

## 4. Test it live, one feature at a time

- Load the pushed file by commit hash (`raw.githubusercontent.com/<repo>/<sha>/Scripts/<Game>.lua`) so the test runs exactly what was pushed.
- For each feature: turn it on, record state changes (attributes, remote responses, positions), and compare off vs on with numbers.
- Long tests: store results in `getgenv()` and read them back later instead of one long blocking call.
- Keep anti-AFK on and re-enable it after every teleport.
- Report only what was observed. Mark anything untested as untested.

## 5. Deliver

- Commit to the working branch and push.
- Copy the script to a `.txt` file and send it to the user.
- Summary: what changed, what was verified live (with numbers), what is still unverified, and the next step.
