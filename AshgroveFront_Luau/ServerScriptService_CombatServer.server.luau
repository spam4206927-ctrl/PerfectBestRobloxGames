-- Ashgrove Front combat server: server-authoritative guns, items, loot chests, FPV drones,
-- explosions, teams and timed rounds. Clients only send intent; the server decides every hit.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Teams = game:GetService("Teams")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Config = require(Combat:WaitForChild("CombatConfig"))
local R = Combat:WaitForChild("Remotes")
local Templates = ServerStorage:WaitForChild("WeaponTemplates")
local API = require(script.Parent:WaitForChild("CombatAPI"))

Players.RespawnTime = Config.RespawnTime

local dronesFolder = workspace:FindFirstChild("Drones") or Instance.new("Folder")
dronesFolder.Name = "Drones"
dronesFolder.Parent = workspace

local ammo = {}          -- [player][weaponId] = { mag, reserve }
local reloading = {}     -- [player][weaponId] = true
local lastShot = {}      -- [player][weaponId] = os.clock()
local drones = {}        -- [player] = drone record
local droneReadyAt = {}  -- [player] = os.clock()
local lastResupply, lastRecharge, lastItem = {}, {}, {}
local score = { Blue = 0, Red = 0 }
local roundOver = false
local roundEndsAt = 0

------------------------------------------------------------------ helpers
local function teamKey(player: Player): string?
	local t = player.Team
	if not t then return nil end
	for key, info in Config.Teams do
		if t.TeamColor == info.color then return key end
	end
	return nil
end
local function teamInstance(key: string): Team?
	for _, t in Teams:GetChildren() do
		if t:IsA("Team") and t.TeamColor == Config.Teams[key].color then return t end
	end
	return nil
end
local function notify(player: Player, text: string, kind: string?)
	R.Notify:FireClient(player, text, kind or "info")
end
local function sendAmmo(player: Player, weaponId: string)
	local a = ammo[player] and ammo[player][weaponId]
	if a then
		R.AmmoState:FireClient(player, weaponId, a.mag, a.reserve, reloading[player] and reloading[player][weaponId] == true)
	end
end
local function resetAmmo(player: Player)
	ammo[player], reloading[player], lastShot[player] = {}, {}, {}
	for id, w in Config.Weapons do
		ammo[player][id] = { mag = w.magSize, reserve = w.reserve }
		sendAmmo(player, id)
	end
end
local function findTool(player: Player, id: string): Tool?
	for _, holder in { player:FindFirstChild("Backpack"), player.Character } do
		if holder then
			for _, t in holder:GetChildren() do
				if t:IsA("Tool") and t:GetAttribute("WeaponId") == id then return t end
			end
		end
	end
	return nil
end
local function equipped(player: Player, id: string): Tool?
	local char = player.Character
	local t = char and char:FindFirstChildOfClass("Tool")
	if t and t:GetAttribute("WeaponId") == id then return t end
	return nil
end
local function aliveHumanoid(player: Player): Humanoid?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return (hum and hum.Health > 0) and hum or nil
end
local function characterFromPart(inst: Instance)
	local model = inst:FindFirstAncestorOfClass("Model")
	while model do
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum then return model, hum end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil, nil
end
local function droneFromPart(inst: Instance)
	local model = inst:FindFirstAncestorOfClass("Model")
	while model do
		if model:GetAttribute("IsDrone") then return model end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end
local function canDamage(attacker: Player?, victim: Player, victimPos: Vector3): boolean
	if roundOver or attacker == victim then return false end
	if attacker and attacker.Team and attacker.Team == victim.Team then return false end
	return Config.inBattlefield(victimPos)
end
local function applyDamage(attacker: Player?, hum: Humanoid, amount: number, weaponName: string, headshot: boolean): boolean
	if hum.Health <= 0 then return false end
	local tag = hum:FindFirstChild("creator") or Instance.new("ObjectValue")
	tag.Name = "creator"
	tag.Value = attacker
	tag:SetAttribute("BotName", nil)
	tag:SetAttribute("BotTeam", nil)
	tag:SetAttribute("Weapon", weaponName)
	tag:SetAttribute("Headshot", headshot)
	tag.Parent = hum
	hum:TakeDamage(amount)
	return hum.Health <= 0
end
local function playSoundAt(pos: Vector3, soundId: string, volume: number, speed: number?)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Transparency = true, false, false, false, 1
	p.Size = Vector3.one
	p.Position = pos
	p.Parent = workspace
	local snd = Instance.new("Sound")
	snd.SoundId = soundId
	snd.Volume = volume
	snd.PlaybackSpeed = speed or 1
	snd.RollOffMaxDistance = 700
	snd.Parent = p
	snd:Play()
	Debris:AddItem(p, 5)
end

------------------------------------------------------------------ rounds & scoring
local function broadcastScore(status: string?, winner: string?)
	R.Score:FireAllClients(score.Blue, score.Red, Config.ScoreToWin, status or (roundOver and "intermission" or "playing"), winner, roundEndsAt)
end
local function stat(player: Player, name: string): IntValue?
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild(name) :: IntValue?
end
local function startRound()
	score.Blue, score.Red = 0, 0
	roundOver = false
	roundEndsAt = workspace:GetServerTimeNow() + Config.RoundMinutes * 60
	broadcastScore("playing")
end
local function endRound(winnerKey: string?)
	if roundOver then return end
	roundOver = true
	broadcastScore("ended", winnerKey and Config.Teams[winnerKey].name or "DRAW")
	task.delay(Config.IntermissionSeconds, function()
		for _, p in Players:GetPlayers() do
			local k, d = stat(p, "Kills"), stat(p, "Deaths")
			if k then k.Value = 0 end
			if d then d.Value = 0 end
		end
		startRound()
		for _, p in Players:GetPlayers() do task.spawn(function() p:LoadCharacter() end) end
	end)
end
local function onDied(victim: Player, hum: Humanoid)
	local d = stat(victim, "Deaths")
	if d then d.Value += 1 end
	local tag = hum:FindFirstChild("creator") :: ObjectValue?
	local killer = tag and tag.Value
	if killer and killer:IsA("Player") and killer ~= victim and killer.Parent then
		local k = stat(killer, "Kills")
		if k then k.Value += 1 end
		local key = teamKey(killer)
		if key and not roundOver and workspace:GetAttribute("GameMode") == "Trenches" then
			score[key] += 1
			if score[key] >= Config.ScoreToWin then endRound(key) else broadcastScore() end
		end
		R.KillFeed:FireAllClients(killer.Name, killer.TeamColor.Color, victim.Name, victim.TeamColor.Color, tag:GetAttribute("Weapon") or "?", tag:GetAttribute("Headshot") == true)
	elseif tag and tag:GetAttribute("BotName") then
		API.creditKill(nil, tag:GetAttribute("BotName"), tag:GetAttribute("BotTeam"), victim.Name, teamKey(victim), tag:GetAttribute("Weapon") or "?", tag:GetAttribute("Headshot") == true)
	else
		R.KillFeed:FireAllClients(nil, nil, victim.Name, victim.TeamColor.Color, workspace:GetAttribute("GameMode") == "Zombies" and "the undead" or "the trenches", false)
	end
end
RunService.Heartbeat:Connect(function()
	if workspace:GetAttribute("GameMode") == "Trenches" and not roundOver and roundEndsAt > 0 and workspace:GetServerTimeNow() >= roundEndsAt then
		if score.Blue > score.Red then endRound("Blue") elseif score.Red > score.Blue then endRound("Red") else endRound(nil) end
	end
end)

------------------------------------------------------------------ explosions (+ falling trees)
local damageDrone -- forward
local function fellTrees(pos: Vector3, radius: number)
	local map = workspace:FindFirstChild("AshgroveFront")
	local trees = map and map:FindFirstChild("DestructibleTrees")
	if not trees then return end
	for _, tree in trees:GetChildren() do
		local root = tree:IsA("Model") and tree.PrimaryPart
		if root and not tree:GetAttribute("Fallen") then
			local flat = Vector3.new(root.Position.X - pos.X, 0, root.Position.Z - pos.Z)
			if flat.Magnitude <= radius + 4 then
				tree:SetAttribute("Fallen", true)
				for _, p in tree:GetDescendants() do if p:IsA("BasePart") then p.Anchored = false end end
				pcall(function() root:SetNetworkOwner(nil) end)
				local cf, size = tree:GetBoundingBox()
				local dir = flat.Magnitude > 0.1 and flat.Unit or Vector3.xAxis
				root:ApplyImpulseAtPosition(dir * root.AssemblyMass * 22, cf.Position + Vector3.new(0, size.Y * 0.4, 0))
				task.delay(7, function()
					for _, p in tree:GetDescendants() do if p:IsA("BasePart") then p.Anchored = true end end
				end)
			end
		end
	end
end
local function blastFalloff(dist: number, radius: number): number
	local core = radius * 0.35
	if dist <= core then return 1 end
	local t = math.clamp((dist - core) / (radius - core), 0, 1)
	return 1 - 0.75 * t ^ 1.3
end
local function explode(pos: Vector3, radius: number, maxDamage: number, attacker: Player?, weaponName: string, ignore: { Instance }?)
	local totalDamage = 0
	local e = Instance.new("Explosion")
	e.Position = pos
	e.BlastRadius = radius
	e.BlastPressure = 0
	e.DestroyJointRadiusPercent = 0
	e.ExplosionType = Enum.ExplosionType.NoCraters
	e.Parent = workspace
	playSoundAt(pos, Config.Sounds.Explosion, 2.5)
	R.Effects:FireAllClients("explosion", nil, nil, pos, nil, nil, nil, radius)
	local anyKill, anyHit = false, false
	for _, victim in Players:GetPlayers() do
		local char = victim.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hum and root and hum.Health > 0 then
			local dist = (root.Position - pos).Magnitude
			if dist <= radius and canDamage(attacker, victim, root.Position) then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				local list = { char, dronesFolder }
				for _, i in ignore or {} do table.insert(list, i) end
				params.FilterDescendantsInstances = list
				params.IgnoreWater = true
				local blocked = workspace:Raycast(pos, root.Position - pos, params)
				local dmg = maxDamage * blastFalloff(dist, radius)
				if blocked then dmg *= 0.5 end -- trench walls and sandbags still give cover
				anyHit = true
				totalDamage += dmg
				if applyDamage(attacker, hum, dmg, weaponName, false) then anyKill = true end
			end
		end
	end
	local zfolder = workspace:FindFirstChild("Zombies")
	if zfolder then
		for _, z in zfolder:GetChildren() do
			local zh = z:FindFirstChildOfClass("Humanoid")
			local zr = z:FindFirstChild("HumanoidRootPart")
			if zh and zr and zh.Health > 0 and (zr.Position - pos).Magnitude <= radius then
				local d = (zr.Position - pos).Magnitude
				local f = blastFalloff(d, radius)
				anyHit = true
				totalDamage += maxDamage * f
				if applyDamage(attacker, zh, maxDamage * f, weaponName, false) then anyKill = true end
				-- knock the body away from the blast
				local away = (zr.Position - pos) * Vector3.new(1, 0, 1)
				away = away.Magnitude > 0.1 and away.Unit or Vector3.xAxis
				pcall(function() zr:ApplyImpulse((away * 55 + Vector3.new(0, 45, 0)) * zr.AssemblyMass * f) end)
			end
		end
	end
	local bfolder = workspace:FindFirstChild("Bots")
	if bfolder and not roundOver then
		local atKey = attacker and teamKey(attacker)
		for _, b in bfolder:GetChildren() do
			local bh = b:FindFirstChildOfClass("Humanoid")
			local br = b:FindFirstChild("HumanoidRootPart")
			if bh and br and bh.Health > 0 and b:GetAttribute("BotTeam") ~= atKey and (br.Position - pos).Magnitude <= radius then
				local d = (br.Position - pos).Magnitude
				local dmg = maxDamage * blastFalloff(d, radius)
				anyHit = true
				totalDamage += dmg
				if applyDamage(attacker, bh, dmg, weaponName, false) then anyKill = true end
			end
		end
	end
	fellTrees(pos, radius)
	for owner, rec in drones do
		if rec.body and (rec.body.Position - pos).Magnitude <= radius and owner ~= attacker then damageDrone(rec.model, 999, attacker) end
	end
	if attacker and anyHit then R.HitConfirm:FireClient(attacker, false, anyKill, math.floor(totalDamage + 0.5)) end
end

------------------------------------------------------------------ drones
local function weldTo(body: BasePart, p: BasePart)
	local w = Instance.new("WeldConstraint"); w.Part0 = body; w.Part1 = p; w.Parent = p
	p.Massless = true
end
local function buildDrone(player: Player, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = player.Name .. "_Drone"
	model:SetAttribute("IsDrone", true)
	model:SetAttribute("OwnerId", player.UserId)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local function part(name, size, rel, color, material, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf * rel
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if shape then p.Shape = shape end
		p.Parent = model
		return p
	end
	local dark = Color3.fromRGB(38, 40, 42)
	local body = part("Body", Vector3.new(1.4, 0.5, 1.8), CFrame.new(), dark, Enum.Material.Metal)
	body.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.3, 0.1)
	for _, a in { 45, -45 } do
		local arm = part("Arm", Vector3.new(0.25, 0.2, 3.6), CFrame.Angles(0, math.rad(a), 0), dark, Enum.Material.Metal)
		arm.CanCollide = false
		weldTo(body, arm)
	end
	for i, off in { Vector3.new(1.27, 0.25, 1.27), Vector3.new(-1.27, 0.25, 1.27), Vector3.new(1.27, 0.25, -1.27), Vector3.new(-1.27, 0.25, -1.27) } do
		local motor = part("Motor" .. i, Vector3.new(0.3, 0.35, 0.35), CFrame.new(off - Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(20, 20, 20), Enum.Material.Metal, Enum.PartType.Cylinder)
		local rotor = part("Rotor" .. i, Vector3.new(0.06, 1.5, 1.5), CFrame.new(off + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(160, 160, 160), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		rotor.Transparency = 0.55
		for _, p in { motor, rotor } do p.CanCollide = false weldTo(body, p) end
	end
	local lens = part("Camera", Vector3.new(0.35, 0.35, 0.3), CFrame.new(0, 0.05, -0.95), Color3.fromRGB(20, 20, 20), Enum.Material.Glass)
	lens.CanCollide = false
	weldTo(body, lens)
	local light = part("TeamLight", Vector3.new(0.3, 0.15, 0.3), CFrame.new(0, 0.32, 0.5), player.TeamColor.Color, Enum.Material.Neon)
	light.CanCollide = false
	weldTo(body, light)
	local pl = Instance.new("PointLight"); pl.Color = player.TeamColor.Color; pl.Range = 6; pl.Brightness = 1; pl.Parent = light
	local bomb = part("Payload", Vector3.new(0.8, 0.45, 0.45), CFrame.new(0, -0.45, 0) * CFrame.Angles(0, math.rad(90), math.rad(90)), Color3.fromRGB(60, 70, 50), Enum.Material.Metal, Enum.PartType.Cylinder)
	bomb.CanCollide = false
	weldTo(body, bomb)
	local att = Instance.new("Attachment"); att.Name = "Control"; att.Parent = body
	local lv = Instance.new("LinearVelocity")
	lv.Name = "Thrust"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 1e6
	lv.VectorVelocity = Vector3.zero
	lv.Parent = body
	local ao = Instance.new("AlignOrientation")
	ao.Name = "Attitude"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = 1e6
	ao.Responsiveness = 35
	ao.CFrame = cf.Rotation
	ao.Parent = body
	local buzz = Instance.new("Sound")
	buzz.Name = "Buzz"
	buzz.SoundId = Config.Sounds.DroneLoop
	buzz.Looped = true
	buzz.PlaybackSpeed = 2.6
	buzz.Volume = 0.6
	buzz.RollOffMaxDistance = 260
	buzz.Parent = body
	model.PrimaryPart = body
	return model, body
end
local function endDrone(player: Player, reason: string)
	local rec = drones[player]
	if not rec then return end
	drones[player] = nil
	droneReadyAt[player] = os.clock() + Config.Drone.cooldown
	if rec.model then rec.model:Destroy() end
	if player.Parent then
		pcall(function() player.ReplicationFocus = nil end)
		R.DroneState:FireClient(player, "ended", reason, Config.Drone.cooldown)
	end
end
damageDrone = function(model: Model, amount: number, attacker: Player?)
	for owner, rec in drones do
		if rec.model == model then
			rec.health -= amount
			if rec.health <= 0 then
				local pos = rec.body.Position
				local e = Instance.new("Explosion")
				e.Position = pos
				e.BlastRadius = 3
				e.BlastPressure = 0
				e.DestroyJointRadiusPercent = 0
				e.Parent = workspace
				playSoundAt(pos, Config.Sounds.Explosion, 1.2, 1.4)
				endDrone(owner, "shot down")
				if attacker then notify(attacker, "Enemy drone shot down", "good") end
			end
			return
		end
	end
end
local function detonate(player: Player, rec, crash: boolean, reported: Vector3?)
	if rec.detonated then return end
	rec.detonated = true
	local pos = rec.body.Position
	if typeof(reported) == "Vector3" and (reported - pos).Magnitude < 25 then pos = reported end
	endDrone(player, crash and "impact" or "detonated")
	explode(pos, Config.Drone.crashRadius, Config.Drone.crashDamage, player, Config.Drone.displayName)
end
local function launchDrone(player: Player)
	if drones[player] or roundOver then return end
	local char = player.Character
	local hum = aliveHumanoid(player)
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if not (hum and head and equipped(player, "Drone")) then return end
	local wait = (droneReadyAt[player] or 0) - os.clock()
	if wait > 0 then
		notify(player, string.format("Drone recharging: %ds (or recharge at a workshop)", math.ceil(wait)), "warn")
		return
	end
	-- launch above the head, but stay under any ceiling (tunnels, dugouts)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, dronesFolder }
	local up = workspace:Raycast(head.Position, Vector3.new(0, 8, 0), params)
	local lift = up and math.max(1.2, (up.Position.Y - head.Position.Y) - 1.4) or 5
	local look = head.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.1 and look.Unit or Vector3.zAxis
	local start = head.Position + Vector3.new(0, lift, 0) + look * 1.5
	local model, body = buildDrone(player, CFrame.lookAt(start, start + look))
	model.Parent = dronesFolder
	body:SetNetworkOwner(player)
	pcall(function() player.ReplicationFocus = body end)
	body.Buzz:Play()
	local rec = { model = model, body = body, grenades = Config.Drone.grenades, expires = os.clock() + Config.Drone.battery, health = Config.Drone.health, lastDrop = 0, born = os.clock() }
	drones[player] = rec
	body.Touched:Connect(function(hit)
		if rec.detonated or hit:IsDescendantOf(model) then return end
		if player.Character and hit:IsDescendantOf(player.Character) then return end
		if os.clock() - rec.born > 0.5 and body.AssemblyLinearVelocity.Magnitude >= Config.Drone.crashSpeed then detonate(player, rec, true) end
	end)
	R.DroneState:FireClient(player, "launched", model, rec.grenades, Config.Drone.battery)
end
local function dropGrenade(player: Player)
	local rec = drones[player]
	if not rec or rec.grenades <= 0 or os.clock() - rec.lastDrop < 0.6 then return end
	rec.lastDrop = os.clock()
	rec.grenades -= 1
	local g = Instance.new("Part")
	g.Name = "DroneGrenade"
	g.Shape = Enum.PartType.Ball
	g.Size = Vector3.new(0.7, 0.7, 0.7)
	g.Color = Color3.fromRGB(60, 70, 50)
	g.Material = Enum.Material.Metal
	g.CFrame = CFrame.new(rec.body.Position - Vector3.new(0, 1.1, 0))
	g.AssemblyLinearVelocity = rec.body.AssemblyLinearVelocity * 0.8
	g.Parent = workspace
	g:SetNetworkOwner(nil)
	local done = false
	local function boom()
		if done then return end
		done = true
		local pos = g.Position
		g:Destroy()
		explode(pos, Config.Drone.grenadeRadius, Config.Drone.grenadeDamage, player, Config.Drone.displayName .. " grenade", { rec.model })
	end
	g.Touched:Connect(function(hit)
		if rec.model and hit:IsDescendantOf(rec.model) then return end
		boom()
	end)
	task.delay(5, boom)
	R.DroneState:FireClient(player, "grenades", rec.grenades)
end
R.DroneAction.OnServerEvent:Connect(function(player, action, reported)
	if action == "launch" then launchDrone(player)
	elseif action == "drop" then dropGrenade(player)
	elseif action == "detonate" then
		local rec = drones[player]
		if rec then detonate(player, rec, false, reported) end
	elseif action == "exit" then endDrone(player, "recalled") end
end)
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for player, rec in drones do
		if not rec.body or not rec.body.Parent then endDrone(player, "lost")
		elseif not aliveHumanoid(player) or not player.Parent then endDrone(player, "pilot down")
		elseif now >= rec.expires then detonate(player, rec, false)
		elseif rec.body.Position.Y > Config.Drone.maxAltitude or rec.body.Position.Y < -30 then endDrone(player, "signal lost") end
	end
end)

------------------------------------------------------------------ guns
R.Fire.OnServerEvent:Connect(function(player, weaponId, origin, dirs)
	if typeof(weaponId) ~= "string" or typeof(origin) ~= "Vector3" then return end
	local w = Config.Weapons[weaponId]
	if not w then return end
	local char = player.Character
	local hum = aliveHumanoid(player)
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if not (hum and head and equipped(player, weaponId)) then return end
	if (origin - head.Position).Magnitude > 10 then return end
	local list = {}
	if typeof(dirs) == "Vector3" then
		list = { dirs }
	elseif typeof(dirs) == "table" then
		for i = 1, math.min(#dirs, w.pellets or 1) do
			if typeof(dirs[i]) == "Vector3" then table.insert(list, dirs[i]) end
		end
	end
	if #list == 0 then return end
	if not (ammo[player] and lastShot[player] and reloading[player]) then return end
	local now = os.clock()
	if now - (lastShot[player][weaponId] or 0) < w.fireInterval * 0.7 then return end
	local a = ammo[player] and ammo[player][weaponId]
	if not a or a.mag <= 0 or reloading[player][weaponId] then sendAmmo(player, weaponId) return end
	lastShot[player][weaponId] = now
	a.mag -= 1

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local own = drones[player]
	params.FilterDescendantsInstances = own and { char, own.model } or { char }
	params.IgnoreWater = true
	local hits = {}
	local anyHit, anyHead, anyKill = false, false, false
	local totalDmg = 0
	local shooterInZone = Config.inBattlefield(char:GetPivot().Position)
	for _, d in list do
		if d.Magnitude > 0.5 then
			d = d.Unit
			local result = workspace:Raycast(origin, d * w.range, params)
			local hitPos = result and result.Position or (origin + d * w.range)
			table.insert(hits, hitPos)
			if result then
				local drone = droneFromPart(result.Instance)
				if drone then
					damageDrone(drone, w.damage, player)
					anyHit = true
				else
					local model, vhum = characterFromPart(result.Instance)
					local victim = model and Players:GetPlayerFromCharacter(model)
					if model and model:GetAttribute("Zombie") and vhum and vhum.Health > 0 then
						local zhead = result.Instance.Name == "Head"
						local dmg = w.damage * (zhead and w.headMultiplier or 1)
						if (hitPos - origin).Magnitude > w.falloffStart then dmg *= w.falloffMultiplier end
						totalDmg += dmg
						if applyDamage(player, vhum, dmg, w.displayName, zhead) then anyKill = true end
						anyHit = true
						anyHead = anyHead or zhead
					elseif model and model:GetAttribute("BotTeam") and vhum and vhum.Health > 0 and shooterInZone and not roundOver
						and model:GetAttribute("BotTeam") ~= teamKey(player) then
						local bhead = result.Instance.Name == "Head"
						local dmg = w.damage * (bhead and w.headMultiplier or 1)
						if (hitPos - origin).Magnitude > w.falloffStart then dmg *= w.falloffMultiplier end
						totalDmg += dmg
						if applyDamage(player, vhum, dmg, w.displayName, bhead) then anyKill = true end
						anyHit = true
						anyHead = anyHead or bhead
					elseif victim and vhum and vhum.Health > 0 and shooterInZone and canDamage(player, victim, model:GetPivot().Position) then
						local vhead = model:FindFirstChild("Head") :: BasePart?
						local headshot = result.Instance.Name == "Head"
							or (vhead ~= nil and result.Instance.Parent:IsA("Accessory") and (hitPos - vhead.Position).Magnitude < 2.2)
						local dmg = w.damage * (headshot and w.headMultiplier or 1)
						if (hitPos - origin).Magnitude > w.falloffStart then dmg *= w.falloffMultiplier end
						totalDmg += dmg
						if applyDamage(player, vhum, dmg, w.displayName, headshot) then anyKill = true end
						anyHit = true
						anyHead = anyHead or headshot
					end
				end
			end
		end
	end
	R.Effects:FireAllClients("shot", player, weaponId, origin, hits)
	if anyHit then R.HitConfirm:FireClient(player, anyHead, anyKill, math.floor(totalDmg + 0.5)) end
end)
R.Reload.OnServerEvent:Connect(function(player, weaponId)
	local w = typeof(weaponId) == "string" and Config.Weapons[weaponId]
	local a = w and ammo[player] and ammo[player][weaponId]
	if not a then return end
	if reloading[player][weaponId] or a.mag >= w.magSize or a.reserve <= 0 then sendAmmo(player, weaponId) return end
	reloading[player][weaponId] = true
	sendAmmo(player, weaponId)
	task.delay(w.reloadTime, function()
		if not (ammo[player] and ammo[player][weaponId] == a) then return end
		local take = math.min(w.magSize - a.mag, a.reserve)
		a.mag += take
		a.reserve -= take
		reloading[player][weaponId] = nil
		sendAmmo(player, weaponId)
	end)
end)

------------------------------------------------------------------ items: grenades & medkits
R.Throw.OnServerEvent:Connect(function(player, dir)
	if typeof(dir) ~= "Vector3" or dir.Magnitude < 0.5 then return end
	local cfg = Config.Items.Grenade
	local tool = equipped(player, "Grenade")
	local char = player.Character
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if not (tool and head and aliveHumanoid(player)) then return end
	if os.clock() - (lastItem[player] or 0) < cfg.cooldown then return end
	local count = tool:GetAttribute("Count") or 0
	if count <= 0 then return end
	lastItem[player] = os.clock()
	dir = dir.Unit
	local g = Instance.new("Part")
	g.Name = "FragGrenade"
	g.Shape = Enum.PartType.Ball
	g.Size = Vector3.new(0.8, 0.8, 0.8)
	g.Color = Color3.fromRGB(62, 72, 50)
	g.Material = Enum.Material.Metal
	g.CustomPhysicalProperties = PhysicalProperties.new(2, 0.6, 0.3)
	g.CFrame = CFrame.new(head.Position + dir * 2.5)
	g.AssemblyLinearVelocity = dir * cfg.throwSpeed + Vector3.new(0, 14, 0)
	g.Parent = workspace
	g:SetNetworkOwner(nil)
	task.delay(cfg.fuse, function()
		if g.Parent then
			local pos = g.Position
			g:Destroy()
			explode(pos, cfg.radius, cfg.damage, player, cfg.displayName)
		end
	end)
	count -= 1
	tool:SetAttribute("Count", count)
	if count <= 0 then tool:Destroy() end
end)
R.UseItem.OnServerEvent:Connect(function(player, kind)
	if kind ~= "Medkit" then return end
	local cfg = Config.Items.Medkit
	local tool = equipped(player, "Medkit")
	local hum = aliveHumanoid(player)
	if not (tool and hum) then return end
	if os.clock() - (lastItem[player] or 0) < cfg.cooldown then return end
	if hum.Health >= hum.MaxHealth - 1 then notify(player, "Already at full health", "warn") return end
	lastItem[player] = os.clock()
	local count = (tool:GetAttribute("Count") or 1) - 1
	tool:SetAttribute("Count", count)
	if count <= 0 then tool:Destroy() end
	notify(player, "Patching up…", "good")
	task.spawn(function()
		local steps = 30
		for _ = 1, steps do
			task.wait(cfg.healTime / steps)
			if hum.Health <= 0 or not hum.Parent then return end
			hum.Health = math.min(hum.MaxHealth, hum.Health + cfg.heal / steps)
		end
	end)
end)

------------------------------------------------------------------ prompts: resupply, workshops, loot chests
local function pickLoot(): string
	local total = 0
	for _, e in Config.Loot.table do total += e[2] end
	local r = math.random() * total
	for _, e in Config.Loot.table do
		r -= e[2]
		if r <= 0 then return e[1] end
	end
	return Config.Loot.table[1][1]
end
local function giveLoot(player: Player, id: string): string
	local w, item = Config.Weapons[id], Config.Items[id]
	local existing = findTool(player, id)
	if existing then
		if w and ammo[player] and ammo[player][id] then
			ammo[player][id].mag = w.magSize
			ammo[player][id].reserve = w.reserve
			sendAmmo(player, id)
			return w.displayName .. " ammo"
		elseif item then
			existing:SetAttribute("Count", math.min((existing:GetAttribute("Count") or 0) + item.count, item.count * 2))
			return item.displayName .. " ×" .. item.count
		end
	end
	for _, t in Templates:GetChildren() do
		if t:GetAttribute("WeaponId") == id then
			local clone = t:Clone()
			clone.Parent = player:FindFirstChild("Backpack")
			if w and ammo[player] and ammo[player][id] then
				ammo[player][id].mag = w.magSize
				ammo[player][id].reserve = w.reserve
				sendAmmo(player, id)
			end
			return (w and w.displayName) or (item and item.displayName) or id
		end
	end
	return id
end
local function setChestOpen(chest: Model, open: boolean)
	local lid = chest:FindFirstChild("Lid") :: BasePart?
	local body = chest:FindFirstChild("Body")
	if lid then
		local target = lid:GetAttribute(open and "OpenCFrame" or "ClosedCFrame")
		if target then TweenService:Create(lid, TweenInfo.new(0.4, Enum.EasingStyle.Back), { CFrame = target }):Play() end
	end
	if body then
		local prompt = body:FindFirstChild("LootPrompt")
		local marker = body:FindFirstChild("Marker")
		if prompt then prompt.Enabled = not open end
		if marker then marker.Enabled = not open end
	end
	chest:SetAttribute("Ready", not open)
end
ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	if not aliveHumanoid(player) then return end
	if prompt.Name == "LootPrompt" then
		local chest = prompt:FindFirstAncestorOfClass("Model")
		if not chest or not chest:GetAttribute("Ready") then return end
		local got = giveLoot(player, pickLoot())
		setChestOpen(chest, true)
		notify(player, "Found: " .. got, "good")
		task.delay(Config.Loot.respawnSeconds, function()
			if chest.Parent then setChestOpen(chest, false) end
		end)
	elseif prompt.Name == "RechargePrompt" then
		local wait = Config.Map.droneRechargeCooldown - (os.clock() - (lastRecharge[player] or -999))
		if wait > 0 then notify(player, string.format("Workshop busy: %ds", math.ceil(wait)), "warn")
		elseif drones[player] then notify(player, "Land your drone first", "warn")
		else
			lastRecharge[player] = os.clock()
			droneReadyAt[player] = 0
			notify(player, "Fresh drone ready", "good")
		end
	elseif prompt.Name == "ResupplyPrompt" then
		if os.clock() - (lastResupply[player] or 0) < 8 then notify(player, "Resupply on cooldown", "warn") return end
		lastResupply[player] = os.clock()
		for id, w in Config.Weapons do
			local a = ammo[player] and ammo[player][id]
			if a then a.reserve = w.reserve sendAmmo(player, id) end
		end
		local g = findTool(player, "Grenade")
		if g then g:SetAttribute("Count", math.max(g:GetAttribute("Count") or 0, 1)) end
		notify(player, "Ammo resupplied", "good")
	end
end)

------------------------------------------------------------------ team switching
R.ChangeTeam.OnServerEvent:Connect(function(player, key)
	if typeof(key) ~= "string" or not Config.Teams[key] then return end
	if workspace:GetAttribute("GameMode") == "Zombies" then notify(player, "Co-op mode: everyone fights together", "warn") return end
	local target = teamInstance(key)
	if not target or player.Team == target then return end
	local current = player.Team
	local nTarget = #target:GetPlayers()
	local nCurrent = current and #current:GetPlayers() or 0
	if nTarget >= nCurrent and nCurrent > 0 and #Players:GetPlayers() > 1 then
		notify(player, "Teams would be unbalanced", "warn")
		return
	end
	endDrone(player, "recalled")
	player.Team = target
	player:LoadCharacter()
end)

------------------------------------------------------------------ players
local function onCharacter(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hum.NameOcclusion = Enum.NameOcclusion.EnemyOcclusion
	task.spawn(function()
		local animate = char:WaitForChild("Animate", 5)
		if not animate then return end
		local function set(folderName, animName, id)
			local f = animate:FindFirstChild(folderName)
			local a = f and f:FindFirstChild(animName)
			if a then a.AnimationId = id end
		end
		set("walk", "WalkAnim", "rbxassetid://2510202577")
		set("run", "RunAnim", "rbxassetid://2510198475")
		set("idle", "Animation1", "rbxassetid://2510196951")
		set("idle", "Animation2", "rbxassetid://2510196951")
	end)
	resetAmmo(player)
	local arm = char:WaitForChild("LeftUpperArm", 5) or char:FindFirstChild("Left Arm")
	if arm and arm:IsA("BasePart") then
		local band = Instance.new("Part")
		band.Name = "TeamArmband"
		band.Size = Vector3.new(arm.Size.X + 0.1, 0.35, arm.Size.Z + 0.1)
		band.CFrame = arm.CFrame
		band.Color = player.TeamColor.Color
		band.Material = Enum.Material.Fabric
		band.CanCollide, band.CanQuery, band.CanTouch, band.Massless = false, false, false, true
		local w = Instance.new("WeldConstraint"); w.Part0 = arm; w.Part1 = band; w.Parent = band
		band.Parent = char
	end
	hum.Died:Connect(function()
		endDrone(player, "pilot down")
		onDied(player, hum)
	end)
end
local function onPlayer(player: Player)
	local ls = Instance.new("Folder"); ls.Name = "leaderstats"
	local k = Instance.new("IntValue"); k.Name = "Kills"; k.Parent = ls
	local d = Instance.new("IntValue"); d.Name = "Deaths"; d.Parent = ls
	ls.Parent = player
	player.CharacterAdded:Connect(function(c) onCharacter(player, c) end)
	if player.Character then task.spawn(onCharacter, player, player.Character) end
	task.delay(2, function()
		if player.Parent then
			R.Score:FireClient(player, score.Blue, score.Red, Config.ScoreToWin, roundOver and "intermission" or "playing", nil, roundEndsAt)
		end
	end)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do onPlayer(p) end
Players.PlayerRemoving:Connect(function(p)
	endDrone(p, "left")
	ammo[p], reloading[p], lastShot[p], droneReadyAt[p], lastResupply[p], lastRecharge[p], lastItem[p] = nil, nil, nil, nil, nil, nil, nil
end)
------------------------------------------------------------------ game modes (vote on the deploy screen)
local mode = "Trenches"
workspace:SetAttribute("GameMode", mode)
local votes = {}
local function tally()
	local t = { Trenches = 0, Zombies = 0 }
	for p, m in votes do if p.Parent then t[m] += 1 end end
	return t
end
local function needed() return math.floor(#Players:GetPlayers() / 2) + 1 end
local function broadcastMode()
	local t = tally()
	R.ModeState:FireAllClients(mode, t.Trenches, t.Zombies, needed())
end
local function setMode(newMode)
	mode = newMode
	workspace:SetAttribute("GameMode", mode)
	table.clear(votes)
	for p in drones do endDrone(p, "recalled") end
	local blueT, redT = teamInstance("Blue"), teamInstance("Red")
	for _, p in Players:GetPlayers() do
		local k, d = stat(p, "Kills"), stat(p, "Deaths")
		if k then k.Value = 0 end
		if d then d.Value = 0 end
	end
	if mode == "Zombies" then
		if redT then redT.AutoAssignable = false end
		for _, p in Players:GetPlayers() do p.Team = blueT end
		score.Blue, score.Red = 0, 0
		roundOver, roundEndsAt = false, 0
		broadcastScore("zombies")
	else
		if redT then redT.AutoAssignable = true end
		for idx, p in ipairs(Players:GetPlayers()) do p.Team = (idx % 2 == 1) and blueT or redT end
		startRound()
	end
	for _, p in Players:GetPlayers() do
		notify(p, mode == "Zombies" and "Mode: UNDEAD TRENCHES (co-op)" or "Mode: TRENCH WARFARE (PvP)", "good")
		task.spawn(function() p:LoadCharacter() end)
	end
	broadcastMode()
end
R.VoteMode.OnServerEvent:Connect(function(player, m)
	if m ~= "Trenches" and m ~= "Zombies" then return end
	votes[player] = m
	if m ~= mode and tally()[m] >= needed() then setMode(m) else broadcastMode() end
end)
Players.PlayerAdded:Connect(function(p)
	task.delay(2.5, function()
		if not p.Parent then return end
		local t = tally()
		R.ModeState:FireClient(p, mode, t.Trenches, t.Zombies, needed())
		if mode == "Zombies" then p.Team = teamInstance("Blue") end
	end)
end)
for _, p in Players:GetPlayers() do
	task.delay(2.5, function()
		if p.Parent then local t = tally() R.ModeState:FireClient(p, mode, t.Trenches, t.Zombies, needed()) end
	end)
end
Players.PlayerRemoving:Connect(function(p) votes[p] = nil end)
local function getFlashlight(char: Model, create: boolean)
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	if not torso then return nil end
	local att = torso:FindFirstChild("FlashlightAttachment")
	if not att and create then
		att = Instance.new("Attachment")
		att.Name = "FlashlightAttachment"
		att.Position = Vector3.new(-0.45, 0.35, -torso.Size.Z / 2 - 0.15)
		att.Parent = torso
		local light = Instance.new("SpotLight")
		light.Name = "Beam"
		light.Face = Enum.NormalId.Front
		light.Angle = 56
		light.Range = 110
		light.Brightness = 7
		light.Color = Color3.fromRGB(255, 244, 222)
		light.Shadows = true
		light.Enabled = false
		light.Parent = att
		local glow = Instance.new("PointLight")
		glow.Name = "Spill"
		glow.Range = 9
		glow.Brightness = 1.2
		glow.Color = Color3.fromRGB(255, 244, 222)
		glow.Enabled = false
		glow.Parent = att
		local lens = Instance.new("Part")
		lens.Name = "FlashlightLens"
		lens.Shape = Enum.PartType.Cylinder
		lens.Size = Vector3.new(0.35, 0.4, 0.4)
		lens.Color = Color3.fromRGB(40, 40, 38)
		lens.Material = Enum.Material.Metal
		lens.CanCollide, lens.CanQuery, lens.CanTouch, lens.Massless = false, false, false, true
		lens.CFrame = torso.CFrame * CFrame.new(att.Position + Vector3.new(0, 0, 0.1)) * CFrame.Angles(0, math.rad(90), 0)
		local w = Instance.new("WeldConstraint"); w.Part0 = torso; w.Part1 = lens; w.Parent = lens
		lens.Parent = char
	end
	return att
end
local lastToggle = {}
R.Flashlight.OnServerEvent:Connect(function(player, on)
	if typeof(on) ~= "boolean" then return end
	if os.clock() - (lastToggle[player] or 0) < 0.2 then return end
	lastToggle[player] = os.clock()
	local char = player.Character
	if not (char and aliveHumanoid(player)) then return end
	local att = getFlashlight(char, true)
	if not att then return end
	att.Beam.Enabled = on
	att.Spill.Enabled = on
	local lens = char:FindFirstChild("FlashlightLens")
	if lens then
		lens.Material = on and Enum.Material.Neon or Enum.Material.Metal
		lens.Color = on and Color3.fromRGB(255, 246, 225) or Color3.fromRGB(40, 40, 38)
	end
	char:SetAttribute("Flashlight", on)
end)
local lastPitch = {}
R.AimPitch.OnServerEvent:Connect(function(player, pitch)
	if typeof(pitch) ~= "number" or pitch ~= pitch then return end
	if os.clock() - (lastPitch[player] or 0) < 0.08 then return end
	lastPitch[player] = os.clock()
	local char = player.Character
	if char then
		pitch = math.clamp(pitch, -1.3, 1.3)
		char:SetAttribute("AimPitch", pitch)
		local att = getFlashlight(char, false)
		if att then att.CFrame = CFrame.new(att.Position) * CFrame.Angles(pitch, 0, 0) end
	end
end)

------------------------------------------------------------------ hooks for the BotDirector
API.teamKey = teamKey
API.isRoundOver = function() return roundOver end
API.creditKill = function(killerPlayer, killerName, killerKey, victimName, victimKey, weapon, headshot)
	if killerPlayer then
		local k = stat(killerPlayer, "Kills")
		if k then k.Value += 1 end
	end
	if killerKey and not roundOver and workspace:GetAttribute("GameMode") == "Trenches" then
		score[killerKey] += 1
		if score[killerKey] >= Config.ScoreToWin then endRound(killerKey) else broadcastScore() end
	end
	local kc = killerKey and Config.Teams[killerKey] and Config.Teams[killerKey].color.Color or Color3.new(1, 1, 1)
	local vc = victimKey and Config.Teams[victimKey] and Config.Teams[victimKey].color.Color or Color3.new(1, 1, 1)
	R.KillFeed:FireAllClients(killerName, kc, victimName, vc, weapon, headshot)
end
API.damageFromBot = function(botModel, victimHum, amount, weaponName, headshot)
	if roundOver or victimHum.Health <= 0 then return false end
	local tag = victimHum:FindFirstChild("creator") or Instance.new("ObjectValue")
	tag.Name = "creator"
	tag.Value = nil
	tag:SetAttribute("Weapon", weaponName)
	tag:SetAttribute("Headshot", headshot)
	tag:SetAttribute("BotName", botModel.Name)
	tag:SetAttribute("BotTeam", botModel:GetAttribute("BotTeam"))
	tag.Parent = victimHum
	victimHum:TakeDamage(amount)
	return victimHum.Health <= 0
end
API.shotFx = function(origin, hitPos, weaponId)
	R.Effects:FireAllClients("shot", nil, weaponId, origin, { hitPos })
end
API.ready = true

startRound()
