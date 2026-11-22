--!strict
-- Shared tuning for Ashgrove Front. Server and client both read this.
local Config = {}

Config.Teams = {
	Blue = { name = "Blue Battalion", color = BrickColor.new("Bright blue") },
	Red = { name = "Red Battalion", color = BrickColor.new("Bright red") },
}
Config.ScoreToWin = 50
Config.RoundMinutes = 15
Config.IntermissionSeconds = 10
Config.RespawnTime = 5
Config.SpawnProtection = 3

Config.Battlefield = { min = Vector3.new(-430, -40, -330), max = Vector3.new(430, 260, 330) }
function Config.inBattlefield(p: Vector3): boolean
	local a, b = Config.Battlefield.min, Config.Battlefield.max
	return p.X >= a.X and p.X <= b.X and p.Y >= a.Y and p.Y <= b.Y and p.Z >= a.Z and p.Z <= b.Z
end

Config.Sounds = {
	Rifle = "rbxassetid://6975483207",
	SMG = "rbxassetid://92011177452282",
	Reload = "rbxassetid://117963160131194",
	Hit = "rbxassetid://138148057831879",
	Explosion = "rbxassetid://138533090376585",
	DroneLoop = "rbxassetid://643755628",
	Rain = "rbxassetid://9112854469",
	Splash = "rbxassetid://9117940837",
}

-- pellets > 1 = shotgun; scope = true shows a sniper scope when aiming
Config.Weapons = {
	Pistol = { displayName = "Service Pistol", auto = false, damage = 26, headMultiplier = 2, fireInterval = 0.2, magSize = 12, reserve = 60, reloadTime = 1.5,
		range = 240, hipSpread = 1.4, adsSpread = 0.5, adsFov = 60, falloffStart = 60, falloffMultiplier = 0.7, recoil = 1.4, sound = "Rifle", soundSpeed = 1.35 },
	Rifle = { displayName = "Bolt Rifle", auto = false, damage = 40, headMultiplier = 2.5, fireInterval = 0.45, magSize = 8, reserve = 56, reloadTime = 2.3,
		range = 700, hipSpread = 1.2, adsSpread = 0.08, adsFov = 35, falloffStart = 400, falloffMultiplier = 0.8, recoil = 2.4, sound = "Rifle", soundSpeed = 1 },
	SMG = { displayName = "Trench SMG", auto = true, damage = 16, headMultiplier = 1.6, fireInterval = 0.09, magSize = 32, reserve = 192, reloadTime = 2.0,
		range = 260, hipSpread = 2.4, adsSpread = 1.1, adsFov = 55, falloffStart = 80, falloffMultiplier = 0.55, recoil = 0.7, sound = "SMG", soundSpeed = 1.25 },
	AssaultRifle = { displayName = "Storm Carbine", auto = true, damage = 22, headMultiplier = 1.8, fireInterval = 0.11, magSize = 30, reserve = 150, reloadTime = 2.3,
		range = 480, hipSpread = 1.9, adsSpread = 0.35, adsFov = 48, falloffStart = 250, falloffMultiplier = 0.75, recoil = 0.9, sound = "SMG", soundSpeed = 1 },
	Shotgun = { displayName = "Trench Shotgun", auto = false, pellets = 8, damage = 14, headMultiplier = 1.4, fireInterval = 0.9, magSize = 6, reserve = 30, reloadTime = 3.0,
		range = 130, hipSpread = 4.5, adsSpread = 3.5, adsFov = 60, falloffStart = 35, falloffMultiplier = 0.6, recoil = 4.5, sound = "Rifle", soundSpeed = 0.75 },
	LMG = { displayName = "Field LMG", auto = true, damage = 25, headMultiplier = 1.6, fireInterval = 0.1, magSize = 75, reserve = 225, reloadTime = 5.2,
		range = 520, hipSpread = 3.4, adsSpread = 1.1, adsFov = 52, falloffStart = 300, falloffMultiplier = 0.8, recoil = 1.1, sound = "SMG", soundSpeed = 0.85 },
	Sniper = { displayName = "Marksman Rifle", auto = false, damage = 92, headMultiplier = 2.5, fireInterval = 1.5, magSize = 5, reserve = 25, reloadTime = 3.3,
		range = 1400, hipSpread = 7, adsSpread = 0, adsFov = 14, scope = true, falloffStart = 1400, falloffMultiplier = 1, recoil = 5.5, sound = "Rifle", soundSpeed = 0.8 },
}

Config.Items = {
	Grenade = { displayName = "Frag Grenade", count = 3, damage = 120, radius = 15, fuse = 3.2, throwSpeed = 85, cooldown = 1 },
	Medkit = { displayName = "Field Medkit", count = 2, heal = 60, healTime = 3, cooldown = 4 },
}

-- weighted loot from supply chests (tools live in ServerStorage.WeaponTemplates)
Config.Loot = {
	respawnSeconds = 90,
	table = { { "SMG", 18 }, { "AssaultRifle", 18 }, { "Shotgun", 16 }, { "LMG", 10 }, { "Sniper", 10 }, { "Grenade", 18 }, { "Medkit", 14 } },
}

Config.Drone = {
	displayName = "FPV Drone",
	health = 30,
	battery = 60,
	speed = 52,
	verticalSpeed = 28,
	grenades = 2,
	grenadeDamage = 110,
	grenadeRadius = 13,
	crashDamage = 150,
	crashRadius = 16,
	crashSpeed = 30,
	cooldown = 25,
	maxAltitude = 180,
}

Config.Map = {
	playMin = Vector2.new(-368, -256), -- x, z: beyond this is the minefield
	playMax = Vector2.new(368, 256),
	mineGrace = 2.5,
	floodSpeed = 10,
	weatherMinutes = { 4, 7 },
	droneRechargeCooldown = 30,
}

return Config
