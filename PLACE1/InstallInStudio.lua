-- INSTALLAZIONE IN UN COLPO
-- 1. Apri PLACE1 in Roblox Studio
-- 2. Menu View -> Command Bar
-- 3. Incolla TUTTO questo file nella Command Bar e premi Invio
-- 4. Premi Play per provare, poi File -> Save / Publish per salvare PLACE1
--
-- Crea (o sostituisce) i 3 script:
--   ReplicatedStorage/StickBallConfig                  (ModuleScript)
--   ServerScriptService/StickBallServer                (Script)
--   StarterPlayer/StarterPlayerScripts/StickBallClient (LocalScript)

local function install(parent, className, name, source)
	local existing = parent:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local script = Instance.new(className)
	script.Name = name
	script.Source = source
	script.Parent = parent
end

install(game:GetService("ReplicatedStorage"), "ModuleScript", "StickBallConfig", [==[
-- Configurazione condivisa tra server e client.
-- Modifica questi valori per provare sensazioni di gioco diverse.

local Config = {}

-- SBARRA ------------------------------------------------------------------

Config.Bar = {
	Length = 8, -- lunghezza della sbarra (studs)
	Thickness = 1.2, -- spessore orizzontale
	Height = 1.5, -- altezza (deve essere > raggio della palla, così la palla non ci sale sopra)
	GroundGap = 0.15, -- distanza tra il fondo della sbarra e il terreno
	SideOffset = 1.2, -- distanza dal centro del personaggio a dove inizia la sbarra
	Side = 1, -- 1 = lato destro, -1 = lato sinistro
	Color = Color3.fromRGB(255, 235, 60),
	Material = Enum.Material.SmoothPlastic,
}

-- PALLA -------------------------------------------------------------------

Config.Ball = {
	Name = "Ball",
	Tag = "StickBall", -- tag CollectionService: il client colpisce tutte le parti con questo tag
	Diameter = 2.5,
	Color = Color3.fromRGB(245, 245, 245),
	Material = Enum.Material.SmoothPlastic,
	Density = 0.3, -- più basso = più leggera
	Friction = 0.5,
	Elasticity = 0.55, -- rimbalzo
	RollingDeceleration = 10, -- quanto rallenta rotolando (studs/s²), 0 = rotola all'infinito
	SpawnOffset = Vector3.new(0, 5, -15), -- rispetto allo SpawnLocation (se non esiste una parte "BallSpawn")
	RespawnBelowY = -50, -- se la palla cade sotto questa Y torna allo spawn
}

-- ROTAZIONE / COLPO -------------------------------------------------------

Config.Spin = {
	HoldSpeed = 360, -- gradi/secondo quando tieni premuto Q / E
	SwingSpeed = 720, -- gradi/secondo durante il colpo (click)
	SwingAngle = 360, -- quanti gradi gira il personaggio con un colpo
	SwingCooldown = 0.15, -- pausa minima tra un colpo e il successivo
}

Config.Hit = {
	Restitution = 0.5, -- 0 = la palla prende solo la velocità della sbarra, 1 = rimbalzo pieno
	Lift = 0.12, -- quanto la palla si alza quando viene colpita (frazione della velocità)
	MinApproachSpeed = 0.5, -- sotto questa velocità relativa non conta come colpo
	MaxBallSpeed = 110, -- velocità massima della palla dopo un colpo
	HitCooldown = 0.1, -- secondi prima che la stessa palla possa essere ricolpita
}

-- RETE --------------------------------------------------------------------

Config.Network = {
	OwnershipRadius = 40, -- il giocatore più vicino entro questo raggio simula la palla (colpi senza lag)
	MaxHitDistance = 25, -- il server rifiuta colpi da giocatori più lontani di così
	ServerHitLock = 0.3, -- dopo un colpo gestito dal server, per quanto il server tiene la palla
	ResetCooldown = 1, -- secondi tra un reset palla (tasto R) e l'altro
}

return Config
]==])

install(game:GetService("ServerScriptService"), "Script", "StickBallServer", [==[
-- Server: attacca la sbarra a ogni personaggio, crea la palla e gestisce
-- chi la simula (network ownership), i colpi validati e il reset.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("StickBallConfig"))

-- Remote --------------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = "StickBallRemotes"

local hitRemote = Instance.new("RemoteEvent")
hitRemote.Name = "HitBall"
hitRemote.Parent = remotes

local resetRemote = Instance.new("RemoteEvent")
resetRemote.Name = "ResetBall"
resetRemote.Parent = remotes

remotes.Parent = ReplicatedStorage

-- Sbarra --------------------------------------------------------------------

-- Distanza verticale tra il centro dell'HumanoidRootPart e il pavimento.
local function getGroundOffset(character: Model, humanoid: Humanoid, root: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	local leg = character:FindFirstChild("Left Leg")
	local legHeight = if leg and leg:IsA("BasePart") then leg.Size.Y else 2
	return root.Size.Y / 2 + legHeight
end

local function getBarOffset(character: Model, humanoid: Humanoid, root: BasePart): CFrame
	local barConfig = Config.Bar
	local x = barConfig.Side * (barConfig.SideOffset + barConfig.Length / 2)
	local y = -getGroundOffset(character, humanoid, root) + barConfig.GroundGap + barConfig.Height / 2
	return CFrame.new(x, y, 0)
end

local function attachBar(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) then
		return
	end
	if character:FindFirstChild("StickBar") then
		return
	end

	local barConfig = Config.Bar
	local offset = getBarOffset(character, humanoid, root)

	-- La lunghezza è sull'asse X, così la sbarra sta di lato al personaggio.
	local bar = Instance.new("Part")
	bar.Name = "StickBar"
	bar.Size = Vector3.new(barConfig.Length, barConfig.Height, barConfig.Thickness)
	bar.Color = barConfig.Color
	bar.Material = barConfig.Material
	bar.TopSurface = Enum.SurfaceType.Smooth
	bar.BottomSurface = Enum.SurfaceType.Smooth
	-- Nessuna collisione fisica: i colpi li calcola lo script client,
	-- così la sbarra scorre a terra senza incastrarsi e senza far volare il personaggio.
	bar.CanCollide = false
	bar.CanTouch = false
	bar.CanQuery = false
	bar.Massless = true
	bar.CFrame = root.CFrame * offset

	local weld = Instance.new("Weld")
	weld.Name = "StickBarWeld"
	weld.Part0 = root
	weld.Part1 = bar
	weld.C0 = offset
	weld.Parent = bar

	bar.Parent = character

	-- Se l'avatar viene riscalato dopo lo spawn, riallinea la sbarra al terreno.
	humanoid:GetPropertyChangedSignal("HipHeight"):Connect(function()
		weld.C0 = getBarOffset(character, humanoid, root)
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(attachBar)
	if player.Character then
		task.spawn(attachBar, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Palla ---------------------------------------------------------------------

local ball: BasePart? = nil
local ownerAssigned = false
local currentOwner: Player? = nil
local serverLockUntil = 0

local function getSpawnPosition(): Vector3
	local marker = workspace:FindFirstChild("BallSpawn")
	if marker and marker:IsA("BasePart") then
		return marker.Position
	end
	local spawnLocation = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnLocation then
		return spawnLocation.Position + Config.Ball.SpawnOffset
	end
	return Vector3.new(0, 5, 0) + Config.Ball.SpawnOffset
end

local function createBall(): BasePart
	local ballConfig = Config.Ball

	local newBall = Instance.new("Part")
	newBall.Name = ballConfig.Name
	newBall.Shape = Enum.PartType.Ball
	newBall.Size = Vector3.one * ballConfig.Diameter
	newBall.Color = ballConfig.Color
	newBall.Material = ballConfig.Material
	newBall.TopSurface = Enum.SurfaceType.Smooth
	newBall.BottomSurface = Enum.SurfaceType.Smooth
	newBall.CustomPhysicalProperties =
		PhysicalProperties.new(ballConfig.Density, ballConfig.Friction, ballConfig.Elasticity, 1, 1)
	newBall.Position = getSpawnPosition()

	-- Attrito di rotolamento: frena la rotazione, quindi la palla rotolando rallenta.
	-- Per una sfera che rotola: decelerazione = coppia / (1.4 * massa * raggio).
	if ballConfig.RollingDeceleration > 0 then
		local attachment = Instance.new("Attachment")
		attachment.Parent = newBall

		local rollingResistance = Instance.new("AngularVelocity")
		rollingResistance.Name = "RollingResistance"
		rollingResistance.Attachment0 = attachment
		rollingResistance.AngularVelocity = Vector3.zero
		rollingResistance.RelativeTo = Enum.ActuatorRelativeTo.World
		rollingResistance.ReactionTorqueEnabled = false
		rollingResistance.MaxTorque = ballConfig.RollingDeceleration * 1.4 * newBall:GetMass() * (ballConfig.Diameter / 2)
		rollingResistance.Parent = newBall
	end

	CollectionService:AddTag(newBall, ballConfig.Tag)
	newBall.Parent = workspace

	ownerAssigned = false
	return newBall
end

local function setOwner(owner: Player?)
	if not ball or (ownerAssigned and currentOwner == owner) then
		return
	end
	local ok = pcall(function()
		(ball :: BasePart):SetNetworkOwner(owner)
	end)
	if ok then
		ownerAssigned = true
		currentOwner = owner
		-- Il client non può leggere GetNetworkOwner(), quindi lo pubblichiamo come attributo.
		ball:SetAttribute("OwnerUserId", if owner then owner.UserId else 0)
	end
end

local function placeBall(position: Vector3)
	if not ball or not ball.Parent then
		ball = createBall()
	end
	local currentBall = ball :: BasePart
	-- Il server prende la palla un attimo, così il teletrasporto non viene sovrascritto dal client.
	serverLockUntil = os.clock() + Config.Network.ServerHitLock
	setOwner(nil)
	currentBall.CFrame = CFrame.new(position)
	currentBall.AssemblyLinearVelocity = Vector3.zero
	currentBall.AssemblyAngularVelocity = Vector3.zero
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function getNearestPlayer(position: Vector3, maxDistance: number): Player?
	local nearest: Player? = nil
	local nearestDistance = maxDistance
	for _, player in Players:GetPlayers() do
		local root = getRoot(player)
		if root then
			local distance = (root.Position - position).Magnitude
			if distance < nearestDistance then
				nearest = player
				nearestDistance = distance
			end
		end
	end
	return nearest
end

ball = createBall()

-- Ogni 0.1 s: respawn se la palla è caduta, e la simula il giocatore più vicino.
-- Così chi colpisce vede la palla partire subito, senza lag.
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.1 then
		return
	end
	accumulator = 0

	if not ball or not ball.Parent or ball.Position.Y < Config.Ball.RespawnBelowY then
		placeBall(getSpawnPosition())
		return
	end

	if os.clock() < serverLockUntil then
		setOwner(nil)
	else
		setOwner(getNearestPlayer(ball.Position, Config.Network.OwnershipRadius))
	end
end)

-- Colpo da un client che NON simula la palla: il server lo valida e lo applica.
hitRemote.OnServerEvent:Connect(function(player: Player, hitBall: any, velocity: any, position: any)
	if hitBall ~= ball or not ball or typeof(velocity) ~= "Vector3" then
		return
	end
	if position ~= nil and typeof(position) ~= "Vector3" then
		return
	end
	-- Scarta NaN / infiniti.
	if velocity.Magnitude ~= velocity.Magnitude or velocity.Magnitude == math.huge then
		return
	end

	local root = getRoot(player)
	if not root or (root.Position - ball.Position).Magnitude > Config.Network.MaxHitDistance then
		return
	end

	if velocity.Magnitude > Config.Hit.MaxBallSpeed then
		velocity = velocity.Unit * Config.Hit.MaxBallSpeed
	end

	serverLockUntil = os.clock() + Config.Network.ServerHitLock
	setOwner(nil)
	if position and (position - ball.Position).Magnitude < 8 then
		ball.CFrame = ball.CFrame.Rotation + position
	end
	ball.AssemblyLinearVelocity = velocity
end)

-- Tasto R: la palla torna davanti al giocatore.
local lastReset: { [Player]: number } = {}

resetRemote.OnServerEvent:Connect(function(player: Player)
	local now = os.clock()
	if lastReset[player] and now - lastReset[player] < Config.Network.ResetCooldown then
		return
	end
	local root = getRoot(player)
	if not root then
		return
	end
	lastReset[player] = now
	placeBall(root.Position + root.CFrame.LookVector * 6 + Vector3.new(0, 2, 0))
end)

Players.PlayerRemoving:Connect(function(player)
	lastReset[player] = nil
end)
]==])

install(game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"), "LocalScript", "StickBallClient", [==[
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
]==])

print("StickBall installato: premi Play per provarlo, poi salva PLACE1.")
