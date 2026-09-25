-- Client: comandi per far girare il personaggio (e quindi la sbarra)
-- e rilevamento dei colpi tra la sbarra e la palla.
--
-- Comandi:
--   Click sinistro / R2 / pulsante "Colpo"  -> giro veloce di 360° (colpo)
--   Q / L1 (tieni premuto)                  -> gira a sinistra
--   E / R1 (tieni premuto)                  -> gira a destra
--   R / Y / pulsante "Palla"                -> riporta la palla davanti a te

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("StickBallConfig"))
local remotes = ReplicatedStorage:WaitForChild("StickBallRemotes")
local hitRemote = remotes:WaitForChild("HitBall") :: RemoteEvent
local resetRemote = remotes:WaitForChild("ResetBall") :: RemoteEvent

local player = Players.LocalPlayer

-- Stato ---------------------------------------------------------------------

local humanoid: Humanoid? = nil
local root: BasePart? = nil
local bar: BasePart? = nil
local barWeld: Weld? = nil

local previousRootCFrame: CFrame? = nil
local autoRotateDisabled = false

local spinLeftHeld = false
local spinRightHeld = false
local swingRemaining = 0 -- radianti ancora da girare nel colpo in corso
local swingDirection = 1
local lastSwingEnd = -math.huge

local lastHitTime: { [BasePart]: number } = setmetatable({}, { __mode = "k" }) :: any

-- UI di debug ----------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StickBallHud"
screenGui.ResetOnSpawn = false

local infoLabel = Instance.new("TextLabel")
infoLabel.AnchorPoint = Vector2.new(0, 1)
infoLabel.Position = UDim2.new(0, 12, 1, -12)
infoLabel.Size = UDim2.fromOffset(360, 44)
infoLabel.BackgroundColor3 = Color3.new(0, 0, 0)
infoLabel.BackgroundTransparency = 0.5
infoLabel.TextColor3 = Color3.new(1, 1, 1)
infoLabel.Font = Enum.Font.GothamMedium
infoLabel.TextSize = 14
infoLabel.TextXAlignment = Enum.TextXAlignment.Left
infoLabel.Text = "  Click: colpo  |  Q/E: gira  |  R: palla\n  Ultimo colpo: -"
infoLabel.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = infoLabel

screenGui.Parent = player:WaitForChild("PlayerGui")

-- Personaggio -----------------------------------------------------------------

local function onCharacterAdded(character: Model)
	humanoid = nil
	root = nil
	bar = nil
	barWeld = nil
	previousRootCFrame = nil
	autoRotateDisabled = false
	swingRemaining = 0
	spinLeftHeld = false
	spinRightHeld = false

	local newHumanoid = character:WaitForChild("Humanoid") :: Humanoid
	local newRoot = character:WaitForChild("HumanoidRootPart") :: BasePart
	local newBar = character:WaitForChild("StickBar", 10) :: BasePart?
	local newWeld = if newBar then newBar:WaitForChild("StickBarWeld", 10) :: Weld? else nil

	-- Nel frattempo potrebbe essere arrivato un altro personaggio.
	if player.Character ~= character then
		return
	end
	if not (newBar and newWeld) then
		warn("[StickBall] Sbarra non trovata sul personaggio: lo script server è in ServerScriptService?")
		return
	end

	humanoid = newHumanoid
	root = newRoot
	bar = newBar
	barWeld = newWeld
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end

-- Comandi ----------------------------------------------------------------------

local function isPressed(state: Enum.UserInputState): boolean?
	if state == Enum.UserInputState.Begin then
		return true
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		return false
	end
	return nil
end

local function onSpinLeft(_, state: Enum.UserInputState)
	local pressed = isPressed(state)
	if pressed ~= nil then
		spinLeftHeld = pressed
	end
	return Enum.ContextActionResult.Sink
end

local function onSpinRight(_, state: Enum.UserInputState)
	local pressed = isPressed(state)
	if pressed ~= nil then
		spinRightHeld = pressed
	end
	return Enum.ContextActionResult.Sink
end

local function onSwing(_, state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if swingRemaining > 0 or os.clock() - lastSwingEnd < Config.Spin.SwingCooldown then
		return Enum.ContextActionResult.Pass
	end
	swingRemaining = math.rad(Config.Spin.SwingAngle)
	-- Gira nel verso in cui la sbarra spazza IN AVANTI:
	-- sbarra a destra -> giro verso sinistra (yaw positivo), e viceversa.
	swingDirection = Config.Bar.Side
	return Enum.ContextActionResult.Pass
end

local function onReset(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		resetRemote:FireServer()
	end
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction("StickSwing", onSwing, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
ContextActionService:BindAction("StickSpinLeft", onSpinLeft, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
ContextActionService:BindAction("StickSpinRight", onSpinRight, true, Enum.KeyCode.E, Enum.KeyCode.ButtonR1)
ContextActionService:BindAction("StickResetBall", onReset, true, Enum.KeyCode.R, Enum.KeyCode.ButtonY)

-- Titoli dei pulsanti su mobile.
ContextActionService:SetTitle("StickSwing", "Colpo")
ContextActionService:SetTitle("StickSpinLeft", "Sx")
ContextActionService:SetTitle("StickSpinRight", "Dx")
ContextActionService:SetTitle("StickResetBall", "Palla")

UserInputService.WindowFocusReleased:Connect(function()
	spinLeftHeld = false
	spinRightHeld = false
end)

-- Rilevamento colpi ----------------------------------------------------------------

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Punto del segmento AB più vicino a P (tutto sul piano orizzontale).
local function closestPointOnSegment(p: Vector3, a: Vector3, b: Vector3): (Vector3, number)
	local ab = b - a
	local lengthSquared = ab:Dot(ab)
	if lengthSquared < 1e-6 then
		return a, 0
	end
	local t = math.clamp((p - a):Dot(ab) / lengthSquared, 0, 1)
	return a + ab * t, t
end

local function applyHit(ball: BasePart, velocity: Vector3, position: Vector3)
	infoLabel.Text = string.format("  Click: colpo  |  Q/E: gira  |  R: palla\n  Ultimo colpo: %d studs/s", math.floor(velocity.Magnitude))

	if ball:GetAttribute("OwnerUserId") == player.UserId then
		-- Siamo noi a simulare la palla: effetto immediato, il server riceve la fisica da noi.
		ball.CFrame = ball.CFrame.Rotation + position
		ball.AssemblyLinearVelocity = velocity
	else
		hitRemote:FireServer(ball, velocity, position)
	end
end

-- Controlla se la sbarra, muovendosi da fromCFrame a toCFrame (CFrame del
-- root), ha toccato una palla. Il movimento è diviso in piccoli passi così una
-- rotazione veloce non "attraversa" la palla senza colpirla.
local function checkHits(fromCFrame: CFrame, toCFrame: CFrame, dt: number)
	local currentBar = bar :: BasePart
	local currentWeld = barWeld :: Weld

	-- Posizione della sbarra rispetto al root (Part1 = Part0 * C0 * C1^-1).
	local barOffset = currentWeld.C0 * currentWeld.C1:Inverse()
	local halfLength = currentBar.Size.X / 2
	local localA = barOffset * Vector3.new(-halfLength, 0, 0)
	local localB = barOffset * Vector3.new(halfLength, 0, 0)
	local barHalfThickness = currentBar.Size.Z / 2
	local barHalfHeight = currentBar.Size.Y / 2
	local reach = math.max(localA.Magnitude, localB.Magnitude)

	local maxMove = math.max(((toCFrame * localA) - (fromCFrame * localA)).Magnitude, ((toCFrame * localB) - (fromCFrame * localB)).Magnitude)

	local hitConfig = Config.Hit
	local now = os.clock()

	for _, instance in CollectionService:GetTagged(Config.Ball.Tag) do
		if not instance:IsA("BasePart") or not instance:IsDescendantOf(workspace) then
			continue
		end
		local ball = instance :: BasePart
		if now - (lastHitTime[ball] or -math.huge) < hitConfig.HitCooldown then
			continue
		end

		local radius = ball.Size.X / 2
		local contactDistance = radius + barHalfThickness
		local ballPosition = ball.Position
		local flatBall = flat(ballPosition)

		-- Scarto veloce: palla troppo lontana o ad altezza diversa dalla sbarra.
		if (flatBall - flat(toCFrame.Position)).Magnitude > reach + contactDistance + maxMove then
			continue
		end
		local barCenterY = (toCFrame * barOffset.Position).Y
		if math.abs(ballPosition.Y - barCenterY) > barHalfHeight + radius then
			continue
		end

		local steps = math.clamp(math.ceil(maxMove / (radius * 0.5)), 1, 24)
		for step = 0, steps do
			local stepCFrame = fromCFrame:Lerp(toCFrame, step / steps)
			local closest, t = closestPointOnSegment(flatBall, flat(stepCFrame * localA), flat(stepCFrame * localB))
			local offset = flatBall - closest
			local distance = offset.Magnitude
			if distance >= contactDistance then
				continue
			end

			-- Velocità del punto della sbarra che tocca la palla (rotazione + camminata).
			local localPoint = localA:Lerp(localB, t)
			local barVelocity = flat((toCFrame * localPoint) - (fromCFrame * localPoint)) / dt

			local normal: Vector3
			if distance > 1e-3 then
				normal = offset / distance
			elseif barVelocity.Magnitude > 1e-3 then
				normal = barVelocity.Unit
			else
				break
			end

			local ballVelocity = ball.AssemblyLinearVelocity
			local approachSpeed = (barVelocity - flat(ballVelocity)):Dot(normal)
			if approachSpeed <= hitConfig.MinApproachSpeed then
				break
			end

			-- Urto con una sbarra "infinitamente pesante" + un po' di spinta verso l'alto.
			local newVelocity = ballVelocity
				+ normal * approachSpeed * (1 + hitConfig.Restitution)
				+ Vector3.yAxis * approachSpeed * hitConfig.Lift
			if newVelocity.Magnitude > hitConfig.MaxBallSpeed then
				newVelocity = newVelocity.Unit * hitConfig.MaxBallSpeed
			end

			-- Sposta la palla davanti alla sbarra nella sua posizione finale,
			-- così non resta compenetrata (o dietro) dopo un giro veloce.
			local finalClosest = closestPointOnSegment(flatBall, flat(toCFrame * localA), flat(toCFrame * localB))
			local separation = (flatBall - finalClosest):Dot(normal)
			local newPosition = ballPosition
			if separation < contactDistance then
				newPosition += normal * (contactDistance - separation + 0.05)
			end

			lastHitTime[ball] = now
			applyHit(ball, newVelocity, newPosition)
			break
		end
	end
end

-- Loop principale --------------------------------------------------------------------

RunService.Heartbeat:Connect(function(dt)
	local currentHumanoid = humanoid
	local currentRoot = root
	if
		not (currentHumanoid and currentRoot and bar and barWeld)
		or not (bar :: BasePart):IsDescendantOf(workspace)
		or currentHumanoid.Health <= 0
	then
		previousRootCFrame = nil
		return
	end

	-- 1) Rotazione: colpo in corso oppure Q/E tenuti premuti.
	local deltaYaw = 0
	local holdDirection = (if spinLeftHeld then 1 else 0) - (if spinRightHeld then 1 else 0)
	if swingRemaining > 0 then
		local step = math.min(swingRemaining, math.rad(Config.Spin.SwingSpeed) * dt)
		swingRemaining -= step
		deltaYaw = step * swingDirection
		if swingRemaining <= 0 then
			lastSwingEnd = os.clock()
		end
	elseif holdDirection ~= 0 then
		deltaYaw = math.rad(Config.Spin.HoldSpeed) * dt * holdDirection
	end

	local spinning = deltaYaw ~= 0
	if spinning ~= autoRotateDisabled then
		-- Mentre giriamo noi, l'Humanoid non deve riorientare il personaggio.
		currentHumanoid.AutoRotate = not spinning
		autoRotateDisabled = spinning
	end

	local newRootCFrame = currentRoot.CFrame
	if spinning then
		newRootCFrame *= CFrame.Angles(0, deltaYaw, 0)
	end

	-- 2) Colpi: confronta dove era la sbarra nel frame precedente con dove sarà ora.
	--    Funziona sia col giro (click, Q/E) sia girandosi/camminando normalmente.
	local previous = previousRootCFrame
	if previous and (previous.Position - newRootCFrame.Position).Magnitude < 20 then
		checkHits(previous, newRootCFrame, dt)
	end

	if spinning then
		currentRoot.CFrame = newRootCFrame
	end
	previousRootCFrame = newRootCFrame
end)
