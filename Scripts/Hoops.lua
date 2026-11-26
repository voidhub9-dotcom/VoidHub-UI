-- VoidHub: basketball (Practical's Games, GameId 7529591378).
-- Remotes, payloads and the shot grade scale were read live from the game's client code (PlaceVersion 138).

if getgenv().HoopHub and getgenv().HoopHub.Unload then pcall(getgenv().HoopHub.Unload) end
if getgenv().__oldnc then pcall(hookmetamethod, game, "__namecall", getgenv().__oldnc) getgenv().__oldnc = nil end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")

local LP = Players.LocalPlayer
local Remote = RS.Aero.AeroRemoteServices
local Input = Remote.InputService
local Aero = LP.PlayerScripts.Aero

local Hub = { Conns = {}, Running = true, Stats = { Shots = 0, Perfect = 0 }, Log = {} }
getgenv().HoopHub = Hub
local function conn(c) table.insert(Hub.Conns, c) return c end
local function log(t) table.insert(Hub.Log, 1, os.date("%H:%M:%S ") .. t) if #Hub.Log > 40 then table.remove(Hub.Log) end end

local Flags
local function F(n)
	local f = Flags and Flags[n]
	if not f then return nil end
	if f.Get then local ok, v = pcall(f.Get, f) if ok then return v end end
	return f.Value
end

-- ===================================================================== character / court helpers
local function MyChar() return workspace.Characters:FindFirstChild(LP.Name) end
local function Root(c) c = c or MyChar() return c and c:FindFirstChild("HumanoidRootPart") end
local function attr(c, k) return c and c:GetAttribute(k) end
local Mobile = require(Aero.Modules.Components.Input.Mobile)

local function isPlayerChar(c) return c:IsA("Model") and c:FindFirstChild("HumanoidRootPart") and c.Name ~= "InvisCharacter" and c.Name ~= "ReferenceRig" end
local function others()
	local t = {}
	for _, c in ipairs(workspace.Characters:GetChildren()) do
		if c ~= MyChar() and isPlayerChar(c) and attr(c, "OnCourt") ~= false then table.insert(t, c) end
	end
	return t
end
local function isOpponent(c)
	local me = MyChar()
	if not F("TeamCheck") then return true end
	return attr(c, "TeamIndex") ~= attr(me, "TeamIndex") or attr(me, "TeamIndex") == 0
end
local function opponents() local t = {} for _, c in ipairs(others()) do if isOpponent(c) then table.insert(t, c) end end return t end

local function balls() return workspace.Basketballs:GetChildren() end
local function ballCarrier()
	-- the ball sits in the carrier's hands; nearest character within 4 studs of a ball
	for _, b in ipairs(balls()) do
		local bp = b:GetPivot().Position
		for _, c in ipairs(workspace.Characters:GetChildren()) do
			local r = Root(c)
			if r and isPlayerChar(c) and (r.Position - bp).Magnitude < 4 then return c, b end
		end
	end
end
local function iHaveBall() local c = ballCarrier() return c == MyChar() end

local function rims()
	local t = {}
	for _, h in ipairs(workspace.Hoops:GetChildren()) do
		local rim = h:FindFirstChild("Rim", true)
		if rim then table.insert(t, rim) end
	end
	return t
end
local function nearestRim(pos)
	local best, bd
	for _, r in ipairs(rims()) do local d = (r.Position - pos).Magnitude if not bd or d < bd then best, bd = r, d end end
	return best, bd
end

-- movement: the game reads the mobile thumbstick vector (camera-relative); we steer by writing it
local steering = false
local function steer(worldTarget)
	local r = Root() if not r then return end
	local w = (worldTarget - r.Position) * Vector3.new(1, 0, 1)
	if w.Magnitude < 0.5 then Mobile.MoveVector = Vector3.zero return true end
	w = w.Unit
	local cam = workspace.CurrentCamera
	local look = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z).Unit
	local right = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z).Unit
	Mobile.MoveVector = Vector3.new(w:Dot(right), 0, -w:Dot(look))
	steering = true
	return false
end
local function stopSteer() if steering then Mobile.MoveVector = Vector3.zero steering = false end end

-- ===================================================================== contest / coverage
local function contestInfo()
	local r = Root() if not r then return 0, nil, math.huge end
	local rim = nearestRim(r.Position)
	local best, bd = nil, math.huge
	for _, c in ipairs(opponents()) do
		local cr = Root(c)
		if cr then local d = (cr.Position - r.Position).Magnitude if d < bd then best, bd = c, d end end
	end
	if not best then return 0, nil, math.huge end
	-- coverage: closer and more between you and the rim means more contest
	local closeness = math.clamp(1 - (bd - 3) / ((F("ContestRange") or 10) - 3), 0, 1)
	local facing = 1
	if rim then
		local toRim = ((rim.Position - r.Position) * Vector3.new(1, 0, 1))
		local toDef = ((Root(best).Position - r.Position) * Vector3.new(1, 0, 1))
		if toRim.Magnitude > 0 and toDef.Magnitude > 0 then facing = math.clamp((toRim.Unit:Dot(toDef.Unit) + 1) / 2, 0.3, 1) end
	end
	return math.floor(closeness * facing * 100), best, bd
end
local function contestLabel(p)
	if p < 15 then return "WIDE OPEN", Color3.fromRGB(80, 255, 120)
	elseif p < 40 then return "OPEN", Color3.fromRGB(170, 255, 80)
	elseif p < 65 then return "CONTESTED", Color3.fromRGB(255, 200, 60)
	elseif p < 85 then return "HEAVILY CONTESTED", Color3.fromRGB(255, 120, 40)
	else return "SMOTHERED", Color3.fromRGB(255, 50, 50) end
end

-- ===================================================================== perfect timing
-- ShowFeedback(player, contest, timing): 1 VeryEarly 2 Early 3 SlightlyEarly 4 Good 5 Perfect 6 SlightlyLate 7 Late 8 VeryLate
local GRADES = { "Very Early", "Early", "Slightly Early", "Good", "PERFECT", "Slightly Late", "Late", "Very Late" }
local Timing = { offsets = {}, pending = false, ours = false, lastPress = 0, rtt = 0.12, cur = nil }
Hub.Timing = Timing
local function holdFor(meter)
	local base = F("HoldTime") or 0.27
	local off = Timing.offsets[meter or "?"] or 0
	local ping = F("PingComp") and math.clamp(Timing.rtt - 0.12, -0.05, 0.15) * (F("PingFactor") or 0.5) or 0
	return math.clamp(base + off - ping, 0.05, 1.5)
end

local shootRemote = Input.Shoot
local oldNC
local function release() Timing.ours = true pcall(function() shootRemote:FireServer({ Shoot = false }) end) Timing.ours = false Timing.pending = false end
local function scheduleRelease(meter)
	local d = holdFor(meter)
	Timing.cur = { hold = d, meter = meter, t = os.clock() }
	task.delay(d, function() if Timing.pending then release() end end)
end

oldNC = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
	if self == shootRemote and not Timing.ours and getnamecallmethod() == "FireServer" and Hub.Running then
		local a = ...
		if F("PerfectTiming") and type(a) == "table" then
			if a.Shoot == true then
				Timing.pending, Timing.lastPress, Timing.meter = true, os.clock(), nil
				local r = oldNC(self, ...)
				-- release starts counting from the press; meter type arrives in RegisterPacket and refines it
				task.spawn(function()
					local t0 = os.clock()
					while Timing.pending and not Timing.meter and os.clock() - t0 < 0.5 do task.wait() end
					if Timing.pending then scheduleRelease(Timing.meter) end
				end)
				return r
			elseif a.Shoot == false and Timing.pending then
				return -- the player's own release is replaced by the timed one
			end
		end
	end
	return oldNC(self, ...)
end))

conn(Remote.MeterService.RegisterPacket.OnClientEvent:Connect(function(pl, meter, value)
	if pl == MyChar() or (typeof(pl) == "Instance" and pl.Name == LP.Name) then
		Timing.meter = meter
		Timing.rtt = os.clock() - Timing.lastPress
	end
end))

conn(Remote.InterfaceService.ShowFeedback.OnClientEvent:Connect(function(pl, contest, timing)
	if not (typeof(pl) == "Instance" and pl.Name == LP.Name) then return end
	local g = tonumber(timing)
	Hub.Stats.Shots += 1
	if g == 5 then Hub.Stats.Perfect += 1 end
	local cur = Timing.cur
	Hub.LastGrade = (GRADES[g] or "?") .. (cur and (" @ %.3fs"):format(cur.hold) or "") .. " contest " .. tostring(contest)
	log("Shot: " .. Hub.LastGrade)
	if F("AutoCalibrate") and cur and g then
		-- early grades mean hold longer, late grades shorter; step shrinks near perfect
		local step = ({ 0.05, 0.03, 0.012, 0.006, 0, -0.012, -0.03, -0.05 })[g] or 0
		Timing.offsets[cur.meter or "?"] = (Timing.offsets[cur.meter or "?"] or 0) + step
	end
	Timing.cur = nil
end))

-- ===================================================================== actions
local function fire(remote, ...) local a = table.pack(...) pcall(function() remote:FireServer(table.unpack(a, 1, a.n)) end) end
local function jump() fire(Input.Jump) end
local function shootTap()
	fire(Input.Shoot, { Shoot = true, Input = "E", UseSpace = true })
	if not F("PerfectTiming") then task.delay(F("HoldTime") or 0.27, function() fire(Input.Shoot, { Shoot = false }) end) end
end

local DribbleMap = require(RS.Aero.Shared.Config.Game.Dribbling).Input
local MoveNames = {}
do
	local seen = {}
	for _, v in pairs(DribbleMap) do for _, n in ipairs({ v.L, v.R }) do if n and n ~= "" and not seen[n] then seen[n] = true table.insert(MoveNames, n) end end end
	table.sort(MoveNames)
end
local function comboFor(move)
	local hand = attr(MyChar(), "Hand") or "R"
	for combo, v in pairs(DribbleMap) do if v[hand] == move then return combo end end
	for combo, v in pairs(DribbleMap) do if v.L == move or v.R == move then return combo end end
end
local function dribble(move)
	local combo = comboFor(move)
	if not combo then log("No input for " .. move .. " with this hand") return false end
	local mv = require(Aero.Modules.Components.Character.Movement)
	fire(Input.Dribble, combo, attr(MyChar(), "Sprinting") == true, mv and mv.lastMoveDirection or Vector3.zero)
	return true
end
local function playCombo(list, gap)
	for _, m in ipairs(list) do if not Hub.Running then break end dribble(m) task.wait(gap or 0.45) end
end

local function pass(name, ptype) fire(Input.Pass, { Player = name, PassType = ptype or 1 }) end

-- ===================================================================== loops
local lastBlock, lastSteal, lastShot, lastJump = 0, 0, 0, 0
conn(RunService.Heartbeat:Connect(function()
	if not Hub.Running then return end
	local me = MyChar() local r = Root(me)
	if not r then return end

	if F("InfStamina") then me:SetAttribute("Stamina", 100) end
	if F("SpeedBoost") then me:SetAttribute("SpeedBoost", F("SpeedValue") or 3) end
	if F("NoStun") and me:GetAttribute("CanMove") == false and me:GetAttribute("Action") ~= "Shooting" then me:SetAttribute("CanMove", true) end
	if F("AlwaysSprint") and not attr(me, "Sprinting") then fire(Input.Sprint, true) end
end))

task.spawn(function()
	while Hub.Running do
		local ok, e = pcall(function()
			local me = MyChar() local r = Root(me)
			if not r then return end
			local carrier, ball = ballCarrier()

			-- auto shoot when open and in range
			if F("AutoShoot") and carrier == me and os.clock() - lastShot > 1.5 then
				local p = contestInfo()
				local _, rimD = nearestRim(r.Position)
				if p <= (F("MaxContest") or 35) and rimD and rimD <= (F("ShootRange") or 30) then lastShot = os.clock() shootTap() log(("Auto shot (contest %d%%, %.0f st)"):format(p, rimD)) end
			end

			-- auto block: an opponent starts a shot near you
			if F("AutoBlock") and os.clock() - lastBlock > 1 then
				for _, c in ipairs(opponents()) do
					local cr = Root(c)
					if cr and attr(c, "Action") == "Shooting" and (cr.Position - r.Position).Magnitude <= (F("BlockRange") or 10) then
						if not (F("PumpFakeFilter") and attr(c, "GatherType") == "Pumpfake" and not attr(c, "InAir")) then
							lastBlock = os.clock()
							if F("SwatAway") then steer(cr.Position) end
							task.delay(F("BlockDelay") or 0.12, jump)
							log("Block attempt on " .. c.Name)
							break
						end
					end
				end
			end

			-- auto steal near the ball handler
			if F("AutoSteal") and carrier and carrier ~= me and isOpponent(carrier) and os.clock() - lastSteal > (F("StealCooldown") or 1.2) then
				local cr = Root(carrier)
				if cr and (cr.Position - r.Position).Magnitude <= (F("StealRange") or 6) and not attr(me, "Fouled") then
					lastSteal = os.clock() fire(Input.Steal) log("Steal attempt")
				end
			end

			-- defense: stay between handler and rim, hold G
			local moving = false
			if F("AutoGuard") and carrier and carrier ~= me and isOpponent(carrier) then
				local cr = Root(carrier)
				local rim = nearestRim(cr.Position)
				if cr and rim and (cr.Position - r.Position).Magnitude < (F("GuardRange") or 40) then
					local dir = ((rim.Position - cr.Position) * Vector3.new(1, 0, 1))
					if dir.Magnitude > 0 then
						local spot = cr.Position + dir.Unit * (F("GuardDistance") or 4)
						if math.random() > (F("Mistakes") or 0) / 100 then steer(spot) moving = true end
					end
					if F("AutoHoldG") and not attr(me, "HoldingG") then fire(Input.HoldG, { HoldingG = true }) end
				end
			end

			-- ball magnet / rebound: go to a loose ball
			if not moving and (F("BallMagnet") or F("AutoRebound")) and not carrier then
				local best, bd
				for _, b in ipairs(balls()) do local d = (b:GetPivot().Position - r.Position).Magnitude if not bd or d < bd then best, bd = b, d end end
				if best and bd <= (F("MagnetRange") or 40) then
					steer(best:GetPivot().Position) moving = true
					if F("AutoRebound") and best:GetPivot().Position.Y - r.Position.Y > 4 and bd < 8 and os.clock() - lastJump > 1 then lastJump = os.clock() jump() end
				end
			end
			if not moving then stopSteer() end
		end)
		if not ok then log("loop: " .. tostring(e)) end
		task.wait(F("ReactionTime") and (F("ReactionTime") / 1000) or 0.05)
	end
end)

-- ===================================================================== overhead contest + range + ESP
local gui = Instance.new("BillboardGui")
gui.Name = "HoopHubContest" gui.Size = UDim2.fromOffset(160, 44) gui.StudsOffset = Vector3.new(0, 3.6, 0) gui.AlwaysOnTop = true
gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
local glabel = Instance.new("TextLabel")
glabel.Size = UDim2.fromScale(1, 1) glabel.BackgroundTransparency = 1 glabel.Font = Enum.Font.GothamBlack glabel.TextScaled = true glabel.TextStrokeTransparency = 0.2 glabel.Parent = gui

local espFolder = Instance.new("Folder") espFolder.Name = "HoopHubESP" espFolder.Parent = gui.Parent
local esp = {}
local function setEsp(model, color, text)
	local o = esp[model]
	if not o then
		o = { hl = Instance.new("Highlight"), bb = Instance.new("BillboardGui") }
		o.hl.FillTransparency = 0.8 o.hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop o.hl.Adornee = model o.hl.Parent = espFolder
		o.bb.Size = UDim2.fromOffset(160, 30) o.bb.StudsOffset = Vector3.new(0, 3, 0) o.bb.AlwaysOnTop = true o.bb.Adornee = model o.bb.Parent = espFolder
		o.tl = Instance.new("TextLabel") o.tl.Size = UDim2.fromScale(1, 1) o.tl.BackgroundTransparency = 1 o.tl.Font = Enum.Font.GothamBold o.tl.TextSize = 13 o.tl.TextStrokeTransparency = 0.3 o.tl.Parent = o.bb
		esp[model] = o
	end
	o.hl.OutlineColor, o.hl.FillColor, o.tl.TextColor3, o.tl.Text = color, color, color, text
	o.alive = true
end

local rangeRing
conn(RunService.RenderStepped:Connect(function()
	local me = MyChar() local r = Root(me)
	-- contest overlay
	if F("ShowContest") and r then
		local p, def, d = contestInfo()
		local txt, col = contestLabel(p)
		gui.Adornee = r gui.Enabled = true
		glabel.Text = ("%s  %d%%"):format(txt, p) glabel.TextColor3 = col
	else gui.Enabled = false end
	-- shooting range ring
	if F("ShowRange") and r then
		if not rangeRing then
			rangeRing = Instance.new("CylinderHandleAdornment") rangeRing.Transparency = 0.75 rangeRing.Height = 0.2 rangeRing.InnerRadius = 0 rangeRing.AlwaysOnTop = false rangeRing.Parent = espFolder
		end
		local rim = nearestRim(r.Position)
		if rim then
			rangeRing.Adornee = workspace.Terrain
			rangeRing.Radius = F("ShootRange") or 30
			rangeRing.CFrame = CFrame.new(rim.Position.X, r.Position.Y - 2.8, rim.Position.Z) * CFrame.Angles(math.rad(90), 0, 0)
			local _, rd = nearestRim(r.Position)
			rangeRing.Color3 = (rd or 99) <= (F("ShootRange") or 30) and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 80, 80)
			rangeRing.Visible = true
		end
	elseif rangeRing then rangeRing.Visible = false end
	-- ESP
	for _, o in pairs(esp) do o.alive = false end
	if F("PlayerESP") then
		for _, c in ipairs(others()) do
			local col = isOpponent(c) and (F("EnemyColor") or Color3.fromRGB(255, 80, 80)) or (F("TeamColor") or Color3.fromRGB(80, 170, 255))
			local info = F("RosterInfo") and (" | %s OVR %s"):format(tostring(attr(c, "BuildName") or ""), tostring(attr(c, "Overall") or "?")) or ""
			setEsp(c, col, c.Name .. info)
		end
	end
	if F("BallESP") then for _, b in ipairs(balls()) do setEsp(b, F("BallColor") or Color3.fromRGB(255, 170, 40), "BALL") end end
	for m, o in pairs(esp) do if not o.alive or not m.Parent then o.hl:Destroy() o.bb:Destroy() esp[m] = nil end end
	-- world
	if F("Fullbright") then Lighting.Brightness, Lighting.ClockTime, Lighting.GlobalShadows = 2, 14, false Lighting.Ambient = Color3.new(1, 1, 1) end
	if F("CustomFOV") then workspace.CurrentCamera.FieldOfView = F("FOV") or 80 end
end))

local savedFx = {}
local function postEffects(off)
	if off then for _, e in ipairs(Lighting:GetChildren()) do if e:IsA("PostEffect") and e.Enabled then e.Enabled = false table.insert(savedFx, e) end end
	else for _, e in ipairs(savedFx) do pcall(function() e.Enabled = true end) end savedFx = {} end
end

conn(LP.Idled:Connect(function() if F("AntiAFK") ~= false then VirtualUser:CaptureController() VirtualUser:ClickButton2(Vector2.zero) end end))

-- ===================================================================== UI
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/voidhub9-dotcom/VoidHub-UI/main/Source.lua"))()
local Window = Library:CreateVoidHubWindow({
	Name = "VoidHub", Title = "VoidHub", LoadingTitle = "VoidHub",
	ToggleUIKeybind = "RightControl",
	ConfigurationSaving = { Enabled = true, FolderName = "VoidHubHoops" },
	Home = { Welcome = "Hoops" },
	ToggleButton = { Platform = "Mobile" },
})
Flags = Window.Flags
Hub.Window = Window
local function notify(t, c, k) Window:Notify({ Title = t, Content = c, Type = k, Duration = 3 }) end

do -- Offense
	local Off = Window:CreateTab({ Name = "Offense", Desc = "Timing, shooting, dribbling, passing", Icon = "target" })
	local PT = Off:CreateSubTab({ Name = "Perfect Timing", Icon = "timer" })
	local AS = Off:CreateSubTab({ Name = "Auto Shoot", Icon = "crosshair" })
	local DR = Off:CreateSubTab({ Name = "Dribble", Icon = "repeat" })
	local CC = Off:CreateSubTab({ Name = "Combo Creator", Icon = "list" })
	local PL = Off:CreateSubTab({ Name = "Pass Link", Icon = "send" })

	local t = PT:CreateGroupbox({ Name = "Perfect Timing", Side = "Left", Icon = "timer" })
	t:CreateToggle({ Name = "Perfect Timing", Desc = "Replaces your release with a timed one.", Flag = "PerfectTiming", CurrentValue = true })
	t:CreateSlider({ Name = "Hold time", Range = { 0.1, 0.8 }, Increment = 0.005, CurrentValue = 0.27, Suffix = " s", Flag = "HoldTime", Desc = "0.20 s graded Early, 0.35 s Late in tests." })
	t:CreateToggle({ Name = "Auto calibrate", Desc = "Learns from the game's own shot feedback.", Flag = "AutoCalibrate", CurrentValue = true })
	t:CreateToggle({ Name = "Ping compensation", Flag = "PingComp", CurrentValue = true })
	t:CreateSlider({ Name = "Ping factor", Range = { 0, 1 }, Increment = 0.05, CurrentValue = 0.5, Flag = "PingFactor" })
	t:CreateButton({ Name = "Reset calibration", Callback = function() Timing.offsets = {} end })
	local s = PT:CreateGroupbox({ Name = "Stats", Side = "Right", Icon = "activity" })
	s:CreateStatus({ Name = "Last shot", Style = "Row", Update = function() return Hub.LastGrade or "-" end })
	s:CreateStatus({ Name = "Perfect / shots", Style = "Row", Update = function() return ("%d / %d"):format(Hub.Stats.Perfect, Hub.Stats.Shots) end })
	s:CreateStatus({ Name = "Ping (press to meter)", Style = "Row", Update = function() return ("%d ms"):format(Timing.rtt * 1000) end })
	s:CreateStatusList({ Name = "Learned offsets", MaxRows = 6, EmptyText = "None yet", Update = function()
		local rows = {} for m, o in pairs(Timing.offsets) do rows[#rows + 1] = { Text = m, Value = ("%+.3f s"):format(o) } end return rows
	end })

	local a = AS:CreateGroupbox({ Name = "Auto Shoot", Side = "Left", Icon = "crosshair" })
	a:CreateToggle({ Name = "Auto shoot when open", Flag = "AutoShoot", CurrentValue = false })
	a:CreateSlider({ Name = "Max contest", Range = { 0, 100 }, Increment = 1, CurrentValue = 35, Suffix = "%", Flag = "MaxContest" })
	a:CreateSlider({ Name = "Shoot range", Range = { 5, 60 }, Increment = 1, CurrentValue = 30, Suffix = " st", Flag = "ShootRange" })
	a:CreateToggle({ Name = "Show range", Flag = "ShowRange", CurrentValue = false })
	a:CreateToggle({ Name = "Show contest overhead", Desc = "WIDE OPEN to SMOTHERED with a coverage percent.", Flag = "ShowContest", CurrentValue = true })
	a:CreateSlider({ Name = "Contest radius", Range = { 4, 20 }, Increment = 1, CurrentValue = 10, Flag = "ContestRange" })
	a:CreateButton({ Name = "Self lob", Callback = function() pass(LP.Name, 4) end })

	local d = DR:CreateGroupbox({ Name = "Dribble moves", Side = "Left", Icon = "repeat" })
	for _, m in ipairs(MoveNames) do d:CreateButton({ Name = m, Callback = function() dribble(m) end }) end
	local d2 = DR:CreateGroupbox({ Name = "Info", Side = "Right", Icon = "info" })
	d2:CreateParagraph({ Name = "Hand aware", Content = "Each move sends the combo that matches your current dribble hand. Euro step, hop step, side steps, spin gather and halo are gather moves with no combo input; not included." })

	local c = CC:CreateGroupbox({ Name = "Combo Creator", Side = "Left", Icon = "list" })
	c:CreateDropdown({ Name = "Moves", Options = MoveNames, MultipleOptions = true, AllowNone = true, Flag = "ComboMoves", NoneText = "Pick moves" })
	c:CreateSlider({ Name = "Gap between moves", Range = { 0.2, 1.5 }, Increment = 0.05, CurrentValue = 0.45, Suffix = " s", Flag = "ComboGap" })
	c:CreateKeybind({ Name = "Play combo", CurrentKeybind = "T", Flag = "ComboKey", Callback = function() task.spawn(playCombo, F("ComboMoves") or {}, F("ComboGap")) end })
	c:CreateButton({ Name = "Play combo now", Callback = function() task.spawn(playCombo, F("ComboMoves") or {}, F("ComboGap")) end })
	c:CreateToggle({ Name = "Loop combo", Flag = "LoopCombo", CurrentValue = false, Callback = function(on)
		if on then task.spawn(function() while F("LoopCombo") and Hub.Running do playCombo(F("ComboMoves") or {}, F("ComboGap")) task.wait(0.3) end end) end
	end })

	local p = PL:CreateGroupbox({ Name = "Pass Link", Side = "Left", Icon = "send" })
	local function names() local t = {} for _, pl in ipairs(Players:GetPlayers()) do if pl ~= LP then t[#t + 1] = pl.Name end end return t end
	local dd = p:CreateDropdown({ Name = "Linked player", Options = names(), AllowNone = true, Flag = "PassTarget" })
	p:CreateButton({ Name = "Refresh players", Callback = function() dd:SetOptions(names()) end })
	p:CreateStepper({ Name = "Pass type", Range = { 1, 4 }, Increment = 1, CurrentValue = 1, Flag = "PassType", Desc = "4 is a lob." })
	p:CreateKeybind({ Name = "Pass to linked", CurrentKeybind = "Q", Flag = "PassKey", Callback = function() if F("PassTarget") then pass(F("PassTarget"), F("PassType")) end end })
end

do -- Defense
	local Def = Window:CreateTab({ Name = "Defense", Desc = "Block, rebound, guard, steal", Icon = "shield" })
	local B = Def:CreateSubTab({ Name = "Block", Icon = "hand" })
	local G = Def:CreateSubTab({ Name = "Guard", Icon = "shield" })
	local b = B:CreateGroupbox({ Name = "Block & rebound", Side = "Left", Icon = "hand" })
	b:CreateToggle({ Name = "Auto block", Flag = "AutoBlock", CurrentValue = false })
	b:CreateSlider({ Name = "Block range", Range = { 3, 20 }, Increment = 0.5, CurrentValue = 10, Flag = "BlockRange" })
	b:CreateSlider({ Name = "Jump delay", Range = { 0, 0.5 }, Increment = 0.01, CurrentValue = 0.12, Suffix = " s", Flag = "BlockDelay" })
	b:CreateToggle({ Name = "Pump fake filter", Flag = "PumpFakeFilter", CurrentValue = true })
	b:CreateToggle({ Name = "Swat away (move into shooter)", Flag = "SwatAway", CurrentValue = false })
	b:CreateToggle({ Name = "Auto rebound", Flag = "AutoRebound", CurrentValue = false })
	b:CreateToggle({ Name = "Ball magnet", Desc = "Walks to the nearest loose ball.", Flag = "BallMagnet", CurrentValue = false })
	b:CreateSlider({ Name = "Magnet range", Range = { 5, 120 }, Increment = 5, CurrentValue = 40, Flag = "MagnetRange" })
	b:CreateToggle({ Name = "Team check", Flag = "TeamCheck", CurrentValue = true })
	local g = G:CreateGroupbox({ Name = "Guard", Side = "Left", Icon = "shield" })
	g:CreateToggle({ Name = "Auto guard", Desc = "Stays between the ball handler and the rim.", Flag = "AutoGuard", CurrentValue = false })
	g:CreateToggle({ Name = "Auto hold G", Flag = "AutoHoldG", CurrentValue = true })
	g:CreateSlider({ Name = "Distance", Range = { 1, 10 }, Increment = 0.5, CurrentValue = 4, Flag = "GuardDistance" })
	g:CreateSlider({ Name = "Engage range", Range = { 10, 90 }, Increment = 5, CurrentValue = 40, Flag = "GuardRange" })
	g:CreateToggle({ Name = "Auto steal", Flag = "AutoSteal", CurrentValue = false })
	g:CreateSlider({ Name = "Steal range", Range = { 2, 12 }, Increment = 0.5, CurrentValue = 6, Flag = "StealRange" })
	g:CreateSlider({ Name = "Steal cooldown", Range = { 0.3, 4 }, Increment = 0.1, CurrentValue = 1.2, Suffix = " s", Flag = "StealCooldown" })
	local h = G:CreateGroupbox({ Name = "Humanization", Side = "Right", Icon = "user" })
	h:CreateSlider({ Name = "Reaction time", Range = { 0, 400 }, Increment = 10, CurrentValue = 50, Suffix = " ms", Flag = "ReactionTime" })
	h:CreateSlider({ Name = "Mistakes", Range = { 0, 50 }, Increment = 1, CurrentValue = 0, Suffix = "%", Flag = "Mistakes" })
end

do -- Player
	local Pl = Window:CreateTab({ Name = "Player", Desc = "Character tweaks", Icon = "user" })
	local C = Pl:CreateSubTab({ Name = "Character", Icon = "user" })
	local c = C:CreateGroupbox({ Name = "Character", Side = "Left", Icon = "user" })
	c:CreateToggle({ Name = "Always sprint", Flag = "AlwaysSprint", CurrentValue = false })
	c:CreateToggle({ Name = "Infinite stamina", Flag = "InfStamina", CurrentValue = false })
	c:CreateToggle({ Name = "Speed boost", Flag = "SpeedBoost", CurrentValue = false })
	c:CreateSlider({ Name = "Speed boost value", Range = { 1, 6 }, Increment = 0.1, CurrentValue = 3, Flag = "SpeedValue" })
	c:CreateToggle({ Name = "No stun", Flag = "NoStun", CurrentValue = false })
	c:CreateToggle({ Name = "Anti AFK", Flag = "AntiAFK", CurrentValue = true })
	c:CreateStatus({ Name = "Overall", Style = "Row", Update = function() return tostring(attr(MyChar(), "Overall") or "-") end })
end

do -- Visuals
	local V = Window:CreateTab({ Name = "Visuals", Desc = "ESP and world", Icon = "eye" })
	local W = V:CreateSubTab({ Name = "World", Icon = "sun" })
	local e = W:CreateGroupbox({ Name = "ESP", Side = "Left", Icon = "eye" })
	e:CreateToggle({ Name = "Player ESP", Flag = "PlayerESP", CurrentValue = false })
	e:CreateToggle({ Name = "Roster info (build, OVR)", Flag = "RosterInfo", CurrentValue = true })
	e:CreateToggle({ Name = "Ball ESP", Flag = "BallESP", CurrentValue = false })
	e:CreateColorPicker({ Name = "Enemy", Color = Color3.fromRGB(255, 80, 80), Flag = "EnemyColor" })
	e:CreateColorPicker({ Name = "Teammate", Color = Color3.fromRGB(80, 170, 255), Flag = "TeamColor" })
	e:CreateColorPicker({ Name = "Ball", Color = Color3.fromRGB(255, 170, 40), Flag = "BallColor" })
	local w = W:CreateGroupbox({ Name = "World", Side = "Right", Icon = "sun" })
	w:CreateToggle({ Name = "Fullbright", Flag = "Fullbright", CurrentValue = false })
	w:CreateToggle({ Name = "Remove post effects", Flag = "NoFx", CurrentValue = false, Callback = postEffects })
	w:CreateToggle({ Name = "Custom FOV", Flag = "CustomFOV", CurrentValue = false })
	w:CreateSlider({ Name = "FOV", Range = { 50, 120 }, Increment = 1, CurrentValue = 80, Flag = "FOV" })
end

do -- Misc
	local M = Window:CreateTab({ Name = "Misc", Desc = "Tasks, log, settings", Icon = "settings" })
	local T = M:CreateSubTab({ Name = "Tasks & Log", Icon = "list" })
	local St = M:CreateSubTab({ Name = "Settings", Icon = "sliders-horizontal" })
	local t = T:CreateGroupbox({ Name = "Daily tasks", Side = "Left", Icon = "gift" })
	t:CreateButton({ Name = "Claim daily tasks", Callback = function()
		task.spawn(function()
			local ok, tasks = pcall(function() return Remote.DailyTaskService.GetTasks:InvokeServer() end)
			local n = 0
			if ok and type(tasks) == "table" then
				for id in pairs(tasks) do local r = { pcall(function() return Remote.DailyTaskService.ClaimTask:InvokeServer(id) end) } if r[1] and r[2] then n += 1 end end
			end
			notify("Daily tasks", ("Claimed %d"):format(n), n > 0 and "Success" or "Warning")
		end)
	end })
	T:CreateGroupbox({ Name = "Log", Side = "Right", Icon = "list" }):CreateStatusList({ Name = "Events", MaxRows = 12, EmptyText = "Nothing yet", Update = function() return Hub.Log end })
	St:CreateConfigManager({ Side = "Left" })
	St:CreateThemeManager({ Side = "Right" })
	St:CreateGroupbox({ Name = "Hub", Side = "Left" }):CreateButton({ Name = "Unload", Style = "Danger", Callback = function() Hub.Unload() end })
end

function Hub.Unload()
	Hub.Running = false
	stopSteer()
	pcall(hookmetamethod, game, "__namecall", oldNC)
	for _, c in ipairs(Hub.Conns) do pcall(function() c:Disconnect() end) end
	postEffects(false)
	pcall(function() gui:Destroy() espFolder:Destroy() end)
	pcall(function() Window:Destroy() end)
	getgenv().HoopHub = nil
end

Window:LoadAutoload()
notify("VoidHub", "Loaded", "Success")
return Hub
