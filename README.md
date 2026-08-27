# Overseer

Overseer is a native macOS app for keeping an eye on a vanilla Minecraft Java server. It watches your server live, keeps a history of what happened, and gives you tools to manage it — all without installing any plugins on the server itself.

Everything here talks to a **strictly vanilla** server. No mods, no plugins required.

## What it does

The sidebar is organized into these sections:

- **Dashboard** — live player count, ping, MOTD, and uptime at a glance.
- **Players** — the current online roster, with quick actions (kick, ban, give item, etc.) from a right-click menu.
- **Leaderboards** — read-only rankings (playtime and more) built from data the app already collects.
- **Broadcasts** — admin-authored chat messages that repeat on their own schedule, plus a manual "Send Now".
- **Access Control** — bans, temp-bans, and the whitelist in one screen, instead of reading raw `/banlist` text.
- **Schematic Builder** — load a Sponge Schematic (`.schem`) file and stream it into the world over RCON, block by block.
- **Inventory Analyzer** — search every player's inventory at once for a specific item (from a downloaded copy of the world save) — the real workflow behind a "someone stole my stuff" report.
- **Playtime Importer** — reconciles the app's tracked playtime against vanilla's own stats files, for gaps left by app restarts or crashes.
- **Performance** — reads a `/perf` report and shows what's actually causing lag: entity/chunk hotspots, tick times, and a profiler breakdown, plus a compare-two-reports view.
- **Entity Management** — a strictly-vanilla "clear lag" tool: periodically sweeps dropped items, XP orbs, and (optionally) stray projectiles/TNT/hostile mobs.
- **Location** — where players actually connect from (from server logs), used to time advertising for your actual audience's timezone.
- **World Map** — a top-down map built from your server's real world files, with player movement trails (12-hour retention) to help investigate griefing.
- **Server History** — long-term charts (player counts, ping, tick time), a weekly activity heatmap, an event timeline, and a predictor for the best times to advertise your server.
- **RCON Console** — run server commands directly, with a safe command queue so commands never collide.
- **Settings** — all connection details, plus the **Auto Updater** *(off by default)*, which checks Mojang for new snapshots and can deploy them automatically. This is a serious, no-confirmation feature — read the warning in Settings before turning it on.

Also included: a menu bar widget for quick status checks, and Siri/Shortcuts support ("what's my server's player count?").

## Requirements

- macOS 14 (Sonoma) or later.
- A Minecraft Java Edition server you control.
- Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you want to build from source.

## Running it

**Option 1 — use the prebuilt app.** Open `Overseer.app` in this folder. Since it isn't signed by an Apple developer account, the first time you open it, right-click (or Control-click) it and choose **Open**, then confirm.

**Option 2 — build it yourself.**
```bash
brew install xcodegen
xcodegen generate
open Overseer.xcodeproj
```
Then build and run the `Overseer` scheme in Xcode (⌘R).

## Configuring your server

Every connection field starts **empty** — there are no server details or passwords baked into this project. Open Overseer, go to **Settings**, and fill in your own:

| Setting | What it's for | Notes |
|---|---|---|
| Host / Port | Live status polling (GS4 Query + Server List Ping) | Default Java port is `25565`. Your server needs `enable-query=true` and a `query.port` set in `server.properties`. |
| RCON Host / Port / Password | Running commands, automation, moderation | Needs `enable-rcon=true`, `rcon.port`, and `rcon.password` set in `server.properties`. |
| SFTP Host / Port / Username / Password | World Map, log/inventory/performance sync, Auto Updater | Optional — only needed for the features that read files directly off the server. |

Passwords are saved in the macOS Keychain, never in a plain settings file.

Some features (Inventory Analyzer, Performance, Playtime Importer, Location) can work either from a manually-downloaded folder or, if you set up SFTP, from an automatic sync — turn on only what you actually want, since SFTP sync and the Auto Updater both touch files on your live server and are off by default.

## A note on the Auto Updater

If you turn it on, it will automatically download new Minecraft snapshots, upload them over SFTP, and stop your server (via RCON) so your host can restart it on the new version — with no backup and no confirmation step. Read the explanation in Settings before enabling it, and make sure your hosting setup actually restarts the server automatically after it stops.

## License

MIT License
