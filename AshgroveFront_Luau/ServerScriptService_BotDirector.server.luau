-- AI soldiers for TRENCH WARFARE: fill each team up to TEAM_SIZE when there aren't enough players.
-- Bots navigate the trenches, spot enemies by line of sight, and fight with the same weapon stats as players.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterPack = game:GetService("StarterPack")
local PathfindingService = game:GetService("PathfindingService")
local Debris = game:GetService("Debris")

local API = require(script.Parent:WaitForChild("CombatAPI"))
local Config = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatConfig"))
repeat task.wait(0.2) until API.ready

local TEAM_SIZE = 5            -- players + bots per team
local DAMAGE_MULT = 0.7        -- bots hit a bit softer than players
local REACTION = { 0.45, 0.9 } -- seconds before a bot opens fire on a new target
local RESPAWN_DELAY = 6
local VIEW_RANGE = { Rifle = 140, SMG = 75 } -- max distance a bot spots AND shoots at
local WEATHER_VIEW = { Fog = 0.5, Night = 0.6, Rain = 0.8 }
local function engageRange(wid)
	return (VIEW_RANGE[wid] or 100) * (WEATHER_VIEW[workspace:GetAttribute("Weather") or ""] or 1)
end

local folder = workspace:FindFirstChild("Bots") or Instance.new("Folder")
folder.Name = "Bots"
folder.Parent = workspace
local map = workspace:WaitForChild("AshgroveFront")

local NAMES = { "Hale", "Brandt", "Okafor", "Lindqvist", "Moreau", "Kowal", "Reyes", "Duncan", "Sato", "Varga", "Ellis", "Novak",
	"Ferreira", "Hughes", "Bakker", "Ruiz", "Petrov", "Nakamura", "Doyle", "Weber", "Costa", "Grant", "Ivanov", "Marsh" }
local RANKS = { "Pvt.", "Pvt.", "Cpl.", "Sgt.", "Pvt.", "L/Cpl." }
local SKIN = { Color3.fromRGB(234, 192, 160), Color3.fromRGB(204, 150, 112), Color3.fromRGB(160, 110, 76), Color3.fromRGB(110, 74, 52), Color3.fromRGB(242, 210, 186) }
local UNIFORM = {
	Blue = { torso = Color3.fromRGB(70, 82, 104), legs = Color3.fromRGB(56, 62, 78), helmet = Color3.fromRGB(78, 88, 92) },
	Red = { torso = Color3.fromRGB(112, 74, 58), legs = Color3.fromRGB(82, 60, 50), helmet = Color3.fromRGB(96, 88, 70) },
}
local ANIM = { walk = "rbxassetid://2510202577", run = "rbxassetid://2510198475", idle = "rbxassetid://2510196951" }

------------------------------------------------------------------ templates
local templates = {}
local function weld(a, b) local w = Instance.new("WeldConstraint") w.Part0 = a w.Part1 = b w.Parent = b end
local function buildTemplate(key)
	local u = UNIFORM[key]
	local desc = Instance.new("HumanoidDescription")
	desc.TorsoColor = u.torso
	desc.LeftLegColor, desc.RightLegColor = u.legs, u.legs
	desc.LeftArmColor, desc.RightArmColor = u.torso, u.torso
	desc.HeadColor = SKIN[1]
	local ok, m = pcall(function() return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15) end)
	if not ok then warn("[Bots] template failed: " .. tostring(m)) return nil end
	for _, d in m:GetDescendants() do if d:IsA("LuaSourceContainer") then d:Destroy() end end
	local head = m:FindFirstChild("Head")
	-- steel helmet: dome + brim
	local dome = Instance.new("Part")
	dome.Name = "HelmetDome"; dome.Shape = Enum.PartType.Ball; dome.Size = Vector3.new(1.5, 1.5, 1.5)
	dome.Color = u.helmet; dome.Material = Enum.Material.Metal
	dome.CanCollide, dome.CanQuery, dome.CanTouch, dome.Massless = false, true, false, true
	dome.CFrame = head.CFrame * CFrame.new(0, 0.42, 0)
	dome.Parent = m
	weld(head, dome)
	local brim = Instance.new("Part")
	brim.Name = "HelmetBrim"; brim.Shape = Enum.PartType.Cylinder; brim.Size = Vector3.new(0.12, 2.1, 2.1)
	brim.Color = u.helmet; brim.Material = Enum.Material.Metal
	brim.CanCollide, brim.CanQuery, brim.CanTouch, brim.Massless = false, false, false, true
	brim.CFrame = head.CFrame * CFrame.new(0, 0.38, 0) * CFrame.Angles(0, 0, math.rad(90))
	brim.Parent = m
	weld(head, brim)
	-- team armband
	local arm = m:FindFirstChild("LeftUpperArm")
	if arm then
		local band = Instance.new("Part")
		band.Name = "TeamArmband"; band.Size = Vector3.new(arm.Size.X + 0.1, 0.35, arm.Size.Z + 0.1)
		band.Color = Config.Teams[key].color.Color; band.Material = Enum.Material.Fabric
		band.CanCollide, band.CanQuery, band.CanTouch, band.Massless = false, false, false, true
		band.CFrame = arm.CFrame
		band.Parent = m
		weld(arm, band)
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	hum.NameDisplayDistance = 45
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	hum.HealthDisplayDistance = 60
	hum.BreakJointsOnDeath = false
	if not hum:FindFirstChildOfClass("Animator") then Instance.new("Animator").Parent = hum end
	m:SetAttribute("BotTeam", key)
	return m
end
templates.Blue = buildTemplate("Blue")
templates.Red = buildTemplate("Red")

local weaponTools = {
	Rifle = StarterPack:FindFirstChild("Rifle"),
	SMG = ServerStorage:FindFirstChild("WeaponTemplates") and ServerStorage.WeaponTemplates:FindFirstChild("SMG"),
}

------------------------------------------------------------------ helpers
local function mode() return workspace:GetAttribute("GameMode") end
local function teamPlayers(key)
	local n = 0
	for _, p in Players:GetPlayers() do if API.teamKey(p) == key then n += 1 end end
	return n
end
local function spawnPoints(key)
	local list = {}
	local spawns = map:FindFirstChild("Spawns")
	if spawns then
		for _, sp in spawns:GetChildren() do
			if sp:IsA("SpawnLocation") and sp.TeamColor == Config.Teams[key].color then table.insert(list, sp) end
		end
	end
	return list
end
local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { workspace.Terrain }
local function groundAt(x, z)
	local r = workspace:Raycast(Vector3.new(x, 80, z), Vector3.new(0, -120, 0), terrainParams)
	return r and r.Position or Vector3.new(x, 22, z)
end

-- tactical goals: own line, enemy line, the middle
local function goalsFor(key)
	local side = key == "Blue" and -1 or 1
	local own, enemy, mid = {}, {}, {}
	for _, z in { -224, -160, -96, -32, 32, 96, 160, 220 } do
		table.insert(own, Vector3.new(148 * side, 15, z))
		table.insert(enemy, Vector3.new(-148 * side, 15, z))
	end
	for _, p in { Vector3.new(0, 23, 0), Vector3.new(0, 15, 240), Vector3.new(0, 15, -240), Vector3.new(-46, 15, 0), Vector3.new(46, 15, 0) } do table.insert(mid, p) end
	for _ = 1, 6 do table.insert(mid, groundAt(math.random(-100, 100), math.random(-230, 230)) + Vector3.new(0, 1, 0)) end
	return own, enemy, mid
end
local GOALS = {}
GOALS.Blue = { goalsFor("Blue") }
GOALS.Red = { goalsFor("Red") }
local function pickGoal(key)
	local g = GOALS[key]
	local r = math.random()
	local list = r < 0.45 and g[2] or (r < 0.75 and g[3] or g[1])
	return list[math.random(1, #list)]
end

------------------------------------------------------------------ bots
local bots = {}      -- [model] = rec
local respawnAt = { Blue = {}, Red = {} }
local usedNames = {}

local function botName()
	for _ = 1, 30 do
		local n = RANKS[math.random(1, #RANKS)] .. " " .. NAMES[math.random(1, #NAMES)]
		if not usedNames[n] then usedNames[n] = true return n end
	end
	return "Pvt. " .. math.random(100, 999)
end

local function spawnBot(key)
	local tpl = templates[key]
	if not tpl then return end
	local m = tpl:Clone()
	m.Name = botName()
	local hum = m:FindFirstChildOfClass("Humanoid")
	local root = m:FindFirstChild("HumanoidRootPart")
	local head = m:FindFirstChild("Head")
	head.Color = SKIN[math.random(1, #SKIN)]
	hum.DisplayName = m.Name
	hum.WalkSpeed = 14
	local pts = spawnPoints(key)
	local sp = pts[math.random(1, math.max(#pts, 1))]
	local pos = sp and sp.Position or Vector3.new(key == "Blue" and -300 or 300, 24, 0)
	local face = key == "Blue" and Vector3.xAxis or -Vector3.xAxis
	m:PivotTo(CFrame.lookAt(pos + Vector3.new(math.random(-2, 2), 3.5, math.random(-2, 2)), pos + face * 10 + Vector3.new(0, 3.5, 0)))
	m.Parent = folder
	pcall(function() root:SetNetworkOwner(nil) end)
	-- weapon
	local wid = math.random() < 0.6 and "Rifle" or "SMG"
	local toolTpl = weaponTools[wid]
	if toolTpl then
		local t = toolTpl:Clone()
		t.CanBeDropped = false
		t.Parent = m
		pcall(function() hum:EquipTool(t) end)
	end
	-- animations
	local animator = hum:FindFirstChildOfClass("Animator")
	local function load(id) local a = Instance.new("Animation") a.AnimationId = id return animator:LoadAnimation(a) end
	local walk, idle = load(ANIM.walk), load(ANIM.idle)
	walk.Looped, idle.Looped = true, true
	idle:Play()
	hum.Running:Connect(function(speed)
		if speed > 0.5 then
			if not walk.IsPlaying then walk:Play(0.2) idle:Stop(0.2) end
			walk:AdjustSpeed(speed / 14)
		elseif walk.IsPlaying then
			walk:Stop(0.2) idle:Play(0.2)
		end
	end)
	local w = Config.Weapons[wid]
	local rec = { model = m, hum = hum, root = root, head = head, key = key, wid = wid, w = w, mag = w.magSize, reloadUntil = 0, nextShot = 0,
		target = nil, reactUntil = 0, goal = nil, goalSince = 0, path = nil, idx = 0, lastPath = 0, stuck = 0, lastPos = root.Position, lastLos = 0 }
	bots[m] = rec
	hum.Died:Connect(function()
		bots[m] = nil
		usedNames[m.Name] = nil
		walk:Stop() idle:Stop()
		table.insert(respawnAt[key], os.clock() + RESPAWN_DELAY)
		local tag = hum:FindFirstChild("creator")
		if tag then
			local killer = tag.Value
			if killer and killer:IsA("Player") then
				API.creditKill(killer, killer.Name, API.teamKey(killer), m.Name, key, tag:GetAttribute("Weapon") or "?", tag:GetAttribute("Headshot") == true)
			elseif tag:GetAttribute("BotName") then
				API.creditKill(nil, tag:GetAttribute("BotName"), tag:GetAttribute("BotTeam"), m.Name, key, tag:GetAttribute("Weapon") or "?", tag:GetAttribute("Headshot") == true)
			end
		end
		Debris:AddItem(m, 5)
	end)
	return rec
end

local function removeBot(rec)
	bots[rec.model] = nil
	usedNames[rec.model.Name] = nil
	rec.model:Destroy()
end

------------------------------------------------------------------ perception & combat
local function enemiesOf(key)
	local list = {}
	for _, p in Players:GetPlayers() do
		local k = API.teamKey(p)
		local c = p.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		local hd = c and c:FindFirstChild("Head")
		if k and k ~= key and h and h.Health > 0 and hd and not c:FindFirstChildOfClass("ForceField") then
			table.insert(list, { model = c, hum = h, head = hd, root = c:FindFirstChild("HumanoidRootPart") })
		end
	end
	for m, rec in bots do
		if rec.key ~= key and rec.hum.Health > 0 then table.insert(list, { model = m, hum = rec.hum, head = rec.head, root = rec.root }) end
	end
	return list
end
local function hasLos(rec, target)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { rec.model }
	params.IgnoreWater = true
	local origin = rec.head.Position
	local to = target.head.Position - origin
	local r = workspace:Raycast(origin, to, params)
	return r == nil or r.Instance:IsDescendantOf(target.model)
end
local function victimFrom(inst)
	local m = inst:FindFirstAncestorOfClass("Model")
	while m do
		local h = m:FindFirstChildOfClass("Humanoid")
		if h then return m, h end
		m = m:FindFirstAncestorOfClass("Model")
	end
	return nil, nil
end
local function shoot(rec, target, now)
	local w = rec.w
	local origin = rec.head.Position + rec.root.CFrame.LookVector * 1.2 - Vector3.new(0, 0.3, 0)
	local aimHead = math.random() < 0.25
	local aim = aimHead and target.head.Position or (target.root and target.root.Position or target.head.Position)
	local dist = (aim - origin).Magnitude
	local maxReach = engageRange(rec.wid) * 1.1
	if dist > maxReach then return end
	local spreadDeg = (rec.wid == "Rifle" and 1.2 or 2.6) + dist * 0.025 + ((target.root and target.root.AssemblyLinearVelocity.Magnitude > 6) and 1.2 or 0)
	local sp = math.rad(spreadDeg)
	local dir = (CFrame.lookAt(origin, aim) * CFrame.Angles((math.random() - 0.5) * 2 * sp, (math.random() - 0.5) * 2 * sp, 0)).LookVector
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { rec.model }
	params.IgnoreWater = true
	local r = workspace:Raycast(origin, dir * maxReach, params)
	local hitPos = r and r.Position or origin + dir * maxReach
	if r then
		local vm, vh = victimFrom(r.Instance)
		if vm and vh and vh.Health > 0 then
			local vKey = vm:GetAttribute("BotTeam") or (Players:GetPlayerFromCharacter(vm) and API.teamKey(Players:GetPlayerFromCharacter(vm)))
			if vKey and vKey ~= rec.key and not vm:GetAttribute("Zombie") then
				local headshot = r.Instance.Name == "Head" or r.Instance.Name == "HelmetDome"
				local dmg = w.damage * DAMAGE_MULT * (headshot and w.headMultiplier or 1)
				if (hitPos - origin).Magnitude > w.falloffStart then dmg *= w.falloffMultiplier end
				API.damageFromBot(rec.model, vh, dmg, w.displayName, headshot)
			end
		end
	end
	API.shotFx(origin, hitPos, rec.wid)
	rec.mag -= 1
	if rec.mag <= 0 then
		rec.reloadUntil = now + w.reloadTime
		rec.mag = w.magSize
	end
	rec.nextShot = now + w.fireInterval * (w.auto and math.random(100, 140) / 100 or math.random(150, 260) / 100)
end

------------------------------------------------------------------ navigation
local function computePath(rec, goal)
	local path = PathfindingService:CreatePath({ AgentRadius = 1.6, AgentHeight = 5.5, AgentCanJump = true, AgentCanClimb = true, WaypointSpacing = 6, Costs = { Water = 6 } })
	local ok = pcall(function() path:ComputeAsync(rec.root.Position, goal) end)
	if ok and path.Status == Enum.PathStatus.Success then
		rec.path = path:GetWaypoints()
		rec.idx = 2
	else
		rec.path = nil
		rec.goal = nil -- unreachable: choose another
	end
end

------------------------------------------------------------------ AI loop
task.spawn(function()
	while true do
		task.wait(0.2)
		if mode() ~= "Trenches" or API.isRoundOver() then
			for _, rec in bots do rec.hum:MoveTo(rec.root.Position) end
			continue
		end
		local now = os.clock()
		local budget = 2
		local enemyCache = { Blue = enemiesOf("Blue"), Red = enemiesOf("Red") }
		for _, rec in bots do
			if rec.hum.Health > 0 and rec.root.Parent then
				-- 1. perception (line-of-sight checks are throttled)
				local range = engageRange(rec.wid)
				if now - rec.lastLos > 0.4 then
					rec.lastLos = now
					local best, bestD
					for _, e in enemyCache[rec.key] do
						local d = (e.head.Position - rec.head.Position).Magnitude
						if d < range and (not bestD or d < bestD) and hasLos(rec, e) then best, bestD = e, d end
					end
					if best and (not rec.target or rec.target.model ~= best.model) then
						rec.reactUntil = now + REACTION[1] + math.random() * (REACTION[2] - REACTION[1])
					end
					rec.target = best
				end
				local t = rec.target
				if t and (t.hum.Health <= 0 or not t.model.Parent or (t.head.Position - rec.head.Position).Magnitude > engageRange(rec.wid)) then rec.target, t = nil, nil end
				if t then
					-- 2. combat: stop, face the target, fire after reacting
					rec.hum:MoveTo(rec.root.Position)
					rec.hum.AutoRotate = false
					local look = Vector3.new(t.head.Position.X, rec.root.Position.Y, t.head.Position.Z)
					rec.root.CFrame = CFrame.lookAt(rec.root.Position, look)
					if now >= rec.reactUntil and now >= rec.reloadUntil and now >= rec.nextShot then shoot(rec, t, now) end
				else
					rec.hum.AutoRotate = true
					-- 3. move towards a tactical goal along a computed path
					if not rec.goal or now - rec.goalSince > 45 or (rec.goal - rec.root.Position).Magnitude < 8 then
						rec.goal = pickGoal(rec.key)
						rec.goalSince = now
						rec.path = nil
					end
					if (not rec.path or rec.idx > #rec.path) and now - rec.lastPath > 2 and budget > 0 then
						budget -= 1
						rec.lastPath = now
						task.spawn(computePath, rec, rec.goal)
					end
					local wp = rec.path and rec.path[rec.idx]
					if wp then
						rec.hum:MoveTo(wp.Position)
						if wp.Action == Enum.PathWaypointAction.Jump then rec.hum.Jump = true end
						if ((wp.Position - rec.root.Position) * Vector3.new(1, 0, 1)).Magnitude < 3 then rec.idx += 1 end
					end
					local moved = (rec.root.Position - rec.lastPos).Magnitude
					rec.lastPos = rec.root.Position
					rec.stuck = (wp and moved < 0.5) and rec.stuck + 0.2 or 0
					if rec.stuck > 1 then rec.hum.Jump = true end
					if rec.stuck > 3 then rec.stuck = 0 rec.path = nil rec.goal = pickGoal(rec.key) rec.goalSince = now end
				end
			end
		end
	end
end)

------------------------------------------------------------------ population manager
local wasOver = false
while true do
	task.wait(2)
	local over = API.isRoundOver()
	if mode() ~= "Trenches" then
		for _, rec in bots do removeBot(rec) end
		respawnAt.Blue, respawnAt.Red = {}, {}
	else
		-- after a round ends everyone starts fresh
		if wasOver and not over then
			for _, rec in bots do removeBot(rec) end
			respawnAt.Blue, respawnAt.Red = {}, {}
		end
		if not over then
			local now = os.clock()
			for _, key in { "Blue", "Red" } do
				local alive = 0
				for _, rec in bots do if rec.key == key then alive += 1 end end
				local pending = 0
				for i = #respawnAt[key], 1, -1 do
					if respawnAt[key][i] <= now then table.remove(respawnAt[key], i) else pending += 1 end
				end
				local want = math.max(0, TEAM_SIZE - teamPlayers(key))
				if alive + pending < want then
					spawnBot(key)
				elseif alive > want then
					for _, rec in bots do
						if rec.key == key then removeBot(rec) break end
					end
				end
				local count = 0
				for _, rec in bots do if rec.key == key then count += 1 end end
				workspace:SetAttribute("Bots" .. key, count)
			end
		end
	end
	wasOver = over
end
