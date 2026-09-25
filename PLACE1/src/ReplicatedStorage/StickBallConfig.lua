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
