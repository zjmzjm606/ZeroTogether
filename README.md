# ZeroTogether

English | [简体中文](README.zh-CN.md)

## ⬇️ [Download ZeroTogether_v10.1.zip](https://github.com/zjmzjm606/ZeroTogether/raw/main/release/ZeroTogether_v10.1.zip)

Unzip into the game's root folder `PBZ\` and overwrite. Needs UE4SS for Phantom Blade Zero 1.0.3 (Vercadi) and the official Phantom Pact 1.7.4 first (see [Install](#install)). Every player in the session needs it.

**ZeroTogether** is an extended, unofficial fork of [Phantom Pact](https://github.com/yhsharaf/PhantomPact) by
yhsharaf, the online co-op mod for **Phantom Blade Zero**. Everything Phantom Pact does is still here, plus the additions
and fixes below. ZeroTogether is not made or endorsed by yhsharaf or by S-GAME; the credit for Phantom Pact itself goes to
its author.

> These changes are new and still being tested in play. Please report problems with ZeroTogether's additions in
> [this repository's issues](https://github.com/zjmzjm606/ZeroTogether/issues), not to Phantom Pact.

## What ZeroTogether adds

**New**

- **Names and health over heads:** each partner's name, in their player colour (red while they're down), with a health
  bar above their figure. Shown up to 60 m away, fading from 45 m.
- **Party list:** down the left of the screen, you first, then each partner: name, health and 血气 (the game's ShaChi,
  the bar under health) in numbers, with a bar for each. A row turns grey while that partner is on another map, in a
  cutscene, or not responding.
- **Your own name:** set `PlayerName` in `PhantomPact.ini`, up to 16 characters (Chinese works). The others see the new
  name within a few seconds; no restart needed.
- **Better bars:** a thin dark frame, a visible empty track, a damage trail that holds for a moment after a hit and then
  runs down, and a soft shine along the top.
- **Down in a boss fight:** while you wait for the fight to end, the boss bar stays up, and the sound follows the camera
  on your partner. When your partner lands the final blow on the last boss, you're revived beside them first, so the
  boss's victory and its cutscene play for you too (`BossWinRevive`).
- **Hide the co-op UI:** F9 hides the names and the party list, and shows them again (`HideUIKey`). The party list now
  starts higher on the screen, and you can move it (`PartyBarsY`).
- **Choose who F3 takes you to:** in a party of three or more, Shift+F3 cycles through "nearest partner" and each
  player. The chosen one has a » in the party list. F3 falls back to the nearest one if they're down or gone.
- **Reset key:** F10 gets you out of a stuck moment (`ResetKey`): it closes any item card, gives the controls back,
  stops your own animation, and makes a door near you passable if it was opened by a partner but never moved for you.

**Fixed**

- **A guest can't move or press anything after first joining.** The F5 panel switches the controls to menu-only mode.
  On a guest's first join the game loads them into the host's world, which replaces the player controller, and the
  panel then closed without giving the controls back. It now gives them back on the current controller, or as soon as
  there is one. Fixed in the online, PvP and local co-op panels.
- **Executions cut short on the other screen.** A death that arrived in the middle of an execution stopped the enemy's
  animation at once, and a guest's killing blow carried no animation for the host to play. The death now waits for
  the execution to finish (up to 2.6 s).
- **Two boss health bars online.** The game's own bar and the mod's bar for a partner's fight could both stay up. One
  bar per boss is kept now, and the one kept follows the shared fight's health.
- **An enemy back at full health when the host arrives.** With the host far off (over about 120 m), the host doesn't
  share the enemies around the guest, so the guest's hits never reached the host's world. When the host came near, its
  whole copy took over. Now the health the guest took off is carried over to the host's copy the moment the two pair up.
- **Frozen by an item card.** The game can leave a loot card on screen with no button, so no key closes it. Such a card
  is now closed on its own after 3 seconds (the item is already in the bag). F10 closes any card at once.
- **Some doors only the first player can open.** A partner's door was opened in your world without its scene, and some
  doors only move in that scene: it stayed shut, with no prompt left to press. If none of its parts moved 2 seconds
  later, the door is made passable for you.

## Install

1. Install **UE4SS for Phantom Blade Zero** (Vercadi, Nexus Mods) 1.0.3 or newer, and **Phantom Pact 1.7.4**, as
   [INSTALL.md](INSTALL.md) describes. ZeroTogether needs Phantom Pact's built `main.dll`, which is in its release and
   not in this source tree.
2. Download the packaged [ZeroTogether_v10.1.zip](https://github.com/zjmzjm606/ZeroTogether/raw/main/release/ZeroTogether_v10.1.zip) and unzip it into the game's root folder `PBZ\`, overwriting. Or download this repository (**Code → Download ZIP**) and copy `mod/PBZCoop/Scripts` and `mod/PBZCoop/art` into
   `PBZ\platform\steam\ue4ss\Mods\PBZCoop\`, replacing files. Your `PhantomPact.ini` is left as it is.
3. Every player should install ZeroTogether: names, 血气 and the guest-side fixes need it on both PCs. A player without
   it still links up, and shows up as "Host" / "Player 2" with health only.

## New settings (`PhantomPact.ini`)

ZeroTogether adds these lines at the end of the file on first start. Each PC has its own.

| Setting | Default | What it does |
| --- | --- | --- |
| `PlayerName` | empty | Your name on the others' screens. Empty: "Host" / "Player 2"... |
| `Nameplates` | `On` | Names and health over the other players. |
| `PartyBars` | `On` | The list down the left of the screen. |
| `BossWinRevive` | `On` | Revive a downed player when the last boss falls, so they see its ending. `Off`: respawn at the bell as before. |
| `PartyBarsY` | `22` | Where the party list starts, in percent of the screen's height from the top. |
| `HideUIKey` | `F9` | Hides and shows the names and the party list. |
| `ResetKey` | `F10` | The reset key above. |

## What changed in the code

| File | |
| --- | --- |
| `Scripts/nameplates.lua` | New: names, health and 血气 over heads and in the party list; the `NAME` and `QI` messages. |
| `Scripts/bossbars.lua` | New: one boss bar per boss online. |
| `Scripts/downed.lua` | New: boss bar, sound and revive for a player down in a boss fight. |
| `Scripts/rescue.lua` | New: stuck item cards closed on their own; the reset key. |
| `Scripts/blockers.lua` | A partner's door that didn't move here is made passable. |
| `Scripts/partner.lua` | Shift+F3 chooses the F3 target. |
| `Scripts/coop.lua` | Executions finish before the death; the revive before a boss's death; a guest's damage on an enemy the host didn't share is carried over. |
| `Scripts/main.lua` | Loads the new modules, each on its own, so an error in one leaves the rest running. |
| `Scripts/panel.lua`, `onlinepanel.lua`, `pvppanel.lua` | Controls given back after a load. |
| `art/nameplate/bar.png` | The bars' texture. |

## Credits

- **Phantom Pact:** yhsharaf and its contributors ([original repository](https://github.com/yhsharaf/PhantomPact)).
  ZeroTogether is built on it.
- **UE4SS for Phantom Blade Zero:** Vercadi (Nexus Mods). **UE4SS:** the UE4SS team (MIT License).
- Fan-made, not affiliated with or endorsed by S-GAME.

---

*The original Phantom Pact README follows.*

<p align="center">
  <img src="art/phantom-pact-banner-1300x372.png" alt="Phantom Pact: Online Co-op for Phantom Blade Zero" width="100%">
</p>

# Phantom Pact: online co-op for Phantom Blade Zero

English | [简体中文](README.zh-CN.md)

Phantom Pact adds online co-op to **Phantom Blade Zero**. Two players each run their own game and keep their own
save, and Phantom Pact links the two worlds: you see each other, fight the same enemies, take on bosses as a team,
share loot and dust, and regroup at bells. The host's world leads, and your partner joins in.

**Download:** [latest release](https://github.com/yhsharaf/PhantomPact/releases/latest) · **Install and play:**
[INSTALL.md](INSTALL.md) · **Found a bug?** [Open an issue](https://github.com/yhsharaf/PhantomPact/issues/new/choose)

## Features

- See your partner's Soul live, with their moves, attacks, dodges and hit reactions
- Shared enemies in both worlds, with shared health, posture and executions
- Your partner's hits count in the host's world, so you can fight the same enemy together
- Your partner's hits on enemies play the game's own hit sound and blood on your screen too (new in 1.7.1)
- Shared boss fights: the boss health bar and arena fog walls for both players
- Boss fights wait for everyone: die and you watch your partner until it's over; join during one and you watch, then go to them
- Shared loot and dust: what either player picks up or earns goes to both
- Bells bring you together: sit at one and a partner who's dead or watching a fight comes to you. Each player rests at their own sit, as in the game; a partner fighting a boss when you sit starts the fight over, rested, with the boss back to full health
- Elden Ring–style co-op difficulty: enemies and bosses get more health and posture while you play together online
- PvP matches (F6, new in 1.7.0): duels (best of three) and death matches, one on one or two teams of up to six, in four
  of the game's own boss arenas or where the host stands. Fair for everyone: the same body and level-30 weapons of your own
  choosing, three drinks of one gourd, a brush-stroke countdown, each foe on the game's own boss health bar, a clock or none, and a boss's move to finish
  the loser. Nothing is saved, and everything goes back after ([docs/PVP.md](docs/PVP.md))
- PvPvE (MORE > PvPvE): fight your partner in the open world, enemies and all: the game's own block, parry and dodge;
  parries stagger the attacker; the loser dies
- A partner compass in the game's ink style, your partner on the map in jade, partner tips, and spectating your
  partner while you're down
- Optional `Secret` that signs every packet; works over Tailscale, Hamachi, Radmin, ZeroTier, UU Accelerator, and
  Steam (beta)
- English, 中文 and العربية (Arabic, new in 1.7.2): the F5 panel, the PvP page and the mod's tips in your language
- Local co-op (F5 > MORE > Mode > LOCAL, in testing): two players on one PC in split screen, one pad each or keyboard plus
  pad, or each on a monitor of their own (F4 panel, or `Monitors = 2`, new in 1.7.2). Player 2 climbs, opens chests, rings bells, drinks and fights on their own, with the game's own HUD, button prompts,
  boss bars and execution points in their half of the screen, and one shared backpack, out of which they wear and hold
  their own: outfit, weapons and talismans, picked in the game's own menu from their own pad's Options
  ([docs/LOCAL_COOP.md](docs/LOCAL_COOP.md))
- 4 players (beta) and 6 players (experimental): the host picks Players under MORE in the F5 panel, and up to three or
  five guests can join. Enemies and bosses get 50% more health for each person connected, up to four players. With five or
  six, every enemy and boss gets a cyan ghost twin with red eyes instead: two bosses in each arena
  ([INSTALL.md](INSTALL.md#4-players-beta-and-6-players-experimental))

## Quick start

1. Install [UE4SS for Phantom Blade Zero](https://www.nexusmods.com/phantombladezero/mods/5) and [Tailscale](https://tailscale.com) (both players).
2. Extract the release zip into the game's `PBZ` folder.
3. In `platform\steam\ue4ss\Mods\PBZCoop\PhantomPact.ini`: host sets `Role = Host`, guest sets `Role = Guest` and
   `HostAddress` to the host's Tailscale IP.
4. Start the game and load your saves, the host first. Co-op starts by itself. Or press F5 in the game for the online panel: Host or Guest with no text file.

Early release, 2 players (4 in beta). Tailscale or any virtual LAN; Steam joining is in beta (see INSTALL.md).

Both players must use the same version: this version has a new connection, and 1.7.3 or older can't connect to it. No Python
needed: the connection runs inside the game. Can't connect, or it feels laggy? See Connection problems in
[INSTALL.md](INSTALL.md#connection-problems).

For two players on one PC, it's in the same download: press F5 in the game, then MORE > Mode > LOCAL, restart the game and
plug in two pads (`Role = Local` in the ini does the same): see [docs/LOCAL_COOP.md](docs/LOCAL_COOP.md).

## Ground rules

- **No DRM bypassing.** Phantom Pact never touches Denuvo or patches the game executable. Everything loads
  through UE4SS and runs inside the normal, legitimately owned game.
- Each player needs their own copy of the game.
- Nothing here contains game files or assets.

## For developers

| Path | What it is |
|---|---|
| [mod/PBZCoop/](mod/PBZCoop/) | UE4SS Lua mod: `coop.lua` (online sync), `pbz.lua` (game adapter: enemies, health, moves, bosses, items), `localcoop.lua` (split screen: player 2's controls, interactions, enemies), `panel.lua` (local co-op F4 panel), `onlinepanel.lua` (online F4 panel: host, join, leave), `autostart.lua` (reads `PhantomPact.ini`, starts the relay, turns sync on), `main.lua` (loader, commands) |
| [native/](native/) | The relay: C++, loaded by UE4SS as `dlls\main.dll` inside the game. Build with `tools\build-native.ps1` (Visual Studio 2022). `native\build\relay_cli.exe test` runs its tests; `relay_cli.exe` is never shipped |
| [tools/netlab/](tools/netlab/) | Online co-op test bench: relay tests through a bad connection, and real game copies from a separate install ([README](tools/netlab/README.md)) |
| [tools/install-mod.ps1](tools/install-mod.ps1) | Installs the mod into the game's UE4SS `Mods` folder (finds the game through Steam) |
| [tools/pbz-e2e.ps1](tools/pbz-e2e.ps1) | End-to-end test: two copies of the game on one PC, PASS/FAIL per feature. Each copy's ini starts its relay, as for players |
| [tools/pbz-selftest.ps1](tools/pbz-selftest.ps1) | Starts two copies with `-allowmultipleinstances`, each with an ini for its role; `-Connect Udp\|Steam`, `-Cuttable`, `-Stop` |
| [tools/make-release.ps1](tools/make-release.ps1) | Builds `dist\PhantomPact-<version>.zip` |
| [docs/NETCODE.md](docs/NETCODE.md) | How online co-op works now: protocol 3, packets, the sure and quick lanes, measurements, testing |
| [docs/AUTHORITY.md](docs/AUTHORITY.md) | Which PC decides what, how duplicates are prevented, who may talk to the relay |
| [docs/COOP_GUIDE.md](docs/COOP_GUIDE.md) | What syncs and how: enemy matching, tests and results |
| [docs/RECON_NOTES.md](docs/RECON_NOTES.md) | Classes, functions and data tables found in the game |
| [docs/LOCAL_COOP.md](docs/LOCAL_COOP.md) | Local co-op: setup, player 2's controls, what the game hardwires to player 1 and how the mod bridges it |
| [docs/PVP.md](docs/PVP.md) | PvP matches (F6): the rules, who decides what, the `AR` events, the network in a match, fair play and putting it all back (`arena.lua`, `arenas.lua`, `arenaui.lua`, `pvppanel.lua`) |
| [tools/localcoop/](tools/localcoop/) | Local co-op test tools: launcher, command runner, Lua probes for enemies and fight areas, soak |

## Credits

- **[appdoze](https://github.com/appdoze)**, for the relay security review and code: packet signing, sender
  filtering, event value checks, faster sending, the settings handshake, in-game status tips, the partner on the map, enemies gliding back on the guest, and smoother partner
  movement
- **[EXACG](https://github.com/EXACG)**, for the four-player design and code (PR #11): the host passing players on to
  each other, a ghost, a compass dot and a map pointer for each partner, tips for each partner, enemy health that grows
  with each player, the `units` check on the real game, and the check that every event has one handler
- **Vercadi**, for UE4SS for Phantom Blade Zero, which made modding this game possible
- **The UE4SS team** ([RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS))
- **S-GAME and the game's developers** for Phantom Blade Zero

*Fan-made mod, not affiliated with or endorsed by S-GAME.*
