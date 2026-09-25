# PLACE1 – Prototipo "sbarra + pallone"

Prototipo per testare la meccanica: il personaggio ha una **sbarra laterale che
scorre per terra** (sul lato destro) e c'è un **pallone** da spingere e colpire.
Girando il personaggio, la sbarra spazza il terreno come la lancetta di un
orologio e colpisce la palla.

## Comandi

| Azione | PC | Gamepad | Mobile |
| --- | --- | --- | --- |
| Colpo (giro veloce di 360°) | Click sinistro | R2 | pulsante **Colpo** |
| Gira a sinistra (tieni premuto) | Q | L1 | pulsante **Sx** |
| Gira a destra (tieni premuto) | E | R1 | pulsante **Dx** |
| Riporta la palla davanti a te | R | Y | pulsante **Palla** |

La palla si colpisce anche solo camminando o girandosi normalmente: conta la
velocità con cui la sbarra la tocca. In basso a sinistra c'è un riquadro che
mostra la velocità dell'ultimo colpo.

## Come metterlo in PLACE1

Questi file sono su GitHub: vanno inseriti nel place PLACE1 da Roblox Studio.

### Metodo veloce: un solo incolla

1. Apri **PLACE1** in Roblox Studio.
2. Menu **View → Command Bar**.
3. Copia **tutto** il file [`InstallInStudio.lua`](InstallInStudio.lua), incollalo nella Command Bar e premi **Invio**.
4. Premi **Play** per provare, poi **File → Save / Publish** per salvare PLACE1.

Crea da solo i 3 script qui sotto (se esistono già li sostituisce).

### Metodo manuale

Crea questi 3 script con **esattamente** questi nomi:

| Dove (Explorer) | Tipo | Nome | Contenuto da incollare |
| --- | --- | --- | --- |
| `ReplicatedStorage` | ModuleScript | `StickBallConfig` | [`src/ReplicatedStorage/StickBallConfig.lua`](src/ReplicatedStorage/StickBallConfig.lua) |
| `ServerScriptService` | Script | `StickBallServer` | [`src/ServerScriptService/StickBallServer.server.lua`](src/ServerScriptService/StickBallServer.server.lua) |
| `StarterPlayer` → `StarterPlayerScripts` | LocalScript | `StickBallClient` | [`src/StarterPlayerScripts/StickBallClient.client.lua`](src/StarterPlayerScripts/StickBallClient.client.lua) |

Poi premi **Play**. La palla compare 15 stud davanti allo `SpawnLocation`. Se
vuoi deciderne tu la posizione, metti nel Workspace una parte chiamata
`BallSpawn` (Anchored, CanCollide off, trasparente).

## In alternativa: Rojo

Dalla cartella `PLACE1`:

```sh
rojo serve
```

poi in Studio, con PLACE1 aperto, clicca **Connect** nel plugin Rojo.
`default.project.json` sincronizza solo i 3 script, il resto di PLACE1 non viene toccato.

## Regolare la meccanica

Tutti i numeri sono in `StickBallConfig`:

- `Bar.Length`, `Bar.Thickness`, `Bar.Height`: dimensioni della sbarra.
- `Bar.Side`: `1` sbarra a destra, `-1` a sinistra.
- `Ball.Diameter`, `Ball.Density`, `Ball.Elasticity`: peso e rimbalzo della palla.
- `Ball.RollingDeceleration`: quanto velocemente la palla si ferma rotolando.
- `Spin.SwingSpeed`, `Spin.SwingAngle`: velocità e ampiezza del colpo col click.
- `Spin.HoldSpeed`: velocità di rotazione con Q/E.
- `Hit.Restitution`, `Hit.Lift`, `Hit.MaxBallSpeed`: potenza dei colpi.

## Come funziona

- **Server** (`StickBallServer`): salda la sbarra all'`HumanoidRootPart` di ogni
  personaggio, all'altezza del terreno (funziona con R15 e R6). Crea la palla e la
  fa simulare al giocatore più vicino (network ownership), così chi colpisce la
  vede partire senza lag. Se la palla cade dalla mappa la rimette allo spawn.
- **Client** (`StickBallClient`): fa girare il personaggio (colpo / Q / E) e a
  ogni frame controlla se la sbarra, muovendosi, ha toccato la palla. Il movimento
  viene diviso in piccoli passi, così anche un giro velocissimo non passa
  attraverso la palla. Al contatto la palla prende la velocità della sbarra in
  quel punto: la punta colpisce più forte del centro.
- La sbarra non ha collisioni fisiche (`CanCollide = false`): scorre a terra
  senza incastrarsi. Il corpo del personaggio invece spinge la palla normalmente.
