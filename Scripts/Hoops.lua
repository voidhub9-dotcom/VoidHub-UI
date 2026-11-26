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
		if c ~= MyChar() and isPlayerChar(c) and (Players:FindFirstChild(c.Name) or attr(c, "OnCourt") == true) then table.insert(t, c) end
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
local heldSeen = {}
local function ballCarrier()
	-- held ball: within 3 studs at hand height; a loose ball rests ~2-3 studs below the root.
	-- dribbling bounces it to the floor, so a recent hand-height sample still counts (0.7 s)
	local now = os.clock()
	for _, b in ipairs(balls()) do
		local bp = b:GetPivot().Position
		for _, c in ipairs(workspace.Characters:GetChildren()) do
			local r = Root(c)
			if r and isPlayerChar(c) and (c == MyChar() or Players:FindFirstChild(c.Name) or attr(c, "OnCourt") == true) then
				local d = ((bp - r.Position) * Vector3.new(1, 0, 1)).Magnitude
				if d < 3 and bp.Y - r.Position.Y > -1.5 then heldSeen[c] = { t = now, b = b } end
			end
		end
	end
	for c, h in pairs(heldSeen) do
		if not c.Parent or now - h.t > 0.7 then heldSeen[c] = nil
		else local r = Root(c) if r and (h.b:GetPivot().Position - r.Position).Magnitude < 4 then return c, h.b end end
	end
	do return nil end
	for _, b in ipairs(balls()) do
		local bp = b:GetPivot().Position
		for _, c in ipairs(workspace.Characters:GetChildren()) do
			local r = Root(c)
			if r and isPlayerChar(c) and (c == MyChar() or Players:FindFirstChild(c.Name) or attr(c, "OnCourt") == true) and (r.Position - bp).Magnitude < 4 then return c, b end
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

-- ===================================================================== ping + server position prediction
local function pingMs()
	local ms
	pcall(function()
		local item = game:GetService("Stats").Network.ServerStatsItem:FindFirstChild("Data Ping")
		if item then ms = item:GetValue() end
	end)
	if not ms or ms <= 0 then
		local ok, p = pcall(function() return LP:GetNetworkPing() end)
		if ok and type(p) == "number" then ms = p <= 5 and p * 1000 or p end
	end
	return math.clamp(ms or 60, 1, 5000)
end
Hub.Ping = pingMs
local cfHistory = {}
conn(RunService.Heartbeat:Connect(function()
	local now = tick()
	for _, c in ipairs(workspace.Characters:GetChildren()) do
		local r = c:FindFirstChild("HumanoidRootPart")
		if r then
			local h = cfHistory[c] or {}
			cfHistory[c] = h
			h[#h + 1] = { t = now, p = r.Position }
			while #h > 0 and now - h[1].t > 2 do table.remove(h, 1) end
		end
	end
	for c in pairs(cfHistory) do if not c.Parent then cfHistory[c] = nil end end
end))
-- where the server most likely has this character right now (client view is ping * 1.2 ahead for us)
local function serverPos(c)
	local r = Root(c) if not r then return nil end
	if not F("Prediction") then return r.Position end
	local h = cfHistory[c]
	if not h or #h == 0 then return r.Position end
	local target = tick() - pingMs() / 1000 * (F("PredictionMult") or 1.2)
	for i = 1, #h do if h[i].t >= target then return h[i].p end end
	return r.Position
end

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
local function rangeBucket()
	local r = Root() if not r then return "mid" end
	local _, d = nearestRim(r.Position)
	if not d then return "mid" end
	return d < 10 and "close" or (d > 22 and "three" or "mid")
end
local function calKey(meter) return (meter or "?") .. "/" .. (Timing.bucket or "mid") end
local function holdFor(meter)
	local base = F("HoldTime") or 0.29
	local off = Timing.offsets[calKey(meter)] or 0
	local ping = F("PingComp") and math.clamp(pingMs() / 1000 / 2, 0, 0.15) * (F("PingFactor") or 0.5) or 0
	return math.clamp(base + off - ping, 0.05, 1.5)
end

local shootRemote = Input.Shoot
local oldNC
local function release() Timing.ours = true pcall(function() shootRemote:FireServer({ Shoot = false }) end) Timing.ours = false Timing.pending = false end
local function scheduleRelease(meter)
	local d = holdFor(meter)
	Timing.cur = { hold = d, meter = meter, t = os.clock(), key = calKey(meter) }
	task.delay(d, function() if Timing.pending then release() end end)
end

oldNC = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
	if self == shootRemote and not Timing.ours and getnamecallmethod() == "FireServer" and Hub.Running then
		local a = ...
		if F("PerfectTiming") and type(a) == "table" then
			if a.Shoot == true then
				Timing.pending, Timing.lastPress, Timing.meter, Timing.bucket = true, os.clock(), nil, rangeBucket()
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

conn(Input.Output.OnClientEvent:Connect(function(kind, text)
	local st = type(text) == "string" and text:match("Shot Type %- ([%w]+)")
	if st then Hub.LastShotType = st end
end))
conn(Remote.InterfaceService.ShowFeedback.OnClientEvent:Connect(function(pl, contest, timing)
	if not (typeof(pl) == "Instance" and pl.Name == LP.Name) then return end
	local g = tonumber(timing)
	Hub.Stats.Shots += 1
	if g == 5 then Hub.Stats.Perfect += 1 end
	local cur = Timing.cur
	task.wait(0.05)
	Hub.LastGrade = (GRADES[g] or "?") .. (cur and (" @ %.3fs [%s]"):format(cur.hold, cur.key) or "") .. " " .. tostring(Hub.LastShotType or "") .. " contest " .. tostring(contest)
	log("Shot: " .. Hub.LastGrade)
	if F("AutoCalibrate") and cur and g then
		-- early grades mean hold longer, late grades shorter; step shrinks near perfect
		local step = ({ 0.05, 0.03, 0.012, 0.006, 0, -0.012, -0.03, -0.05 })[g] or 0
		local k = cur.key or calKey(cur.meter)
		Timing.offsets[k] = math.clamp((Timing.offsets[k] or 0) + step, -0.2, 0.3)
	end
	Timing.cur = nil
end))

-- ===================================================================== actions
local function fire(remote, ...) local a = table.pack(...) pcall(function() remote:FireServer(table.unpack(a, 1, a.n)) end) end
local function jump() fire(Input.Jump) end
local lastTap = 0
local function shootTap()
	local me = MyChar()
	if os.clock() - lastTap < 1.6 or Timing.pending or attr(me, "Action") == "Shooting" then return false end
	lastTap = os.clock()
	stopSteer()
	local r = Root(me)
	local t0 = os.clock()
	while r and (r.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude > 1.5 and os.clock() - t0 < 0.8 do task.wait() end
	task.wait(0.1)
	fire(Input.Shoot, { Shoot = true, Input = "E", UseSpace = true })
	if not F("PerfectTiming") then task.delay(F("HoldTime") or 0.29, function() fire(Input.Shoot, { Shoot = false }) end) end
	return true
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
					if cr and attr(c, "Action") == "Shooting" and (cr.Position - (serverPos(me) or r.Position)).Magnitude <= (F("BlockRange") or 10) then
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
				if cr and (cr.Position - (serverPos(me) or r.Position)).Magnitude <= (F("StealRange") or 6) and not attr(me, "Fouled") then
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
			if not moving and not F("AutoPlay") then stopSteer() end
		end)
		if not ok then log("loop: " .. tostring(e)) end
		task.wait(F("ReactionTime") and (F("ReactionTime") / 1000) or 0.05)
	end
end)


-- ===================================================================== auto play
local function openTeammate()
	local me = MyChar() local r = Root(me) if not r then return end
	local best, bs
	for _, c in ipairs(others()) do
		if not isOpponent(c) and Players:FindFirstChild(c.Name) then
			local cr = Root(c)
			local near = math.huge
			for _, o in ipairs(opponents()) do local orr = Root(o) if orr and cr then near = math.min(near, (orr.Position - cr.Position).Magnitude) end end
			if cr and (not bs or near > bs) then best, bs = c, near end
		end
	end
	return best, bs
end
local lastPlay, lastMove = 0, 0
local function autoPlayStep()
	local me = MyChar() local r = Root(me) if not r then return end
	local carrier = ballCarrier()
	local rim, rimD = nearestRim(r.Position)
	if carrier == me then
		local p = contestInfo()
		if rim and rimD <= 9 and (F("APDunks") or F("APRimRun")) then if shootTap() then log("AutoPlay: finish at rim") end return end
		local three = rimD and rimD > 22
		local wantShoot = (F("APShootOpen") and p <= (F("MaxContest") or 35)) and rimD and rimD <= (F("ShootRange") or 30)
		if wantShoot and (not three or math.random(100) <= (F("AP3Chance") or 40)) and (F("APMidrange") or three) then if shootTap() then log("AutoPlay: shot") end return end
		if F("APPass") and p >= 60 then local t = openTeammate() if t then pass(t.Name, 1) log("AutoPlay: pass to " .. t.Name) return end end
		if F("APBreakAnkles") and p >= 40 and os.clock() - lastMove > 1.2 then
			lastMove = os.clock()
			local pool = F("APUseCombo") and (F("ComboMoves") or {}) or (F("APMoves") or {})
			if #pool > 0 then dribble(pool[math.random(#pool)]) end
		end
		if rim and (F("APRimRun") or F("APDunks")) then steer(rim.Position) end
	elseif carrier and isOpponent(carrier) then
		if F("APDefense") then
			local cr = Root(carrier)
			local orim = cr and nearestRim(cr.Position)
			if cr and orim then steer(cr.Position + ((orim.Position - cr.Position) * Vector3.new(1, 0, 1)).Unit * (F("GuardDistance") or 4)) end
			if F("APSteal") and cr and (cr.Position - r.Position).Magnitude < (F("StealRange") or 6) and os.clock() - lastPlay > (F("StealCooldown") or 1.2) then lastPlay = os.clock() fire(Input.Steal) end
		end
	elseif carrier then
		-- teammate has it: find open space toward a shooting spot
		if rim and F("APSpots") then
			local ang = (os.clock() * 0.2) % (math.pi * 2)
			steer(rim.Position + Vector3.new(math.cos(ang), 0, math.sin(ang)) * 20)
		end
	else
		local best, bd
		for _, b in ipairs(balls()) do local d = (b:GetPivot().Position - r.Position).Magnitude if not bd or d < bd then best, bd = b, d end end
		if best then steer(best:GetPivot().Position) if best:GetPivot().Position.Y - r.Position.Y > 4 and bd < 8 then jump() end end
	end
end
task.spawn(function()
	while Hub.Running do
		if F("AutoPlay") then
			local ok, e = pcall(autoPlayStep) if not ok then log("autoplay: " .. tostring(e)) end
			-- jump ball: the court status label says JUMP BALL
			if F("AutoJumpBall") then
				for _, d in ipairs(LP.PlayerGui:GetDescendants()) do if d:IsA("TextLabel") and d.Name == "Status" and d.Visible and d.Text:upper():find("JUMP") then jump() break end end
			end
		end
		task.wait(0.1)
	end
end)

-- ===================================================================== matches
local function webhook(title, fields)
	local url = F("WebhookURL") if not url or url == "" then return end
	local req = request or http_request if not req then return end
	pcall(req, { Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = HttpService:JSONEncode({ embeds = { { title = title, fields = fields, color = 0xE6E6E6 } } }) })
end
Hub.Session = { games = 0, wins = 0 }
conn(Remote.InterfaceService.Summary.OnClientEvent:Connect(function(data)
	Hub.Session.games += 1
	local fields = {}
	if type(data) == "table" then
		for k, v in pairs(data) do if type(v) ~= "table" and #fields < 20 then fields[#fields + 1] = { name = tostring(k), value = tostring(v), inline = true } end end
		if data.Won == true or data.Result == "Win" then Hub.Session.wins += 1 end
	end
	fields[#fields + 1] = { name = "Session", value = ("%d games, %d wins"):format(Hub.Session.games, Hub.Session.wins) }
	log("Game over (" .. Hub.Session.games .. ")")
	if F("ResultWebhook") then webhook("Game result", fields) end
	if F("AutoLeaveRec") then task.delay(4, function() pcall(function() Remote.InterfaceService.LeaveRec:InvokeServer() end) end) end
	if F("BadgeFarm") then
		if (F("LeaveAfter") or 0) > 0 and Hub.Session.games >= F("LeaveAfter") then Flags.BadgeFarm:Set(false) return end
		task.delay(5, function() pcall(function() Remote.InterfaceService.JoinPlace:InvokeServer("BlacktopMatchmaking") end) end)
	end
end))
local function queueReload()
	if queue_on_teleport then pcall(queue_on_teleport, 'task.wait(6) loadstring(game:HttpGet("https://raw.githubusercontent.com/voidhub9-dotcom/VoidHub-UI/claude/admiring-brown-dzzpni/Scripts/Hoops.lua"))()') end
end
task.spawn(function()
	while Hub.Running do
		if F("HopNoOpponents") and #opponents() == 0 and MyChar() and attr(MyChar(), "InGame") then
			log("No opponents, hopping") queueReload()
			pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId, LP) end)
		end
		task.wait(15)
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
	t:CreateSlider({ Name = "Hold time", Range = { 0.1, 0.8 }, Increment = 0.005, CurrentValue = 0.29, Suffix = " s", Flag = "HoldTime", Desc = "Perfect at 0.28-0.30 s in tests (Vertical meter)." })
	t:CreateToggle({ Name = "Auto calibrate", Desc = "Learns from the game's own shot feedback.", Flag = "AutoCalibrate", CurrentValue = true })
	t:CreateToggle({ Name = "Ping compensation", Desc = "Off by default: shortened holds graded Early in tests.", Flag = "PingComp", CurrentValue = false })
	t:CreateSlider({ Name = "Ping factor", Range = { 0, 1 }, Increment = 0.05, CurrentValue = 0.5, Flag = "PingFactor" })
	t:CreateButton({ Name = "Reset calibration", Callback = function() Timing.offsets = {} end })
	t:CreateDropdown({ Name = "Meter", Options = { "None", "Bat", "Roblox", "Rocket", "Hoop", "Vertical", "Funnel", "Funnel2", "Pill", "Arrow", "Tube", "Diamond" }, AllowNone = true, NoneText = "Keep current", Flag = "MeterType", Callback = function(v)
		if v then fire(Remote.PlayerService.UpdateSetting, { "Meter" }, "Type", v) end
	end })
	local s = PT:CreateGroupbox({ Name = "Stats", Side = "Right", Icon = "activity" })
	s:CreateStatus({ Name = "Last shot", Style = "Row", Update = function() return Hub.LastGrade or "-" end })
	s:CreateStatus({ Name = "Perfect / shots", Style = "Row", Update = function() return ("%d / %d"):format(Hub.Stats.Perfect, Hub.Stats.Shots) end })
	s:CreateStatus({ Name = "Ping", Style = "Row", Update = function() return ("%d ms (press to meter %d ms)"):format(pingMs(), Timing.rtt * 1000) end })
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


do -- Auto Play
	local AP = Window:CreateTab({ Name = "Auto Play", Desc = "Plays both ends, Rec and badge farm", Icon = "bot" })
	local P = AP:CreateSubTab({ Name = "Auto Play", Icon = "bot" })
	local R = AP:CreateSubTab({ Name = "Rec", Icon = "users" })
	local BF = AP:CreateSubTab({ Name = "Badge Farm", Icon = "award" })
	local a = P:CreateGroupbox({ Name = "Auto Play", Side = "Left", Icon = "bot" })
	a:CreateToggle({ Name = "Auto Play", Flag = "AutoPlay", CurrentValue = false })
	a:CreateToggle({ Name = "Rim run", Flag = "APRimRun", CurrentValue = true })
	a:CreateToggle({ Name = "Go for dunks", Flag = "APDunks", CurrentValue = true })
	a:CreateToggle({ Name = "Midranges", Flag = "APMidrange", CurrentValue = true })
	a:CreateSlider({ Name = "3PT chance", Range = { 0, 100 }, Increment = 5, CurrentValue = 40, Suffix = "%", Flag = "AP3Chance" })
	a:CreateToggle({ Name = "Shoot when open", Flag = "APShootOpen", CurrentValue = true })
	a:CreateToggle({ Name = "Pass to teammates", Flag = "APPass", CurrentValue = true })
	a:CreateToggle({ Name = "Shooting spots", Flag = "APSpots", CurrentValue = true })
	local b = P:CreateGroupbox({ Name = "Handles & defense", Side = "Right", Icon = "repeat" })
	b:CreateToggle({ Name = "Break ankles", Flag = "APBreakAnkles", CurrentValue = true })
	b:CreateDropdown({ Name = "Move pool", Options = MoveNames, MultipleOptions = true, AllowNone = true, Flag = "APMoves", NoneText = "Pick moves" })
	b:CreateToggle({ Name = "Use my combo instead", Flag = "APUseCombo", CurrentValue = false })
	b:CreateToggle({ Name = "Auto defense", Flag = "APDefense", CurrentValue = true })
	b:CreateToggle({ Name = "Auto steal", Flag = "APSteal", CurrentValue = true })
	b:CreateToggle({ Name = "Auto jump ball", Flag = "AutoJumpBall", CurrentValue = true })
	local r = R:CreateGroupbox({ Name = "Rec", Side = "Left", Icon = "users" })
	r:CreateToggle({ Name = "Auto leave Rec after game", Flag = "AutoLeaveRec", CurrentValue = false })
	r:CreateButton({ Name = "Leave Rec now", Callback = function() pcall(function() Remote.InterfaceService.LeaveRec:InvokeServer() end) end })
	r:CreateButton({ Name = "Forfeit", Style = "Danger", Confirm = true, Callback = function() fire(Remote.GamemodeService.Forfeit) end })
	r:CreateToggle({ Name = "Server hop when no opponents", Flag = "HopNoOpponents", CurrentValue = false })
	r:CreateInput({ Name = "Webhook URL", PlaceholderText = "https://discord.com/api/webhooks/...", Flag = "WebhookURL" })
	r:CreateToggle({ Name = "Game results webhook", Flag = "ResultWebhook", CurrentValue = false })
	r:CreateStatus({ Name = "Session", Style = "Row", Update = function() return ("%d games, %d wins"):format(Hub.Session.games, Hub.Session.wins) end })
	local f = BF:CreateGroupbox({ Name = "Blacktop farm", Side = "Left", Icon = "award" })
	f:CreateToggle({ Name = "Badge farm loop", Desc = "Queues Blacktop, auto plays, re-queues after each game.", Flag = "BadgeFarm", CurrentValue = false, Callback = function(on)
		if on then queueReload() Flags.AutoPlay:Set(true) if not attr(MyChar(), "InGame") then pcall(function() Remote.InterfaceService.JoinPlace:InvokeServer("BlacktopMatchmaking") end) end end
	end })
	f:CreateStepper({ Name = "Leave after games (0 = never)", Range = { 0, 100 }, Increment = 1, CurrentValue = 0, Flag = "LeaveAfter" })
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
	b:CreateToggle({ Name = "Prediction mode", Desc = "Uses your ping-delayed server position for block and steal range.", Flag = "Prediction", CurrentValue = true })
	b:CreateSlider({ Name = "Prediction multiplier", Range = { 0.5, 2 }, Increment = 0.05, CurrentValue = 1.2, Flag = "PredictionMult" })
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
	local function pnames() local t = {} for _, c in ipairs(workspace.Characters:GetChildren()) do if Players:FindFirstChild(c.Name) then t[#t + 1] = c.Name end end return t end
	local sp = w:CreateDropdown({ Name = "Spectate", Options = pnames(), AllowNone = true, NoneText = "Myself", Flag = "Spectate", Callback = function(n)
		local c = n and workspace.Characters:FindFirstChild(n) or MyChar()
		if c and c:FindFirstChild("Head") then workspace.CurrentCamera.CameraSubject = c.Head end
	end })
	w:CreateButton({ Name = "Refresh players", Callback = function() sp:SetOptions(pnames()) end })
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
