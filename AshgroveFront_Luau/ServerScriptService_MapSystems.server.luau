-- Ashgrove Front map systems: changing weather, minefield borders and flooded trenches.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Config = require(Combat:WaitForChild("CombatConfig"))
local Notify = Combat.Remotes:WaitForChild("Notify")
local map = workspace:WaitForChild("AshgroveFront")
local MapCfg = Config.Map

------------------------------------------------------------------ weather
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere", Lighting)
local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds", workspace.Terrain)

local WEATHER = {
	Clear = { clock = 13.5, brightness = 2.2, ambient = Color3.fromRGB(120, 118, 112), outdoor = Color3.fromRGB(128, 126, 120),
		density = 0.28, haze = 1, color = Color3.fromRGB(200, 200, 194), cover = 0.45, cloudDensity = 0.5 },
	Overcast = { clock = 15, brightness = 1.3, ambient = Color3.fromRGB(100, 100, 100), outdoor = Color3.fromRGB(110, 110, 112),
		density = 0.4, haze = 2.2, color = Color3.fromRGB(176, 178, 180), cover = 0.85, cloudDensity = 0.75 },
	Fog = { clock = 9, brightness = 1.1, ambient = Color3.fromRGB(110, 110, 110), outdoor = Color3.fromRGB(120, 120, 122),
		density = 0.64, haze = 3, color = Color3.fromRGB(196, 198, 200), cover = 0.9, cloudDensity = 0.8 },
	Rain = { clock = 16, brightness = 0.9, ambient = Color3.fromRGB(86, 88, 92), outdoor = Color3.fromRGB(92, 96, 104),
		density = 0.48, haze = 2.6, color = Color3.fromRGB(150, 156, 164), cover = 0.95, cloudDensity = 0.95 },
	Night = { clock = 0.3, brightness = 0.35, ambient = Color3.fromRGB(40, 44, 58), outdoor = Color3.fromRGB(52, 58, 78),
		density = 0.36, haze = 1.4, color = Color3.fromRGB(90, 98, 120), cover = 0.5, cloudDensity = 0.6 },
}
local ORDER = { "Clear", "Overcast", "Fog", "Rain", "Night" }

local function setWeather(name: string, seconds: number)
	local w = WEATHER[name]
	workspace:SetAttribute("Weather", name)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine)
	-- ClockTime wraps at 24, so jump it instead of tweening across midnight
	if seconds <= 0 or math.abs(Lighting.ClockTime - w.clock) > 10 then
		Lighting.ClockTime = w.clock
	else
		TweenService:Create(Lighting, info, { ClockTime = w.clock }):Play()
	end
	TweenService:Create(Lighting, info, { Brightness = w.brightness, Ambient = w.ambient, OutdoorAmbient = w.outdoor }):Play()
	TweenService:Create(atmosphere, info, { Density = w.density, Haze = w.haze, Color = w.color }):Play()
	TweenService:Create(clouds, info, { Cover = w.cover, Density = w.cloudDensity }):Play()
	for _, p in Players:GetPlayers() do
		Notify:FireClient(p, "Weather: " .. name, "info")
	end
end

task.spawn(function()
	local rng = Random.new()
	setWeather(ORDER[rng:NextInteger(1, #ORDER)], 0)
	while true do
		task.wait(rng:NextNumber(MapCfg.weatherMinutes[1], MapCfg.weatherMinutes[2]) * 60)
		local current = workspace:GetAttribute("Weather")
		local nextW = current
		while nextW == current do
			nextW = ORDER[rng:NextInteger(1, #ORDER)]
		end
		setWeather(nextW, 25)
	end
end)

------------------------------------------------------------------ minefield + flooded trenches
local floods = HttpService:JSONDecode(map:GetAttribute("Floods"))
local inMines = {}
local lastSplash = {}

local function mineBlast(player: Player, root: BasePart, hum: Humanoid)
	local e = Instance.new("Explosion")
	e.Position = root.Position - Vector3.new(0, 2.5, 0)
	e.BlastRadius = 6
	e.BlastPressure = 0
	e.DestroyJointRadiusPercent = 0
	e.Parent = workspace
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Transparency = true, false, false, false, 1
	p.Position = e.Position
	p.Parent = workspace
	local s = Instance.new("Sound")
	s.SoundId = Config.Sounds.Explosion
	s.Volume = 2.5
	s.RollOffMaxDistance = 600
	s.Parent = p
	s:Play()
	Debris:AddItem(p, 4)
	local tag = hum:FindFirstChild("creator")
	if tag then tag:Destroy() end
	hum.Health = 0
end

local function inFlood(pos: Vector3): boolean
	if pos.Y > 15 then return false end
	for _, f in floods do
		if pos.X > f.x1 and pos.X < f.x2 and pos.Z > f.z1 and pos.Z < f.z2 then return true end
	end
	return false
end

while true do
	task.wait(0.2)
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if hum and root and hum.Health > 0 then
			local pos = root.Position
			-- minefield
			local outside = pos.X < MapCfg.playMin.X or pos.X > MapCfg.playMax.X or pos.Z < MapCfg.playMin.Y or pos.Z > MapCfg.playMax.Y
			if outside then
				if not inMines[player] then
					inMines[player] = now
					Notify:FireClient(player, "MINEFIELD! Turn back now", "warn")
				elseif now - inMines[player] >= MapCfg.mineGrace then
					inMines[player] = nil
					mineBlast(player, root, hum)
				end
			else
				inMines[player] = nil
			end
			-- flooded trenches: slow and loud
			local wet = inFlood(pos)
			if wet ~= (player:GetAttribute("InFlood") == true) then
				player:SetAttribute("InFlood", wet)
				if hum.WalkSpeed > 0 then
					hum.WalkSpeed = wet and MapCfg.floodSpeed or 16
				end
			end
			if wet and root.AssemblyLinearVelocity.Magnitude > 3 and now - (lastSplash[player] or 0) > 0.45 then
				lastSplash[player] = now
				local s = Instance.new("Sound")
				s.SoundId = Config.Sounds.Splash
				s.Volume = 1.2
				s.PlaybackSpeed = 0.9 + math.random() * 0.25
				s.RollOffMinDistance = 8
				s.RollOffMaxDistance = 140
				s.Parent = root
				s:Play()
				Debris:AddItem(s, 2)
			end
		end
	end
end
