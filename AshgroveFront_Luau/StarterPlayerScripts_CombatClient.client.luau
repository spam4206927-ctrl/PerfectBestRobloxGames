-- Ashgrove Front client: weapons, items, drone piloting, helmet cam, weather FX and the full HUD.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Teams = game:GetService("Teams")

local player = Players.LocalPlayer
local Combat = ReplicatedStorage:WaitForChild("Combat")
local Config = require(Combat:WaitForChild("CombatConfig"))
local R = Combat:WaitForChild("Remotes")
local camera = workspace.CurrentCamera
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local INK = Color3.fromRGB(18, 20, 22)
local SAND = Color3.fromRGB(232, 222, 196)
local AMBER = Color3.fromRGB(240, 190, 90)
local GREEN = Color3.fromRGB(120, 255, 170)

------------------------------------------------------------------------ UI helpers
local gui = Instance.new("ScreenGui")
gui.Name = "CombatHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")
local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in props do o[k] = v end
	o.Parent = parent
	return o
end
local function corner(o, r) make("UICorner", { CornerRadius = UDim.new(0, r) }, o) end
local function label(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or SAND
	return make("TextLabel", props, parent)
end
local function hex(c) return string.format("#%02X%02X%02X", c.R * 255, c.G * 255, c.B * 255) end

------------------------------------------------------------------------ HUD elements
local damageFlash = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(150, 0, 0), BackgroundTransparency = 1 }, gui)

-- sniper scope: a circle whose giant stroke blacks out the rest of the screen
local scope = make("Frame", { Name = "Scope", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.8, 0.8), BackgroundTransparency = 1, Visible = false }, gui)
make("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, scope)
corner(scope, 9999)
make("UIStroke", { Thickness = 3000, Color = Color3.new(0, 0, 0) }, scope)
make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, scope)
make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, scope)

local cross = make("Frame", { Name = "Crosshair", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(60, 60), BackgroundTransparency = 1, Visible = false }, gui)
local crossBars = {}
for i, d in { Vector2.new(0, -1), Vector2.new(0, 1), Vector2.new(-1, 0), Vector2.new(1, 0) } do
	local vertical = d.X == 0
	crossBars[i] = { dir = d, bar = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = vertical and UDim2.fromOffset(2, 9) or UDim2.fromOffset(9, 2), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, cross) }
	make("UIStroke", { Thickness = 1, Color = Color3.new(0, 0, 0), Transparency = 0.5 }, crossBars[i].bar)
end
local dot = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(3, 3), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, cross)
corner(dot, 2)

local hitmarker = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(34, 34), BackgroundTransparency = 1, Visible = false }, gui)
local hmBars = {}
for i, a in { 45, 135, 225, 315 } do
	local r = math.rad(a)
	hmBars[i] = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.cos(r) * 11, 0.5, math.sin(r) * 11), Size = UDim2.fromOffset(10, 2), Rotation = a, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, hitmarker)
end

local ammoPanel = make("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -24), Size = UDim2.fromOffset(230, 74), BackgroundColor3 = INK, BackgroundTransparency = 0.25, Visible = false }, gui)
corner(ammoPanel, 10)
local weaponName = label({ Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(180, 172, 150), Text = "" }, ammoPanel)
local ammoText = label({ Position = UDim2.fromOffset(14, 26), Size = UDim2.new(1, -28, 0, 38), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 34, RichText = true, Text = "" }, ammoPanel)

-- health bar
local healthPanel = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -46), Size = UDim2.fromOffset(240, 30), BackgroundColor3 = INK, BackgroundTransparency = 0.25 }, gui)
corner(healthPanel, 8)
local healthBack = make("Frame", { Position = UDim2.fromOffset(44, 10), Size = UDim2.new(1, -56, 0, 10), BackgroundColor3 = Color3.fromRGB(50, 46, 42), BorderSizePixel = 0 }, healthPanel)
corner(healthBack, 5)
local healthFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(120, 200, 110), BorderSizePixel = 0 }, healthBack)
corner(healthFill, 5)
local healthText = label({ Position = UDim2.fromOffset(8, 0), Size = UDim2.new(0, 34, 1, 0), Text = "100", TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left }, healthPanel)

-- score bar with round timer
local scoreBar = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(320, 40), BackgroundColor3 = INK, BackgroundTransparency = 0.25 }, gui)
corner(scoreBar, 8)
local blueBox = make("Frame", { Size = UDim2.new(0, 70, 1, 0), BackgroundColor3 = Config.Teams.Blue.color.Color }, scoreBar)
corner(blueBox, 8)
local blueScore = label({ Size = UDim2.fromScale(1, 1), TextScaled = true, Text = "0" }, blueBox)
make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, blueBox)
local redBox = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 70, 1, 0), BackgroundColor3 = Config.Teams.Red.color.Color }, scoreBar)
corner(redBox, 8)
local redScore = label({ Size = UDim2.fromScale(1, 1), TextScaled = true, Text = "0" }, redBox)
make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, redBox)
local timerText = label({ Position = UDim2.fromOffset(70, 2), Size = UDim2.new(1, -140, 0, 20), Text = "--:--", TextSize = 17 }, scoreBar)
local goalText = label({ Position = UDim2.fromOffset(70, 21), Size = UDim2.new(1, -140, 0, 16), Text = "FIRST TO " .. Config.ScoreToWin, TextSize = 11, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(190, 182, 160) }, scoreBar)
local roundEndsAt = 0

local banner = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(700, 70), TextScaled = true, Font = Enum.Font.SpecialElite, Text = "", Visible = false, TextStrokeTransparency = 0.4 }, gui)
local feed = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 64), Size = UDim2.fromOffset(360, 200), BackgroundTransparency = 1 }, gui)
make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Right }, feed)
local toast = label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -120), Size = UDim2.fromOffset(480, 34), BackgroundColor3 = INK, BackgroundTransparency = 0.3, TextSize = 16, Text = "", Visible = false }, gui)
corner(toast, 8)
local hint = label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -20), Size = UDim2.fromOffset(620, 18), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 13, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(205, 196, 172),
	Text = isTouch and "" or "LMB fire/use · RMB / Q aim · R reload · L flashlight · N map · E open chest · F resupply · V bodycam · M menu" }, gui)

-- helmet-cam vignette
local vignette = make("Frame", { Name = "HelmetVignette", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, gui)
for _, spec in { { UDim2.fromScale(1, 0.2), UDim2.fromScale(0, 0), 90 }, { UDim2.fromScale(1, 0.2), UDim2.fromScale(0, 0.8), -90 }, { UDim2.fromScale(0.16, 1), UDim2.fromScale(0, 0), 0 }, { UDim2.fromScale(0.16, 1), UDim2.fromScale(0.84, 0), 180 } } do
	local f = make("Frame", { Size = spec[1], Position = spec[2], BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, vignette)
	make("UIGradient", { Rotation = spec[3], Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }) }, f)
end

-- drone overlay
local droneUI = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, gui)
make("UIStroke", { Thickness = 3, Color = GREEN, Transparency = 0.4 }, make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -60, 1, -60), BackgroundTransparency = 1 }, droneUI))
local droneReticle = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 1 }, droneUI)
make("UIStroke", { Thickness = 2, Color = GREEN }, droneReticle)
corner(droneReticle, 20)
local recLabel = label({ Position = UDim2.fromOffset(46, 42), Size = UDim2.fromOffset(200, 22), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 80, 80), TextSize = 18, Text = "● FPV LIVE" }, droneUI)
local droneInfo = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -46, 0, 42), Size = UDim2.fromOffset(320, 22), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = GREEN, TextSize = 18, Text = "" }, droneUI)
label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -44), Size = UDim2.fromOffset(720, 22), TextColor3 = Color3.fromRGB(200, 255, 220), TextSize = 15, Font = Enum.Font.GothamMedium,
	Text = isTouch and "Stick: fly · Drag: look · Buttons: up/down/drop/boom/exit" or "WASD fly · Mouse look · Space/Ctrl up/down · Click drop grenade · X detonate · Q exit" }, droneUI)
local batteryBar = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 46), Size = UDim2.fromOffset(240, 8), BackgroundColor3 = Color3.fromRGB(30, 50, 40) }, droneUI)
corner(batteryBar, 4)
local batteryFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = GREEN, BorderSizePixel = 0 }, batteryBar)
corner(batteryFill, 4)

-- respawn overlay
local deathUI = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 6, 6), BackgroundTransparency = 0.45, Visible = false }, gui)
local deathTitle = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(700, 50), TextScaled = true, Font = Enum.Font.SpecialElite, Text = "YOU WERE KILLED", TextColor3 = Color3.fromRGB(230, 90, 80) }, deathUI)
local deathSub = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(600, 26), TextSize = 20, Font = Enum.Font.GothamMedium, Text = "" }, deathUI)

-- touch buttons
local function touchButton(text, pos, size)
	local b = make("TextButton", { AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = UDim2.fromOffset(size, size), BackgroundColor3 = INK, BackgroundTransparency = 0.35, Text = text, TextColor3 = SAND, Font = Enum.Font.GothamBold, TextSize = 14, Visible = false, AutoButtonColor = true }, gui)
	corner(b, size / 2)
	return b
end
local tFire = touchButton("FIRE", UDim2.new(1, -90, 1, -190), 80)
local tAim = touchButton("AIM", UDim2.new(1, -190, 1, -220), 56)
local tReload = touchButton("R", UDim2.new(1, -170, 1, -140), 48)
local tUp = touchButton("▲", UDim2.new(1, -90, 1, -260), 56)
local tDown = touchButton("▼", UDim2.new(1, -90, 1, -190), 56)
local tDrop = touchButton("DROP", UDim2.new(1, -170, 1, -150), 56)
local tBoom = touchButton("BOOM", UDim2.new(1, -170, 1, -230), 56)
local tExit = touchButton("EXIT", UDim2.new(0, 80, 0, 120), 48)
local tMenu = touchButton("MENU", UDim2.new(0, 60, 0, 70), 44)
tMenu.Visible = isTouch
local tLight = touchButton("LIGHT", UDim2.new(0, 60, 0, 124), 44)
tLight.Visible = isTouch

------------------------------------------------------------------------ deploy screen
local deploy = make("Frame", { Name = "Deploy", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(14, 14, 12), BackgroundTransparency = 0.12, Visible = false, ZIndex = 20 }, gui)
make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(40, 36, 28), Color3.fromRGB(10, 10, 10)) }, deploy)
label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.08, 0), Size = UDim2.fromOffset(800, 64), Text = "ASHGROVE FRONT", TextScaled = true, Font = Enum.Font.SpecialElite, ZIndex = 21 }, deploy)
label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.08, 70), Size = UDim2.fromOffset(800, 22), Text = "Hold the trenches. First team to " .. Config.ScoreToWin .. " kills — or the most kills after " .. Config.RoundMinutes .. " minutes — wins.", TextSize = 16, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(200, 190, 166), ZIndex = 21 }, deploy)
local cards = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.08, 116), Size = UDim2.fromOffset(620, 170), BackgroundTransparency = 1, ZIndex = 21 }, deploy)
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 20), HorizontalAlignment = Enum.HorizontalAlignment.Center }, cards)
local teamCards = {}
for _, key in { "Blue", "Red" } do
	local info = Config.Teams[key]
	local card = make("TextButton", { Size = UDim2.fromOffset(300, 170), BackgroundColor3 = info.color.Color, BackgroundTransparency = 0.35, Text = "", AutoButtonColor = true, ZIndex = 22 }, cards)
	corner(card, 12)
	local stroke = make("UIStroke", { Thickness = 0, Color = Color3.new(1, 1, 1) }, card)
	label({ Position = UDim2.fromOffset(16, 14), Size = UDim2.new(1, -32, 0, 34), Text = info.name:upper(), TextScaled = true, ZIndex = 23 }, card)
	label({ Position = UDim2.fromOffset(16, 54), Size = UDim2.new(1, -32, 0, 40), Text = key == "Blue" and "West: forest camp, west trench line" or "East: ruined village, east trench line", TextWrapped = true, TextSize = 15, Font = Enum.Font.GothamMedium, ZIndex = 23 }, card)
	local count = label({ Position = UDim2.fromOffset(16, 104), Size = UDim2.new(1, -32, 0, 22), Text = "", TextSize = 16, Font = Enum.Font.GothamMedium, ZIndex = 23 }, card)
	local status = label({ Position = UDim2.fromOffset(16, 132), Size = UDim2.new(1, -32, 0, 24), Text = "", TextSize = 16, ZIndex = 23 }, card)
	card.Activated:Connect(function() R.ChangeTeam:FireServer(key) end)
	teamCards[key] = { card = card, stroke = stroke, count = count, status = status }
end
label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -86), Size = UDim2.fromOffset(760, 96), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextSize = 15, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(200, 190, 166), ZIndex = 21,
	Text = isTouch and "Joystick to move · FIRE/AIM/R buttons · tap chests to open them" or
		"Move WASD · Fire LMB · Aim RMB (hold) or Q (toggle) · Flashlight L · Reload R · Weapons 1-9 · Open supply chests E · Resupply / drone recharge F · Bodycam V · Menu M\nDrone: equip it and click to launch, WASD + mouse to fly, click to drop a grenade, X to detonate, Q to land.\nTunnels (▼ TUNNELS): staircases behind each front line and beside the chapel saps. Supply chests (▼ SUPPLY) hold extra guns, grenades and medkits. Flooded trenches are slow and loud. Stay out of the minefield." }, deploy)
local deployBtn = make("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22), Size = UDim2.fromOffset(260, 56), BackgroundColor3 = Color3.fromRGB(196, 160, 90), Text = "DEPLOY", TextColor3 = INK, Font = Enum.Font.GothamBold, TextSize = 24, ZIndex = 22 }, deploy)
corner(deployBtn, 10)
-- game mode vote row
local currentMode, modeVotes, modeNeeded = "Trenches", { Trenches = 0, Zombies = 0 }, 1
local modeRow = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.08, 296), Size = UDim2.fromOffset(620, 50), BackgroundTransparency = 1, ZIndex = 21 }, deploy)
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 20), HorizontalAlignment = Enum.HorizontalAlignment.Center }, modeRow)
local modeButtons = {}
for _, m in { { "Trenches", "TRENCH WARFARE · PvP" }, { "Zombies", "UNDEAD TRENCHES · Co-op" } } do
	local key, title = m[1], m[2]
	local b = make("TextButton", { Size = UDim2.fromOffset(300, 50), BackgroundColor3 = Color3.fromRGB(46, 42, 36), Text = "", AutoButtonColor = true, ZIndex = 22 }, modeRow)
	corner(b, 10)
	local st = make("UIStroke", { Thickness = 0, Color = AMBER }, b)
	label({ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 4), Text = title, TextSize = 17, ZIndex = 23 }, b)
	local v = label({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 29), Text = "", TextSize = 13, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(200, 190, 166), ZIndex = 23 }, b)
	b.Activated:Connect(function() R.VoteMode:FireServer(key) end)
	modeButtons[key] = { button = b, stroke = st, votes = v }
end
local function refreshModes()
	for key, mb in modeButtons do
		local isCurrent = key == currentMode
		mb.stroke.Thickness = isCurrent and 3 or 0
		mb.votes.Text = isCurrent and "● PLAYING NOW" or string.format("Vote to switch  (%d / %d)", modeVotes[key] or 0, modeNeeded)
	end
end
refreshModes()

local function refreshCards()
	for key, c in teamCards do
		local n = 0
		for _, t in Teams:GetChildren() do
			if t:IsA("Team") and t.TeamColor == Config.Teams[key].color then n = #t:GetPlayers() end
		end
		local mine = player.Team and player.Team.TeamColor == Config.Teams[key].color
		local bots = workspace:GetAttribute("Bots" .. key) or 0
		c.count.Text = n .. (n == 1 and " soldier" or " soldiers") .. (bots > 0 and ("  +  " .. bots .. " AI") or "")
		c.status.Text = currentMode == "Zombies" and (key == "Blue" and "✔ CO-OP: everyone defends the west" or "—") or (mine and "✔ YOUR TEAM" or "Click to switch")
		c.stroke.Thickness = mine and 3 or 0
	end
end
local function showDeploy(on)
	deploy.Visible = on
	if on then
		refreshCards()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end
deployBtn.Activated:Connect(function() showDeploy(false) end)
tMenu.Activated:Connect(function() showDeploy(not deploy.Visible) end)
player:GetPropertyChangedSignal("Team"):Connect(function() if deploy.Visible then refreshCards() end end)
for _, t in Teams:GetChildren() do
	if t:IsA("Team") then
		t.PlayerAdded:Connect(function() if deploy.Visible then refreshCards() end end)
		t.PlayerRemoved:Connect(function() if deploy.Visible then refreshCards() end end)
	end
end

------------------------------------------------------------------------ state
local character, humanoid, root
local equippedTool, equippedId
local ammoState = {}
local lastFire = 0
local triggerHeld = false
local aiming = false
local bloom, recoilPitch, shakeAmount = 0, 0, 0
local piloting = false
local drone, droneBody
local droneYaw, dronePitch, droneVertical = 0, 0, 0
local droneEnds, droneGrenades, lastDroneSpeed = 0, 0, 0
local droneCmd = Vector3.zero
local toastToken = 0
local flashlightOn = false
local zombieInfo = { status = "off", wave = 0, remaining = 0, endsAt = 0 }
local helmetCam, bobT, baseFov = false, 0, 70
local lastKiller = nil

local function showToast(text, color, dur)
	toastToken += 1
	local t = toastToken
	toast.Text = text
	toast.TextColor3 = color or SAND
	toast.Visible = true
	task.delay(dur or 2.5, function() if t == toastToken then toast.Visible = false end end)
end
local function isGun(id) return id ~= nil and Config.Weapons[id] ~= nil end

local function updateAmmoUI()
	if not equippedId then ammoPanel.Visible = false return end
	ammoPanel.Visible = true
	if equippedId == "Drone" then
		weaponName.Text = Config.Drone.displayName:upper()
		ammoText.Text = piloting and "<font color='#78FFAA'>IN FLIGHT</font>" or "<font size='24'>Click to launch</font>"
		return
	end
	local item = Config.Items[equippedId]
	if item then
		weaponName.Text = item.displayName:upper()
		ammoText.Text = "×" .. tostring(equippedTool and equippedTool:GetAttribute("Count") or 0) .. (equippedId == "Grenade" and " <font size='18' color='#9A927C'>click to throw</font>" or " <font size='18' color='#9A927C'>click to heal</font>")
		return
	end
	local w = Config.Weapons[equippedId]
	local a = ammoState[equippedId] or { mag = w.magSize, reserve = w.reserve }
	weaponName.Text = w.displayName:upper()
	if a.reloading then
		ammoText.Text = "<font color='#F0BE5A'>RELOADING…</font>"
	else
		local magColor = a.mag <= math.ceil(w.magSize * 0.25) and "#FF7A6A" or "#E8DEC4"
		ammoText.Text = string.format("<font color='%s'>%d</font> <font size='22' color='#9A927C'>/ %d</font>", magColor, a.mag, a.reserve)
	end
end
local function playSound(id, parent, volume, speed)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.8
	s.PlaybackSpeed = speed or 1
	s.RollOffMaxDistance = 600
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 4)
end
local fxFolder = make("Folder", { Name = "LocalFX" }, workspace)
local function soundAt(pos, id, volume, speed)
	local p = make("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.one, Position = pos }, fxFolder)
	playSound(id, p, volume, speed)
	Debris:AddItem(p, 4)
end

------------------------------------------------------------------------ effects
local function tracer(from, to)
	local len = (to - from).Magnitude
	if len < 1 then return end
	local p = make("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 214, 140), Size = Vector3.new(0.07, 0.07, len), CFrame = CFrame.lookAt((from + to) / 2, to), Transparency = 0.15 }, fxFolder)
	TweenService:Create(p, TweenInfo.new(0.09), { Transparency = 1 }):Play()
	Debris:AddItem(p, 0.12)
end
local function muzzleFlash(pos)
	local p = make("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 190, 90), Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6), Position = pos }, fxFolder)
	make("PointLight", { Color = Color3.fromRGB(255, 180, 90), Brightness = 4, Range = 8 }, p)
	Debris:AddItem(p, 0.05)
end
local function impact(pos, normal, material)
	if not pos then return end
	local col = Color3.fromRGB(120, 100, 80)
	if material == Enum.Material.Metal or material == Enum.Material.CorrodedMetal then col = Color3.fromRGB(255, 220, 140) end
	local p = make("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Color = col, Shape = Enum.PartType.Ball, Size = Vector3.new(0.3, 0.3, 0.3), Position = pos + (normal or Vector3.zero) * 0.1 }, fxFolder)
	TweenService:Create(p, TweenInfo.new(0.35), { Size = Vector3.new(1.4, 1.4, 1.4), Transparency = 1 }):Play()
	Debris:AddItem(p, 0.4)
end
local function flashHitmarker(color, size)
	hitmarker.Visible = true
	hitmarker.Size = UDim2.fromOffset(size, size)
	for _, b in hmBars do b.BackgroundColor3 = color end
	local token = os.clock()
	hitmarker:SetAttribute("t", token)
	task.delay(0.18, function() if hitmarker:GetAttribute("t") == token then hitmarker.Visible = false end end)
end

------------------------------------------------------------------------ shooting & items
local function rayParams()
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = { character, fxFolder, drone }
	p.IgnoreWater = true
	return p
end
local function aimRay(range)
	local vp = camera.ViewportSize
	local ray = camera:ViewportPointToRay(vp.X / 2, vp.Y / 2)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * range, rayParams())
	return hit and hit.Position or (ray.Origin + ray.Direction * range), ray
end
local function requestReload()
	if not isGun(equippedId) then return end
	local w = Config.Weapons[equippedId]
	local a = ammoState[equippedId]
	if a and (a.reloading or a.mag >= w.magSize or a.reserve <= 0) then
		if a.reserve <= 0 and a.mag <= 0 then showToast("Out of ammo — resupply at an AMMO crate (hold F)", AMBER) end
		return
	end
	if a then a.reloading = true end
	updateAmmoUI()
	R.Reload:FireServer(equippedId)
	local handle = equippedTool and equippedTool:FindFirstChild("Handle")
	if handle then playSound(Config.Sounds.Reload, handle, 0.7) end
end
local function fireOnce()
	if not isGun(equippedId) or piloting or not humanoid or humanoid.Health <= 0 or deploy.Visible then return end
	local w = Config.Weapons[equippedId]
	if os.clock() - lastFire < w.fireInterval then return end
	local a = ammoState[equippedId]
	if not a or a.reloading then return end
	if a.mag <= 0 then requestReload() return end
	lastFire = os.clock()
	a.mag -= 1
	updateAmmoUI()
	local handle = equippedTool:FindFirstChild("Handle")
	local muzzleAtt = handle and handle:FindFirstChild("Muzzle")
	local muzzle = muzzleAtt and muzzleAtt.WorldPosition or (root.Position + Vector3.new(0, 1.5, 0))
	local aimPoint = aimRay(w.range)
	local baseDir = (aimPoint - muzzle).Unit
	local spread = math.rad((aiming and w.adsSpread or w.hipSpread) + bloom)
	local dirs = {}
	for _ = 1, (w.pellets or 1) do
		local rx, ry = (math.random() - 0.5) * 2 * spread, (math.random() - 0.5) * 2 * spread
		table.insert(dirs, (CFrame.lookAt(Vector3.zero, baseDir) * CFrame.Angles(rx, ry, 0)).LookVector)
	end
	R.Fire:FireServer(equippedId, muzzle, w.pellets and dirs or dirs[1])
	local params = rayParams()
	for _, d in dirs do
		local hit = workspace:Raycast(muzzle, d * w.range, params)
		tracer(muzzle, hit and hit.Position or (muzzle + d * w.range))
		if hit then impact(hit.Position, hit.Normal, hit.Material) end
	end
	muzzleFlash(muzzle)
	if handle then playSound(Config.Sounds[w.sound], handle, 0.9, w.soundSpeed) end
	recoilPitch += math.rad(w.recoil) * (aiming and 0.6 or 1)
	bloom = math.min(bloom + (w.auto and 0.35 or 1.2), 5)
	if a.mag <= 0 then task.delay(0.15, requestReload) end
end
local function useItem()
	if deploy.Visible or not humanoid or humanoid.Health <= 0 then return end
	if equippedId == "Grenade" then
		local aimPoint, ray = aimRay(200)
		local head = character and character:FindFirstChild("Head")
		local dir = head and (aimPoint - head.Position).Unit or ray.Direction
		R.Throw:FireServer(dir)
	elseif equippedId == "Medkit" then
		R.UseItem:FireServer("Medkit")
	end
end

------------------------------------------------------------------------ equip handling
local function setToolHidden(hidden)
	if not equippedTool then return end
	for _, p in equippedTool:GetDescendants() do
		if p:IsA("BasePart") then p.LocalTransparencyModifier = hidden and 1 or 0 end
	end
end
local function setAiming(on)
	if on and (not isGun(equippedId) or piloting) then on = false end
	aiming = on
	local w = equippedId and Config.Weapons[equippedId]
	TweenService:Create(camera, TweenInfo.new(0.15), { FieldOfView = (on and w) and w.adsFov or baseFov }):Play()
	local scoped = on and w and w.scope == true
	scope.Visible = scoped or false
	cross.Visible = isGun(equippedId) and not piloting and not scoped
	setToolHidden(scoped)
	tAim.BackgroundColor3 = on and Color3.fromRGB(90, 70, 30) or INK
end
local function fireButtonLabel()
	if equippedId == "Drone" then return "LAUNCH" elseif equippedId == "Grenade" then return "THROW" elseif equippedId == "Medkit" then return "USE" end
	return "FIRE"
end
local function onEquipped(tool)
	equippedTool = tool
	equippedId = tool:GetAttribute("WeaponId")
	bloom = 0
	updateAmmoUI()
	cross.Visible = isGun(equippedId) and not piloting
	tFire.Text = fireButtonLabel()
	tFire.Visible = isTouch and not piloting
	tAim.Visible = isTouch and isGun(equippedId)
	tReload.Visible = isTouch and isGun(equippedId)
	tool:GetAttributeChangedSignal("Count"):Connect(function() if tool == equippedTool then updateAmmoUI() end end)
end
local function onUnequipped()
	setAiming(false)
	equippedTool, equippedId = nil, nil
	triggerHeld = false
	cross.Visible = false
	ammoPanel.Visible = false
	tFire.Visible, tAim.Visible, tReload.Visible = false, false, false
	if humanoid then
		humanoid.AutoRotate = true
		humanoid.CameraOffset = Vector3.zero
	end
	UserInputService.MouseIconEnabled = true
end

------------------------------------------------------------------------ drone piloting
local function endPiloting()
	piloting = false
	drone, droneBody = nil, nil
	droneUI.Visible = false
	for _, b in { tUp, tDown, tDrop, tBoom, tExit } do b.Visible = false end
	camera.CameraType = Enum.CameraType.Custom
	if humanoid then
		camera.CameraSubject = humanoid
		humanoid.WalkSpeed = player:GetAttribute("InFlood") and Config.Map.floodSpeed or 16
		humanoid.JumpHeight = 7.2
	end
	camera.FieldOfView = baseFov
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	if equippedTool then onEquipped(equippedTool) end
end
R.DroneState.OnClientEvent:Connect(function(state, a, b, c)
	if state == "launched" then
		local model = a or workspace:WaitForChild("Drones"):WaitForChild(player.Name .. "_Drone", 3)
		local body = model and model:WaitForChild("Body", 3)
		if not body then return end
		drone, droneBody = model, body
		piloting = true
		droneGrenades = b
		droneEnds = os.clock() + c
		local _, yaw = droneBody.CFrame:ToOrientation()
		droneYaw, dronePitch = yaw, math.rad(-12)
		lastDroneSpeed = 0
		droneCmd = Vector3.zero
		setAiming(false)
		cross.Visible = false
		droneUI.Visible = true
		for _, btn in { tUp, tDown, tDrop, tBoom, tExit } do btn.Visible = isTouch end
		tFire.Visible, tAim.Visible, tReload.Visible = false, false, false
		if humanoid then humanoid.WalkSpeed = 0 humanoid.JumpHeight = 0 end
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 90
		updateAmmoUI()
	elseif state == "grenades" then
		droneGrenades = a
	elseif state == "ended" then
		if piloting then endPiloting() end
		showToast(string.format("Drone %s — new drone in %ds (or recharge at a workshop)", a or "ended", b or Config.Drone.cooldown), AMBER, 3)
		updateAmmoUI()
	end
end)
local function keyAxis(pos, neg)
	return (UserInputService:IsKeyDown(pos) and 1 or 0) - (UserInputService:IsKeyDown(neg) and 1 or 0)
end
local function droneInput(look)
	local f = keyAxis(Enum.KeyCode.W, Enum.KeyCode.S) + keyAxis(Enum.KeyCode.Up, Enum.KeyCode.Down)
	local r = keyAxis(Enum.KeyCode.D, Enum.KeyCode.A) + keyAxis(Enum.KeyCode.Right, Enum.KeyCode.Left)
	if f == 0 and r == 0 and humanoid then
		local md = humanoid.MoveDirection
		if md.Magnitude > 0.05 then
			local flat = look.LookVector * Vector3.new(1, 0, 1)
			flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.zAxis
			local right = Vector3.new(-flat.Z, 0, flat.X)
			f, r = md:Dot(flat), md:Dot(right)
		end
	end
	return math.clamp(f, -1, 1), math.clamp(r, -1, 1)
end

------------------------------------------------------------------------ helmet cam & rain
local helmetFx = {}
local CHEST = Vector3.new(-0.25, -1.0, -0.6) -- chest-mounted camera
local camRoll, camSwayYaw, lastCamYaw = 0, 0, nil
local recOverlay = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -26, 0, 58), Size = UDim2.fromOffset(330, 18), Text = "", TextSize = 14, Font = Enum.Font.Code,
	TextColor3 = Color3.fromRGB(235, 235, 225), TextXAlignment = Enum.TextXAlignment.Right, TextStrokeTransparency = 0.5 }, vignette)
local function bobOffset(dt)
	if not root then return CHEST end
	local v = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
	local k = math.clamp(v.Magnitude / 16, 0, 1.3)
	if k > 0.05 then bobT += dt * (5.5 + v.Magnitude * 0.42) end
	return CHEST + Vector3.new(math.sin(bobT) * 0.09 * k, math.abs(math.cos(bobT)) * 0.14 * k, 0)
end
local function bodycamMotion(dt)
	if not root then return end
	local cf = camera.CFrame
	local localVel = cf:VectorToObjectSpace(root.AssemblyLinearVelocity)
	local _, yaw = cf:ToOrientation()
	if lastCamYaw then
		local dYaw = (yaw - lastCamYaw + math.pi) % (2 * math.pi) - math.pi
		camSwayYaw = camSwayYaw * math.exp(-dt * 8) - dYaw * 0.35
	end
	lastCamYaw = yaw
	local targetRoll = -math.clamp(localVel.X / 16, -1, 1) * math.rad(3.5) + camSwayYaw * 0.6
	camRoll += (targetRoll - camRoll) * math.min(1, dt * 7)
	local speed = Vector2.new(localVel.X, localVel.Z).Magnitude
	local stepJolt = math.sin(bobT * 2) * math.rad(0.35) * math.clamp(speed / 16, 0, 1.3)
	camera.CFrame = cf * CFrame.Angles(stepJolt, camSwayYaw * 0.5, camRoll)
	recOverlay.Text = "● REC   " .. os.date("%Y-%m-%d  %H:%M:%S") .. "   UNIT-07"
end
local ARM_PARTS = {} -- hands stay hidden in bodycam; only the weapon is shown
local function showOwnArms()
	if not character or not isGun(equippedId) then return end
	for _, n in ARM_PARTS do
		local p = character:FindFirstChild(n)
		if p and p:IsA("BasePart") then p.LocalTransparencyModifier = 0 end
	end
	if equippedTool and not scope.Visible then
		for _, p in equippedTool:GetDescendants() do
			if p:IsA("BasePart") then p.LocalTransparencyModifier = 0 end
		end
	end
end
local function setHelmetCam(on)
	helmetCam = on
	baseFov = on and 96 or 70
	if on then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		helmetFx.cc = helmetFx.cc or Instance.new("ColorCorrectionEffect")
		helmetFx.cc.Saturation, helmetFx.cc.Contrast = -0.25, 0.2
		helmetFx.cc.TintColor = Color3.fromRGB(236, 244, 255)
		helmetFx.cc.Parent = camera
		helmetFx.blur = helmetFx.blur or Instance.new("BlurEffect")
		helmetFx.blur.Size = 2
		helmetFx.blur.Parent = camera
	else
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMinZoomDistance = 10
		task.delay(0.1, function() player.CameraMinZoomDistance = 0.5 end)
		for _, fx in helmetFx do fx.Parent = nil end
		if humanoid then humanoid.CameraOffset = Vector3.zero end
	end
	vignette.Visible = on
	if not aiming and not piloting then camera.FieldOfView = baseFov end
	showToast(on and "Bodycam ON  (V to switch)" or "Shoulder cam ON  (V to switch)", SAND, 2)
end
local rainPart, rainEmitter, rainSound
local function ensureRain()
	if rainPart then return end
	rainPart = make("Part", { Name = "RainCloud", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Transparency = 1, Size = Vector3.new(140, 1, 140) }, fxFolder)
	rainEmitter = make("ParticleEmitter", { Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(Color3.fromRGB(190, 200, 215)), LightEmission = 0.1, LightInfluence = 1,
		Size = NumberSequence.new(0.14), Squash = NumberSequence.new(5), Orientation = Enum.ParticleOrientation.VelocityParallel, Transparency = NumberSequence.new(0.35),
		Lifetime = NumberRange.new(0.8, 1), Rate = 1400, Speed = NumberRange.new(100, 120), EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(4, 4), Enabled = false }, rainPart)
	rainSound = make("Sound", { SoundId = Config.Sounds.Rain, Looped = true, Volume = 0 }, game:GetService("SoundService"))
end
RunService.Heartbeat:Connect(function()
	local raining = workspace:GetAttribute("Weather") == "Rain"
	if raining then ensureRain() end
	if rainPart then
		local camPos = camera.CFrame.Position
		local underground = camPos.Y < 8
		rainPart.CFrame = CFrame.new(camPos + Vector3.new(0, 45, 0))
		rainEmitter.Enabled = raining and not underground
		local targetVol = raining and (underground and 0.12 or 0.55) or 0
		rainSound.Volume += (targetVol - rainSound.Volume) * 0.05
		if rainSound.Volume > 0.01 then
			if not rainSound.IsPlaying then rainSound:Play() end
		elseif rainSound.IsPlaying then rainSound:Stop() end
	end
end)

local function setFlashlight(on)
	flashlightOn = on
	R.Flashlight:FireServer(on)
	R.AimPitch:FireServer(math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1)))
	tLight.BackgroundColor3 = on and Color3.fromRGB(110, 96, 50) or INK
	showToast(on and "Flashlight ON  (L)" or "Flashlight OFF  (L)", SAND, 1.2)
end
tLight.Activated:Connect(function() setFlashlight(not flashlightOn) end)

------------------------------------------------------------------------ input
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	local t = input.UserInputType
	if input.KeyCode == Enum.KeyCode.M then showDeploy(not deploy.Visible) return end
	if deploy.Visible then return end
	if piloting then
		if t == Enum.UserInputType.MouseButton1 then R.DroneAction:FireServer("drop")
		elseif input.KeyCode == Enum.KeyCode.X then R.DroneAction:FireServer("detonate", droneBody and droneBody.Position)
		elseif input.KeyCode == Enum.KeyCode.Q then R.DroneAction:FireServer("exit")
		elseif input.KeyCode == Enum.KeyCode.Space then droneVertical = 1
		elseif input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then droneVertical = -1 end
		return
	end
	if t == Enum.UserInputType.MouseButton1 then
		if equippedId == "Drone" then R.DroneAction:FireServer("launch")
		elseif Config.Items[equippedId or ""] then useItem()
		elseif equippedId then triggerHeld = true fireOnce() end
	elseif t == Enum.UserInputType.MouseButton2 then setAiming(true)
	elseif input.KeyCode == Enum.KeyCode.R then requestReload()
	elseif input.KeyCode == Enum.KeyCode.Q then setAiming(not aiming)
	elseif input.KeyCode == Enum.KeyCode.L then setFlashlight(not flashlightOn)
	elseif input.KeyCode == Enum.KeyCode.V then setHelmetCam(not helmetCam) end
end)
UserInputService.InputEnded:Connect(function(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 then triggerHeld = false
	elseif t == Enum.UserInputType.MouseButton2 then setAiming(false)
	elseif input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then droneVertical = 0 end
end)
UserInputService.InputChanged:Connect(function(input, processed)
	if piloting and isTouch and input.UserInputType == Enum.UserInputType.Touch and not processed then
		droneYaw -= input.Delta.X * 0.006
		dronePitch = math.clamp(dronePitch - input.Delta.Y * 0.006, math.rad(-80), math.rad(40))
	end
end)
tFire.MouseButton1Down:Connect(function()
	if equippedId == "Drone" then R.DroneAction:FireServer("launch")
	elseif Config.Items[equippedId or ""] then useItem()
	else triggerHeld = true fireOnce() end
end)
tFire.MouseButton1Up:Connect(function() triggerHeld = false end)
tAim.Activated:Connect(function() setAiming(not aiming) end)
tReload.Activated:Connect(requestReload)
tUp.MouseButton1Down:Connect(function() droneVertical = 1 end)
tUp.MouseButton1Up:Connect(function() droneVertical = 0 end)
tDown.MouseButton1Down:Connect(function() droneVertical = -1 end)
tDown.MouseButton1Up:Connect(function() droneVertical = 0 end)
tDrop.Activated:Connect(function() R.DroneAction:FireServer("drop") end)
tBoom.Activated:Connect(function() R.DroneAction:FireServer("detonate", droneBody and droneBody.Position) end)
tExit.Activated:Connect(function() R.DroneAction:FireServer("exit") end)

------------------------------------------------------------------------ per frame
RunService:BindToRenderStep("CombatCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	bloom = math.max(0, bloom - dt * 3)
	recoilPitch = recoilPitch * math.exp(-dt * 14)
	shakeAmount = shakeAmount * math.exp(-dt * 6)
	if humanoid then
		local h = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
		healthFill.Size = UDim2.fromScale(h, 1)
		healthFill.BackgroundColor3 = Color3.fromRGB(220, 80, 70):Lerp(Color3.fromRGB(120, 200, 110), h)
		healthText.Text = tostring(math.ceil(humanoid.Health))
	end
	if currentMode == "Zombies" then
		if zombieInfo.status == "intermission" then
			local left = math.max(0, zombieInfo.endsAt - workspace:GetServerTimeNow())
			timerText.Text = string.format("NEXT 0:%02d", math.floor(left))
		else
			timerText.Text = "WAVE " .. zombieInfo.wave
		end
	elseif roundEndsAt > 0 then
		local left = math.max(0, roundEndsAt - workspace:GetServerTimeNow())
		timerText.Text = string.format("%02d:%02d", math.floor(left / 60), math.floor(left % 60))
	end
	if deploy.Visible then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		return
	end

	if piloting and droneBody and droneBody.Parent then
		if not isTouch then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
			local d = UserInputService:GetMouseDelta()
			droneYaw -= d.X * 0.0035
			dronePitch = math.clamp(dronePitch - d.Y * 0.0035, math.rad(-80), math.rad(40))
		end
		local look = CFrame.Angles(0, droneYaw, 0) * CFrame.Angles(dronePitch, 0, 0)
		local forward, right = droneInput(look)
		local vel = (look.LookVector * forward + look.RightVector * right) * Config.Drone.speed + Vector3.new(0, droneVertical * Config.Drone.verticalSpeed, 0)
		droneCmd = droneCmd:Lerp(vel, math.min(1, dt * 4))
		local thrust = droneBody:FindFirstChild("Thrust")
		local attitude = droneBody:FindFirstChild("Attitude")
		if thrust then thrust.VectorVelocity = droneCmd end
		if attitude then attitude.CFrame = CFrame.Angles(0, droneYaw, 0) * CFrame.Angles(-forward * 0.35 + dronePitch * 0.3, 0, -right * 0.3) end
		camera.CFrame = CFrame.new(droneBody.Position + Vector3.new(0, 0.1, 0)) * look * CFrame.new(0, 0, -1.1) * CFrame.Angles(math.random() * shakeAmount, math.random() * shakeAmount, 0)
		local speed = droneBody.AssemblyLinearVelocity.Magnitude
		if lastDroneSpeed >= Config.Drone.crashSpeed and droneCmd.Magnitude >= Config.Drone.crashSpeed * 0.8 and speed < lastDroneSpeed * 0.45 then
			R.DroneAction:FireServer("detonate", droneBody and droneBody.Position)
		end
		lastDroneSpeed = speed
		local left = math.max(0, droneEnds - os.clock())
		batteryFill.Size = UDim2.fromScale(left / Config.Drone.battery, 1)
		batteryFill.BackgroundColor3 = left < 10 and Color3.fromRGB(255, 110, 90) or GREEN
		droneInfo.Text = string.format("BAT %02ds   ALT %d   GREN %d", left, math.floor(droneBody.Position.Y), droneGrenades)
		recLabel.Visible = (os.clock() % 1) < 0.6
		return
	end

	if isGun(equippedId) and humanoid and root and humanoid.Health > 0 then
		if not isTouch then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
		end
		humanoid.AutoRotate = false
		local look = camera.CFrame.LookVector
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0)
		if helmetCam then
			humanoid.CameraOffset = bobOffset(dt)
		else
			local target = aiming and Vector3.new(1.1, 0.35, 0) or Vector3.new(1.8, 0.5, 0)
			humanoid.CameraOffset = humanoid.CameraOffset:Lerp(target, math.min(1, dt * 12))
		end
		local w = Config.Weapons[equippedId]
		if triggerHeld and w.auto then fireOnce() end
		local gap = 6 + ((aiming and w.adsSpread or w.hipSpread) + bloom) * 7
		for _, cb in crossBars do cb.bar.Position = UDim2.new(0.5, cb.dir.X * gap, 0.5, cb.dir.Y * gap) end
	elseif helmetCam and humanoid and humanoid.Health > 0 then
		humanoid.CameraOffset = bobOffset(dt)
	end
	if helmetCam and humanoid and humanoid.Health > 0 and not piloting then
		bodycamMotion(dt)
		showOwnArms()
	end
	if recoilPitch > 0.0005 or shakeAmount > 0.0005 then
		camera.CFrame = camera.CFrame * CFrame.Angles(recoilPitch + (math.random() - 0.5) * shakeAmount, (math.random() - 0.5) * shakeAmount, 0)
	end
end)

------------------------------------------------------------------------ aiming pose (all players)
local function poseMotor(motor, offset)
	if motor then motor.Transform = motor.Transform * offset end
end
local function resetMotor(_) end -- the animator restores the pose every frame
local function setMotor(motor, cf)
	if motor then motor.Transform = cf end
end
local lastSentPitch, lastSendTime = 0, 0
RunService.PreSimulation:Connect(function()
	local myPitch = math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1))
	if (isGun(equippedId) or flashlightOn) and not piloting and math.abs(myPitch - lastSentPitch) > 0.03 and os.clock() - lastSendTime > 0.1 then
		lastSentPitch, lastSendTime = myPitch, os.clock()
		R.AimPitch:FireServer(myPitch)
	end
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local upper = char and char:FindFirstChild("UpperTorso")
		if upper then
			local tool = char:FindFirstChildOfClass("Tool")
			local holding = tool ~= nil and Config.Weapons[tool:GetAttribute("WeaponId") or ""] ~= nil
			local waist = upper:FindFirstChild("Waist")
			local head = char:FindFirstChild("Head")
			local neck = head and head:FindFirstChild("Neck")
			local rua = char:FindFirstChild("RightUpperArm")
			local lua = char:FindFirstChild("LeftUpperArm")
			local lla = char:FindFirstChild("LeftLowerArm")
			local rs = rua and rua:FindFirstChild("RightShoulder")
			local lsh = lua and lua:FindFirstChild("LeftShoulder")
			local le = lla and lla:FindFirstChild("LeftElbow")
			local rla = char:FindFirstChild("RightLowerArm")
			local re = rla and rla:FindFirstChild("RightElbow")
			local lh = char:FindFirstChild("LeftHand")
			local lw = lh and lh:FindFirstChild("LeftWrist")
			local rh = char:FindFirstChild("RightHand")
			local rw = rh and rh:FindFirstChild("RightWrist")
			if holding then
				local pitch = (p == player) and myPitch or (char:GetAttribute("AimPitch") or 0)
				poseMotor(waist, CFrame.Angles(pitch * 0.35, 0, 0))
				poseMotor(neck, CFrame.Angles(pitch * 0.35, 0, 0))
				-- steady two-handed hold: arms ignore the walk/run swing
				setMotor(rs, CFrame.Angles(math.rad(88) + pitch * 0.6, math.rad(8), 0))
				setMotor(re, CFrame.Angles(math.rad(6), 0, 0))
				setMotor(rw, CFrame.new())
				setMotor(lsh, CFrame.Angles(0, math.rad(-40), 0) * CFrame.Angles(math.rad(84) + pitch * 0.6, 0, 0))
				setMotor(le, CFrame.Angles(math.rad(32), 0, 0))
				setMotor(lw, CFrame.new())
			else
				resetMotor(waist)
				resetMotor(neck)
				resetMotor(rs)
				resetMotor(lsh)
				resetMotor(le)
			end
		end
	end
end)

------------------------------------------------------------------------ server events
R.AmmoState.OnClientEvent:Connect(function(id, mag, reserve, reloading)
	ammoState[id] = { mag = mag, reserve = reserve, reloading = reloading }
	if id == equippedId then updateAmmoUI() end
end)
local function damageNumber(amount, killed)
	if not amount or amount <= 0 then return end
	local l = label({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, 26 + math.random(-6, 6), 0.5, -18 + math.random(-6, 6)), Size = UDim2.fromOffset(120, 26),
		Text = (killed and "✖ " or "") .. tostring(amount), TextSize = killed and 24 or 20, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = killed and Color3.fromRGB(255, 80, 70) or AMBER, TextStrokeTransparency = 0.3 }, gui)
	TweenService:Create(l, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = l.Position - UDim2.fromOffset(0, 34), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(l, 0.85)
end
R.HitConfirm.OnClientEvent:Connect(function(headshot, killed, amount)
	damageNumber(amount, killed)
	flashHitmarker(killed and Color3.fromRGB(255, 70, 60) or (headshot and AMBER or Color3.new(1, 1, 1)), headshot and 42 or 34)
	soundAt(camera.CFrame.Position, Config.Sounds.Hit, killed and 1 or 0.6, killed and 0.8 or 1)
end)
R.Effects.OnClientEvent:Connect(function(kind, shooter, weaponId, origin, hits, _, _, radius)
	if kind == "shot" then
		if shooter == player then return end
		local list = typeof(hits) == "table" and hits or { hits }
		for _, h in list do
			tracer(origin, h)
			impact(h)
		end
		muzzleFlash(origin)
		local w = Config.Weapons[weaponId]
		if w then soundAt(origin, Config.Sounds[w.sound], 0.9, w.soundSpeed) end
	elseif kind == "explosion" then
		local r = radius or 12
		local fx = make("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.one, Position = origin }, fxFolder)
		make("PointLight", { Color = Color3.fromRGB(255, 170, 90), Brightness = 8, Range = r * 2.5 }, fx)
		local dirt = make("ParticleEmitter", { Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(Color3.fromRGB(70, 56, 42), Color3.fromRGB(110, 96, 80)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, r * 0.5) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(1, 2.2), Speed = NumberRange.new(r * 1.5, r * 3), SpreadAngle = Vector2.new(35, 35), Acceleration = Vector3.new(0, -40, 0), EmissionDirection = Enum.NormalId.Top, Enabled = false, Rate = 0 }, fx)
		local smoke = make("ParticleEmitter", { Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(Color3.fromRGB(60, 58, 56), Color3.fromRGB(140, 138, 134)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, r * 0.4), NumberSequenceKeypoint.new(1, r * 1.2) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(3, 6), Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0.5, 2, 0), Enabled = false, Rate = 0 }, fx)
		dirt:Emit(45)
		smoke:Emit(14)
		task.delay(0.15, function() local l = fx:FindFirstChildOfClass("PointLight") if l then l.Enabled = false end end)
		Debris:AddItem(fx, 7)
		local dist = (camera.CFrame.Position - origin).Magnitude
		shakeAmount = math.max(shakeAmount, math.clamp(0.08 * (1 - dist / 120), 0, 0.08))
	end
end)
R.KillFeed.OnClientEvent:Connect(function(killer, killerColor, victim, victimColor, weapon, headshot)
	local row = make("Frame", { Size = UDim2.fromOffset(360, 24), BackgroundColor3 = INK, BackgroundTransparency = 0.35, LayoutOrder = -math.floor(os.clock() * 100) }, feed)
	corner(row, 6)
	local text = killer
		and string.format("<font color='%s'>%s</font>  [%s%s]  <font color='%s'>%s</font>", hex(killerColor), killer, weapon, headshot and " ⊕" or "", hex(victimColor), victim)
		or string.format("<font color='%s'>%s</font> fell in %s", hex(victimColor), victim, weapon)
	label({ Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), RichText = true, Text = text, TextSize = 14, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Right }, row)
	local rows = {}
	for _, c in feed:GetChildren() do if c:IsA("Frame") then table.insert(rows, c) end end
	if #rows > 5 then
		table.sort(rows, function(x, y) return x.LayoutOrder > y.LayoutOrder end)
		rows[1]:Destroy()
	end
	Debris:AddItem(row, 7)
	if killer == player.Name then showToast("Eliminated " .. victim .. (headshot and "  (headshot)" or ""), AMBER, 2) end
	if victim == player.Name then lastKiller = killer and (killer .. " — " .. weapon) or ("the " .. weapon) end
end)
R.Score.OnClientEvent:Connect(function(blue, red, goal, status, winner, endsAt)
	blueScore.Text = tostring(blue)
	redScore.Text = tostring(red)
	goalText.Text = "FIRST TO " .. goal
	if endsAt then roundEndsAt = endsAt end
	if status == "ended" and winner then
		banner.Text = winner == "DRAW" and "DRAW — NEW ROUND SOON" or (winner:upper() .. " WINS")
		banner.Visible = true
	elseif status == "playing" then
		banner.Visible = false
	end
end)
R.ModeState.OnClientEvent:Connect(function(mode, vT, vZ, need)
	currentMode = mode
	modeVotes.Trenches, modeVotes.Zombies, modeNeeded = vT, vZ, need
	refreshModes()
	if deploy.Visible then refreshCards() end
	local z = mode == "Zombies"
	goalText.Text = z and "UNDEAD LEFT" or ("FIRST TO " .. Config.ScoreToWin)
	blueBox.BackgroundColor3 = z and Color3.fromRGB(60, 70, 50) or Config.Teams.Blue.color.Color
	redBox.BackgroundColor3 = z and Color3.fromRGB(110, 30, 30) or Config.Teams.Red.color.Color
	if z then roundEndsAt = 0 blueScore.Text = "W" .. zombieInfo.wave redScore.Text = tostring(zombieInfo.remaining) end
end)
R.ZombieState.OnClientEvent:Connect(function(status, wave, remaining, endsAt)
	zombieInfo.status, zombieInfo.wave, zombieInfo.remaining, zombieInfo.endsAt = status, wave, remaining, endsAt
	if currentMode == "Zombies" then
		blueScore.Text = "W" .. wave
		redScore.Text = tostring(remaining)
		if status == "intermission" then
			banner.Text = "WAVE " .. (wave + 1) .. " INCOMING"
			banner.Visible = true
			task.delay(3, function() if zombieInfo.status == "intermission" then banner.Visible = false end end)
		elseif status == "failed" then
			banner.Text = "THE LINE HAS FALLEN"
			banner.Visible = true
			task.delay(4, function() banner.Visible = false end)
		else
			banner.Visible = false
		end
	end
end)
R.Notify.OnClientEvent:Connect(function(text, kind)
	local c = kind == "good" and Color3.fromRGB(150, 230, 160) or kind == "warn" and AMBER or SAND
	showToast(text, c, 2.5)
end)

------------------------------------------------------------------------ minimap (N to hide)
local HttpService = game:GetService("HttpService")
local MAP_MIN_X, MAP_MAX_X, MAP_MIN_Z, MAP_MAX_Z = -368, 368, -256, 256
local MM_W = 140
local MM_S = MM_W / (MAP_MAX_X - MAP_MIN_X)
local MM_H = math.floor((MAP_MAX_Z - MAP_MIN_Z) * MM_S)
local minimap = make("Frame", { Name = "Minimap", Position = UDim2.fromOffset(16, 60), Size = UDim2.fromOffset(MM_W, MM_H),
	BackgroundColor3 = Color3.fromRGB(76, 62, 46), BackgroundTransparency = 0.12, ClipsDescendants = true }, gui)
corner(minimap, 6)
make("UIStroke", { Color = Color3.fromRGB(214, 180, 112), Thickness = 1.5, Transparency = 0.25 }, minimap)
local function mmPos(x, z) return (x - MAP_MIN_X) * MM_S, (z - MAP_MIN_Z) * MM_S end
local function mmRect(x1, z1, x2, z2, color, transp, zi)
	local a, b = mmPos(x1, z1)
	local c, d = mmPos(x2, z2)
	return make("Frame", { Position = UDim2.fromOffset(math.min(a, c), math.min(b, d)), Size = UDim2.fromOffset(math.max(1, math.abs(c - a)), math.max(1, math.abs(d - b))),
		BackgroundColor3 = color, BackgroundTransparency = transp or 0, BorderSizePixel = 0, ZIndex = zi or 1 }, minimap)
end
mmRect(-368, -256, -228, 256, Color3.fromRGB(52, 72, 44), 0.05)          -- forest
mmRect(236, -256, 368, 256, Color3.fromRGB(108, 98, 72), 0.05)           -- fields & village
mmRect(236, -6, 368, 6, Color3.fromRGB(130, 126, 118), 0.2, 2)           -- village road
mmRect(-24, -32, 24, 32, Color3.fromRGB(160, 154, 142), 0, 3)            -- chapel
mmRect(-334, -14, -302, 14, Config.Teams.Blue.color.Color, 0.15, 3)     -- Blue camp
mmRect(302, -14, 334, 14, Config.Teams.Red.color.Color, 0.15, 3)        -- Red camp
do
	local ok, rects = pcall(function() return HttpService:JSONDecode(Combat:GetAttribute("MapTrenches") or "[]") end)
	if ok then
		for _, t in rects do mmRect(t.x1, t.z1, t.x2, t.z2, Color3.fromRGB(30, 25, 20), 0, 2) end
	end
end
label({ Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(60, 12), Text = "W", TextSize = 9, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(200, 214, 230), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 }, minimap)
label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 2), Size = UDim2.fromOffset(60, 12), Text = "E", TextSize = 9, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(240, 200, 190), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 }, minimap)
local mmArrow = label({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12), Text = "▲", TextSize = 11, TextColor3 = Color3.fromRGB(255, 236, 120), TextStrokeTransparency = 0.2, ZIndex = 7 }, minimap)
local mmDots = {}
local function mmDot(i, color, x, z)
	local d = mmDots[i]
	if not d then
		d = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(4, 4), BorderSizePixel = 0, ZIndex = 6 }, minimap)
		corner(d, 3)
		mmDots[i] = d
	end
	local px, py = mmPos(x, z)
	d.Position = UDim2.fromOffset(px, py)
	d.BackgroundColor3 = color
	d.Visible = true
end
local mmAccum = 0
RunService.Heartbeat:Connect(function(dt)
	if root and root.Parent then
		local px, py = mmPos(root.Position.X, root.Position.Z)
		mmArrow.Position = UDim2.fromOffset(px, py)
		local lv = camera.CFrame.LookVector
		mmArrow.Rotation = math.deg(math.atan2(lv.X, -lv.Z))
		mmArrow.Visible = true
	else
		mmArrow.Visible = false
	end
	mmAccum += dt
	if mmAccum < 0.25 then return end
	mmAccum = 0
	local n = 0
	local myTeam = player.Team
	local myKey
	for k, info in Config.Teams do if myTeam and myTeam.TeamColor == info.color then myKey = k end end
	for _, p in Players:GetPlayers() do
		if p ~= player and myTeam and p.Team == myTeam then
			local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if r then n += 1 mmDot(n, Color3.fromRGB(120, 200, 255), r.Position.X, r.Position.Z) end
		end
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots and myKey then
		for _, b in bots:GetChildren() do
			if b:GetAttribute("BotTeam") == myKey then
				local r = b:FindFirstChild("HumanoidRootPart")
				local h = b:FindFirstChildOfClass("Humanoid")
				if r and h and h.Health > 0 then n += 1 mmDot(n, Color3.fromRGB(150, 220, 150), r.Position.X, r.Position.Z) end
			end
		end
	end
	if currentMode == "Zombies" and root then
		local zf = workspace:FindFirstChild("Zombies")
		if zf then
			for _, z in zf:GetChildren() do
				local r = z:FindFirstChild("HumanoidRootPart")
				if r and (r.Position - root.Position).Magnitude < 90 then n += 1 mmDot(n, Color3.fromRGB(230, 70, 60), r.Position.X, r.Position.Z) end
			end
		end
	end
	for i = n + 1, #mmDots do mmDots[i].Visible = false end
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.N then minimap.Visible = not minimap.Visible end
end)

------------------------------------------------------------------------ character lifecycle
local firstSpawn = true
local function onCharacter(char)
	character = char
	humanoid = char:WaitForChild("Humanoid")
	root = char:WaitForChild("HumanoidRootPart")
	deathUI.Visible = false
	piloting = false
	flashlightOn = false
	tLight.BackgroundColor3 = INK
	onUnequipped()
	endPiloting()
	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(h)
		if h < lastHealth then
			damageFlash.BackgroundTransparency = 0.6
			TweenService:Create(damageFlash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		end
		lastHealth = h
	end)
	char.ChildAdded:Connect(function(c) if c:IsA("Tool") and c:GetAttribute("WeaponId") then onEquipped(c) end end)
	char.ChildRemoved:Connect(function(c) if c == equippedTool then onUnequipped() end end)
	humanoid.Died:Connect(function()
		onUnequipped()
		if piloting then endPiloting() end
		task.wait(0.3)
		deathUI.Visible = true
		deathTitle.Text = "YOU WERE KILLED"
		local t0 = os.clock()
		while deathUI.Visible and humanoid and humanoid.Health <= 0 do
			local left = math.max(0, Config.RespawnTime - (os.clock() - t0))
			deathSub.Text = (lastKiller and ("by " .. lastKiller .. "   ·   ") or "") .. string.format("redeploying in %d", math.ceil(left))
			task.wait(0.2)
		end
	end)
	if firstSpawn then
		firstSpawn = false
	else
		task.delay(0.8, function()
			local team = player.Team
			if team then
				local west = team.TeamColor == Config.Teams.Blue.color
				showToast(team.Name:upper() .. " — " .. (west and "hold the WEST line" or "hold the EAST line"), team.TeamColor.Color, 3)
			end
		end)
	end
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then task.spawn(onCharacter, player.Character) end
task.defer(function()
	showDeploy(true)
	if not isTouch then setHelmetCam(true) end -- bodycam is the default view
end)
