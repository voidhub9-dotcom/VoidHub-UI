if getgenv().VoidHubFeral then pcall(getgenv().VoidHubFeral.Unload) end
local Hub = { Running = true, Conns = {}, Log = {} }
getgenv().VoidHubFeral = Hub

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local VirtualUser = game:GetService("VirtualUser")
local VIM = game:GetService("VirtualInputManager")
local LP = Players.LocalPlayer

local function conn(c) table.insert(Hub.Conns, c) return c end
local function log(s) table.insert(Hub.Log, 1, os.date("%X ") .. tostring(s)) if #Hub.Log > 60 then table.remove(Hub.Log) end end
local function char() return LP.Character end
local function root() local c = char() return c and c:FindFirstChild("HumanoidRootPart") end
local function hum() local c = char() return c and c:FindFirstChildOfClass("Humanoid") end

local ST = function() return workspace:GetServerTimeNow() end
pcall(function() local m = require(RS:WaitForChild("FeralWorld", 5):WaitForChild("SafeTime", 5)) if type(m) == "function" then ST = m end end)

local R = {
	Actions = RS:FindFirstChild("WolfActions"),
	Lunge = RS:FindFirstChild("FeralLunge"),
	Grab = RS:FindFirstChild("FeralGrabV2"),
	Afk = RS:FindFirstChild("FeralAfk"),
}
local function fire(remote, ...) if remote then local a = table.pack(...) pcall(function() remote:FireServer(table.unpack(a, 1, a.n)) end) end end

local Places = {
	["Golden Waterhole"] = Vector2.new(-240, 220), ["Den Hollow"] = Vector2.new(-510, 1116), ["Alder Creek"] = Vector2.new(-885, 1044),
	["Elk Crossing"] = Vector2.new(-6, 606), ["Golden Plains"] = Vector2.new(717, 882), ["Beaver Ponds"] = Vector2.new(-546, 60),
	["Eagle Rock"] = Vector2.new(711, -105), ["Pine Woods"] = Vector2.new(-1140, 180), ["Great Falls"] = Vector2.new(15, -504),
	["Frost Lake"] = Vector2.new(30, -990), ["Lunar Crest"] = Vector2.new(-600, -1050), ["Goat Cliffs"] = Vector2.new(1215, -855),
	["Black Ravine"] = Vector2.new(165, 1620), ["Juniper Fields"] = Vector2.new(932, -642), ["Granite Basin"] = Vector2.new(-961, -632),
	["Elder Giants"] = Vector2.new(-1182, 583), ["Rattlebone Mesa"] = Vector2.new(1158, 621), ["Red Canyon"] = Vector2.new(839, 1535),
	["Tall Marsh"] = Vector2.new(-826, 1996), ["Mudlands"] = Vector2.new(860, 2110), ["Dead Lagoon"] = Vector2.new(180, 2142),
}
local PlaceNames = {}
for k in pairs(Places) do PlaceNames[#PlaceNames + 1] = k end
table.sort(PlaceNames)
local WaterPlaces = { "Golden Waterhole", "Beaver Ponds", "Great Falls", "Frost Lake", "Alder Creek", "Tall Marsh", "Dead Lagoon" }

conn(LP.Idled:Connect(function() pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton2(Vector2.new()) end) end))

local oldNC
pcall(function()
	oldNC = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
		if Hub.Running and Hub.AntiAfk and self == R.Afk and getnamecallmethod() == "FireServer" then
			local a = ...
			if a == "hop" then return nil end
		end
		if Hub.Running and self == R.Actions and getnamecallmethod() == "FireServer" and Hub.onBite then
			local a, b = ...
			if a == "Bite" and type(b) == "number" then task.spawn(Hub.onBite, b) end
		end
		if Hub.Running and self == LP and getnamecallmethod() == "Kick" then return nil end
		return oldNC(self, ...)
	end))
end)

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/voidhub9-dotcom/VoidHub-UI/main/Source.lua"))()
local Window = Library:CreateVoidHubWindow({
	Name = "VoidHub", Title = "VoidHub", LoadingTitle = "VoidHub",
	ToggleUIKeybind = "RightControl",
	ConfigurationSaving = { Enabled = true, FolderName = "VoidHub_Feral" },
	Home = { Welcome = "FERAL" },
})
Hub.Window = Window
local function F(flag) local f = Window.Flags[flag] return f and f.Value end

local function isTarget(m)
	if not m or not m.Parent or m == char() then return false end
	local h = m:FindFirstChildOfClass("Humanoid")
	local r = m:FindFirstChild("HumanoidRootPart")
	if not (h and r) or h.Health <= 0 then return false end
	local myPack = char() and char():GetAttribute("FeralPack")
	if myPack and m:GetAttribute("FeralPack") == myPack then return false end
	local p = Players:GetPlayerFromCharacter(m)
	if p then
		local wl = tostring(F("AuraWhitelistText") or ""):lower()
		for n in wl:gmatch("[^,%s]+") do if p.Name:lower():find(n, 1, true) or p.DisplayName:lower():find(n, 1, true) then return false end end
	end
	return true
end

local function candidates(mode)
	local list = {}
	if mode ~= "NPCs" then for _, p in ipairs(Players:GetPlayers()) do if p ~= LP and p.Character then list[#list + 1] = p.Character end end end
	if mode ~= "Players" then local f = workspace:FindFirstChild("FeralNPCs") if f then for _, m in ipairs(f:GetChildren()) do if m:IsA("Model") then list[#list + 1] = m end end end end
	return list
end

local function nearestTarget(mode, range)
	local r = root() if not r then return end
	local best, bd
	for _, m in ipairs(candidates(mode)) do
		if isTarget(m) then
			local d = (m.HumanoidRootPart.Position - r.Position).Magnitude
			if d <= range and (not bd or d < bd) then best, bd = m, d end
		end
	end
	return best, bd
end

local function face(m)
	local r = root() local tr = m and m:FindFirstChild("HumanoidRootPart")
	if not (r and tr) then return end
	local look = (tr.Position - r.Position) * Vector3.new(1, 0, 1)
	if look.Magnitude > 0.1 then r.CFrame = CFrame.lookAt(r.Position, r.Position + look) end
end

local lastBite = 0
local function bite(m)
	if os.clock() - lastBite < (F("AuraDelay") or 0.6) then return end
	lastBite = os.clock()
	local c = char()
	if (F("BiteMethod") or "Game") == "Game" and c then
		c:SetAttribute("WolfDbgBite", os.clock())
	else
		local t = ST()
		fire(R.Actions, "Bite", t)
		task.delay(0.28, function() if m and m.Parent then fire(R.Actions, "BiteHit", { t = t, m = m }) end end)
	end
end

local boxSaved
local reachBall
local function reachFor(box, hip) return ((box * 0.5) + hip * 1.45 + 1.2) * 1.15 end
local function applyReach()
	local r, h = root(), hum()
	if not (r and h) then return end
	if F("BiteReach") then
		if not boxSaved then boxSaved = { r:GetAttribute("FeralBoxFull") or false } end
		local want = F("ReachStuds") or 40
		local box = math.max(0.5, 2 * (want / 1.15 - h.HipHeight * 1.45 - 1.2))
		r:SetAttribute("FeralBoxFull", box)
		if F("ShowReach") ~= false then
			local rad = F("ReachStuds") or 40
			local holder = Hub.reachPart
			if not (holder and holder.Parent) then
				holder = Instance.new("Part")
				holder.Name = "VoidReach"
				holder.Shape = Enum.PartType.Ball
				holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch, holder.CastShadow = true, false, false, false, false
				holder.Material = Enum.Material.ForceField
				holder.Color = Color3.fromRGB(255, 255, 255)
				holder.Transparency = 0.6
				holder.Parent = workspace
				Hub.reachPart = holder
			end
			if not (reachBall and reachBall.Parent) then
				reachBall = Instance.new("SelectionSphere")
				reachBall.Color3 = Color3.fromRGB(255, 255, 255)
				reachBall.SurfaceTransparency = 1
				reachBall.Transparency = 0
				reachBall.Adornee = holder
				reachBall.Parent = holder
			end
			holder.Size = Vector3.new(rad * 2, rad * 2, rad * 2)
			holder.CFrame = CFrame.new(r.Position)
		elseif reachBall then reachBall:Destroy() reachBall = nil if Hub.reachPart then Hub.reachPart:Destroy() Hub.reachPart = nil end end
	else
		if boxSaved then r:SetAttribute("FeralBoxFull", boxSaved[1] ~= false and boxSaved[1] or nil) boxSaved = nil end
		if reachBall then reachBall:Destroy() reachBall = nil end
		if Hub.reachPart then Hub.reachPart:Destroy() Hub.reachPart = nil end
	end
end
conn(LP.CharacterAdded:Connect(function() boxSaved = nil end))

function Hub.onBite(t)
	if not F("BiteReach") then return end
	local r = root() if not r then return end
	local best, bd
	local range = F("ReachStuds") or 40
	for _, m in ipairs(candidates(F("AuraTarget") or "Both")) do
		if isTarget(m) then
			local d = (m.HumanoidRootPart.Position - r.Position).Magnitude
			if d <= range and (not bd or d < bd) then best, bd = m, d end
		end
	end
	if not best then return end
	local saved = r.CFrame
	local look = (best.HumanoidRootPart.Position - r.Position) * Vector3.new(1, 0, 1)
	if look.Magnitude > 0.1 then r.CFrame = CFrame.lookAt(r.Position, r.Position + look) end
	task.wait(0.27)
	if best.Parent then fire(R.Actions, "BiteHit", { t = t, m = best }) end
	if not F("FaceTarget") then local rr = root() if rr then rr.CFrame = CFrame.new(rr.Position) * saved.Rotation end end
end

local espFolder = Instance.new("Folder")
espFolder.Name = "VoidFeralESP"
pcall(function() espFolder.Parent = gethui and gethui() or game.CoreGui end)
local espMade = {}
local function espTag(m, color)
	local hr = m:FindFirstChild("HumanoidRootPart")
	local hm = m:FindFirstChildOfClass("Humanoid")
	if not (hr and hm) then return end
	local e = espMade[m]
	if not e then
		local hl = Instance.new("Highlight")
		hl.FillTransparency, hl.OutlineTransparency = 0.75, 0
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Adornee = m
		hl.Parent = espFolder
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(140, 36)
		bb.AlwaysOnTop = true
		bb.StudsOffset = Vector3.new(0, 4, 0)
		bb.Adornee = hr
		bb.Parent = espFolder
		local tl = Instance.new("TextLabel")
		tl.BackgroundTransparency = 1
		tl.Size = UDim2.new(1, 0, 0, 20)
		tl.Font = Enum.Font.GothamBold
		tl.TextSize = 12
		tl.TextStrokeTransparency = 0.3
		tl.Parent = bb
		local back = Instance.new("Frame")
		back.Size = UDim2.new(0.7, 0, 0, 5)
		back.Position = UDim2.new(0.15, 0, 0, 24)
		back.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		back.BorderSizePixel = 0
		back.Parent = bb
		local bar = Instance.new("Frame")
		bar.BorderSizePixel = 0
		bar.Size = UDim2.fromScale(1, 1)
		bar.Parent = back
		e = { hl = hl, bb = bb, tl = tl, back = back, bar = bar }
		espMade[m] = e
	end
	local r = root()
	local d = r and math.floor((hr.Position - r.Position).Magnitude) or 0
	local hp, mx = hm.Health, math.max(hm.MaxHealth, 1)
	local p = Players:GetPlayerFromCharacter(m)
	local name = p and p.DisplayName or (m:GetAttribute("Species") or m.Name)
	e.hl.FillColor, e.hl.OutlineColor, e.tl.TextColor3 = color, color, color
	e.tl.Text = ("%s [%d]%s"):format(name, d, F("EspHealth") and (" %d/%d"):format(hp, mx) or "")
	e.back.Visible = F("EspHealth") and true or false
	local frac = math.clamp(hp / mx, 0, 1)
	e.bar.Size = UDim2.fromScale(frac, 1)
	e.bar.BackgroundColor3 = Color3.fromRGB(255 * (1 - frac), 255 * frac, 60)
	e.seen = true
end
local function espStep()
	for _, e in pairs(espMade) do e.seen = false end
	if F("EspPlayers") then for _, p in ipairs(Players:GetPlayers()) do if p ~= LP and p.Character then espTag(p.Character, Color3.fromRGB(90, 170, 255)) end end end
	if F("EspNPCs") then local f = workspace:FindFirstChild("FeralNPCs") if f then for _, m in ipairs(f:GetChildren()) do if m:IsA("Model") then espTag(m, Color3.fromRGB(255, 90, 90)) end end end end
	for m, e in pairs(espMade) do
		if not e.seen or not m.Parent then e.hl:Destroy() e.bb:Destroy() espMade[m] = nil end
	end
end

local function key(k, down) pcall(function() VIM:SendKeyEvent(down, k, false, game) end) end
local lastLunge = 0
local function lungeTarget()
	local r = root() if not r then return end
	local best, bd
	for _, m in ipairs(candidates(F("LungeTarget") or "Both")) do
		if isTarget(m) then
			local d = (m.HumanoidRootPart.Position - r.Position).Magnitude
			if d >= (F("LungeMin") or 6) and d <= (F("LungeRange") or 30) and (not bd or d < bd) then best, bd = m, d end
		end
	end
	return best, bd
end
local function lungeAt(m)
	local r, tr = root(), m and m:FindFirstChild("HumanoidRootPart")
	if not (r and tr) then return false end
	local aim = tr.Position
	if F("LungePredict") ~= false then aim = aim + tr.AssemblyLinearVelocity * Vector3.new(1, 0, 1) * 0.35 end
	local look = (aim - r.Position) * Vector3.new(1, 0, 1)
	if look.Magnitude > 0.1 then r.CFrame = CFrame.lookAt(r.Position, r.Position + look) end
	task.wait()
	local c = char()
	if c then c:SetAttribute("WolfDbgLunge", os.clock()) end
	lastLunge = os.clock()
	log("lunge at " .. m.Name)
	return true
end
function Hub.lungeNow()
	local m = lungeTarget() or nearestTarget(F("LungeTarget") or "Both", 60)
	if m then lungeAt(m) else log("no lunge target") end
end
local function lungeStep()
	if not F("AutoLunge") or os.clock() - lastLunge < 1.5 then return end
	if LP:GetAttribute("HudLungeReady") == false and LP:GetAttribute("HudAbilityLocked") ~= true then return end
	local m = lungeTarget()
	if m then lungeAt(m) end
end

local shakeAt = 0
local function escapeStep()
	if not F("AutoEscape") then return end
	local c = char() if not c then return end
	local latched = c:FindFirstChild("FeralClamp") or c:GetAttribute("FeralPinned") or c:GetAttribute("FeralLatchedBy")
	if latched and os.clock() - shakeAt > 0.17 then shakeAt = os.clock() fire(R.Lunge, "shake") end
end
if R.Grab then
	conn(R.Grab.OnClientEvent:Connect(function(kind, d)
		if not (Hub.Running and F("AutoEscape")) or kind ~= "strike" or type(d) ~= "table" then return end
		local zc = d.zc or 0.5
		local target = (d.t0 or ST()) + ((d.from == 0) and zc or (1 - zc)) / math.max(d.spd or 1, 0.01)
		task.delay(math.max(0, target - ST()), function() fire(R.Grab, "press", d.f, d.k, ST()) end)
	end))
end

local sprintHeld
local SprintAttr = { Sprint = "WolfDbgSprint", Trot = "WolfDbgTrot", Gallop = "WolfDbgBurst" }
local function sprintStep()
	local c = char() if not c then return end
	local on = F("AutoSprint")
	local typ = F("SprintType") or "Sprint"
	for t, a in pairs(SprintAttr) do
		local want = on and t == typ or nil
		if c:GetAttribute(a) ~= want then c:SetAttribute(a, want) end
	end
end
local function clearSprint()
	local c = char()
	if c then for _, a in pairs(SprintAttr) do c:SetAttribute(a, nil) end end
end

conn(RunService.RenderStepped:Connect(function()
	local rp, r0 = Hub.reachPart, root()
	if rp and rp.Parent and r0 then rp.CFrame = CFrame.new(r0.Position) end
end))

local SafeSpeed = 32
local stopTravel = false
local function groundAt(xz)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { char() }
	local hit = workspace:Raycast(Vector3.new(xz.X, 1500, xz.Y), Vector3.new(0, -3000, 0), rp)
	return hit and hit.Position or nil
end
local function travelTo(pos)
	local r, h = root(), hum()
	if not (r and h) then return false, "no character" end
	stopTravel = false
	Hub.Traveling = true
	local lift = h.HipHeight + r.Size.Y / 2 + 1
	local t0 = os.clock()
	while Hub.Running and not stopTravel do
		local dt = RunService.Heartbeat:Wait()
		r = root() if not r then break end
		local flat = (pos - r.Position) * Vector3.new(1, 0, 1)
		if flat.Magnitude < 3 then break end
		local step = math.min(flat.Magnitude, SafeSpeed * dt)
		local nxt = r.Position + flat.Unit * step
		local g = groundAt(Vector2.new(nxt.X, nxt.Z))
		local y = g and (g.Y + lift) or nxt.Y
		r.CFrame = CFrame.lookAt(Vector3.new(nxt.X, y, nxt.Z), Vector3.new(nxt.X, y, nxt.Z) + flat.Unit)
		r.AssemblyLinearVelocity = Vector3.zero
		if os.clock() - t0 > 600 then break end
	end
	Hub.Traveling = false
	r = root()
	local ok = r and ((pos - r.Position) * Vector3.new(1, 0, 1)).Magnitude < 6
	return ok, ok and "arrived" or (stopTravel and "stopped" or "failed")
end
local function travelPlace(name)
	local xz = Places[name] if not xz then return false, "unknown place" end
	local g = groundAt(xz)
	return travelTo(g or Vector3.new(xz.X, 0, xz.Y))
end
local function nearestWater()
	local r = root() if not r then return end
	local best, bd
	for _, n in ipairs(WaterPlaces) do
		local xz = Places[n]
		local d = (Vector2.new(r.Position.X, r.Position.Z) - xz).Magnitude
		if not bd or d < bd then best, bd = n, d end
	end
	return best
end
local function findWaterNear(center)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { char() }
	for rad = 0, 120, 12 do
		for a = 0, 330, 30 do
			local x = center.X + math.cos(math.rad(a)) * rad
			local z = center.Z + math.sin(math.rad(a)) * rad
			local hit = workspace:Raycast(Vector3.new(x, 1500, z), Vector3.new(0, -3000, 0), rp)
			if hit and hit.Material == Enum.Material.Water then return hit.Position end
		end
	end
end
local function waitCan(kind, t)
	local t0 = os.clock()
	while os.clock() - t0 < (t or 3) do
		local c = char()
		if c and c:GetAttribute("FeedCan") == kind then return true end
		task.wait(0.1)
	end
	return false
end
local function feed(kind)
	local r = root()
	if r then r.AssemblyLinearVelocity = Vector3.zero end
	waitCan(kind, 2)
	fire(R.Actions, "Feed", kind)
	local c = char()
	local stat = kind == "drink" and "Thirst" or "Hunger"
	local t0 = os.clock()
	while Hub.Running and not stopTravel and os.clock() - t0 < 25 do
		task.wait(0.5)
		if c and (c:GetAttribute(stat) or 0) >= 99 then break end
	end
	fire(R.Actions, "Feed", false)
	return c and math.floor(c:GetAttribute(stat) or 0)
end
local function goWater()
	local name = nearestWater()
	local ok, msg = travelPlace(name)
	if not ok then return false, msg end
	local r = root()
	local w = r and findWaterNear(r.Position)
	if w then
		local back = (r.Position - w) * Vector3.new(1, 0, 1)
		local edge = w + (back.Magnitude > 0 and back.Unit * 3 or Vector3.zero)
		travelTo(edge)
		for _ = 1, 10 do
			local rr = root()
			if not rr then break end
			rr.CFrame = CFrame.lookAt(rr.Position, Vector3.new(w.X, rr.Position.Y, w.Z))
			if waitCan("drink", 0.6) then break end
			local dir = (w - rr.Position) * Vector3.new(1, 0, 1)
			if dir.Magnitude < 0.5 then break end
			rr.CFrame = rr.CFrame + dir.Unit * 1.5
		end
	end
	if not waitCan("drink", 1) then return false, "reached " .. name .. " but no drinkable water in front" end
	local v = feed("drink")
	return true, ("drank at %s, thirst %s"):format(name, tostring(v))
end
local function foodList()
	local c = char()
	local diet = c and c:GetAttribute("Diet")
	local list = {}
	for _, o in ipairs(CollectionService:GetTagged("FeralFood")) do
		if not o:GetAttribute("Consumed") and (o:GetAttribute("FoodLeft") or 1) > 0 then
			local p = o:GetAttribute("FoodPos")
			if typeof(p) ~= "Vector3" then p = o:IsA("BasePart") and o.Position or (o:IsA("Model") and o:GetPivot().Position) end
			if p and (not diet or not o:GetAttribute("Diet") or o:GetAttribute("Diet") == diet) then list[#list + 1] = p end
		end
	end
	return list
end
local function goFood()
	local r = root() if not r then return false, "no character" end
	local best, bd
	for _, p in ipairs(foodList()) do local d = (p - r.Position).Magnitude if not bd or d < bd then best, bd = p, d end end
	local c0 = char()
	if c0 and c0:GetAttribute("FeedCan") == "eat" then
		local v = feed("eat")
		return true, "grazed here, hunger " .. tostring(v)
	end
	local sp = c0 and c0:GetAttribute("Species")
	local grazers = { Deer = true, Elk = true, Bison = true, Elephant = true, Rhino = true, Gorilla = true, RedPanda = true, Hippo = true, Porcupine = true }
	if grazers[sp] then
		for _, pl in ipairs({ "Golden Plains", "Elk Crossing", "Juniper Fields", "Golden Waterhole" }) do
			local xz = Places[pl]
			local rr = root()
			if rr and (Vector2.new(rr.Position.X, rr.Position.Z) - xz).Magnitude > 40 then travelPlace(pl) end
			for _ = 1, 8 do
				if waitCan("eat", 0.6) then
					local v = feed("eat")
					return true, ("grazed at %s, hunger %s"):format(pl, tostring(v))
				end
				local r2 = root()
				if r2 then r2.CFrame = r2.CFrame + Vector3.new(math.random(-6, 6), 0, math.random(-6, 6)) end
			end
		end
		return false, "no grass found to graze"
	end
	if not best then
		local v = feed("eat")
		return v ~= nil, "no tagged food; tried grazing here, hunger " .. tostring(v)
	end
	local ok, msg = travelTo(best)
	if not ok then return false, msg end
	local v = feed("eat")
	return true, ("ate, hunger %s"):format(tostring(v))
end

task.spawn(function()
	while Hub.Running do
		pcall(function()
			applyReach()
			if F("KillAura") then
				local m = nearestTarget(F("AuraTarget") or "Both", F("AuraRange") or 12)
				if m then
					if F("StickTarget") then
						local r, tr = root(), m:FindFirstChild("HumanoidRootPart")
						if r and tr then
							local fl = (tr.Position - r.Position) * Vector3.new(1, 0, 1)
							local want = fl.Magnitude > 0.1 and (tr.Position - fl.Unit * (F("StickDistance") or 1.8)) or r.Position
							r.CFrame = CFrame.lookAt(Vector3.new(want.X, r.Position.Y, want.Z), Vector3.new(tr.Position.X, r.Position.Y, tr.Position.Z))
						end
					elseif F("FaceTarget") then face(m) end
					bite(m)
				end
			end
			escapeStep()
		end)
		task.wait(0.05)
	end
end)
task.spawn(function()
	while Hub.Running do
		pcall(espStep)
		pcall(lungeStep)
		pcall(sprintStep)
		task.wait(0.2)
	end
end)

task.spawn(function()
	while Hub.Running do
		if F("AutoSpawn") and not char() then
			local slots = RS:FindFirstChild("FeralSlots")
			if slots then fire(slots, "play", F("SpawnSlot") or 1) log("spawned from slot " .. tostring(F("SpawnSlot") or 1)) end
			task.wait(4)
		end
		task.wait(1)
	end
end)

local amberVisited = {}
local lastClaim = 0
local function claimRewards()
	local rw = RS:FindFirstChild("FeralRewards")
	if not rw then return end
	fire(rw, "claim", "daily", nil)
	for i = 1, 8 do fire(rw, "claim", "play", i) end
end
local function amberStep()
	if os.clock() - lastClaim > 60 then lastClaim = os.clock() claimRewards() end
	local f = workspace:FindFirstChild("FeralAmberChunks")
	local r = root()
	if not (f and r) then task.wait(1) return end
	local best, bd
	for _, c in ipairs(f:GetChildren()) do
		local t = amberVisited[c]
		if not t or os.clock() - t > 90 then
			local d = (c:GetPivot().Position - r.Position).Magnitude
			if not bd or d < bd then best, bd = c, d end
		end
	end
	if not best then task.wait(2) return end
	local before = LP:GetAttribute("Amber") or 0
	travelTo(best:GetPivot().Position)
	r = root()
	if r and best.Parent then r.CFrame = CFrame.new(best:GetPivot().Position + Vector3.new(0, 1, 0)) end
	task.wait(0.8)
	amberVisited[best] = os.clock()
	log(("amber %d -> %d"):format(before, LP:GetAttribute("Amber") or 0))
end
task.spawn(function()
	while Hub.Running do
		if F("AutoAmber") and char() then pcall(amberStep) else task.wait(1) end
		task.wait(0.1)
	end
end)

local function act(fn, ...)
	local a = table.pack(...)
	task.spawn(function()
		local ok, res, msg = pcall(fn, table.unpack(a, 1, a.n))
		log(ok and tostring(msg or res) or ("error: " .. tostring(res)))
	end)
end

local Combat = Window:CreateTab({ Name = "Combat", Desc = "Aura, lunge, reach", Icon = "swords" })
local AuraSub = Combat:CreateSubTab({ Name = "Aura", Icon = "crosshair" })
local ReachSub = Combat:CreateSubTab({ Name = "Reach & ESP", Icon = "maximize" })

local aura = AuraSub:CreateGroupbox({ Name = "Kill Aura", Side = "Left", Icon = "zap" })
aura:CreateToggle({ Name = "Kill Aura", Flag = "KillAura", CurrentValue = false })
aura:CreateDropdown({ Name = "Aura Target", Options = { "Both", "Players", "NPCs" }, CurrentOption = "Both", Flag = "AuraTarget" })
aura:CreateSlider({ Name = "Aura Range", Range = { 4, 40 }, Increment = 1, CurrentValue = 12, Suffix = " st", Flag = "AuraRange" })
aura:CreateDropdown({ Name = "Bite Method", Options = { "Game", "Remote" }, CurrentOption = "Game", Flag = "BiteMethod" })
aura:CreateSlider({ Name = "Bite Delay", Range = { 0.6, 2 }, Increment = 0.05, CurrentValue = 0.6, Suffix = " s", Flag = "AuraDelay" })
aura:CreateToggle({ Name = "Face Target", Flag = "FaceTarget", CurrentValue = true })
aura:CreateToggle({ Name = "Stick To Target", Desc = "Server only accepts bites inside real reach", Flag = "StickTarget", CurrentValue = true })
aura:CreateSlider({ Name = "Stick Distance", Range = { 0.5, 6 }, Increment = 0.1, CurrentValue = 1.8, Suffix = " st", Flag = "StickDistance" })
aura:CreateInput({ Name = "Whitelist", Desc = "Names, comma separated", PlaceholderText = "name1, name2", Flag = "AuraWhitelistText" })

local lungeG = AuraSub:CreateGroupbox({ Name = "Lunge", Side = "Right", Icon = "move-up-right" })
lungeG:CreateToggle({ Name = "Auto Lunge", Flag = "AutoLunge", CurrentValue = false })
lungeG:CreateDropdown({ Name = "Lunge Target", Options = { "Both", "Players", "NPCs" }, CurrentOption = "Both", Flag = "LungeTarget" })
lungeG:CreateSlider({ Name = "Lunge Range", Range = { 8, 60 }, Increment = 1, CurrentValue = 30, Suffix = " st", Flag = "LungeRange" })
lungeG:CreateSlider({ Name = "Min Lunge Range", Range = { 0, 20 }, Increment = 1, CurrentValue = 6, Suffix = " st", Flag = "LungeMin" })
lungeG:CreateToggle({ Name = "Predict Target", Flag = "LungePredict", CurrentValue = true })
lungeG:CreateButton({ Name = "Lunge Now", Icon = "zap", Callback = function() Hub.lungeNow() end })
lungeG:CreateKeybind({ Name = "Lunge Key", CurrentKeybind = "Q", Flag = "LungeKey", Callback = function() Hub.lungeNow() end })
local esc = AuraSub:CreateGroupbox({ Name = "Defense", Side = "Right", Icon = "shield" })
esc:CreateToggle({ Name = "Auto Grab Escape", Flag = "AutoEscape", CurrentValue = false })

local reach = ReachSub:CreateGroupbox({ Name = "Bite Reach", Side = "Left", Icon = "ruler" })
reach:CreateToggle({ Name = "Bite Reach", Flag = "BiteReach", CurrentValue = false })
reach:CreateSlider({ Name = "Reach", Range = { 2, 60 }, Increment = 0.5, CurrentValue = 40, Suffix = " st", Flag = "ReachStuds" })
reach:CreateToggle({ Name = "Show Reach Hitbox", Flag = "ShowReach", CurrentValue = true })
local espG = ReachSub:CreateGroupbox({ Name = "ESP", Side = "Right", Icon = "eye" })
espG:CreateToggle({ Name = "Player ESP", Flag = "EspPlayers", CurrentValue = false })
espG:CreateToggle({ Name = "NPC ESP", Flag = "EspNPCs", CurrentValue = false })
espG:CreateToggle({ Name = "Health ESP", Flag = "EspHealth", CurrentValue = true })

local Move = Window:CreateTab({ Name = "Movement", Desc = "Sprint, speed, survival", Icon = "footprints" })
local sp = Move:CreateGroupbox({ Name = "Sprint", Side = "Left", Icon = "wind" })
sp:CreateToggle({ Name = "Auto Sprint", Flag = "AutoSprint", CurrentValue = false })
sp:CreateDropdown({ Name = "Sprint Type", Options = { "Sprint", "Trot", "Gallop" }, CurrentOption = "Sprint", Flag = "SprintType" })
local tr = Move:CreateGroupbox({ Name = "Survival", Side = "Right", Icon = "droplet" })
tr:CreateButton({ Name = "Travel To Food", Icon = "drumstick", Callback = function() act(goFood) end })
tr:CreateButton({ Name = "Stop Travel", Style = "Danger", Callback = function() stopTravel = true fire(R.Actions, "Feed", false) end })

local Misc = Window:CreateTab({ Name = "Misc", Desc = "Anti AFK, farm, status", Icon = "settings" })
local mg = Misc:CreateGroupbox({ Name = "Utility", Side = "Left", Icon = "wrench" })
mg:CreateToggle({ Name = "Anti AFK", Flag = "AntiAfk", CurrentValue = true, Callback = function(v) Hub.AntiAfk = v end })
Hub.AntiAfk = true
mg:CreateToggle({ Name = "Auto Amber Farm", Desc = "Collects amber chunks and claims rewards", Flag = "AutoAmber", CurrentValue = false })
mg:CreateButton({ Name = "Claim Rewards", Callback = function() claimRewards() end })
mg:CreateToggle({ Name = "Auto Spawn (menu)", Flag = "AutoSpawn", CurrentValue = true })
mg:CreateSlider({ Name = "Spawn Slot", Range = { 1, 10 }, Increment = 1, CurrentValue = 1, Flag = "SpawnSlot" })
mg:CreateButton({ Name = "Unload", Style = "Danger", Callback = function() Hub.Unload() end })
local stat = Misc:CreateGroupbox({ Name = "Status", Side = "Right", Icon = "activity" })
stat:CreateLabel({ Text = "", Update = function()
	local c = char()
	return ("Hunger %d | Thirst %d | Stamina %d | Amber %d"):format(c and c:GetAttribute("Hunger") or 0, c and c:GetAttribute("Thirst") or 0, c and c:GetAttribute("Stamina") or 0, LP:GetAttribute("Amber") or 0)
end })
stat:CreateLabel({ Text = "", Update = function() return Hub.Log[1] or "" end })

function Hub.Unload()
	Hub.Running = false
	stopTravel = true
	clearSprint()
	pcall(function() espFolder:Destroy() end)
	if reachBall then reachBall:Destroy() end
	if Hub.reachPart then Hub.reachPart:Destroy() end
	local r = root()
	if r and boxSaved then r:SetAttribute("FeralBoxFull", boxSaved[1] ~= false and boxSaved[1] or nil) end
	if oldNC then pcall(hookmetamethod, game, "__namecall", oldNC) end
	for _, c in ipairs(Hub.Conns) do pcall(function() c:Disconnect() end) end
	pcall(function() Window:Destroy() end)
	getgenv().VoidHubFeral = nil
end

Hub.travelPlace, Hub.goWater, Hub.goFood, Hub.nearestTarget, Hub.bite, Hub.travelTo = travelPlace, goWater, goFood, nearestTarget, bite, travelTo
Window:LoadAutoload()
return Hub
