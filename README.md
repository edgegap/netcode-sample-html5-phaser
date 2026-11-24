# HTML5 Multiplayer Game Tutorial: Phaser + Node.js WebSockets on Edgegap

**Splat Arena** is a small 2D HTML5 multiplayer game you can read in one sitting and copy into your own project. It's a paintball free-for-all for 1 to 8 players:

- The browser client is [Phaser 4](https://phaser.io), with no bundler and no build step.
- Each match runs on its own authoritative Node.js WebSocket server, started by [Edgegap](https://edgegap.com) close to the players.
- Players get into a match with **Find match**, which uses the [Edgegap matchmaker](https://docs.edgegap.com/learn/matchmaking).

```
browser (Phaser, HTML5 canvas) --Find match--> Edgegap matchmaker --starts a server near the players--> Edgegap
browser <-- wss://<id>.pr.edgegap.net:<port> --
browser --inputs (keys, aim, fire)--> Node.js game server (one per match) --20 snapshots/s--> browser
                                      match over --> the server stops itself, billing stops
```

What this tutorial covers:

- **Authoritative server.** The server moves everyone, fires the paint, decides hits and keeps score. The browser only sends intents (keys, aim angle, fire) and draws what it receives, so editing the page in devtools can't make a player faster or score a hit.
- **Smooth rendering from 20 Hz snapshots.** The client eases each player toward the latest server position and moves bullets along their velocity between updates.
- **Bots.** A lone player gets a match after 20 seconds, with bots filling the arena up to 4 players.
- **Matchmaking from the browser** through the [Edgegap JS SDK](https://github.com/edgegap/sdk-js-sessions-matchmaker-server-browser), loaded from a CDN with an import map.
- **`wss://` from an `https` page.** Edgegap terminates TLS on the port (TLS Upgrade), so the Node server stays plain `ws`.
- **One server per match that stops itself** when the match ends, so you only pay while people play.

| Folder | What's in it |
|---|---|
| [`client/`](client) | The HTML5 game: `index.html`, `main.js` (menu, Find Match, connection), `scene.js` (the Phaser scene), `net.js` (WebSocket with retries). A static page you host anywhere. |
| [`server/`](server) | The Node.js game server: `game.js` (all the rules), `room.js` (players, phases, broadcast), `edgegap.js` (deployment info, self-stop), `main.js`. |
| [`matchmaker/`](matchmaker) | Edgegap matchmaker configuration. |
| [`tools/`](tools) | Headless players: `npm test` plays a full match locally; `e2e.mjs` tests a real deployment or the matchmaker. |
| [`Dockerfile`](Dockerfile) | The server image Edgegap runs. |

## 1. Run it locally (no account needed)

You need [Node.js 22+](https://nodejs.org).

```bash
git clone https://github.com/edgegap/netcode-sample-html5-phaser.git
cd netcode-sample-html5-phaser
npm install
npm start          # game server on ws://localhost:7777
```

In a second terminal, serve the page:

```bash
npm run client     # http://localhost:8080
```

Open http://localhost:8080 in two browser tabs and click **Local server :7777** in both. The match starts 15 seconds after the first player joins, with bots filling up to 4 players. Controls: WASD or the arrow keys to move, the mouse to aim, click or Space to fire. First to 10 hits wins.

`npm test` plays a whole match with two headless players and checks it ends with a winner.

## 2. How the multiplayer works

### The protocol

JSON text frames over one WebSocket:

| Direction | Message |
|---|---|
| client → server | `{t:"hello", name, ticket}` once, then `{t:"input", mx, my, aim, fire}` when input changes (at most ~30/s), plus `{t:"ping"}` every 5 s |
| server → client | `{t:"welcome", id, info}` once (arena size and walls), then `{t:"state", phase, timer, players, s}` 20 times a second |

`s` is the snapshot: players `{id, x, y, a, d, sh}` (position, aim, down, spawn shield), bullets `{id, o, x, y, vx, vy}` and paint splats `fx` since the last snapshot. Numbers are rounded to keep it small.

### The server owns the game ([`server/game.js`](server/game.js))

```js
input(p, msg) {
  // Clamp everything that comes from the network.
  b.input = { mx: axisIn(msg.mx), my: axisIn(msg.my), aim: angleIn(msg.aim), fire: msg.fire === true };
},
update(dt, room) {
  // Movement speed, fire rate, bullet travel and hits are all decided here, 30 times a second.
}
```

[`server/room.js`](server/room.js) runs the match: `waiting → countdown → playing → over`, adds bots, broadcasts state, and on Edgegap stops the deployment when the match is over, when nobody joined within 2 minutes, or when everyone left for 30 seconds.

### The client only draws ([`client/scene.js`](client/scene.js))

```js
// Every frame: ease toward the latest server position (snapshots arrive every 50 ms).
p.view.x += (p.x - p.view.x) * t;
// Bullets keep moving along their velocity between snapshots.
b.x += b.vx * dt;
// Send intents, never positions.
this.match.send({ mx, my, aim, fire });
```

Your own barrel follows the mouse right away, so aiming feels instant; the server still decides where the shots go.

### Using another HTML5 engine

Only `client/scene.js` depends on Phaser. You can swap it for a plain `<canvas>` 2D context, PixiJS, Kaboom/Kaplay or Three.js and keep `main.js`, `net.js` and the whole server as they are. For a 3D version, see [netcode-sample-threejs-minigames](https://github.com/edgegap/netcode-sample-threejs-minigames).

## 3. Host the server on Edgegap

Create a free account at [app.edgegap.com](https://app.edgegap.com).

1. **Build and push the image** (Docker, logged in to your Edgegap Container Registry from the dashboard):

   ```bash
   docker build --platform linux/amd64 -t registry.edgegap.com/<project>/splat-arena:20261124-1200 .
   docker push registry.edgegap.com/<project>/splat-arena:20261124-1200
   ```

   Use a new tag for every build (the UTC time works well), never `latest`.

2. **Create an application** `splat-arena` with a version named after the tag:

   | Setting | Value |
   |---|---|
   | Image | `registry.edgegap.com/<project>/splat-arena:<tag>` |
   | Port | `7777`, protocol **WS**, name `gameport`, **TLS Upgrade on** |
   | Resources | 0.25 vCPU / 512 MB |
   | Max duration | 30 minutes (a safety net: the server stops itself) |
   | Restart policy | Never |

3. **Try one server directly.** Deploy the version from the dashboard and copy its `wss://<id>.pr.edgegap.net:<port>` address. Then open `http://localhost:8080/?server=wss://<id>.pr.edgegap.net:<port>` in two tabs, or run:

   ```bash
   SERVER_URL=wss://<id>.pr.edgegap.net:<port> node tools/e2e.mjs 2
   ```

   The deployment stops itself about 12 seconds after the match ends.

   **On Windows**, `.\tools\edgegap-test.ps1 all` does steps 1 to 3 in one go: it asks for your API token and registry credentials (kept in that PowerShell window only), builds and pushes the image with Docker (Docker Desktop, or Docker Engine in WSL), creates the app and version, deploys near you, prints the `wss://` URL and waits for the server to stop itself.

## 4. Add matchmaking

1. Edit [`matchmaker/splat-arena.json`](matchmaker/splat-arena.json):
   - set `application.version` to your version name;
   - list every origin your page is served from in `allowed_cors_origins` (scheme + host + port, for example `http://localhost:8080` or `https://<you>.github.io`).
2. In the dashboard, go to **Matchmaker → Create**, upload the file, then click **Create and Start**. Copy the **API URL** and **Auth Token** into [`client/config.js`](client/config.js), or into `client/config.local.js` (git-ignored). The Auth Token is made to ship in game clients. Never put your Edgegap API token in the page.
3. Click **Find match** in two tabs within 20 seconds. Both land on the same new server, close to you. A lone player gets a match with bots after 20 seconds.

To test the matchmaker from the command line:

```bash
MM_URL=<api url> MM_TOKEN=<auth token> node tools/e2e.mjs splat-arena 2
```

Before launch: set `"inspect": false`, list only your real origins, and set `REQUIRE_TICKET=1` on the app version so only matched players can join.

## 5. Publish the page

The client is static files. [`.github/workflows/pages.yml`](.github/workflows/pages.yml) publishes `client/` to GitHub Pages once you turn Pages on (Source: GitHub Actions) and set the repository variable `PAGES_ENABLED` to `true`. You can also upload the folder to itch.io as an HTML5 game; add `https://html-classic.itch.zone` to `allowed_cors_origins` if you do. [`.github/workflows/server-image.yml`](.github/workflows/server-image.yml) tests the server and pushes a new image on every change.

## Server settings

Environment variables on the app version (all optional):

| Variable | Default | Meaning |
|---|---|---|
| `WAIT_SECONDS` | 15 | Wait after the first player joins (not used when the matchmaker says how many are coming) |
| `MATCH_SECONDS` | 120 | Match length if nobody reaches 10 hits |
| `RESULTS_SECONDS` | 12 | Results screen before the server stops |
| `FIRST_JOIN_TIMEOUT_S` | 120 | Stop if nobody joins |
| `EMPTY_TIMEOUT_S` | 30 | Stop when everyone has left |
| `IDLE_TIMEOUT_S` | 0 (off) | Drop a player who sent nothing for this long |
| `REQUIRE_TICKET` | off | `1` = only players with a matchmaker ticket for this match can join |

## FAQ

**Is this "real" HTML5, or Unity WebGL?** Real HTML5: JavaScript, a `<canvas>` drawn by Phaser, and a WebSocket. No engine export or plugin. If your game is made in Unity, see [netcode-game-sample-webgl-mirror-tanks](https://github.com/edgegap/netcode-game-sample-webgl-mirror-tanks).

**Why not socket.io?** Browsers have WebSocket built in, and on the server the `ws` package is all this needs. Socket.io works on Edgegap too, with the same WS + TLS Upgrade port.

**Why one server per match instead of one big server?** Each match runs close to its players (lower ping), a crash only affects one match, and there's no room routing or capacity planning. Billing is per running server, and each server stops itself when its match ends.

**Can players cheat?** They can change anything in their own browser, but the server ignores everything except clamped inputs. Movement speed, fire rate and hits are all decided on the server.

**I use Colyseus.** See [backend-game-sample-threejs-colyseus-tanks](https://github.com/edgegap/backend-game-sample-threejs-colyseus-tanks).

## Learn more

- [Edgegap docs: HTML5 Multiplayer (Phaser)](https://docs.edgegap.com/docs/sample-projects/web-games/html5-phaser), the step-by-step version of this README
- [`edgegap-html5` agent skill](https://github.com/edgegap/llm-agent-skills): lets a coding agent apply this sample to your own HTML5 game
- [Edgegap deployments](https://docs.edgegap.com/learn/orchestration/deployments) and [matchmaking](https://docs.edgegap.com/learn/matchmaking)
- [Edgegap JS SDK](https://github.com/edgegap/sdk-js-sessions-matchmaker-server-browser) (`@edgegap/sdk` on npm)
- [Edgegap MCP server](https://github.com/edgegap/llm-mcp-server): let a coding agent build, deploy and test this for you
- [Phaser documentation](https://docs.phaser.io)

## License

MIT. See [LICENSE](LICENSE).
