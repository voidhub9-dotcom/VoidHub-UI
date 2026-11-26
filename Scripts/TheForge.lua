-- The Forge hub (VoidHub UI). Game: The Forge, GameId 7671049560.
-- Remote paths and flows were recovered live on PlaceVersion 445 (Island 1, Stonewake's Cross).

if getgenv().ForgeHub and getgenv().ForgeHub.Unload then pcall(getgenv().ForgeHub.Unload) end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local VirtualUser = game:GetService("VirtualUser")

local LP = Players.LocalPlayer
local Knit = require(RS.Shared.Packages.Knit)
local Svc = RS.Shared.Packages.Knit.Services
local DataFolder = RS.Shared.Data

local Hub = { Conns = {}, Running = true, Stats = { Rocks = 0, Kills = 0, Forged = 0, Sold = 0, Bought = 0 }, State = "Idle", Target = "-", LastError = "-" }
getgenv().ForgeHub = Hub

local function conn(c) table.insert(Hub.Conns, c) return c end
local function setState(s, t) Hub.State = s if t then Hub.Target = t end end
local function err(msg) Hub.LastError = tostring(msg) warn("[ForgeHub] " .. tostring(msg)) end

local function RF(service, name) return Svc[service].RF[name] end
local function invoke(service, name, ...)
	local args = table.pack(...)
	local ok, a, b = pcall(function() return RF(service, name):InvokeServer(table.unpack(args, 1, args.n)) end)
	if not ok then err(service .. "." .. name .. ": " .. tostring(a)) end
	return ok, a, b
end

-- Replica data (inventory, gold, potions, gamepasses)
local Replica
for _ = 1, 100 do
	local ok, c = pcall(Knit.GetController, "ToolController")
	if ok and c and c.replica then Replica = c.replica break end
	task.wait(0.1)
end
local function Data() return Replica and Replica.Data end
local function ItemTypes() return getrenv()._G.ItemTypes or {} end
local function itemKind(name) local t = ItemTypes()[name] return t and t[1] end

-- Game data tables
local OreInfo, OreNames, Rarities = {}, {}, {}
for _, o in pairs(require(DataFolder.Ore)) do
	if type(o) == "table" and o.Name and not OreInfo[o.Name] then
		OreInfo[o.Name] = o
		table.insert(OreNames, o.Name)
		Rarities[o.Rarity or "?"] = true
	end
end
table.sort(OreNames)
local RarityList = {}
for _, r in ipairs({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Relic", "Exotic", "Divine" }) do if Rarities[r] then table.insert(RarityList, r) end end
local RockData = require(DataFolder.Rock)
local RockNames = {}
for k in pairs(RockData) do table.insert(RockNames, k) end
table.sort(RockNames)
local PotionNames = {}
for k, v in pairs(ItemTypes()) do if type(v) == "table" and v[1] == "Potion" then table.insert(PotionNames, k) end end
table.sort(PotionNames)
local IslandNames = {}
pcall(function() for _, v in pairs(require(DataFolder.Islands).Data) do table.insert(IslandNames, v.Name) end end)

-- Character helpers
local function Char() return LP.Character end
local function Root() local c = Char() return c and c:FindFirstChild("HumanoidRootPart") end
local function Hum() local c = Char() return c and c:FindFirstChildOfClass("Humanoid") end
local function alive() local h = Hum() return h and h.Health > 0 and Root() ~= nil end
local function hpPct() local h = Hum() return h and h.MaxHealth > 0 and h.Health / h.MaxHealth * 100 or 0 end

local Flags -- set after window creation
local function F(name)
	local f = Flags and Flags[name]
	if not f then return nil end
	if f.Get then local ok, v = pcall(f.Get, f) if ok then return v end end
	return f.Value
end
local function list(name) local v = F(name) if type(v) == "table" then return v end if v == nil or v == "" then return {} end return { v } end
local function set(t) local s = {} for _, v in ipairs(t) do s[v] = true end return s end

-- Noclip during automation / movement
local noclipRefs = 0
conn(RunService.Stepped:Connect(function()
	if noclipRefs > 0 or F("Noclip") then
		local c = Char()
		if c then for _, p in ipairs(c:GetDescendants()) do if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end end end
	end
end))

-- Holding: keeps the character still at a CFrame without falling
local Hold = { cf = nil }
conn(RunService.Heartbeat:Connect(function()
	local r = Root()
	if Hold.cf and r then
		r.CFrame = Hold.cf
		r.AssemblyLinearVelocity = Vector3.zero
		r.AssemblyAngularVelocity = Vector3.zero
	end
end))
local function hold(cf) Hold.cf = cf end
local function release() Hold.cf = nil end

-- Tween travel (instant teleports are reverted by the server; ~70 studs/s was stable in tests)
local travelId = 0
local function cancelTravel() travelId += 1 end
local function travel(cf, speed)
	local r = Root() if not r then return false end
	travelId += 1
	local my = travelId
	release()
	noclipRefs += 1
	local ok = pcall(function()
		local dist = (cf.Position - r.Position).Magnitude
		local tw = TweenService:Create(r, TweenInfo.new(math.max(dist / (speed or F("TweenSpeed") or 70), 0.05), Enum.EasingStyle.Linear), { CFrame = cf })
		tw:Play()
		while tw.PlaybackState == Enum.PlaybackState.Playing do
			if my ~= travelId or not Hub.Running or not alive() then tw:Cancel() break end
			r.AssemblyLinearVelocity = Vector3.zero
			task.wait()
		end
	end)
	noclipRefs -= 1
	return ok and my == travelId and alive()
end

local function equip(toolName)
	local c, h = Char(), Hum()
	if not c or not h then return false end
	if c:FindFirstChild(toolName) then return true end
	local t = LP.Backpack:FindFirstChild(toolName)
	if t then h:EquipTool(t) task.wait(0.25) return c:FindFirstChild(toolName) ~= nil end
	return false
end

local function closeDialogue()
	local h = LP.PlayerGui:FindFirstChild("DialogueUI")
	h = h and h:FindFirstChild("DialogueHandler")
	if h then pcall(function() local env = getsenv(h) if env and env.Close then env.Close() end end) end
end

local function nearestPlayerDist(pos)
	local best = math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
			best = math.min(best, (p.Character.HumanoidRootPart.Position - pos).Magnitude)
		end
	end
	return best
end

-- ============================================================ Mobs
local function mobType(m) return (m.Name:gsub("%d+$", "")) end
local function isMob(m)
	if not m:GetAttribute("IsNpc") then return false end
	local h = m:FindFirstChildOfClass("Humanoid")
	return h and h.Health > 0 and m:FindFirstChild("HumanoidRootPart") ~= nil
end
local function mobsNear(pos, radius)
	local out = {}
	local living = workspace:FindFirstChild("Living")
	if not living then return out end
	for _, m in ipairs(living:GetChildren()) do
		if isMob(m) and (m.HumanoidRootPart.Position - pos).Magnitude <= radius then table.insert(out, m) end
	end
	return out
end
local function mobTypeList()
	local s, out = {}, {}
	pcall(function() for k in pairs(require(DataFolder.Enemies)) do s[k] = true end end)
	if workspace:FindFirstChild("Living") then for _, m in ipairs(workspace.Living:GetChildren()) do if m:GetAttribute("IsNpc") then s[mobType(m)] = true end end end
	for k in pairs(s) do table.insert(out, k) end
	table.sort(out)
	return out
end

-- Block on the mob's ParryWindow (appears ~0.3 s before each hit)
local Blocking = false
local parryWatch = {}
local function watchParry(m, onHit)
	if parryWatch[m] then return end
	parryWatch[m] = m.DescendantAdded:Connect(function(d)
		if d.Name == "ParryWindow" then onHit(m) end
	end)
	m.AncestryChanged:Connect(function(_, p) if not p and parryWatch[m] then parryWatch[m]:Disconnect() parryWatch[m] = nil end end)
end
local function doBlock(m)
	if not F("AutoBlock") or Blocking or not alive() then return end
	if (m.HumanoidRootPart.Position - Root().Position).Magnitude > 18 then return end
	Blocking = true
	task.spawn(function()
		local prev = Char():FindFirstChildWhichIsA("Tool")
		equip("Weapon")
		invoke("ToolService", "StartBlock")
		task.wait(0.7)
		invoke("ToolService", "StopBlock")
		if prev and prev.Name ~= "Weapon" and prev.Parent then equip(prev.Name) end
		Blocking = false
	end)
end
local Dodging = false
local function doDodge(m)
	if not F("AutoDodge") or Dodging or not alive() or not Hold.cf then return end
	if (m.HumanoidRootPart.Position - Root().Position).Magnitude > 18 then return end
	Dodging = true
	task.spawn(function()
		local base = Hold.cf
		hold(base + Vector3.new(0, 14, 0))
		task.wait(0.8)
		if Hold.cf then hold(base) end
		Dodging = false
	end)
end
local function onParry(m) doBlock(m) doDodge(m) end

local function attack(heavy)
	if Blocking then return end
	if not equip("Weapon") then return end
	invoke("ToolService", "ToolActivated", "Weapon", heavy or nil)
end

local function mobCFrame(m)
	local mr = m.HumanoidRootPart
	local mode, dist, h = F("MobPosition") or "Behind", F("MobDistance") or 4, F("MobHeight") or 0
	local p
	if mode == "Behind" then p = (mr.CFrame * CFrame.new(0, h, dist)).Position
	elseif mode == "Front" then p = (mr.CFrame * CFrame.new(0, h, -dist)).Position
	elseif mode == "Above" then p = mr.Position + Vector3.new(0, dist + h, 0)
	else p = mr.Position - Vector3.new(0, dist - h, 0) end
	local look = mr.Position
	if (look - p).Magnitude < 0.1 then look += Vector3.new(0.01, 0, 0) end
	return CFrame.lookAt(p, look)
end

local function camLock(target)
	local cam = workspace.CurrentCamera
	if target and cam then cam.CFrame = CFrame.lookAt(cam.CFrame.Position, target) end
end

-- Kill one mob, holding a position relative to it
local function fightMob(m, timeout)
	if not isMob(m) then return end
	watchParry(m, onParry)
	setState("Fighting", m.Name)
	if not travel(mobCFrame(m)) then return end
	local t0 = tick()
	while Hub.Running and isMob(m) and alive() and tick() - t0 < (timeout or 30) do
		if Hub.Paused then break end
		if F("RetreatEnabled") and hpPct() < (F("RetreatAt") or 35) then break end
		if not Dodging then hold(mobCFrame(m)) end
		if F("CamLockMob") then camLock(m.HumanoidRootPart.Position) end
		attack(F("HeavyAttacks"))
		task.wait(0.05)
	end
	if not isMob(m) then Hub.Stats.Kills += 1 end
	release()
end

-- ============================================================ Rocks
local function rockAlive(m)
	return m.Parent and m:FindFirstChild("Hitbox") and (m:GetAttribute("Health") or 0) > 0 and not m:GetAttribute("IsBroken")
end
local function revealedOres(m)
	local out = {}
	for _, c in ipairs(m:GetChildren()) do if c.Name == "Ore" and c:GetAttribute("Ore") then table.insert(out, c:GetAttribute("Ore")) end end
	return out
end
local function possibleOres(name)
	local d = RockData[name]
	local out = {}
	if d and d.Ores then for _, o in pairs(d.Ores) do table.insert(out, type(o) == "table" and (o.Name or o[1]) or o) end end
	return out
end
local badRock = {}

local function rockOk(m, zoneSet, typeSet, neverSet, oreSet)
	if not rockAlive(m) or badRock[m] and badRock[m] > tick() then return false end
	if next(typeSet) and not typeSet[m.Name] then return false end
	if neverSet[m.Name] then return false end
	local zone = m.Parent and m.Parent.Parent
	if next(zoneSet) and not (zone and zoneSet[zone.Name]) then return false end
	if next(oreSet) then
		local rev = revealedOres(m)
		if #rev > 0 then
			local hit = false for _, o in ipairs(rev) do if oreSet[o] then hit = true end end
			if not hit and F("SkipRevealedMismatch") then return false end
		end
		if F("SkipWithoutOre") then
			local hit = false for _, o in ipairs(possibleOres(m.Name)) do if oreSet[o] then hit = true end end
			if not hit then return false end
		end
	end
	local pos = m.Hitbox.Position
	if F("SkipOthersRocks") then
		local who, when = m:GetAttribute("LastHitPlayer"), m:GetAttribute("LastHitTime")
		if who and who ~= LP.Name and when and workspace:GetServerTimeNow() - when < 8 then return false end
	end
	if F("AvoidPlayers") and nearestPlayerDist(pos) < (F("PlayerDistance") or 30) then return false end
	if F("AvoidMobRocks") and #mobsNear(pos, F("MobAvoidRadius") or 25) > 0 then return false end
	return true
end

local function pickRock()
	local r = Root() if not r then return end
	local folder = workspace:FindFirstChild("Rocks") if not folder then return end
	local zoneSet, typeSet, neverSet, oreSet = set(list("MineZones")), set(list("RockTypes")), set(list("NeverMine")), set(list("OreFilter"))
	local prio = {}
	for i, n in ipairs(F("RockPriority") or {}) do prio[n] = i end
	local range = F("SearchRange") or 2000
	local best, bestScore
	for _, zone in ipairs(folder:GetChildren()) do
		for _, sp in ipairs(zone:GetChildren()) do
			for _, m in ipairs(sp:GetChildren()) do
				if m:IsA("Model") and m:GetAttribute("Health") and rockOk(m, zoneSet, typeSet, neverSet, oreSet) then
					local d = (m.Hitbox.Position - r.Position).Magnitude
					if d <= range then
						local score = (prio[m.Name] or 999) * 100000 + d
						if not bestScore or score < bestScore then best, bestScore = m, score end
					end
				end
			end
		end
	end
	return best
end

local function mineCFrame(m)
	local hb = m.Hitbox
	local gap = F("RockGap") or 2.5
	local mode = F("MinePosition") or "Side"
	local p
	if mode == "Above" then p = hb.Position + Vector3.new(0, hb.Size.Y / 2 + math.min(gap, 3.5), 0)
	elseif mode == "Below" then p = hb.Position - Vector3.new(0, hb.Size.Y / 2 + gap, 0)
	else
		local r = Root()
		local dir = r and (r.Position - hb.Position) * Vector3.new(1, 0, 1) or Vector3.new(0, 0, 1)
		if dir.Magnitude < 0.1 then dir = Vector3.new(0, 0, 1) end
		p = hb.Position + dir.Unit * (math.max(hb.Size.X, hb.Size.Z) / 2 + gap) + Vector3.new(0, F("MineHeight") or 0, 0)
	end
	local look = Vector3.new(hb.Position.X, mode == "Side" and p.Y or hb.Position.Y, hb.Position.Z)
	if mode ~= "Side" then look += Vector3.new(0.01, 0, 0) end
	return CFrame.lookAt(p, look)
end

local function mineRock(m)
	setState("Mining", m.Name)
	local cf = mineCFrame(m)
	if not travel(cf) then return end
	hold(cf)
	local t0, lastHp, stuck = tick(), m:GetAttribute("Health"), 0
	while Hub.Running and F("AutoMine") and rockAlive(m) and alive() and tick() - t0 < 40 do
		if Hub.Paused or F("RetreatEnabled") and hpPct() < (F("RetreatAt") or 35) then break end
		if F("FightBack") then
			local mobs = mobsNear(Root().Position, F("FightRange") or 15)
			for _, mob in ipairs(mobs) do watchParry(mob, onParry) end
			if #mobs > 0 then
				fightMob(mobs[1], 20)
				if not rockAlive(m) then break end
				if not travel(cf) then break end
			end
		end
		if not Dodging then hold(cf) end
		if F("CamLockRock") then camLock(m.Hitbox.Position) end
		if not Blocking then
			if equip("Pickaxe") then invoke("ToolService", "ToolActivated", "Pickaxe") end
		end
		local hp = m:GetAttribute("Health")
		if hp == lastHp then stuck += 1 else stuck, lastHp = 0, hp end
		if F("SkipHard") and stuck >= 6 then badRock[m] = tick() + 120 err("Skipped rock (no damage): " .. m.Name) break end
		task.wait(F("SwingDelay") or 0.1)
	end
	if not rockAlive(m) and m:GetAttribute("LastHitPlayer") == LP.Name then Hub.Stats.Rocks += 1 end
	release()
end

-- ============================================================ Inventory / selling
local function invCount(name)
	local d = Data() if not d then return 0 end
	local v = d.Inventory[name]
	if type(v) == "number" then return v end
	for _, m in ipairs(d.Inventory.Misc or {}) do if m.Name == name then return m.Quantity or 1 end end
	return 0
end
local function oreTotal()
	local d = Data() if not d then return 0 end
	local n = 0
	for k, v in pairs(d.Inventory) do if type(v) == "number" and itemKind(k) == "Ore" then n += v end end
	return n
end
local function bagCapacity()
	local d = Data() if not d then return 0 end
	local c = 100 + (d.Level or 0) * 2
	if d.Gamepasses and d.Gamepasses.DoubleStorage then c *= 2 end
	return c
end

local function buildBasket()
	local d = Data() if not d then return {}, 0 end
	local oreSel, rarSel, never = set(list("SellOres")), set(list("SellRarities")), set(list("NeverSell"))
	local keep = F("KeepAmount") or 0
	local basket, count = {}, 0
	for k, v in pairs(d.Inventory) do
		if type(v) == "number" and v > 0 and itemKind(k) == "Ore" and not never[k] then
			local info = OreInfo[k]
			if oreSel[k] or (info and rarSel[info.Rarity]) then
				local n = v - keep
				if n > 0 then basket[k] = n count += n end
			end
		end
	end
	if F("SellRunes") then
		local tiers, kinds = set(list("RuneTiers")), set(list("RuneKinds"))
		local favs = d.Favorites or {}
		for _, m in ipairs(d.Inventory.Misc or {}) do
			if m.GUID and m.Id and itemKind(m.Id) == "Rune" and not favs[m.GUID] then
				local kind, tier = m.Id:match("^(.-)_(T%d+)$")
				if (not next(tiers) or tiers[tier]) and (not next(kinds) or kinds[kind]) then basket[m.GUID] = 1 count += 1 end
			end
		end
	end
	return basket, count
end

local function sellNow()
	local basket, count = buildBasket()
	if count == 0 then return false, "Nothing to sell" end
	local d = Data()
	local g0 = d and d.Gold or 0
	setState("Selling", count .. " items")
	if d and d.Gamepasses and d.Gamepasses.SellAnywhere then
		invoke("InventoryService", "SellAnywhere", basket)
	else
		local cey = workspace.Proximity:FindFirstChild("Greedy Cey")
		if not cey then return false, "Greedy Cey is not on this island" end
		local back = Root() and Root().CFrame
		if not travel(cey:GetPivot() * CFrame.new(0, 0, -5)) then return false, "Travel interrupted" end
		task.wait(0.3)
		invoke("ProximityService", "ForceDialogue", cey, "SellConfirmMisc")
		task.wait(0.3)
		invoke("DialogueService", "RunCommand", "SellConfirm", { Basket = basket })
		task.wait(0.5)
		closeDialogue()
		if F("ReturnAfterSell") and back then travel(back) end
	end
	task.wait(0.5)
	local gained = (Data() and Data().Gold or 0) - g0
	if gained > 0 then Hub.Stats.Sold += count end
	return gained > 0, ("+%d gold for %d items"):format(math.floor(gained), count)
end

-- Gear (weapons / armor): sold to Marbles, basket {[GUID] = true}
local function equippedGUIDs()
	local t = {}
	local d = Data()
	if d then for _, e in pairs(d.Equipped or {}) do if type(e) == "table" and e.GUID then t[e.GUID] = true end end end
	return t
end
local function buildGearBasket()
	local d = Data() if not d then return {}, 0 end
	local kinds = set(list("GearKinds"))
	local maxQ = F("GearMaxQuality") or 50
	local eq, favs = equippedGUIDs(), d.Favorites or {}
	local basket, n = {}, 0
	for _, e in ipairs(d.Inventory.Equipments or {}) do
		local kind = itemKind(e.Type)
		if e.GUID and not eq[e.GUID] and not favs[e.GUID] and (e.Quality or 0) <= maxQ and (not next(kinds) or kinds[kind]) then
			if not (F("GearKeepRuned") and e.Runes and next(e.Runes)) and (e.Upgrade or 0) <= (F("GearMaxUpgrade") or 0) then
				basket[e.GUID] = true n += 1
			end
		end
	end
	return basket, n
end
local function sellGear()
	local basket, n = buildGearBasket()
	if n == 0 then return false, "No gear matches" end
	local d = Data()
	local g0 = d.Gold
	setState("Selling gear", n .. " items")
	if d.Gamepasses and d.Gamepasses.SellAnywhere then
		invoke("InventoryService", "SellAnywhere", basket, true)
	else
		local npc = workspace.Proximity:FindFirstChild("Marbles")
		if not npc then return false, "Marbles is not on this island" end
		local back = Root() and Root().CFrame
		if not travel(npc:GetPivot() * CFrame.new(0, 0, -5)) then return false, "Travel interrupted" end
		task.wait(0.3)
		invoke("ProximityService", "ForceDialogue", npc, "SellConfirm")
		task.wait(0.3)
		invoke("DialogueService", "RunCommand", "SellConfirm", { Basket = basket })
		task.wait(0.5)
		closeDialogue()
		if F("ReturnAfterSell") and back then travel(back) end
	end
	task.wait(0.5)
	local gained = (Data().Gold or 0) - g0
	return gained > 0, ("+%d gold for %d gear"):format(math.floor(gained), n)
end

local lastSell = 0
local function sellDue()
	if not F("AutoSell") then return false end
	local _, count = buildBasket()
	if count == 0 then return false end
	if F("SellMode") == "Interval" then return tick() - lastSell >= (F("SellInterval") or 300) end
	if F("SellMode") == "Bag full" then return oreTotal() >= bagCapacity() * 0.95 end
	return oreTotal() >= (F("SellThreshold") or 100)
end

-- ============================================================ Shop
local function buyItem(name, qty)
	local p = workspace.Proximity:FindFirstChild(name)
	if not p then return false, name .. " is not sold here" end
	local prompt = p:FindFirstChildWhichIsA("ProximityPrompt", true)
	setState("Buying", name)
	if not travel(CFrame.new(p:GetPivot().Position + Vector3.new(0, 2, 5))) then return false, "Travel interrupted" end
	task.wait(0.3)
	if prompt then pcall(fireproximityprompt, prompt) end
	task.wait(0.6)
	local before = invCount(name)
	local ok, res = invoke("ProximityService", "Purchase", name, qty)
	pcall(function() Knit.GetController("ProximityController").PurchaseModule:CloseUI() end)
	task.wait(0.5)
	local got = invCount(name) - before
	if got > 0 then Hub.Stats.Bought += got end
	if type(res) == "table" and res.Success == false then return false, tostring(res.WarnMessage) end
	return got > 0, ("Bought %d %s"):format(got, name)
end

local lastBuyCheck = 0
local function buyStep()
	if not F("AutoBuy") or tick() - lastBuyCheck < 10 then return false end
	lastBuyCheck = tick()
	local target = F("TargetStock") or 5
	for _, name in ipairs(list("BuyItems")) do
		local have = invCount(name)
		if have < target and workspace.Proximity:FindFirstChild(name) then
			buyItem(name, math.min(target - have, F("BuyMax") or 10))
			return true
		end
	end
	return false
end

-- ============================================================ Potions
local function usePotion(name)
	if invCount(name) <= 0 then return false end
	local prev = Char() and Char():FindFirstChildWhichIsA("Tool")
	if not LP.Backpack:FindFirstChild(name) and not Char():FindFirstChild(name) then
		invoke("CharacterService", "EquipMisc", name)
		task.wait(0.5)
	end
	if not equip(name) then return false end
	invoke("ToolService", "ToolActivated", name)
	task.wait(0.4)
	if prev and prev.Parent and prev.Name ~= name then equip(prev.Name) end
	return true
end
local lastPotion = 0
local function potionStep()
	if tick() - lastPotion < 2 then return end
	lastPotion = tick()
	local d = Data() if not d then return end
	if F("AutoPotions") then
		for _, name in ipairs(list("PotionList")) do
			if not tostring(name):find("Health") and not d.Potions[name] and invCount(name) > 0 then usePotion(name) end
		end
	end
	if F("AutoHealthPotion") and hpPct() < (F("HealthPotionAt") or 40) then
		for _, name in ipairs({ "HealthPotion3", "HealthPotion2", "HealthPotion1" }) do
			if invCount(name) > 0 then usePotion(name) break end
		end
	end
end

-- ============================================================ Forge
local FC = Knit.GetController("ForgeController")
local ForgeMods = RS.Controllers.ForgeController
local Mini = { Melt = require(ForgeMods.MeltMinigame), Pour = require(ForgeMods.PourMinigame), Hammer = require(ForgeMods.HammerMinigame) }
local MiniOrig = { Melt = Mini.Melt.Start, Pour = Mini.Pour.Start, Note = Mini.Hammer.CreateNote }

local function waitUntil(t) while workspace:GetServerTimeNow() < t do task.wait() end end
local function setPerfect(on)
	if on then
		Mini.Melt.Start = function(_, data) waitUntil(data.StartTime + data.RequiredTime + 0.05) return workspace:GetServerTimeNow() end
		Mini.Pour.Start = function(_, data) waitUntil(data.StartTime + data.RequiredTime + 0.05) return workspace:GetServerTimeNow() end
		Mini.Hammer.CreateNote = function(_, data) task.wait(data.Lifetime * 25 / 44) end
	else
		Mini.Melt.Start, Mini.Pour.Start, Mini.Hammer.CreateNote = MiniOrig.Melt, MiniOrig.Pour, MiniOrig.Note
	end
end

local function forgeRecipe()
	local ores, total = {}, 0
	for i = 1, 4 do
		local o = F("ForgeOre" .. i)
		local q = F("ForgeQty" .. i) or 0
		if o and o ~= "" and o ~= "None" and q > 0 then ores[o] = (ores[o] or 0) + q total += q end
	end
	return ores, total
end
local function recipeReady()
	local ores, total = forgeRecipe()
	if total < 3 then return false, "Need at least 3 ores" end
	if not Hub.BagInfo or tick() - Hub.BagInfo.t > 5 then
		local okInfo, res = pcall(function() return RF("StatusService", "GetPlayerEquipmentInfo"):InvokeServer() end)
		Hub.BagInfo = { t = tick(), ok = okInfo, info = res }
	end
	local okInfo, info = Hub.BagInfo.ok, Hub.BagInfo.info
	if okInfo and type(info) == "table" and info.Count and info.Capacity and info.Count >= info.Capacity then
		return false, ("Equipment bag full (%d/%d)"):format(info.Count, info.Capacity)
	end
	for o, q in pairs(ores) do if invCount(o) < q then return false, ("Missing %s (%d/%d)"):format(o, invCount(o), q) end end
	return true
end

local function cancelForge()
	pcall(function() if FC.ForgeActive then FC:EndForge() end end)
end

local function forgeOnce()
	local ok, why = recipeReady()
	if not ok then return false, why end
	local forge = workspace.Proximity:FindFirstChild("Forge")
	if not forge then return false, "No forge on this island" end
	setState("Forging", F("ForgeType") or "Weapon")
	if not travel(CFrame.new(forge.Position + Vector3.new(0, 0, 6))) then return false, "Travel interrupted" end
	setPerfect(true)
	local eq0 = Data() and #Data().Inventory.Equipments or 0
	invoke("ProximityService", "Forge", forge)
	local t0 = tick()
	while FC.Sequence ~= "OreSelect" and tick() - t0 < 6 do task.wait(0.1) end
	if FC.Sequence ~= "OreSelect" then cancelForge() return false, "Forge did not open" end
	task.wait(2) -- the forge UI opens ~0.4 s after OreSelect and resets state; melting earlier double-fires Melt and burns the ores
	local ores = forgeRecipe()
	FC.Ores = ores
	FC.ItemType = F("ForgeType") or "Weapon"
	pcall(function()
		local ui = Knit.GetController("UIController").Modules.Forge
		if F("FastForge") and Data().Gamepasses.FastForge then ui:ChangeFastForge(true) end
	end)
	task.spawn(function() FC:ChangeSequence("Melt") end)
	local clicked = false
	t0 = tick()
	while Hub.Running and tick() - t0 < 150 do
		if FC.Sequence == "Hammer" then
			-- the minigame only listens ~1.8 s after the mold spawns and ignores clicks past 3, so keep clicking
			for _, mold in ipairs(workspace.Debris:GetChildren()) do
				local cd = mold.Name == "Mold" and mold:FindFirstChildWhichIsA("ClickDetector", true)
				if cd then pcall(firesignal, cd.MouseClick, LP) clicked = true end
			end
			task.wait(0.3)
		end
		if FC.Sequence == "Showcase" then task.wait(2.5) break end
		if FC.Sequence == "OreSelect" and tick() - t0 > 15 then break end
		if Hub.ForgeCancel then break end
		task.wait(0.1)
	end
	Hub.ForgeCancel = false
	cancelForge()
	if not F("PerfectForge") then setPerfect(false) end
	task.wait(1)
	local made = (Data() and #Data().Inventory.Equipments or 0) > eq0
	if made then
		Hub.Stats.Forged += 1
		local e = Data().Inventory.Equipments[#Data().Inventory.Equipments]
		return true, ("%s, quality %.1f"):format(tostring(e.Type), e.Quality or 0), e
	end
	return false, "Forge ended without a new item"
end

-- ============================================================ Webhook
local function webhook(title, fields, color)
	local url = F("WebhookURL")
	if not url or url == "" then return false end
	local req = request or http_request or (syn and syn.request)
	if not req then return false end
	local c = F("WebhookColor") or Color3.fromRGB(230, 230, 230)
	local body = HttpService:JSONEncode({ embeds = { {
		title = title,
		color = math.floor(c.R * 255) * 65536 + math.floor(c.G * 255) * 256 + math.floor(c.B * 255),
		fields = fields,
		footer = { text = "The Forge hub" },
		timestamp = DateTime.now():ToIsoDate(),
	} } })
	local ok, res = pcall(req, { Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
	return ok and res and (res.StatusCode == 204 or res.StatusCode == 200)
end

local lastInv = {}
local function snapshotOres()
	local d = Data() local t = {}
	if d then for k, v in pairs(d.Inventory) do if type(v) == "number" then t[k] = v end end end
	return t
end
lastInv = snapshotOres()
local function webhookStep()
	local now = snapshotOres()
	if F("WebhookOres") then
		local watch = set(list("WebhookOreList"))
		for k, v in pairs(now) do
			local gain = v - (lastInv[k] or 0)
			if gain > 0 and watch[k] then
				local info = OreInfo[k] or {}
				webhook("Ore found: " .. k, {
					{ name = "Amount", value = "+" .. gain .. " (total " .. v .. ")", inline = true },
					{ name = "Rarity", value = tostring(info.Rarity or "?"), inline = true },
					{ name = "Chance", value = info.Chance and ("1 in " .. tostring(info.Chance)) or "?", inline = true },
					{ name = "Player", value = F("WebhookHideName") and "hidden" or LP.Name, inline = true },
				})
			end
		end
	end
	lastInv = now
end

-- ============================================================ Staff
local function isStaff(p)
	local ok, rank = pcall(function() return p:GetRankInGroup(35489258) end)
	return ok and rank and rank >= 35 and rank ~= 64
end
local function staffInServer()
	for _, p in ipairs(Players:GetPlayers()) do if p ~= LP and isStaff(p) then return p end end
end

-- ============================================================ Brain
local function retreatStep()
	if not (F("RetreatEnabled") and hpPct() < (F("RetreatAt") or 35)) then return false end
	setState("Retreating", "HP " .. math.floor(hpPct()) .. "%")
	local r = Root()
	local spot = CFrame.new(r.Position + Vector3.new(0, F("RetreatHeight") or 60, 0))
	travel(spot)
	hold(spot)
	while Hub.Running and alive() and hpPct() < (F("ResumeAt") or 80) do task.wait(0.5) end
	release()
	return true
end

local function mobFarmStep()
	local r = Root() if not r then return false end
	local types = set(list("MobTypes"))
	local best, bd
	for _, m in ipairs(workspace.Living:GetChildren()) do
		if isMob(m) and (not next(types) or types[mobType(m)]) then
			local d = (m.HumanoidRootPart.Position - r.Position).Magnitude
			if d <= (F("FarmRange") or 500) and (not F("MobAvoidPlayers") or nearestPlayerDist(m.HumanoidRootPart.Position) > (F("MobPlayerDist") or 30)) then
				if not bd or d < bd then best, bd = m, d end
			end
		end
	end
	if not best then setState("Waiting for mobs", "-") return false end
	fightMob(best, 60)
	return true
end

local function brain()
	while Hub.Running do
		local ok, e = pcall(function()
			if not alive() then setState("Dead / respawning") task.wait(1) return end
			if Hub.Paused then setState("Paused (staff)") release() task.wait(1) return end
			potionStep()
			if retreatStep() then return end
			if sellDue() then local _, msg = sellNow() lastSell = tick() Hub.LastSell = msg return end
			if buyStep() then return end
			if F("AutoSellGear") then
				local _, n = buildGearBasket()
				if n >= (F("GearSellAt") or 3) then local _, msg = sellGear() Hub.LastGear = msg return end
			end
			if F("AutoForge") and recipeReady() then local _, msg = forgeOnce() Hub.LastForge = msg return end
			if F("MobFarm") then if mobFarmStep() then return end end
			if F("AutoMine") then
				local rock = pickRock()
				if rock then mineRock(rock) return end
				setState("No rock matches filters", "-")
			end
			if not (F("MobFarm") or F("AutoMine")) then setState("Idle", "-") end
			task.wait(0.5)
		end)
		if not ok then err(e) release() task.wait(1) end
		task.wait()
	end
end

-- ============================================================ ESP
local ESP = { objs = {}, draw = {} }
local hasDrawing = pcall(function() local l = Drawing.new("Line") l:Remove() end)
local espFolder = Instance.new("Folder")
espFolder.Name = "ForgeHubESP"
espFolder.Parent = (gethui and gethui()) or game:GetService("CoreGui")

local function espColor(kind) return F(kind .. "Color") or Color3.new(1, 1, 1) end
local function newDraw(kind, props)
	if not hasDrawing then return end
	local d = Drawing.new(kind)
	for k, v in pairs(props or {}) do d[k] = v end
	return d
end

local function makeEsp(model, kind)
	local o = { kind = kind, model = model }
	local hl = Instance.new("Highlight")
	hl.FillTransparency = 1
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = model
	hl.Parent = espFolder
	o.hl = hl
	local bb = Instance.new("BillboardGui")
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(200, 60)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.Adornee = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Hitbox") or model.PrimaryPart
	bb.Parent = espFolder
	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1
	tl.Size = UDim2.new(1, 0, 1, -6)
	tl.Font = Enum.Font.GothamBold
	tl.TextStrokeTransparency = 0.3
	tl.TextYAlignment = Enum.TextYAlignment.Bottom
	tl.Parent = bb
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0.5, 0, 0, 4)
	bar.Position = UDim2.new(0.25, 0, 1, -4)
	bar.BackgroundColor3 = Color3.new(0, 0, 0)
	bar.BorderSizePixel = 0
	bar.Parent = bb
	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = bar
	o.bb, o.tl, o.bar, o.fill = bb, tl, bar, fill
	if hasDrawing then
		o.box = newDraw("Square", { Thickness = 1, Filled = false })
		o.boxFill = newDraw("Square", { Thickness = 0, Filled = true, Transparency = 0.2 })
		o.tracer = newDraw("Line", { Thickness = 1 })
		o.arrow = newDraw("Triangle", { Filled = true })
		o.lines = {}
		for i = 1, 12 do o.lines[i] = newDraw("Line", { Thickness = 1 }) end
	end
	ESP.objs[model] = o
	return o
end

local function hideDraw(o)
	if not o.box then return end
	o.box.Visible, o.boxFill.Visible, o.tracer.Visible, o.arrow.Visible = false, false, false, false
	for _, l in ipairs(o.lines) do l.Visible = false end
end
local function killEsp(model)
	local o = ESP.objs[model]
	if not o then return end
	o.hl:Destroy() o.bb:Destroy()
	if o.box then
		o.box:Remove() o.boxFill:Remove() o.tracer:Remove() o.arrow:Remove()
		for _, l in ipairs(o.lines) do l:Remove() end
	end
	ESP.objs[model] = nil
end

local function espCandidates()
	local out = {}
	local onlyRocks = set(list("EspRockTypes"))
	if F("RockESP") and workspace:FindFirstChild("Rocks") then
		for _, z in ipairs(workspace.Rocks:GetChildren()) do for _, sp in ipairs(z:GetChildren()) do for _, m in ipairs(sp:GetChildren()) do
			if m:IsA("Model") and rockAlive(m) and (not next(onlyRocks) or onlyRocks[m.Name]) then out[m] = "Rock" end
		end end end
	end
	if workspace:FindFirstChild("Living") then
		for _, m in ipairs(workspace.Living:GetChildren()) do
			if F("MobESP") and isMob(m) then out[m] = "Mob"
			elseif F("PlayerESP") and m ~= Char() and Players:GetPlayerFromCharacter(m) and m:FindFirstChild("HumanoidRootPart") then out[m] = "Player" end
		end
	end
	return out
end

local function espLabel(m, kind, dist)
	local parts = {}
	if F("EspNames") then
		if kind == "Player" and F("EspAnon") then table.insert(parts, "Player")
		elseif kind == "Mob" then table.insert(parts, mobType(m))
		else table.insert(parts, m.Name) end
	end
	if F("EspDistance") then table.insert(parts, ("[%dm]"):format(dist)) end
	local h = m:FindFirstChildOfClass("Humanoid")
	if F("EspHealthText") then
		if h then table.insert(parts, ("%d/%d"):format(h.Health, h.MaxHealth))
		elseif m:GetAttribute("Health") then table.insert(parts, ("%d/%d"):format(m:GetAttribute("Health"), m:GetAttribute("MaxHealth") or 0)) end
	end
	local text = table.concat(parts, " ")
	if kind == "Rock" then
		local rev = revealedOres(m)
		if F("RevealedOreLabels") and #rev > 0 then text = text .. "\n" .. table.concat(rev, ", ")
		elseif F("PossibleOres") then text = text .. "\n" .. table.concat(possibleOres(m.Name), ", ") end
	end
	return text
end

local function hpFrac(m)
	local h = m:FindFirstChildOfClass("Humanoid")
	if h then return math.clamp(h.Health / math.max(h.MaxHealth, 1), 0, 1) end
	local mh = m:GetAttribute("MaxHealth")
	if mh and mh > 0 then return math.clamp((m:GetAttribute("Health") or 0) / mh, 0, 1) end
	return 1
end

local function updateEspList()
	local want = espCandidates()
	local r = Root()
	local maxD, maxN = F("EspMaxDistance") or 1000, F("EspMaxShown") or 60
	local arr = {}
	if r then for m, kind in pairs(want) do
		local pivot = m:GetPivot().Position
		local d = (pivot - r.Position).Magnitude
		if d <= maxD then table.insert(arr, { m = m, kind = kind, d = d }) end
	end end
	table.sort(arr, function(a, b) return a.d < b.d end)
	local keep = {}
	for i = 1, math.min(#arr, maxN) do keep[arr[i].m] = arr[i] end
	for m in pairs(ESP.objs) do if not keep[m] then killEsp(m) end end
	for m, e in pairs(keep) do
		local o = ESP.objs[m] or makeEsp(m, e.kind)
		o.d = e.d
		local col = espColor(e.kind)
		local fade = F("EspFade") and math.clamp(e.d / maxD, 0, 0.8) or 0
		o.hl.Enabled = F("EspOutlines") ~= false
		o.hl.OutlineColor = col
		o.hl.FillColor = col
		o.hl.FillTransparency = F("EspBoxFill") and 0.7 or 1
		o.hl.OutlineTransparency = fade
		o.tl.Text = espLabel(m, e.kind, e.d)
		o.tl.TextColor3 = col
		o.tl.TextTransparency = fade
		o.tl.TextSize = F("EspTextSize") or 13
		o.bar.Visible = F("EspHealthBars") == true
		local f = hpFrac(m)
		o.fill.Size = UDim2.fromScale(f, 1)
		o.fill.BackgroundColor3 = Color3.fromRGB(255 * (1 - f), 255 * f, 60)
	end
end

local function project(p)
	local cam = workspace.CurrentCamera
	local v, on = cam:WorldToViewportPoint(p)
	return Vector2.new(v.X, v.Y), on and v.Z > 0, v.Z
end

local function renderDrawings()
	if not hasDrawing then return end
	local cam = workspace.CurrentCamera
	local vp = cam.ViewportSize
	local center = vp / 2
	for m, o in pairs(ESP.objs) do
		if not m.Parent then hideDraw(o) continue end
		local col = espColor(o.kind)
		local cf, size = m:GetBoundingBox()
		local scr, on = project(cf.Position)
		if not on then
			hideDraw(o)
			if F("EspArrows") then
				local rel = cam.CFrame:PointToObjectSpace(cf.Position)
				local dir = Vector2.new(rel.X, -rel.Y)
				if rel.Z > 0 then dir = -dir end
				if dir.Magnitude > 0 then
					dir = dir.Unit
					local tip = center + dir * (math.min(vp.X, vp.Y) / 2 - 30)
					local perp = Vector2.new(-dir.Y, dir.X)
					o.arrow.PointA, o.arrow.PointB, o.arrow.PointC = tip, tip - dir * 16 + perp * 8, tip - dir * 16 - perp * 8
					o.arrow.Color, o.arrow.Visible = col, true
				end
			end
			continue
		end
		o.arrow.Visible = false
		local corners = {}
		local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
		local allOn = true
		for i = 0, 7 do
			local off = Vector3.new((i % 2 == 0) and -1 or 1, (math.floor(i / 2) % 2 == 0) and -1 or 1, (i < 4) and -1 or 1) * size / 2
			local p, ok = project((cf * CFrame.new(off)).Position)
			if not ok then allOn = false end
			corners[i + 1] = p
			minX, minY, maxX, maxY = math.min(minX, p.X), math.min(minY, p.Y), math.max(maxX, p.X), math.max(maxY, p.Y)
		end
		local show2d = F("EspBoxes") and allOn
		o.box.Visible = show2d
		o.boxFill.Visible = show2d and F("EspBoxFill") == true
		if show2d then
			o.box.Position, o.box.Size, o.box.Color = Vector2.new(minX, minY), Vector2.new(maxX - minX, maxY - minY), col
			o.boxFill.Position, o.boxFill.Size, o.boxFill.Color = o.box.Position, o.box.Size, col
		end
		local edges = { { 1, 2 }, { 3, 4 }, { 5, 6 }, { 7, 8 }, { 1, 3 }, { 2, 4 }, { 5, 7 }, { 6, 8 }, { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 } }
		for i, e in ipairs(edges) do
			local l = o.lines[i]
			l.Visible = F("Esp3DBoxes") == true and allOn
			if l.Visible then l.From, l.To, l.Color = corners[e[1]], corners[e[2]], col end
		end
		o.tracer.Visible = F("EspTracers") == true
		if o.tracer.Visible then o.tracer.From, o.tracer.To, o.tracer.Color = Vector2.new(center.X, vp.Y), scr, col end
	end
end

-- ============================================================ Rendering tweaks
local savedLighting
local function fullbright(on)
	if on then
		savedLighting = savedLighting or { Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd, GlobalShadows = Lighting.GlobalShadows, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient }
	elseif savedLighting then
		for k, v in pairs(savedLighting) do Lighting[k] = v end
		savedLighting = nil
	end
end
conn(RunService.RenderStepped:Connect(function()
	if F("Fullbright") then
		Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.GlobalShadows = 2, 14, 1e6, false
		Lighting.Ambient, Lighting.OutdoorAmbient = Color3.new(1, 1, 1), Color3.new(1, 1, 1)
	end
	renderDrawings()
end))

local lowGfxChanged = {}
local function lowGraphics(on)
	if on then
		pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Smoke") or d:IsA("Fire") or d:IsA("Sparkles") then
				if d.Enabled then d.Enabled = false table.insert(lowGfxChanged, d) end
			end
		end
		for _, e in ipairs(Lighting:GetChildren()) do if e:IsA("PostEffect") and e.Enabled then e.Enabled = false table.insert(lowGfxChanged, e) end end
	else
		for _, d in ipairs(lowGfxChanged) do pcall(function() d.Enabled = true end) end
		lowGfxChanged = {}
	end
end

-- ============================================================ Movement
local flyBV, flyBG
local function setFly(on)
	if flyBV then flyBV:Destroy() flyBV = nil end
	if flyBG then flyBG:Destroy() flyBG = nil end
	if on and Root() then
		flyBV = Instance.new("BodyVelocity") flyBV.MaxForce = Vector3.one * 1e9 flyBV.Velocity = Vector3.zero flyBV.Parent = Root()
		flyBG = Instance.new("BodyGyro") flyBG.MaxTorque = Vector3.one * 1e9 flyBG.P = 9e4 flyBG.Parent = Root()
	end
end
conn(RunService.RenderStepped:Connect(function()
	local h = Hum()
	if F("WalkSpeedOn") and h then h.WalkSpeed = F("WalkSpeed") or 30 end
	if F("JumpPowerOn") and h then h.UseJumpPower = true h.JumpPower = F("JumpPower") or 60 end
	if F("Fly") and flyBV and h then
		local cam = workspace.CurrentCamera
		local md = h.MoveDirection
		local v = Vector3.zero
		if md.Magnitude > 0 then
			local look = cam.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			local fwd = flat.Magnitude > 0 and md:Dot(flat.Unit) or 0
			v = md * (F("FlySpeed") or 60) + Vector3.new(0, look.Y * fwd * (F("FlySpeed") or 60), 0)
		end
		if UIS:IsKeyDown(Enum.KeyCode.Space) then v += Vector3.new(0, F("FlySpeed") or 60, 0) end
		if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then v -= Vector3.new(0, F("FlySpeed") or 60, 0) end
		flyBV.Velocity = v
		flyBG.CFrame = cam.CFrame
	end
end))
-- the game rewrites WalkSpeed every frame, so re-apply it whenever it changes
local wsConn
local function hookWalkSpeed()
	if wsConn then wsConn:Disconnect() end
	local h = Hum()
	if not h then return end
	wsConn = h:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		local want = F("WalkSpeedOn") and (F("WalkSpeed") or 30)
		if want and h.WalkSpeed ~= want then h.WalkSpeed = want end
	end)
	table.insert(Hub.Conns, wsConn)
end
hookWalkSpeed()
conn(LP.CharacterAdded:Connect(function() task.wait(0.5) hookWalkSpeed() end))
conn(UIS.JumpRequest:Connect(function()
	if F("InfJump") and Hum() then Hum():ChangeState(Enum.HumanoidStateType.Jumping) end
end))
conn(LP.Idled:Connect(function()
	if F("AntiAFK") ~= false then VirtualUser:CaptureController() VirtualUser:ClickButton2(Vector2.zero) end
end))
conn(LP.CharacterAdded:Connect(function()
	task.wait(1)
	if F("Fly") then setFly(true) end
end))
conn(GuiService.ErrorMessageChanged:Connect(function(msg)
	if F("AutoRejoin") and msg and msg ~= "" then
		task.wait(3)
		pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP) end)
		task.wait(5)
		pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
	end
end))

-- ============================================================ UI
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/voidhub9-dotcom/VoidHub-UI/main/Source.lua"))()
local Window = Library:CreateVoidHubWindow({
	Name = "The Forge",
	ToggleUIKeybind = "RightControl",
	ConfigurationSaving = { Enabled = true, FolderName = "ForgeHub" },
	Home = { Welcome = "Forge hub" },
	ToggleButton = { Platform = "Mobile", Icon = "hammer" },
})
Flags = Window.Flags
Hub.Window = Window
local function notify(title, content, kind) Window:Notify({ Title = title, Content = content, Type = kind, Duration = 4 }) end

local AutoToggles = { "AutoSellGear", "AutoClaim", "AutoMine", "MobFarm", "AutoForge", "AutoSell", "AutoBuy", "AutoPotions", "AutoHealthPotion", "Fly", "Noclip", "WalkSpeedOn", "JumpPowerOn", "InfJump" }

-- Farm tab ------------------------------------------------------------
local Farm = Window:CreateTab({ Name = "Farm", Desc = "Mining, combat, forge, selling, potions", Icon = "pickaxe" })
local MinePage = Farm:CreateSubTab({ Name = "Mining", Icon = "pickaxe" })
local CombatPage = Farm:CreateSubTab({ Name = "Combat", Icon = "swords" })
local ForgePage = Farm:CreateSubTab({ Name = "Forge", Icon = "flame" })
local SellPage = Farm:CreateSubTab({ Name = "Sell & Shop", Icon = "coins" })
local PotionPage = Farm:CreateSubTab({ Name = "Potions", Icon = "flask-conical" })

local zoneNames = {}
if workspace:FindFirstChild("Rocks") then for _, z in ipairs(workspace.Rocks:GetChildren()) do table.insert(zoneNames, z.Name) end end

local MineBox = MinePage:CreateGroupbox({ Name = "Auto mine", Side = "Left", Icon = "pickaxe" })
MineBox:CreateToggle({ Name = "Auto mine", Desc = "Flies to the best matching rock and swings the pickaxe.", Flag = "AutoMine", CurrentValue = false })
MineBox:CreateDropdown({ Name = "Rock types", Options = RockNames, MultipleOptions = true, AllowNone = true, Searchable = true, NoneText = "Any rock", Flag = "RockTypes" })
MineBox:CreateDropdown({ Name = "Never mine", Options = RockNames, MultipleOptions = true, AllowNone = true, Searchable = true, NoneText = "None", Flag = "NeverMine" })
MineBox:CreateDropdown({ Name = "Mining zones", Options = zoneNames, MultipleOptions = true, AllowNone = true, NoneText = "All zones", Flag = "MineZones" })
local prioList = MineBox:CreateOrderList({ Name = "Rock priority", Items = RockNames, MaxRows = 6, Numbered = true, Arrows = true, Flag = "RockPriority" })
MineBox:CreateButton({ Name = "Reset rock priority", Callback = function() prioList:Set(RockNames) end })
MineBox:CreateButton({ Name = "Refresh zones", Callback = function()
	local z = {} for _, c in ipairs(workspace.Rocks:GetChildren()) do table.insert(z, c.Name) end
	Flags.MineZones:SetOptions(z)
end })

local OreBox = MinePage:CreateGroupbox({ Name = "Ore filter", Side = "Left", Icon = "gem" })
OreBox:CreateDropdown({ Name = "Wanted ores", Options = OreNames, MultipleOptions = true, AllowNone = true, Searchable = true, NoneText = "No filter", Flag = "OreFilter" })
OreBox:CreateToggle({ Name = "Skip rocks that can't drop them", Desc = "Uses the rock's drop table.", Flag = "SkipWithoutOre", CurrentValue = false })
OreBox:CreateToggle({ Name = "Skip revealed mismatches", Desc = "Leaves a rock once its revealed ores don't match.", Flag = "SkipRevealedMismatch", CurrentValue = false })

local PosBox = MinePage:CreateGroupbox({ Name = "Position", Side = "Right", Icon = "move" })
PosBox:CreateDropdown({ Name = "Mine from", Options = { "Side", "Above", "Below" }, CurrentOption = "Side", AllowNone = false, Flag = "MinePosition",
	Desc = "Side and Above hit in tests. Below did no damage in tests." })
PosBox:CreateSlider({ Name = "Gap from rock", Range = { 0, 6 }, Increment = 0.5, CurrentValue = 2.5, Suffix = " st", Flag = "RockGap", Desc = "Reach is about 3 studs above the rock." })
PosBox:CreateSlider({ Name = "Height offset (side)", Range = { -4, 4 }, Increment = 0.5, CurrentValue = 0, Flag = "MineHeight" })
PosBox:CreateSlider({ Name = "Search range", Range = { 50, 3000 }, Increment = 50, CurrentValue = 2000, Suffix = " st", Flag = "SearchRange" })
PosBox:CreateSlider({ Name = "Swing delay", Range = { 0, 1 }, Increment = 0.05, CurrentValue = 0.1, Suffix = " s", Flag = "SwingDelay" })
PosBox:CreateToggle({ Name = "Camera lock to rock", Flag = "CamLockRock", CurrentValue = false })

local SafeBox = MinePage:CreateGroupbox({ Name = "Safety while mining", Side = "Right", Icon = "shield" })
SafeBox:CreateToggle({ Name = "Skip rocks with mobs nearby", Flag = "AvoidMobRocks", CurrentValue = true })
SafeBox:CreateSlider({ Name = "Mob check radius", Range = { 5, 80 }, Increment = 1, CurrentValue = 25, Flag = "MobAvoidRadius" })
SafeBox:CreateToggle({ Name = "Fight back while mining", Flag = "FightBack", CurrentValue = true })
SafeBox:CreateSlider({ Name = "Fight back range", Range = { 5, 50 }, Increment = 1, CurrentValue = 15, Flag = "FightRange" })
SafeBox:CreateToggle({ Name = "Skip rocks others mine", Flag = "SkipOthersRocks", CurrentValue = true })
SafeBox:CreateToggle({ Name = "Avoid players", Flag = "AvoidPlayers", CurrentValue = false })
SafeBox:CreateSlider({ Name = "Player distance", Range = { 5, 150 }, Increment = 5, CurrentValue = 30, Flag = "PlayerDistance" })
SafeBox:CreateToggle({ Name = "Skip rocks too hard", Desc = "Leaves a rock after 6 swings without damage.", Flag = "SkipHard", CurrentValue = true })
SafeBox:CreateStatus({ Name = "Rocks broken", Style = "Stat", Value = 0, Update = function() return Hub.Stats.Rocks end })

local MobBox = CombatPage:CreateGroupbox({ Name = "Mob farm", Side = "Left", Icon = "swords" })
MobBox:CreateToggle({ Name = "Mob farm", Flag = "MobFarm", CurrentValue = false })
MobBox:CreateDropdown({ Name = "Mobs", Options = mobTypeList(), MultipleOptions = true, AllowNone = true, Searchable = true, NoneText = "Any mob", Flag = "MobTypes" })
MobBox:CreateButton({ Name = "Refresh mob list", Callback = function() Flags.MobTypes:SetOptions(mobTypeList()) end })
MobBox:CreateSlider({ Name = "Farm range", Range = { 25, 3000 }, Increment = 25, CurrentValue = 500, Flag = "FarmRange" })
MobBox:CreateToggle({ Name = "Heavy attacks", Flag = "HeavyAttacks", CurrentValue = false })
MobBox:CreateToggle({ Name = "Keep away from players", Flag = "MobAvoidPlayers", CurrentValue = false })
MobBox:CreateSlider({ Name = "Player distance", Range = { 5, 150 }, Increment = 5, CurrentValue = 30, Flag = "MobPlayerDist" })
MobBox:CreateStatus({ Name = "Kills", Style = "Stat", Value = 0, Update = function() return Hub.Stats.Kills end })

local MobPosBox = CombatPage:CreateGroupbox({ Name = "Positioning", Side = "Right", Icon = "crosshair" })
MobPosBox:CreateDropdown({ Name = "Stand", Options = { "Behind", "Front", "Above", "Below" }, CurrentOption = "Behind", AllowNone = false, Flag = "MobPosition" })
MobPosBox:CreateSlider({ Name = "Distance", Range = { 1, 15 }, Increment = 0.5, CurrentValue = 4, Flag = "MobDistance" })
MobPosBox:CreateSlider({ Name = "Height offset", Range = { -10, 10 }, Increment = 0.5, CurrentValue = 0, Flag = "MobHeight" })
MobPosBox:CreateToggle({ Name = "Camera lock to mob", Flag = "CamLockMob", CurrentValue = false })

local DefBox = CombatPage:CreateGroupbox({ Name = "Defense", Side = "Right", Icon = "shield" })
DefBox:CreateToggle({ Name = "Auto block (parry)", Desc = "Blocks on the mob's ParryWindow cue.", Flag = "AutoBlock", CurrentValue = true })
DefBox:CreateToggle({ Name = "Auto dodge", Desc = "Hops above for 0.8 s when a mob winds up.", Flag = "AutoDodge", CurrentValue = false })
DefBox:CreateToggle({ Name = "Retreat on low health", Flag = "RetreatEnabled", CurrentValue = true })
DefBox:CreateSlider({ Name = "Retreat below", Range = { 5, 90 }, Increment = 1, CurrentValue = 35, Suffix = "%", Flag = "RetreatAt" })
DefBox:CreateSlider({ Name = "Resume at", Range = { 20, 100 }, Increment = 1, CurrentValue = 80, Suffix = "%", Flag = "ResumeAt" })
DefBox:CreateSlider({ Name = "Retreat height", Range = { 20, 200 }, Increment = 5, CurrentValue = 60, Flag = "RetreatHeight" })

local FBox = ForgePage:CreateGroupbox({ Name = "Auto forge", Side = "Left", Icon = "flame" })
FBox:CreateToggle({ Name = "Auto forge", Desc = "Repeats the recipe while you have the ores.", Flag = "AutoForge", CurrentValue = false })
FBox:CreateToggle({ Name = "Perfect melt, pour and hammer", Desc = "Also applies when you forge by hand.", Flag = "PerfectForge", CurrentValue = true, Callback = function(on) setPerfect(on) end })
FBox:CreateDropdown({ Name = "Item type", Options = { "Weapon", "Armor" }, CurrentOption = "Weapon", AllowNone = false, Flag = "ForgeType" })
FBox:CreateToggle({ Name = "Fast forge (gamepass)", Flag = "FastForge", CurrentValue = false })
FBox:CreateButton({ Name = "Forge once", Icon = "hammer", Callback = function() task.spawn(function() local ok, msg = forgeOnce() notify("Forge", msg, ok and "Success" or "Warning") end) end })
FBox:CreateButton({ Name = "Cancel forge", Style = "Danger", Callback = function() Hub.ForgeCancel = true cancelForge() end })
FBox:CreateStatus({ Name = "Forged", Style = "Stat", Value = 0, Update = function() return Hub.Stats.Forged end })
FBox:CreateLabel({ Text = "-", Update = function() return "Last: " .. tostring(Hub.LastForge or "-") end })

local RecBox = ForgePage:CreateGroupbox({ Name = "Recipe", Side = "Right", Icon = "list" })
local oreOpts = { "None" }
for _, n in ipairs(OreNames) do table.insert(oreOpts, n) end
for i = 1, 4 do
	RecBox:CreateDropdown({ Name = "Ore slot " .. i, Options = oreOpts, CurrentOption = "None", AllowNone = false, Searchable = true, Flag = "ForgeOre" .. i })
	RecBox:CreateStepper({ Name = "Amount " .. i, Range = { 0, 99 }, Increment = 1, CurrentValue = i == 1 and 3 or 0, Flag = "ForgeQty" .. i })
end
RecBox:CreateStatusList({ Name = "Recipe preview", MaxRows = 6, EmptyText = "Pick ores", Update = function()
	local rows = {}
	local ores, total = forgeRecipe()
	for o, q in pairs(ores) do
		local have = invCount(o)
		table.insert(rows, { Text = o, Value = ("%d / %d"):format(q, have), Tone = have >= q and "Success" or "Error" })
	end
	local ok, why = recipeReady()
	table.insert(rows, { Text = "Total " .. total, Value = ok and "Ready" or why, Tone = ok and "Success" or "Warning" })
	return rows
end })

local SBox = SellPage:CreateGroupbox({ Name = "Auto sell", Side = "Left", Icon = "coins" })
SBox:CreateToggle({ Name = "Auto sell", Flag = "AutoSell", CurrentValue = false })
SBox:CreateDropdown({ Name = "Sell ores", Options = OreNames, MultipleOptions = true, AllowNone = true, Searchable = true, NoneText = "None", Flag = "SellOres" })
SBox:CreateDropdown({ Name = "Sell by rarity", Options = RarityList, MultipleOptions = true, AllowNone = true, NoneText = "None", Flag = "SellRarities" })
SBox:CreateDropdown({ Name = "Never sell", Options = OreNames, MultipleOptions = true, AllowNone = true, Searchable = true, NoneText = "None", Flag = "NeverSell" })
SBox:CreateStepper({ Name = "Keep of each ore", Range = { 0, 500 }, Increment = 1, CurrentValue = 0, Flag = "KeepAmount" })
SBox:CreateDropdown({ Name = "Sell when", Options = { "Ore count", "Bag full", "Interval" }, CurrentOption = "Ore count", AllowNone = false, Flag = "SellMode" })
SBox:CreateSlider({ Name = "Ore count", Range = { 10, 1000 }, Increment = 10, CurrentValue = 150, Flag = "SellThreshold" })
SBox:CreateSlider({ Name = "Interval", Range = { 60, 1800 }, Increment = 30, CurrentValue = 300, Suffix = " s", Flag = "SellInterval" })
SBox:CreateToggle({ Name = "Sell runes too", Desc = "Favorited runes are kept.", Flag = "SellRunes", CurrentValue = false })
local runeKinds, runeSeen = {}, {}
for k, v in pairs(ItemTypes()) do
	if type(v) == "table" and v[1] == "Rune" then local kind = tostring(k):match("^(.-)_T%d+$") if kind and not runeSeen[kind] then runeSeen[kind] = true table.insert(runeKinds, kind) end end
end
table.sort(runeKinds)
SBox:CreateDropdown({ Name = "Rune tiers", Options = { "T1", "T2", "T3", "T4", "T5" }, MultipleOptions = true, AllowNone = true, NoneText = "All tiers", Flag = "RuneTiers" })
SBox:CreateDropdown({ Name = "Rune types", Options = runeKinds, MultipleOptions = true, AllowNone = true, Searchable = true, NoneText = "All types", Flag = "RuneKinds" })
SBox:CreateToggle({ Name = "Fly back after selling", Flag = "ReturnAfterSell", CurrentValue = true })
SBox:CreateButton({ Name = "Sell now", Style = "Primary", Callback = function() task.spawn(function() local ok, msg = sellNow() notify("Sell", msg, ok and "Success" or "Warning") end) end })

local BasketBox = SellPage:CreateGroupbox({ Name = "Basket preview", Side = "Right", Icon = "shopping-basket" })
BasketBox:CreateStatusList({ Name = "Will sell", MaxRows = 8, EmptyText = "Nothing selected", Update = function()
	local rows = {}
	for k, v in pairs((buildBasket())) do table.insert(rows, { Text = OreInfo[k] and k or "Rune " .. tostring(k):sub(1, 8), Value = "x" .. v }) end
	return rows
end })
BasketBox:CreateStatus({ Name = "Bag", Style = "Row", Update = function() return ("%d / %d ores"):format(oreTotal(), bagCapacity()) end })

local GearBox = SellPage:CreateGroupbox({ Name = "Gear sell", Side = "Left", Icon = "sword" })
GearBox:CreateToggle({ Name = "Auto sell gear", Desc = "Never sells equipped or favorited gear.", Flag = "AutoSellGear", CurrentValue = false })
GearBox:CreateDropdown({ Name = "Gear types", Options = { "Weapon", "Armor" }, MultipleOptions = true, AllowNone = true, NoneText = "Weapons and armor", Flag = "GearKinds" })
GearBox:CreateSlider({ Name = "Sell at or below quality", Range = { 0, 100 }, Increment = 1, CurrentValue = 50, Flag = "GearMaxQuality" })
GearBox:CreateStepper({ Name = "Max upgrade level", Range = { 0, 20 }, Increment = 1, CurrentValue = 0, Flag = "GearMaxUpgrade" })
GearBox:CreateToggle({ Name = "Keep gear with runes", Flag = "GearKeepRuned", CurrentValue = true })
GearBox:CreateStepper({ Name = "Sell when this many match", Range = { 1, 50 }, Increment = 1, CurrentValue = 3, Flag = "GearSellAt" })
GearBox:CreateStatusList({ Name = "Will sell", MaxRows = 6, EmptyText = "Nothing matches", Update = function()
	local rows, d = {}, Data()
	local b = buildGearBasket()
	for _, e in ipairs(d and d.Inventory.Equipments or {}) do if b[e.GUID] then table.insert(rows, { Text = tostring(e.Type), Value = ("Q%.0f %s"):format(e.Quality or 0, tostring(e.Ore)) }) end end
	return rows
end })
GearBox:CreateButton({ Name = "Sell gear now", Style = "Primary", Callback = function() task.spawn(function() local ok, msg = sellGear() notify("Gear", msg, ok and "Success" or "Warning") end) end })

local ShopBox = SellPage:CreateGroupbox({ Name = "Shop", Side = "Right", Icon = "store" })
local shopItems = {}
for _, p in ipairs(workspace.Proximity:GetChildren()) do if ItemTypes()[p.Name] then table.insert(shopItems, p.Name) end end
table.sort(shopItems)
ShopBox:CreateToggle({ Name = "Auto buy", Desc = "Keeps the stock of each picked item.", Flag = "AutoBuy", CurrentValue = false })
ShopBox:CreateDropdown({ Name = "Items", Options = shopItems, MultipleOptions = true, AllowNone = true, Searchable = true, NoneText = "None", Flag = "BuyItems" })
ShopBox:CreateStepper({ Name = "Target stock", Range = { 1, 99 }, Increment = 1, CurrentValue = 5, Flag = "TargetStock" })
ShopBox:CreateStepper({ Name = "Max per purchase", Range = { 1, 99 }, Increment = 1, CurrentValue = 10, Flag = "BuyMax" })
ShopBox:CreateButton({ Name = "Buy one of each now", Callback = function() task.spawn(function()
	for _, n in ipairs(list("BuyItems")) do local ok, msg = buyItem(n, 1) notify("Shop", msg, ok and "Success" or "Warning") end
end) end })

local PBox = PotionPage:CreateGroupbox({ Name = "Potions", Side = "Left", Icon = "flask-conical" })
PBox:CreateToggle({ Name = "Auto drink potions", Desc = "Drinks each picked buff potion when it runs out.", Flag = "AutoPotions", CurrentValue = false })
PBox:CreateDropdown({ Name = "Potions", Options = PotionNames, MultipleOptions = true, AllowNone = true, Searchable = true, NoneText = "None", Flag = "PotionList" })
PBox:CreateButton({ Name = "Refresh potions", Callback = function()
	local t = {} for k, v in pairs(ItemTypes()) do if type(v) == "table" and v[1] == "Potion" then table.insert(t, k) end end table.sort(t)
	Flags.PotionList:SetOptions(t)
end })
PBox:CreateToggle({ Name = "Health potion on low HP", Flag = "AutoHealthPotion", CurrentValue = false })
PBox:CreateSlider({ Name = "Health threshold", Range = { 5, 95 }, Increment = 1, CurrentValue = 40, Suffix = "%", Flag = "HealthPotionAt" })
PBox:CreateButton({ Name = "Drink picked now", Callback = function() task.spawn(function() for _, n in ipairs(list("PotionList")) do usePotion(n) end end) end })
local PotStat = PotionPage:CreateGroupbox({ Name = "Active", Side = "Right", Icon = "timer" })
PotStat:CreateStatusList({ Name = "Active potions", MaxRows = 8, EmptyText = "None active", Update = function()
	local rows = {}
	for k, v in pairs(Data() and Data().Potions or {}) do table.insert(rows, { Text = k, Value = tostring(v) .. " s" }) end
	return rows
end })

-- Visuals tab ---------------------------------------------------------
local Visuals = Window:CreateTab({ Name = "Visuals", Desc = "ESP and rendering", Icon = "eye" })
local EspPage = Visuals:CreateSubTab({ Name = "ESP", Icon = "scan" })
local RenderPage = Visuals:CreateSubTab({ Name = "Rendering", Icon = "sun" })

local EBox = EspPage:CreateGroupbox({ Name = "Targets", Side = "Left", Icon = "scan" })
EBox:CreateToggle({ Name = "Rock ESP", Flag = "RockESP", CurrentValue = false })
EBox:CreateDropdown({ Name = "Only these rocks", Options = RockNames, MultipleOptions = true, AllowNone = true, Searchable = true, NoneText = "All rocks", Flag = "EspRockTypes" })
EBox:CreateToggle({ Name = "Revealed ore labels", Flag = "RevealedOreLabels", CurrentValue = true })
EBox:CreateToggle({ Name = "Show possible ores", Flag = "PossibleOres", CurrentValue = false })
EBox:CreateToggle({ Name = "Mob ESP", Flag = "MobESP", CurrentValue = false })
EBox:CreateToggle({ Name = "Player ESP", Flag = "PlayerESP", CurrentValue = false })
EBox:CreateColorPicker({ Name = "Rock color", Color = Color3.fromRGB(120, 200, 255), Flag = "RockColor" })
EBox:CreateColorPicker({ Name = "Mob color", Color = Color3.fromRGB(255, 90, 90), Flag = "MobColor" })
EBox:CreateColorPicker({ Name = "Player color", Color = Color3.fromRGB(120, 255, 140), Flag = "PlayerColor" })

local EOpt = EspPage:CreateGroupbox({ Name = "Style", Side = "Right", Icon = "palette" })
EOpt:CreateToggle({ Name = "Outlines", Flag = "EspOutlines", CurrentValue = true })
EOpt:CreateToggle({ Name = "Names", Flag = "EspNames", CurrentValue = true })
EOpt:CreateToggle({ Name = "Anonymous player names", Flag = "EspAnon", CurrentValue = false })
EOpt:CreateToggle({ Name = "Distance", Flag = "EspDistance", CurrentValue = true })
EOpt:CreateToggle({ Name = "Health numbers", Flag = "EspHealthText", CurrentValue = false })
EOpt:CreateToggle({ Name = "Health bars", Flag = "EspHealthBars", CurrentValue = false })
EOpt:CreateToggle({ Name = "Boxes", Flag = "EspBoxes", CurrentValue = false, Disabled = not hasDrawing })
EOpt:CreateToggle({ Name = "Box fill", Flag = "EspBoxFill", CurrentValue = false })
EOpt:CreateToggle({ Name = "3D boxes", Flag = "Esp3DBoxes", CurrentValue = false, Disabled = not hasDrawing })
EOpt:CreateToggle({ Name = "Tracers", Flag = "EspTracers", CurrentValue = false, Disabled = not hasDrawing })
EOpt:CreateToggle({ Name = "Off-screen arrows", Flag = "EspArrows", CurrentValue = false, Disabled = not hasDrawing })
EOpt:CreateToggle({ Name = "Fade with distance", Flag = "EspFade", CurrentValue = false })
EOpt:CreateSlider({ Name = "Max shown", Range = { 5, 200 }, Increment = 5, CurrentValue = 60, Flag = "EspMaxShown" })
EOpt:CreateSlider({ Name = "Max distance", Range = { 50, 5000 }, Increment = 50, CurrentValue = 1000, Flag = "EspMaxDistance" })
EOpt:CreateSlider({ Name = "Text size", Range = { 8, 24 }, Increment = 1, CurrentValue = 13, Flag = "EspTextSize" })

local RBox = RenderPage:CreateGroupbox({ Name = "Rendering", Side = "Left", Icon = "sun" })
RBox:CreateToggle({ Name = "Fullbright", Flag = "Fullbright", CurrentValue = false, Callback = fullbright })
RBox:CreateToggle({ Name = "Low graphics / FPS boost", Flag = "LowGfx", CurrentValue = false, Callback = lowGraphics })
RBox:CreateToggle({ Name = "Streamer mode", Desc = "Hides your name and avatar in the hub.", Flag = "Streamer", CurrentValue = false, Callback = function(on)
	pcall(function() Window:SetHideName(on) Window:SetHideAvatar(on) end)
end })

-- Misc tab ------------------------------------------------------------
local Misc = Window:CreateTab({ Name = "Misc", Desc = "Player, travel, staff, webhook, settings", Icon = "settings" })
local PlayerPage = Misc:CreateSubTab({ Name = "Player", Icon = "user" })
local TravelPage = Misc:CreateSubTab({ Name = "Travel", Icon = "map" })
local StaffPage = Misc:CreateSubTab({ Name = "Staff", Icon = "shield-alert" })
local HookPage = Misc:CreateSubTab({ Name = "Webhook", Icon = "webhook" })
local SetPage = Misc:CreateSubTab({ Name = "Settings", Icon = "sliders-horizontal" })

local MoveBox = PlayerPage:CreateGroupbox({ Name = "Movement", Side = "Left", Icon = "footprints" })
MoveBox:CreateToggle({ Name = "Anti AFK", Flag = "AntiAFK", CurrentValue = true })
MoveBox:CreateToggle({ Name = "Noclip", Flag = "Noclip", CurrentValue = false })
MoveBox:CreateToggle({ Name = "Infinite jump", Flag = "InfJump", CurrentValue = false })
MoveBox:CreateToggle({ Name = "Walk speed", Flag = "WalkSpeedOn", CurrentValue = false, Callback = function(on) if not on and Hum() then Hum().WalkSpeed = 16 end end })
MoveBox:CreateSlider({ Name = "Speed", Range = { 16, 120 }, Increment = 1, CurrentValue = 30, Flag = "WalkSpeed" })
MoveBox:CreateToggle({ Name = "Jump power", Flag = "JumpPowerOn", CurrentValue = false })
MoveBox:CreateSlider({ Name = "Power", Range = { 30, 200 }, Increment = 5, CurrentValue = 60, Flag = "JumpPower" })
MoveBox:CreateToggle({ Name = "Fly", Desc = "Move stick steers; look up or down to climb.", Flag = "Fly", CurrentValue = false, Callback = setFly })
MoveBox:CreateSlider({ Name = "Fly speed", Range = { 10, 150 }, Increment = 5, CurrentValue = 60, Flag = "FlySpeed" })

local ServerBox = PlayerPage:CreateGroupbox({ Name = "Server", Side = "Right", Icon = "server" })
ServerBox:CreateButton({ Name = "Rejoin", Callback = function() Window:Rejoin() end })
ServerBox:CreateButton({ Name = "Server hop", Callback = function() Window:ServerHop() end })
ServerBox:CreateButton({ Name = "Smallest server", Callback = function() Window:JoinLowestServer() end })
ServerBox:CreateToggle({ Name = "Auto rejoin on disconnect", Flag = "AutoRejoin", CurrentValue = false })

local TBox = TravelPage:CreateGroupbox({ Name = "Locations", Side = "Left", Icon = "map-pin" })
local function locationNames()
	local t = {} for _, p in ipairs(workspace.Proximity:GetChildren()) do table.insert(t, p.Name) end table.sort(t) return t
end
TBox:CreateSlider({ Name = "Travel speed", Range = { 20, 150 }, Increment = 5, CurrentValue = 70, Suffix = " st/s", Flag = "TweenSpeed", Desc = "Instant teleports get reverted by the server." })
TBox:CreateDropdown({ Name = "Destination", Options = locationNames(), Searchable = true, AllowNone = true, NoneText = "Pick a place", Flag = "TravelTarget" })
TBox:CreateButtonRow({
	{ Name = "Go", Style = "Primary", Callback = function()
		local p = workspace.Proximity:FindFirstChild(F("TravelTarget") or "")
		if p then task.spawn(travel, CFrame.new(p:GetPivot().Position + Vector3.new(0, 3, 5))) end
	end },
	{ Name = "Stop", Style = "Danger", Callback = cancelTravel },
})
TBox:CreateButton({ Name = "Refresh destinations", Callback = function() Flags.TravelTarget:SetOptions(locationNames()) end })

local IBox = TravelPage:CreateGroupbox({ Name = "Islands", Side = "Right", Icon = "globe" })
IBox:CreateDropdown({ Name = "Island", Options = IslandNames, AllowNone = true, NoneText = "Pick an island", Flag = "Island" })
IBox:CreateButton({ Name = "Travel to island", Style = "Primary", Callback = function()
	local n = F("Island")
	if n then task.spawn(function() local ok, r = invoke("PortalService", "TeleportToIsland", n) notify("Island", tostring(r), ok and "Success" or "Error") end) end
end })

local StBox = StaffPage:CreateGroupbox({ Name = "Staff watch", Side = "Left", Icon = "shield-alert" })
StBox:CreateToggle({ Name = "Watch for staff", Desc = "Group 35489258, rank 35 and up.", Flag = "StaffWatch", CurrentValue = true })
StBox:CreateDropdown({ Name = "When staff join", Options = { "Notify only", "Pause farming", "Leave (server hop)", "Keep farming" }, CurrentOption = "Pause farming", AllowNone = false, Flag = "StaffAction" })
StBox:CreateStatus({ Name = "Staff here", Style = "Badge", Update = function() local s = staffInServer() return s and ("<Error>" .. s.Name .. "</Error>") or "<Success>None</Success>" end })

local HBox = HookPage:CreateGroupbox({ Name = "Discord webhook", Side = "Left", Icon = "webhook" })
HBox:CreateInput({ Name = "Webhook URL", PlaceholderText = "https://discord.com/api/webhooks/...", Flag = "WebhookURL" })
HBox:CreateToggle({ Name = "Ore gain alerts", Flag = "WebhookOres", CurrentValue = false })
HBox:CreateDropdown({ Name = "Alert ores", Options = OreNames, MultipleOptions = true, AllowNone = true, Searchable = true, NoneText = "None", Flag = "WebhookOreList" })
HBox:CreateToggle({ Name = "Forged item alerts", Flag = "WebhookForge", CurrentValue = false })
HBox:CreateToggle({ Name = "Hide my name", Flag = "WebhookHideName", CurrentValue = false })
HBox:CreateColorPicker({ Name = "Embed color", Color = Color3.fromRGB(230, 230, 230), Flag = "WebhookColor" })
HBox:CreateButton({ Name = "Test webhook", Callback = function()
	local ok = webhook("Webhook test", { { name = "Status", value = "Working" } })
	notify("Webhook", ok and "Sent" or "Failed (check the URL)", ok and "Success" or "Error")
end })

local ClaimPage = Misc:CreateSubTab({ Name = "Claims", Icon = "gift" })
local function claimAll()
	local res = {}
	local function try(label, service, name, ...)
		local ok, a, b = invoke(service, name, ...)
		local msg = type(a) == "table" and (a.Message or (a.Ok and "ok") or "done") or tostring(a)
		if b ~= nil then msg = msg .. " " .. tostring(b) end
		table.insert(res, label .. ": " .. (ok and msg or "error"))
	end
	if F("ClaimMail") then try("Mail", "MailService", "ClaimAll") end
	if F("ClaimLevel") then try("Level rewards", "LevelRewardsService", "ClaimAll") end
	if F("ClaimDaily") then for day = 1, 7 do invoke("DailyLoginService", "Claim", day) end table.insert(res, "Daily login: checked days 1-7") end
	if F("ClaimCodex") then try("Codex", "CodexService", "ClaimAll") end
	if F("ClaimSeasonal") then try("Event milestones", "SeasonalEventService", "ClaimAllMilestones") try("Event quests", "SeasonalEventService", "ClaimAll") end
	if F("ClaimAltar") then try("Twilight altar", "TwilightAltarService", "ClaimDaily") end
	if F("ClaimGroup") then try("Group reward", "GroupRewardService", "Claim") end
	return res
end
local CBox = ClaimPage:CreateGroupbox({ Name = "Auto claim", Side = "Left", Icon = "gift" })
CBox:CreateToggle({ Name = "Auto claim every 5 min", Flag = "AutoClaim", CurrentValue = false })
CBox:CreateToggle({ Name = "Mail", Flag = "ClaimMail", CurrentValue = true })
CBox:CreateToggle({ Name = "Level rewards", Flag = "ClaimLevel", CurrentValue = true })
CBox:CreateToggle({ Name = "Daily login", Flag = "ClaimDaily", CurrentValue = true })
CBox:CreateToggle({ Name = "Codex", Flag = "ClaimCodex", CurrentValue = true })
CBox:CreateToggle({ Name = "Event quests and milestones", Flag = "ClaimSeasonal", CurrentValue = true })
CBox:CreateToggle({ Name = "Twilight altar daily", Flag = "ClaimAltar", CurrentValue = true })
CBox:CreateToggle({ Name = "Group reward", Flag = "ClaimGroup", CurrentValue = true })
local claimLog = ClaimPage:CreateGroupbox({ Name = "Results", Side = "Right", Icon = "list" }):CreateLog({ Name = "Claim log", MaxRows = 10, Timestamps = true })
CBox:CreateButton({ Name = "Claim now", Style = "Primary", Callback = function()
	task.spawn(function() for _, line in ipairs(claimAll()) do claimLog:Push(line) end end)
end })
local CodeBox = ClaimPage:CreateGroupbox({ Name = "Codes", Side = "Right", Icon = "ticket" })
CodeBox:CreateInput({ Name = "Codes", PlaceholderText = "CODE1, CODE2, ...", Flag = "CodeList" })
CodeBox:CreateButton({ Name = "Redeem all", Callback = function()
	task.spawn(function()
		for code in tostring(F("CodeList") or ""):gmatch("[^,%s]+") do
			local ok, r = invoke("CodeService", "RedeemCode", code)
			claimLog:Push(code .. ": " .. tostring(type(r) == "table" and r.Message or r))
			task.wait(0.5)
		end
	end)
end })
task.spawn(function()
	while Hub.Running do
		if F("AutoClaim") then for _, line in ipairs(claimAll()) do claimLog:Push(line) end end
		for _ = 1, 300 do if not Hub.Running then break end task.wait(1) end
	end
end)

local DiagBox = SetPage:CreateGroupbox({ Name = "Runtime", Side = "Left", Icon = "activity" })
DiagBox:CreateStatus({ Name = "State", Style = "Row", Pin = true, Update = function() return Hub.State end })
DiagBox:CreateStatus({ Name = "Target", Style = "Row", Update = function() return Hub.Target end })
DiagBox:CreateStatus({ Name = "Last error", Style = "Row", Update = function() return Hub.LastError end })
DiagBox:CreateStatus({ Name = "Drawing API", Style = "Row", Value = hasDrawing and "<Success>Yes</Success>" or "<Warning>No</Warning>" })
local function emergencyStop()
	for _, f in ipairs(AutoToggles) do if Flags[f] and Flags[f].Value then Flags[f]:Set(false) end end
	cancelTravel() release() cancelForge()
	notify("Stopped", "All automation is off.", "Warning")
end
DiagBox:CreateKeybind({ Name = "Emergency stop", CurrentKeybind = "F8", Flag = "StopKey", Callback = emergencyStop })
DiagBox:CreateKeybind({ Name = "Unload", CurrentKeybind = "F9", Flag = "UnloadKey", Callback = function() Hub.Unload() end })
DiagBox:CreateButton({ Name = "Emergency stop", Style = "Danger", Callback = emergencyStop })
DiagBox:CreateButton({ Name = "Unload hub", Style = "Danger", Confirm = true, Callback = function() Hub.Unload() end })
SetPage:CreateConfigManager({ Side = "Right" })
SetPage:CreateThemeManager({ Side = "Right" })

-- ============================================================ Loops
task.spawn(brain)
task.spawn(function()
	while Hub.Running do
		pcall(updateEspList)
		task.wait(0.25)
	end
end)
task.spawn(function()
	local lastEq = Data() and #Data().Inventory.Equipments or 0
	while Hub.Running do
		pcall(webhookStep)
		pcall(function()
			local eqs = Data().Inventory.Equipments
			if #eqs > lastEq and F("WebhookForge") then
				local e = eqs[#eqs]
				webhook("Forged: " .. tostring(e.Type), { { name = "Quality", value = ("%.1f"):format(e.Quality or 0), inline = true }, { name = "Main ore", value = tostring(e.Ore), inline = true } })
			end
			lastEq = #eqs
		end)
		local s = F("StaffWatch") and staffInServer()
		local act = F("StaffAction")
		Hub.Paused = s ~= nil and act == "Pause farming"
		if s and not Hub.StaffSeen then
			Hub.StaffSeen = true
			notify("Staff in server", s.Name, "Warning")
			if act == "Leave (server hop)" then Window:ServerHop() end
		elseif not s then Hub.StaffSeen = false end
		task.wait(2)
	end
end)

function Hub.Unload()
	Hub.Running = false
	cancelTravel() release() setFly(false) setPerfect(false) fullbright(false) lowGraphics(false)
	for _, c in ipairs(Hub.Conns) do pcall(function() c:Disconnect() end) end
	for m in pairs(ESP.objs) do killEsp(m) end
	for _, c in pairs(parryWatch) do pcall(function() c:Disconnect() end) end
	espFolder:Destroy()
	pcall(function() Window:Destroy() end)
	getgenv().ForgeHub = nil
end

setPerfect(true)
Window:LoadAutoload()
notify("The Forge", "Hub loaded. F8 stops everything, F9 unloads.", "Success")
return Hub
