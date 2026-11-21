<div align="center">

<img src="design/voidhub-logo.png" width="112" alt="Silver VoidHub V on black" />

# VoidHub

**A single-file Roblox client UI library by von63rd.**

[![Luau](https://img.shields.io/badge/runtime-Luau-E6E6E6?style=flat-square&labelColor=191919)](Source.lua)
[![Version](https://img.shields.io/badge/version-1.2.0-E6E6E6?style=flat-square&labelColor=191919)](#metadata)
[![License](https://img.shields.io/badge/license-MIT-E6E6E6?style=flat-square&labelColor=191919)](#license)

[Quick start](#quick-start) · [Controls](#tabs-groupboxes-and-controls) · [Appearance](#appearance) · [Files](#repository-layout)

</div>

---

VoidHub is a Luau UI library for Roblox client executor scripts. It gives you a window with tabs, sub-tabs, groupboxes, native controls, search, flags, configuration helpers, themes, responsive sizing, notifications, and a draggable minimized island.

It is distributed as readable Lua source rather than a Studio project. Load `Source.lua`, create a window, and add the UI your script needs. The bundled `Example.lua` is a standalone interface showcase; its controls demonstrate UI behavior only and do not automate gameplay.

## Quick start

Run this in a compatible client executor for an experience you own or are authorized to test:

```lua
local Library = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/voidhub9-dotcom/Aqua/main/Source.lua"
))()

local Window = Library:CreateVoidHubWindow({
    Name = "VoidHub",
    LoadingSubtitle = "by von63rd",
})

local Main = Window:CreateTab({
    Name = "Main",
    Icon = "layout-grid",
})

local Controls = Main:CreateGroupbox({
    Name = "Controls",
    Side = "Left",
})

Controls:CreateToggle({
    Name = "Enabled",
    Flag = "Demo_Enabled",
    CurrentValue = true,
    Callback = function(value)
        print("Enabled:", value)
    end,
})

Controls:CreateSlider({
    Name = "Intensity",
    Range = { 0, 100 },
    Increment = 5,
    CurrentValue = 65,
    Suffix = "%",
})

Window:CreateAppearanceTab({ Name = "Appearance", Icon = "palette" })
Window:SelectTab(Main)
```

The enhanced factory defaults to **VoidHub**, the monochrome `VoidHub` palette, and the silver V logo `rbxassetid://101833678008843`. Use `Icon` (or `Image`) to override the logo. A saved player theme can still take precedence, and the default config folder remains `AquaHub` so the rebrand does not move existing data.

### Standalone showcase

`Example.lua` contains the library and can be loaded independently:

```lua
loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/voidhub9-dotcom/Aqua/main/Example.lua"
))()
```

The showcase does not require a second copy of `Source.lua`. It demonstrates selected controls and appearance features without gameplay automation.

The [VoidHub UI mockup](design/voidhub-ui.svg) shows normal and compact layouts plus the opening effect treatment. It is a design reference, not a Roblox client screenshot.

## Tabs, groupboxes, and controls

Create tabs on the window, then place groupboxes on a tab. Groupboxes can use `Side = "Left"` or `Side = "Right"`; controls added directly to a tab are full-width cards.

```lua
local Settings = Window:CreateTab({ Name = "Settings", Icon = "settings" })
local Left = Settings:CreateGroupbox({ Name = "Preferences", Side = "Left" })
local Right = Settings:CreateGroupbox({ Name = "Actions", Side = "Right" })

Left:CreateDropdown({
    Name = "Mode",
    Options = { "Safe", "Balanced", "Fast" },
    CurrentOption = "Balanced",
    Flag = "Mode",
})

Left:CreateInput({
    Name = "Label",
    PlaceholderText = "Type a label",
    Flag = "Label",
})

Right:CreateButton({
    Name = "Print status",
    Callback = function()
        print("VoidHub is ready")
    end,
})

Right:CreateKeybind({
    Name = "Toggle key",
    CurrentKeybind = "RightControl",
    Flag = "ToggleKey",
})
```

Common constructors include:

- `CreateButton` and `CreateButtonRow`
- `CreateToggle`
- `CreateSlider` and `CreateStepper`
- `CreateDropdown` and `CreateOrderList`
- `CreateInput`, `CreateKeybind`, and `CreateColorPicker`
- `CreateLabel`, `CreateParagraph`, `CreateSection`, and `CreateDivider`
- `CreateStatus`, `CreateStatuses`, `CreateStatusList`, and `CreateProgress`
- `CreateTable`, `CreateLog`, and `CreateImage`

Most value controls accept `Name`, `Desc`, `Tooltip`, `Visible`, `Disabled`, `DependsOn`, and a unique `Flag`. Handles generally expose `Set`, `Get`, visibility, disabled, dependency, tooltip, and destroy methods; collection and manager handles have their own documented methods. Use the aliases in `llms.txt` when you need a compact constructor or handle reference.

### Sub-tabs and managers

Tabs can contain sub-tabs. Add groupboxes and controls to the selected sub-tab after creating one. Built-in managers avoid duplicating configuration or theme UI:

```lua
Settings:CreateConfigManager({ Side = "Left" })
Settings:CreateThemeManager({ Side = "Right" })
```

`Window:SelectTab(tab)` and `Tab:SelectSubTab(subTab)` accept an object, an exact name, or a one-based index. The selected tab has its own marker and the incoming page animates once. The window runs a brief edge sheen on opening or restoring; pass `OpenEffects = false` or call `Window:SetOpenEffects(false)` to disable the sheen without changing the window transitions.

## Flags and configuration

Give saveable controls unique flags within each window. Flagged controls are available through the compatibility map and can be stored by native configuration APIs:

```lua
local Enabled = Controls:CreateToggle({
    Name = "Enabled",
    Flag = "MyHub_Enabled",
    CurrentValue = false,
})

Enabled:Set(true, true) -- second argument skips the callback
print(Enabled:Get())
```

Window-scoped flag maps are available as `Window.Flags`. `Library.Flags` remains the latest-registered compatibility map, so code that already reads `Library.Flags.SomeFlag` continues to work. Prefer the window-scoped map when working with a specific window.

Native configuration calls include `SaveConfig`, `LoadConfig`, `ListConfigs`, `DeleteConfig`, `ExportConfig`, `ImportConfig`, autoload helpers, and the config manager. Use a clear `FolderName` in `ConfigurationSaving`:

```lua
local Window = Library:CreateVoidHubWindow({
    ConfigurationSaving = { FolderName = "MyHub" },
})
```

**Configuration caveat:** `ConfigurationSaving.Enabled` is currently not enforced by the implementation. Setting it to `false` must not be treated as a switch that disables file operations. Explicit native config calls depend on executor file APIs such as `readfile` and `writefile`; configure and call those APIs deliberately.

## Appearance

Appearance methods attach to windows created by `CreateVoidHubWindow` or its legacy aliases. The optional appearance tab exposes theme selection, background styling, sizing, density, and profile import/export.

```lua
Window:CreateAppearanceTab({ Name = "Appearance", Icon = "palette" })

Library:SetTheme("VoidHub")
Window:SetUIScale(1.1)
Window:SetAdaptiveSize(true)

local profile = Window:ExportAppearance()
if profile then
    print("Appearance profile exported")
end
```

### Themes

The new Aqua presets are:

| Preset | Character |
| --- | --- |
| `Aqua` | Blue `#38BDF8` accent on navy `#07111F`; the default enhanced theme |
| `Aqua Ice` | A lighter, cooler blue variation |
| `Aqua Mono` | A restrained neutral variation |

Native theme presets remain available as well. Select a preset or register a partial custom palette:

```lua
local ok, err = Library:RegisterTheme("My Aqua", {
    Accent = "#7DD3FC",
    AccentDark = "#0C4A6E",
})

if ok then
    Library:SetTheme("My Aqua")
else
    warn(err)
end
```

`RegisterTheme` returns `true`, or `false, error`. Palette keys are `Background`, `Surface`, `Surface2`, `Surface3`, `Stroke`, `StrokeHover`, `Accent`, `AccentDark`, `Text`, `Muted`, `Success`, `Warning`, and `Error`. Values may be `Color3` values or six-digit hex strings; omitted keys inherit the current theme.

### Backgrounds and profiles

```lua
local ok, err = Window:SetBackgroundStyle({
    Source = "Cyanic",
    Transparency = 0.25,
    Tint = "#FFFFFF",
    ScaleType = "Crop",
    Dim = 0.2,
})

local style = Window:GetBackgroundStyle()
local json, exportErr = Window:ExportAppearance()
-- Window:ApplyAppearance(json) restores a table or JSON profile.
```

`Source` can be a built-in preset, accessible Roblox asset ID, supported URL/file source, or `"None"`. `ScaleType` accepts `Crop`, `Fit`, `Tile`, or `Stretch`; `TileSize` dimensions are limited to 1–4096. Invalid or unresolved sources preserve the previous background. URL, local-file, and custom-asset support depends on the executor and image permissions.

Appearance profiles contain theme colors, background style, UI scale, adaptive sizing, density, and corner radius. They are explicit export/import data: profiles are not automatically written to disk and do not contain control flags, credentials, or gameplay state. Themes, density, and corner radius are shared by windows in one library instance; backgrounds are per-window.

## Capabilities and safety

VoidHub is a client-side UI library, not a gameplay automation package. The demo only changes interface state. Use scripts only in experiences you own or have permission to test, and keep callbacks limited to behavior you intend to run.

Basic loading requires executor support for `loadstring` and `game:HttpGet`. Native configs need file APIs. Clipboard actions need a clipboard API. URL/file images and custom fonts may need request, file, and custom-asset APIs. Unsupported features should be treated as unavailable rather than assumed portable across executors.

Adaptive sizing fits the available viewport, including touch layouts; it is not physical display-DPI detection. Callbacks run in the client context, so validate external data and keep long-running work off the immediate UI callback path.

## Metadata

```lua
Library.VoidHub.Version        -- "1.2.0"
Library.VoidHub.Author         -- "von63rd"
```

The primary factory is `Library:CreateVoidHubWindow(options)`. `Library:CreateAquaHubWindow`, `Library:CreateKawiXDWindow`, and `Library:CreateNullFireWindow` remain compatible aliases. Their metadata aliases still work, Aqua presets remain available, and appearance profiles keep format version 1.

The native `Library:CreateWindow(options)` API remains available when you want the base window without the enhanced appearance methods. For new scripts that need appearance helpers, use `CreateVoidHubWindow`.

## Repository layout

The distribution has exactly four root files:

| File | Purpose |
| --- | --- |
| [`Source.lua`](Source.lua) | Complete VoidHub library and appearance extension |
| [`Example.lua`](Example.lua) | Standalone UI showcase with the library embedded |
| [`Readme.MD`](Readme.MD) | Installation, usage, API overview, and license |
| [`llms.txt`](llms.txt) | Compact API guidance for coding assistants |

Repository: [voidhub9-dotcom/Aqua](https://github.com/voidhub9-dotcom/Aqua)

## License

The four distributed files are provided under the MIT License.

```text
MIT License

Copyright (c) 2026 voidhub9-dotcom

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
