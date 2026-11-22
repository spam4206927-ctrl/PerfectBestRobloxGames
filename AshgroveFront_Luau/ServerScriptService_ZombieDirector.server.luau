-- UNDEAD TRENCHES: co-op wave mode. Active only while workspace.GameMode == "Zombies".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local PathfindingService = game:GetService("PathfindingService")
local Debris = game:GetService("Debris")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local R = Combat:WaitForChild("Remotes")
local template = ServerStorage:WaitForChild("ZombieTemplate")
local folder = workspace:FindFirstChild("Zombies") or Instance.new("Folder")
folder.Name = "Zombies"
folder.Parent = workspace

local ANIM = { walk = "rbxassetid://616168032", run = "rbxassetid://616163682" }
local MAX_ALIVE = 28
local wave, remaining = 0, 0
local zombies = {}

local function active() return workspace:GetAttribute("GameMode") == "Zombies" end
local function broadcast(status, endsAt)
	R.ZombieState:FireAllClients(status, wave, remaining, endsAt or 0)
end
local function alivePlayers()
	local list = {}
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		local r = c and c:FindFirstChild("HumanoidRootPart")
		if h and r and h.Health > 0 then table.insert(list, { player = p, hum = h, root = r }) end
	end
	return list
end
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { workspace.Terrain }
local function groundAt(x, z)
	local r = workspace:Raycast(Vector3.new(x, 120, z), Vector3.new(0, -160, 0), params)
	return r and r.Position or Vector3.new(x, 22, z)
end
local function spawnPoint()
	if math.random() < 0.5 then return groundAt(math.random(250, 360), math.random(-230, 230)) end
	return groundAt(math.random(30, 110), math.random(-240, 240))
end
local function clearAll()
	for m in zombies do m:Destroy() end
	table.clear(zombies)
	folder:ClearAllChildren()
end
local function spawnZombie()
	local m = template:Clone()
	m:PivotTo(CFrame.new(spawnPoint() + Vector3.new(0, 4, 0)) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0))
	local hum = m:FindFirstChildOfClass("Humanoid")
	local root = m:FindFirstChild("HumanoidRootPart")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	hum.HealthDisplayDistance = 90
	hum.NameDisplayDistance = 0
	hum.MaxHealth = 70 + wave * 15
	hum.Health = hum.MaxHealth
	local runner = wave >= 3 and math.random() < math.min(0.15 + wave * 0.05, 0.5)
	hum.WalkSpeed = runner and math.min(14 + wave * 0.5, 20) or math.min(6.5 + wave * 0.6, 12)
	m.Parent = folder
	pcall(function() root:SetNetworkOwner(nil) end)
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local a = Instance.new("Animation")
	a.AnimationId = runner and ANIM.run or ANIM.walk
	local track = animator:LoadAnimation(a)
	track.Looped = true
	track:Play(0.3)
	local rec = { hum = hum, root = root, track = track, lastPos = root.Position, stuck = 0, lastPath = 0, lastAttack = 0, path = nil, idx = 0, damage = 12 + wave * 1.5 }
	zombies[m] = rec
	hum.Died:Connect(function()
		zombies[m] = nil
		track:Stop()
		remaining = math.max(0, remaining - 1)
		local tag = hum:FindFirstChild("creator")
		local killer = tag and tag.Value
		if killer and killer:IsA("Player") then
			local ls = killer:FindFirstChild("leaderstats")
			local k = ls and ls:FindFirstChild("Kills")
			if k then k.Value += 1 end
		end
		broadcast("wave")
		Debris:AddItem(m, 6)
	end)
end
local function computePath(rec, goal)
	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, AgentCanClimb = true, WaypointSpacing = 5, Costs = { Water = 4 } })
	local ok = pcall(function() path:ComputeAsync(rec.root.Position, goal) end)
	if ok and path.Status == Enum.PathStatus.Success then
		rec.path = path:GetWaypoints()
		rec.idx = 2
	end
end

task.spawn(function()
	while true do
		task.wait(0.25)
		if next(zombies) then
			local targets = alivePlayers()
			local now = os.clock()
			local budget = 3
			for _, rec in zombies do
				if rec.hum.Health > 0 and rec.root.Parent then
					local best, bestD
					for _, t in targets do
						local d = (t.root.Position - rec.root.Position).Magnitude
						if not bestD or d < bestD then best, bestD = t, d end
					end
					if not best then
						rec.hum:MoveTo(rec.root.Position)
					else
						local delta = best.root.Position - rec.root.Position
						if bestD < 4.5 and math.abs(delta.Y) < 5 then
							rec.hum:MoveTo(best.root.Position)
							if now - rec.lastAttack > 1.1 then
								rec.lastAttack = now
								best.hum:TakeDamage(rec.damage)
							end
						else
							local wp = rec.path and rec.path[rec.idx]
							if wp and now - rec.lastPath < 5 then
								rec.hum:MoveTo(wp.Position)
								if wp.Action == Enum.PathWaypointAction.Jump then rec.hum.Jump = true end
								if ((wp.Position - rec.root.Position) * Vector3.new(1, 0, 1)).Magnitude < 3 then rec.idx += 1 end
							else
								rec.path = nil
								rec.hum:MoveTo(best.root.Position)
							end
							local moved = (rec.root.Position - rec.lastPos).Magnitude
							rec.lastPos = rec.root.Position
							rec.stuck = moved < 0.8 and rec.stuck + 0.25 or 0
							if rec.stuck > 1 then rec.hum.Jump = true end
							if rec.stuck > 2 and now - rec.lastPath > 3 and budget > 0 then
								budget -= 1
								rec.lastPath = now
								rec.stuck = 0
								task.spawn(computePath, rec, best.root.Position)
							end
						end
					end
				end
			end
		end
	end
end)

while true do
	if not active() then
		if wave > 0 or next(zombies) then
			clearAll()
			wave, remaining = 0, 0
			broadcast("off")
		end
		task.wait(1)
	else
		local endsAt = workspace:GetServerTimeNow() + (wave == 0 and 12 or 18)
		broadcast("intermission", endsAt)
		while active() and workspace:GetServerTimeNow() < endsAt do task.wait(0.5) end
		if active() then
			wave += 1
			local total = 6 + wave * 4
			remaining = total
			local spawned = 0
			local wipeSince
			broadcast("wave")
			for _, p in Players:GetPlayers() do R.Notify:FireClient(p, "WAVE " .. wave .. " — " .. total .. " undead incoming", "warn") end
			while active() and (spawned < total or next(zombies)) do
				local alive = 0
				for _ in zombies do alive += 1 end
				if spawned < total and alive < MAX_ALIVE then
					spawnZombie()
					spawned += 1
					task.wait(0.7)
				else
					task.wait(0.5)
				end
				if #Players:GetPlayers() > 0 and #alivePlayers() == 0 then
					wipeSince = wipeSince or os.clock()
					if os.clock() - wipeSince > 6 then
						for _, p in Players:GetPlayers() do R.Notify:FireClient(p, "The line fell at wave " .. wave .. ". Regrouping…", "warn") end
						clearAll()
						wave, remaining = 0, 0
						broadcast("failed")
						break
					end
				else
					wipeSince = nil
				end
			end
			if active() and wave > 0 and remaining == 0 then
				for _, p in Players:GetPlayers() do R.Notify:FireClient(p, "Wave " .. wave .. " cleared!", "good") end
			end
		end
	end
end
