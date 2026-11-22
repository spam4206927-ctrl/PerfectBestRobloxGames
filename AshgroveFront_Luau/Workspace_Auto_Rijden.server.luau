-- Stuurt de auto aan met de VehicleSeat (W/S = gas/achteruit, A/D = sturen)
local auto = script.Parent
local stoel = auto:WaitForChild("Bestuurdersstoel")

local MAX_SNELHEID = 60    -- studs per seconde
local WIELSTRAAL = 1.2
local MAX_STUURHOEK = 30   -- graden
local KOPPEL_GAS = 40000
local KOPPEL_RUST = 2500   -- remt de auto rustig af als je geen gas geeft

local motoren, sturen = {}, {}
for _, d in auto:GetDescendants() do
	if d:IsA("HingeConstraint") then
		if d.Name == "Aandrijving" then
			table.insert(motoren, d)
		elseif d.Name == "Stuur" then
			table.insert(sturen, d)
		end
	end
end

local function update()
	local gas = stoel.ThrottleFloat
	local stuur = stoel.SteerFloat
	-- Wielen draaien om +X; een negatieve hoeksnelheid rijdt de auto vooruit (-Z)
	local hoeksnelheid = -gas * MAX_SNELHEID / WIELSTRAAL
	for _, motor in motoren do
		motor.AngularVelocity = hoeksnelheid
		motor.MotorMaxTorque = if gas ~= 0 then KOPPEL_GAS else KOPPEL_RUST
	end
	for _, servo in sturen do
		servo.TargetAngle = -stuur * MAX_STUURHOEK
	end
end

stoel:GetPropertyChangedSignal("ThrottleFloat"):Connect(update)
stoel:GetPropertyChangedSignal("SteerFloat"):Connect(update)
update()
