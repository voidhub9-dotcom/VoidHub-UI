if getgenv().SnowyHub then pcall(getgenv().SnowyHub.Unload) end
local Hub = { Running = true, Conns = {}, Log = {} }
getgenv().SnowyHub = Hub

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local PPS = game:GetService("ProximityPromptService")
local CollectionService = game:GetService("CollectionService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local VirtualUser = game:GetService("VirtualUser")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local function conn(c) table.insert(Hub.Conns, c) return c end
local function log(s) table.insert(Hub.Log, 1, os.date("%X ") .. tostring(s)) if #Hub.Log > 60 then table.remove(Hub.Log) end end
local function char() return LP.Character end
local function root() local c = char() return c and c:FindFirstChild("HumanoidRootPart") end
local function hum() local c = char() return c and c:FindFirstChildOfClass("Humanoid") end
local function coins() local l = LP:FindFirstChild("leaderstats") local c = l and l:FindFirstChild("Coins") return c and c.Value or 0 end
local function posOf(o)
	if not o then return nil end
	if o:IsA("BasePart") then return o.Position end
	if o:IsA("Attachment") then return o.WorldPosition end
	if o:IsA("Model") then return o:GetPivot().Position end
	return nil
end

local Places = {
	Locker = Vector3.new(-431, 83, 245),
	Lobby = Vector3.new(-336.5, 82, 269.3),
	Machine = Vector3.new(-101, 215, 765),
	Shop = Vector3.new(-332, 83, 179),
	Cameras = Vector3.new(-83, 155, 306),
	ElevatorF1 = Vector3.new(-228.4, 95.2, 170),
	ElevatorF2 = Vector3.new(-229.6, 148.3, 168.4),
	Colors = Vector3.new(-362.8, 82.6, 261),
}
local ShopKeys = { "EnergyDrink", "SpeedPotion", "NoiseMaker", "Molotov", "Radar", "Flashlight" }
local ColorNames = { "Blue", "Cyan", "Yellow", "White", "Black", "Green", "Red", "Orange", "Rainbow", "Vip", "Purple", "Pink" }

local Opt = { Speed = 100, SellAt = 3, FlySpeed = 50, ScrapMin = "Copper" }
local ScrapValue = { Copper = 1, Silver = 2, Gold = 3, Emerald = 6, Ruby = 8, Diamond = 10 }

conn(LP.Idled:Connect(function()
	pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton2(Vector2.new()) end)
end))

local oldNC
pcall(function()
	oldNC = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
		if Hub.Running and self == LP and getnamecallmethod() == "Kick" then return nil end
		return oldNC(self, ...)
	end))
end)

local busy = false
local stopMove = false

local function seq()
	local c = char()
	return c and c:GetAttribute("AntinoclipTeleportSequence")
end

local function glideTo(r, target, speed)
	local t0 = os.clock()
	local dist = (target - r.Position).Magnitude
	local limit = dist / speed + 2
	while Hub.Running and not stopMove and (r.Position - target).Magnitude > 0.6 and os.clock() - t0 < limit do
		local dt = RunService.Heartbeat:Wait()
		if not r.Parent then return false end
		local d = target - r.Position
		r.CFrame = CFrame.new(r.Position + d.Unit * math.min(d.Magnitude, speed * dt)) * r.CFrame.Rotation
		r.AssemblyLinearVelocity = Vector3.zero
	end
	return (r.Position - target).Magnitude <= 1.5
end

local function travel(target, within)
	within = within or 3
	for _ = 1, 3 do
		local r, h = root(), hum()
		if not (r and h) or h.Health <= 0 then return false, "no character" end
		if (r.Position - target).Magnitude <= within then return true end
		local wps
		for i = 0, 8 do
			local goal = target
			if i > 0 then local a = i * math.pi / 4 goal = target + Vector3.new(math.cos(a) * 5, 0, math.sin(a) * 5) end
			local path = PathfindingService:CreatePath({ AgentRadius = 1, AgentHeight = 4, AgentCanJump = true, AgentCanClimb = true, WaypointSpacing = 4 })
			local ok = pcall(function() path:ComputeAsync(r.Position, goal) end)
			if ok and path.Status == Enum.PathStatus.Success then wps = path:GetWaypoints() break end
		end
		local lift = h.HipHeight + r.Size.Y / 2
		local start = seq()
		if wps then
			for _, w in ipairs(wps) do
				if stopMove or not Hub.Running then return false, "stopped" end
				glideTo(r, w.Position + Vector3.new(0, lift, 0), Opt.Speed)
				if seq() ~= start then break end
				if (r.Position - target).Magnitude <= within then return true end
			end
		elseif (r.Position - target).Magnitude < 160 then
			glideTo(r, target + Vector3.new(0, lift * 0.5, 0), Opt.Speed)
			if seq() ~= start then return false, "reverted" end
		else
			return false, "no path"
		end
		if seq() == start and (r.Position - target).Magnitude <= within + 2 then return true end
		task.wait(0.3)
	end
	local r = root()
	return r and (r.Position - target).Magnitude <= within + 2, "blocked"
end

local function holdPrompt(p)
	if not p then return false end
	local shown = false
	local c = PPS.PromptShown:Connect(function(pp) if pp == p then shown = true end end)
	local t0 = os.clock()
	while not shown and os.clock() - t0 < 1.5 do task.wait() end
	c:Disconnect()
	pcall(function() p:InputHoldBegin() end)
	task.wait(p.HoldDuration + 0.2)
	pcall(function() p:InputHoldEnd() end)
	return shown
end

local function findPrompt(action)
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.ActionText == action then return d end
	end
end

local function clickPart(part)
	local cd = part and (part:FindFirstChildOfClass("ClickDetector") or part:FindFirstChildWhichIsA("ClickDetector", true))
	if not cd then return false end
	local ok = pcall(fireclickdetector, cd)
	return ok
end

local function scrapTools()
	local n = 0
	for _, t in ipairs(LP.Backpack:GetChildren()) do if t:GetAttribute("scrap") then n += (t:GetAttribute("ScrapCount") or 1) end end
	local c = char()
	if c then for _, t in ipairs(c:GetChildren()) do if t:IsA("Tool") and t:GetAttribute("scrap") then n += (t:GetAttribute("ScrapCount") or 1) end end end
	return n
end

local blacklist = setmetatable({}, { __mode = "k" })
local badRegion = {}
local regionOK, regionAt = {}, 0
local function sellPoints()
	local pts = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.ActionText == "Sell Scraps" then
			local c = posOf(d.Parent)
			if c then for k = 0, 4 do local a = k * math.pi / 2 local o = k > 0 and 6 or 0 pts[#pts + 1] = c + Vector3.new(math.cos(a) * o, 0, math.sin(a) * o) end end
		end
	end
	return pts
end
local function pathOK(a, b)
	local path = PathfindingService:CreatePath({ AgentRadius = 1, AgentHeight = 4, AgentCanJump = true, AgentCanClimb = true })
	local ok = pcall(function() path:ComputeAsync(a, b) end)
	return ok and path.Status == Enum.PathStatus.Success
end
local function regionSells(reg, sample)
	if os.clock() - regionAt > 120 then regionOK = {} regionAt = os.clock() end
	local st = regionOK[reg]
	if st == true then return true end
	st = st or 0
	if st >= 3 then return false end
	for _, m in ipairs(sellPoints()) do if pathOK(sample, m) then regionOK[reg] = true return true end end
	regionOK[reg] = st + 1
	return st + 1 < 3
end

local function nextScrap()
	local r = root() if not r then return end
	local folder = workspace:FindFirstChild("Scraps") if not folder then return end
	local minV = ScrapValue[Opt.ScrapMin] or 1
	local best, bd
	for _, s in ipairs(folder:GetChildren()) do
		if s:IsA("BasePart") and not blacklist[s] and (ScrapValue[s.Name] or 1) >= minV and s:FindFirstChildWhichIsA("ProximityPrompt", true) then
			local reg = s:GetAttribute("ScrapRegion")
			if not (reg and (badRegion[reg] or 0) >= 2) and not (reg and not regionSells(reg, s.Position)) then
				local d = (s.Position - r.Position).Magnitude + math.abs(s.Position.Y - r.Position.Y) * 8
				if not bd or d < bd then best, bd = s, d end
			end
		end
	end
	return best, bd
end

local function pickScrap(s)
	local ok, why = travel(s.Position, 4)
	if not ok and (why == "no path" or why == "reverted") then task.wait(2) return false end
	if not ok or not s.Parent then
		blacklist[s] = true
		local reg = s:GetAttribute("ScrapRegion")
		if reg and s.Parent then badRegion[reg] = (badRegion[reg] or 0) + 1 end
		return false
	end
	task.wait(0.25)
	local r0 = root()
	if r0 and (r0.Position - s.Position).Magnitude > 10 then
		blacklist[s] = true
		local reg = s:GetAttribute("ScrapRegion")
		if reg then badRegion[reg] = (badRegion[reg] or 0) + 1 end
		return false
	end
	local p = s:FindFirstChildWhichIsA("ProximityPrompt", true)
	local r = root()
	for _ = 1, 3 do
		if r then r.AssemblyLinearVelocity = Vector3.zero end
		task.wait(0.35)
		holdPrompt(p)
		task.wait(0.5)
		if not s.Parent then return true end
	end
	blacklist[s] = true
	local reg = s:GetAttribute("ScrapRegion")
	if reg then badRegion[reg] = (badRegion[reg] or 0) + 1 end
	return false
end

local function sell()
	local before = coins()
	local r = root() if not r then return false, "no character" end
	local list = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.ActionText == "Sell Scraps" then
			local p = posOf(d.Parent)
			if p then list[#list + 1] = { d, p, (p - r.Position).Magnitude } end
		end
	end
	if #list == 0 then return false, "no scrap machine found" end
	table.sort(list, function(a, b) return a[3] < b[3] end)
	local function canPath(a, b)
		local path = PathfindingService:CreatePath({ AgentRadius = 1, AgentHeight = 4, AgentCanJump = true, AgentCanClimb = true })
		local ok = pcall(function() path:ComputeAsync(a, b) end)
		return ok and path.Status == Enum.PathStatus.Success
	end
	for _, m in ipairs(list) do
		local reach = m[1].MaxActivationDistance - 1.5
		local arrived = travel(m[2], reach)
		if not arrived and workspace:FindFirstChild("Scraps") then
			local me = root() and root().Position
			local hops = {}
			for _, sc in ipairs(workspace.Scraps:GetChildren()) do
				if sc:IsA("BasePart") then hops[#hops + 1] = { sc.Position, (sc.Position - m[2]).Magnitude } end
			end
			table.sort(hops, function(a, b) return a[2] < b[2] end)
			for i = 1, math.min(12, #hops) do
				local h = hops[i][1]
				if me and canPath(h, m[2]) and canPath(me, h) then
					if travel(h, 4) then arrived = travel(m[2], reach) end
					break
				end
			end
		end
		if arrived then
			local off = {}
			for _, d in ipairs(workspace:GetDescendants()) do
				if d:IsA("ProximityPrompt") and d ~= m[1] and d.Enabled then
					local pp = posOf(d.Parent)
					if pp and (pp - m[2]).Magnitude < 25 then d.Enabled = false off[#off + 1] = d end
				end
			end
			local tool = LP.Backpack:FindFirstChildWhichIsA("Tool")
			if tool and tool:GetAttribute("scrap") and hum() then pcall(function() hum():EquipTool(tool) end) end
			task.wait(0.4)
			holdPrompt(m[1])
			task.wait(1.2)
			for _, d in ipairs(off) do pcall(function() d.Enabled = true end) end
			if coins() > before then return true, ("sold: %d -> %d coins"):format(before, coins()) end
		end
	end
	task.wait(2)
	return false, "could not sell at any machine"
end

local function autoFarm()
	local resetAt = os.clock() + 60
	while Hub.Running and Hub.Farm do
		if os.clock() > resetAt then badRegion = {} resetAt = os.clock() + 60 end
		local ok, err = pcall(function()
			local h = hum()
			if not h or h.Health <= 0 then task.wait(1) return end
			local r = root()
			if r and (r.Position - Places.Lobby).Magnitude < 90 and r.Position.Y < 88 then
				local pads = workspace:FindFirstChild("TPButtons")
				local q = pads and pads:FindFirstChild("QuickPlay")
				if q then
					travel(q.Position, 8)
					clickPart(q)
					log("in lobby: pressed QuickPlay")
					task.wait(4)
					return
				end
			end
			local s = nextScrap()
			if scrapTools() >= Opt.SellAt or (not s and scrapTools() > 0) then
				local _, msg = sell()
				log(msg)
			elseif s then
				if pickScrap(s) then log("picked " .. s.Name .. " (" .. scrapTools() .. " held)") end
			else
				task.wait(2)
			end
		end)
		if not ok then log("farm: " .. tostring(err)) task.wait(1) end
		task.wait(0.1)
	end
end

local espFolder = Instance.new("Folder")
espFolder.Name = "SnowyESP"
pcall(function() espFolder.Parent = gethui and gethui() or game.CoreGui end)
if not espFolder.Parent then espFolder.Parent = LP:WaitForChild("PlayerGui") end
local Esp = { Monsters = false, Scraps = false, Players = false }
local espMade = {}
local function tagFor(obj, color, text)
	local e = espMade[obj]
	if not e then
		local hl = Instance.new("Highlight")
		hl.FillTransparency = 0.6
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Adornee = obj
		hl.Parent = espFolder
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(160, 30)
		bb.AlwaysOnTop = true
		bb.StudsOffset = Vector3.new(0, 3, 0)
		bb.Adornee = obj:IsA("Model") and (obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart) or obj
		local tl = Instance.new("TextLabel")
		tl.BackgroundTransparency = 1
		tl.Size = UDim2.fromScale(1, 1)
		tl.TextStrokeTransparency = 0.3
		tl.Font = Enum.Font.GothamBold
		tl.TextSize = 13
		tl.Parent = bb
		bb.Parent = espFolder
		e = { hl = hl, bb = bb, tl = tl }
		espMade[obj] = e
	end
	e.hl.FillColor, e.hl.OutlineColor, e.tl.TextColor3 = color, color, color
	e.tl.Text = text
	e.seen = true
end
local function monsters()
	local list = {}
	for _, part in ipairs(CollectionService:GetTagged("dangersource")) do
		local m = part:FindFirstAncestorOfClass("Model")
		if m and m.Parent and not Players:GetPlayerFromCharacter(m) then list[#list + 1] = m end
	end
	return list
end
local function espStep()
	for _, e in pairs(espMade) do e.seen = false end
	local r = root()
	local function dist(o) local p = posOf(o) return (r and p) and math.floor((p - r.Position).Magnitude) or 0 end
	if Esp.Monsters then for _, m in ipairs(monsters()) do tagFor(m, Color3.fromRGB(255, 60, 60), m.Name .. " [" .. dist(m) .. "]") end end
	if Esp.Scraps and workspace:FindFirstChild("Scraps") then
		for _, s in ipairs(workspace.Scraps:GetChildren()) do
			if s:IsA("BasePart") then tagFor(s, Color3.fromRGB(255, 210, 60), s.Name .. " +" .. (ScrapValue[s.Name] or "?") .. " [" .. dist(s) .. "]") end
		end
	end
	if Esp.Players then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LP and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then tagFor(p.Character, Color3.fromRGB(80, 170, 255), p.DisplayName .. " [" .. dist(p.Character) .. "]") end
		end
	end
	for obj, e in pairs(espMade) do
		if not e.seen or not obj.Parent then e.hl:Destroy() e.bb:Destroy() espMade[obj] = nil end
	end
end
task.spawn(function() while Hub.Running do pcall(espStep) task.wait(0.5) end end)

local flyBV, flyBG
local function setFly(on)
	Hub.Fly = on
	if flyBV then flyBV:Destroy() flyBV = nil end
	if flyBG then flyBG:Destroy() flyBG = nil end
	local h = hum()
	if h then h.PlatformStand = false end
	if not on then return end
	local r = root() if not r then return end
	flyBV = Instance.new("BodyVelocity")
	flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	flyBV.Velocity = Vector3.zero
	flyBV.Parent = r
	flyBG = Instance.new("BodyGyro")
	flyBG.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
	flyBG.P = 9e3
	flyBG.Parent = r
end
conn(RunService.RenderStepped:Connect(function()
	if not (Hub.Running and Hub.Fly and flyBV and flyBV.Parent) then return end
	local h, cam = hum(), workspace.CurrentCamera
	if not h then return end
	local mv = Vector3.zero
	pcall(function()
		Hub.Controls = Hub.Controls or require(LP.PlayerScripts:WaitForChild("PlayerModule", 2)):GetControls()
		mv = Hub.Controls:GetMoveVector()
	end)
	local v = Vector3.zero
	if mv.Magnitude > 0.05 then
		v = cam.CFrame:VectorToWorldSpace(Vector3.new(mv.X, 0, mv.Z)).Unit * Opt.FlySpeed
	elseif h.MoveDirection.Magnitude > 0 then
		v = h.MoveDirection * Opt.FlySpeed
	end
	flyBV.Velocity = v
	flyBG.CFrame = cam.CFrame
end))
conn(LP.CharacterAdded:Connect(function() if Hub.Fly then task.wait(1) setFly(true) end end))

task.spawn(function()
	while Hub.Running do
		if Hub.SpeedOn then
			pcall(function()
				local t = getrenv().shared.SpeedBoostTable
				if t then table.insert(t, { time = time(), duration = 1.2, mult = Opt.Boost or 3 }) end
			end)
		end
		task.wait(1)
	end
end)

local lightSaved
local function fullbright(on)
	if on then
		lightSaved = lightSaved or { Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.GlobalShadows, Lighting.Ambient }
		Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.GlobalShadows, Lighting.Ambient = 2, 14, 1e5, false, Color3.fromRGB(180, 180, 180)
	elseif lightSaved then
		Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.GlobalShadows, Lighting.Ambient = unpack(lightSaved)
		lightSaved = nil
	end
end
local nightLight
local function enhanced(on)
	Hub.Enhanced = on
	if on then
		fullbright(true)
		Lighting.FogStart = 1e5
		local r = root()
		if r and not (nightLight and nightLight.Parent) then
			nightLight = Instance.new("PointLight")
			nightLight.Range, nightLight.Brightness, nightLight.Shadows = 80, 3, false
			nightLight.Parent = r
		end
	else
		if nightLight then nightLight:Destroy() nightLight = nil end
		if not Hub.Bright then fullbright(false) end
	end
end

local function escapeStep()
	local r = root() if not r then return end
	local best, bd
	for _, m in ipairs(monsters()) do
		local p = posOf(m)
		if p then local d = (p - r.Position).Magnitude if not bd or d < bd then best, bd = p, d end end
	end
	if not best or bd > (Opt.EscapeRange or 40) then return end
	local away = (r.Position - best) * Vector3.new(1, 0, 1)
	if away.Magnitude < 0.1 then away = Vector3.new(1, 0, 0) end
	local goal = r.Position + away.Unit * 35
	stopMove = true task.wait(0.05) stopMove = false
	travel(goal, 6)
	log(("escaped: monster was %d studs away"):format(math.floor(bd)))
end
task.spawn(function()
	while Hub.Running do
		if Hub.Escape then pcall(escapeStep) end
		task.wait(0.25)
	end
end)

conn(RunService.Heartbeat:Connect(function() if Hub.Bright or Hub.Enhanced then Lighting.FogEnd = 1e5 Lighting.Brightness = 2 end end))

local function serverHop()
	local ok, body = pcall(function()
		return game:HttpGet(("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100"):format(game.PlaceId))
	end)
	if not ok then return false, "server list failed" end
	local data = HttpService:JSONDecode(body)
	local list = {}
	for _, s in ipairs(data.data or {}) do
		if s.id ~= game.JobId and s.playing < s.maxPlayers then list[#list + 1] = s.id end
	end
	if #list == 0 then return false, "no other server" end
	TeleportService:TeleportToPlaceInstance(game.PlaceId, list[math.random(#list)], LP)
	return true, "hopping"
end

Hub.AutoRejoin = true
conn(GuiService.ErrorMessageChanged:Connect(function(msg)
	if Hub.Running and Hub.AutoRejoin and msg and msg ~= "" then
		task.wait(2)
		pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP) end)
		task.wait(8)
		pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
	end
end))

local function runTask(fn, ...)
	if busy then return false, "busy" end
	busy = true
	stopMove = false
	local res = table.pack(pcall(fn, ...))
	busy = false
	if not res[1] then return false, tostring(res[2]) end
	return res[2], res[3]
end

local function goPlace(name) return runTask(function() return travel(Places[name], 4) end) end

local function openShop()
	local ui = LP.PlayerGui:FindFirstChild("ShopUI")
	if ui then
		for _, d in ipairs(ui:GetDescendants()) do if d:IsA("GuiObject") and d.Name == "Shop" then d.Visible = true end end
		ui.Enabled = true
	end
	return runTask(function()
		if not travel(Places.Shop, 6) then return false, "could not reach shop" end
		local p = workspace:FindFirstChild("ShopPrompt") and workspace.ShopPrompt:FindFirstChild("PromptShop")
		return holdPrompt(p), "shop opened"
	end)
end

local function buy(key)
	local r = RS:FindFirstChild("shoppurchase")
	if not r then return false, "no shop remote" end
	local before = coins()
	local ok, res = pcall(function() return r:InvokeServer(key) end)
	return ok and res == true, ("%s: %s (%d -> %d)"):format(key, tostring(res), before, coins())
end

local function pickColor(name)
	return runTask(function()
		local f = workspace:FindFirstChild("ColorCustomizations")
		local part = f and f:FindFirstChild(name)
		local target = part and posOf(part) or Places.Colors
		if not travel(target, 6) then return false, "could not reach colors" end
		part = f and f:FindFirstChild(name)
		return clickPart(part), "color " .. name
	end)
end

local function pressPad(name)
	return runTask(function()
		local f = workspace:FindFirstChild("TPButtons")
		local part = f and f:FindFirstChild(name)
		if not part then return false, "pad not found" end
		if not travel(posOf(part), 6) then return false, "could not reach pad" end
		return clickPart(part), name .. " pressed"
	end)
end

local function elevator(floor)
	return runTask(function()
		local e = workspace:FindFirstChild("Elevators")
		local target = floor == 2 and Places.ElevatorF2 or Places.ElevatorF1
		if not travel(target, 6) then return false, "could not reach elevator" end
		local part = e and e:FindFirstChild(floor == 2 and "f2" or "f1", true)
		return clickPart(part), "elevator called"
	end)
end

local function camsOpen()
	local g = LP.PlayerGui:FindFirstChild("CameraGui")
	local h = g and g:FindFirstChild("Holder", true)
	return g and g.Enabled and (not h or h.Visible) or false
end
local function openCameras()
	return runTask(function()
		local p = workspace:FindFirstChild("SecCams") and workspace.SecCams:FindFirstChild("SecCamToggle", true)
		if not p then return false, "camera prompt not loaded" end
		holdPrompt(p) task.wait(0.6)
		if camsOpen() then return true, "cameras opened" end
		if not travel(posOf(p.Parent) or Places.Cameras, p.MaxActivationDistance - 1.5) then return false, "could not reach cameras" end
		holdPrompt(p) task.wait(0.6)
		return camsOpen(), camsOpen() and "cameras opened" or "camera prompt held, viewer did not open"
	end)
end

local function notify(window, text)
	log(text)
	pcall(function() window:Notify({ Title = "SnowyHub", Text = text, Duration = 3 }) end)
end

local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/0x1s2s/Snowy-Ui-Library/refs/heads/main/SnowyUi"))()
local Window = lib:Window({ Subtitle = "SnowyHub | Lethal Ape", Keybind = Enum.KeyCode.RightControl, Width = 580, Height = 440 })
Hub.Window = Window
local function say(t) task.spawn(notify, Window, t) end
local function act(fn, ...) local a = table.pack(...) task.spawn(function() local _, msg = fn(table.unpack(a, 1, a.n)) say(tostring(msg)) end) end

local farmTab = Window:Tab({ Name = "Farm", Icon = "wallet" })
local farm = farmTab:Section({ Title = "Auto Farm Coins", Column = 1 })
Hub.UI = {}
Hub.UI.Farm = farm:Toggle({ Text = "Auto farm coins", Default = false, Callback = function(v)
	if v == (Hub.Farm or false) then return end
	Hub.Farm = v
	if v then
		if busy then stopMove = true task.wait(0.3) end
		task.spawn(function() busy = true stopMove = false autoFarm() busy = false end)
		say("Auto farm on")
	else
		stopMove = true
		say("Auto farm off")
	end
end })
farm:Slider({ Text = "Sell when holding", Min = 1, Max = 30, Default = 3, Callback = function(v) Opt.SellAt = v end })
farm:Dropdown({ Text = "Minimum scrap", Options = { "Copper", "Silver", "Gold", "Emerald", "Ruby", "Diamond" }, Default = "Copper", Callback = function(v) Opt.ScrapMin = v end })
farm:Slider({ Text = "Move speed", Min = 20, Max = 200, Default = 100, Callback = function(v) Opt.Speed = v end })
farm:Button({ Text = "Sell now", Callback = function() act(runTask, sell) end })
local stats = farmTab:Section({ Title = "Status", Column = 2 })
local coinLabel = stats:Label({ Text = "Coins: " .. coins() })
local logLabel = stats:Label({ Text = "" })
task.spawn(function()
	while Hub.Running do
		pcall(function()
			coinLabel:Set("Coins: " .. coins() .. " | Held scraps: " .. scrapTools())
			logLabel:Set(Hub.Log[1] or "")
		end)
		task.wait(1)
	end
end)

local shopTab = Window:Tab({ Name = "Shop", Icon = "shopping-cart" })
local shop = shopTab:Section({ Title = "Shopping", Column = 1 })
shop:Button({ Text = "Open shop", Callback = function() act(openShop) end })
local buyKey = ShopKeys[1]
shop:Dropdown({ Text = "Item", Options = ShopKeys, Default = buyKey, Callback = function(v) buyKey = v end })
shop:Button({ Text = "Buy selected item", Callback = function() act(buy, buyKey) end })
local custom = shopTab:Section({ Title = "Color Custom", Column = 2 })
local colorName = ColorNames[1]
custom:Dropdown({ Text = "Select color", Options = ColorNames, Default = colorName, Callback = function(v) colorName = v end })
custom:Button({ Text = "Apply color", Callback = function() act(pickColor, colorName) end })

local tpTab = Window:Tab({ Name = "Teleport", Icon = "map-pin" })
local tp = tpTab:Section({ Title = "Facility", Column = 1 })
tp:Button({ Text = "Teleport to Locker Room", Callback = function() act(goPlace, "Locker") end })
tp:Button({ Text = "Teleport to Monster Room", Callback = function() act(pressPad, "MonsterRoom") end })
tp:Button({ Text = "Teleport to Elevator", Callback = function() act(elevator, 1) end })
tp:Button({ Text = "Quick Play", Callback = function() act(pressPad, "QuickPlay") end })
tp:Button({ Text = "Scrap Machine", Callback = function() act(goPlace, "Machine") end })
tp:Button({ Text = "Stop moving", Callback = function() stopMove = true end })

local visTab = Window:Tab({ Name = "Visuals", Icon = "eye" })
local vis = visTab:Section({ Title = "ESP", Column = 1 })
Hub.UI.MonsterESP = vis:Toggle({ Text = "Monster ESP + model", Default = false, Callback = function(v) Esp.Monsters = v end })
Hub.UI.ScrapESP = vis:Toggle({ Text = "Scraps ESP", Default = false, Callback = function(v) Esp.Scraps = v end })
Hub.UI.PlayerESP = vis:Toggle({ Text = "Player ESP", Default = false, Callback = function(v) Esp.Players = v end })
local vis2 = visTab:Section({ Title = "World", Column = 2 })
Hub.UI.Fullbright = vis2:Toggle({ Text = "Fullbright", Default = false, Callback = function(v) Hub.Bright = v fullbright(v) end })
Hub.UI.Enhanced = vis2:Toggle({ Text = "Enhanced visibility", Default = false, Callback = function(v) enhanced(v) end })
vis2:Button({ Text = "Open cameras", Callback = function() act(openCameras) end })

local moveTab = Window:Tab({ Name = "Movement", Icon = "wind" })
local mv = moveTab:Section({ Title = "Movement", Column = 1 })
Hub.UI.Fly = mv:Toggle({ Text = "Fly", Default = false, Callback = function(v) if v ~= (Hub.Fly or false) then setFly(v) end end })
Hub.UI.Speed = mv:Toggle({ Text = "Speed boost (game cap 90)", Default = false, Callback = function(v) Hub.SpeedOn = v end })
mv:Slider({ Text = "Boost multiplier", Min = 1, Max = 3, Default = 3, Callback = function(v) Opt.Boost = v end })
mv:Slider({ Text = "Fly speed", Min = 10, Max = 120, Default = 50, Callback = function(v) Opt.FlySpeed = v end })
local surv = moveTab:Section({ Title = "Survival", Column = 1 })
Hub.UI.Escape = surv:Toggle({ Text = "Auto escape monsters", Default = false, Callback = function(v) Hub.Escape = v end })
surv:Slider({ Text = "Escape range", Min = 15, Max = 100, Default = 40, Callback = function(v) Opt.EscapeRange = v end })
local srv = moveTab:Section({ Title = "Server", Column = 2 })
srv:Button({ Text = "Server hop", Callback = function() act(serverHop) end })
srv:Button({ Text = "Rejoin", Callback = function() pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP) end) end })
srv:Toggle({ Text = "Auto rejoin on kick", Default = true, Callback = function(v) Hub.AutoRejoin = v end })
srv:Button({ Text = "Unload", Callback = function() Hub.Unload() end })

function Hub.Unload()
	Hub.Running = false
	Hub.Farm = false
	stopMove = true
	setFly(false)
	enhanced(false)
	fullbright(false)
	if oldNC then pcall(hookmetamethod, game, "__namecall", oldNC) end
	for _, c in ipairs(Hub.Conns) do pcall(function() c:Disconnect() end) end
	pcall(function() espFolder:Destroy() end)
	pcall(function() if getgenv().SnowyStudiosUnload then getgenv().SnowyStudiosUnload() end end)
	for _, g in ipairs((gethui and gethui() or game.CoreGui):GetChildren()) do if g.Name == "SnowyStudios" then pcall(function() g:Destroy() end) end end
	getgenv().SnowyHub = nil
end

Hub.Opt = Opt
Hub.travel, Hub.sell, Hub.buy, Hub.pick, Hub.openShop, Hub.pickColor, Hub.pressPad, Hub.elevator, Hub.openCameras, Hub.goPlace, Hub.serverHop, Hub.monsters = travel, sell, buy, pickScrap, openShop, pickColor, pressPad, elevator, openCameras, goPlace, serverHop, monsters
say("Loaded")
return Hub
