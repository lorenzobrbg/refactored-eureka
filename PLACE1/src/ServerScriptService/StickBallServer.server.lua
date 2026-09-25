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
