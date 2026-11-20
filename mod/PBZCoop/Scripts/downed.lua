-- Down in a boss fight a partner is still in. A patch on Phantom Pact 1.7.4, not part of the mod itself.
--
-- The mod holds the respawn of a player who falls in a boss fight till it's over, and the camera follows a partner who's
-- still up (coop.lua's holdForFight, pbz.lua's spectate). Three things more here:
--   The boss bar. The game takes its bars down as its player dies (coop.lua's IN_FIGHT_S note): put back, for the bosses of
--     the fight that player was in and of the partners' fights, while the respawn is held; its health is the fight's (the
--     copy follows). The HUD itself, if the game hid it, is shown. What's put up here comes down once they're up again,
--     unless a fight of theirs or a partner's still has it.
--   The sound. While the camera follows a partner, the game's ear (the player controller's audio listener) goes with the
--     camera, not with the body lying where it fell: SetAudioListenerOverride on the camera, put back as it was after.
--   The boss's fall. A boss that falls with its player dead runs its death another way in that world: no win's steps, no
--     scene after it (flowsync.lua's note of the bench, 11-12), and the respawn never brings them. So when the partner's
--     blow is the last boss's end, this player is brought back on their feet beside the partner first (the steps local
--     co-op brings player 1 back with, localcoop.lua's revivePlayer1), and the boss falls a moment later: its whole win,
--     its scene too, as for a player who was up. coop.lua's handlers.K (a guest down) and handlers.D (a host down) ask
--     here first. BossWinRevive = Off in PhantomPact.ini: the respawn at the bell as before.
-- And once each time this player goes down in a fight, the log says how the game's sound stood (for a later fix, if the
-- game's own death silences it another way): the listener, and the Wwise states named for death.

return function(api)
    local log, valid, game = api.log, api.valid, api.game
    local coop = api.coop
    local net = coop.net

    local D = {
        LOOK_S = 0.25, BAR_S = 1.0, INI_S = 3.0, WIN_AFTER_S = 0.4, BESIDE_CM = 150, DIAG_S = 3.0,
        revive = true, iniAt = 0, barAt = 0, wasDownAt = nil,
        shown = {},                 -- boss address -> { actor, fname }: bars put up here
        ear = nil,                  -- the listener as it was before the camera took it: { on, comp, loc, rot }
        frozen = nil,               -- a death screen left held after a revive here: { addr, vis }
        told = false,
    }
    net.winHeld = net.winHeld or {}

    ------------------------------------------------------------------ settings

    local function readIni()
        local f = io.open(api.modDir() .. "PhantomPact.ini", "rb")
        if not f then
            return nil
        end
        local text = f:read("a") or ""
        f:close()
        local s = {}
        for line in text:gsub("^\239\187\191", ""):gmatch("[^\r\n]+") do
            local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
            if key and not line:match("^%s*[;#]") then
                s[key:lower()] = value
            end
        end
        return s
    end

    local function lookAtIni()
        local s = readIni()
        if not s then
            return
        end
        if s.bosswinrevive == nil and not D.added and api.panel and api.panel.kit and api.panel.kit.save then
            D.added = true
            pcall(api.panel.kit.save, { BossWinRevive = "On" })
        end
        D.added = true
        D.revive = (s.bosswinrevive or "on"):lower() ~= "off"
    end

    ------------------------------------------------------------------ the fight's bosses

    -- Bosses of the fight this player fell in and of the partners' fights, alive, by id.
    local function fightBosses()
        local out = {}
        for _, set in ipairs({ net.fightNames or {}, net.partnerBosses or {}, net.hostBosses or {} }) do
            for name in pairs(set) do
                local a = coop.enemyActor(name)
                if valid(a) and not game.isDead(a) then
                    out[name] = a
                end
            end
        end
        return out
    end

    local function fnameOf(a)
        return select(2, pcall(function() return a:GetFName():ToString() end))
    end

    local function hudBars(hud)
        local out = {}
        pcall(function()
            local list = hud:GetBossHPBarInstances()
            for i = 1, #list do
                local bar = nil
                pcall(function() bar = list[i]:get() end)
                if valid(bar) then
                    out[#out + 1] = bar
                end
            end
        end)
        return out
    end

    local function barFor(bars, addr)
        for _, bar in ipairs(bars) do
            local who = nil
            pcall(function() who = bar.Character end)
            if valid(who) and who:GetAddress() == addr then
                return bar
            end
        end
        return nil
    end

    -- Each boss of the fight with its bar on screen: one the HUD still has but hid, shown again; one it took down, put
    -- back (pbz.lua's keepBossBar, which looks for it on the HUD itself, not at the mod's own note of it); and the HUD
    -- shown and opaque, if the game put it away for the death.
    local function keepBars(bosses)
        local hud = FindFirstOf("PBZHUDLayout")
        if not valid(hud) then
            return
        end
        pcall(function()
            local vis = hud:GetVisibility()
            if vis == 1 or vis == 2 then
                hud:SetVisibility(4)
                log("Down: the game had put the HUD away (" .. vis .. "); shown for the boss's bar.")
            end
            if hud:GetRenderOpacity() < 0.5 then
                hud:SetRenderOpacity(1.0)
                log("Down: the HUD was see-through; made solid for the boss's bar.")
            end
        end)
        local bars = hudBars(hud)
        for name, a in pairs(bosses) do
            local addr = a:GetAddress()
            local bar = barFor(bars, addr)
            if bar then
                local vis = select(2, pcall(function() return bar:GetVisibility() end))
                if vis == 1 or vis == 2 then
                    pcall(function() bar:SetVisibility(4) end)
                    log("Down: " .. name .. "'s bar was hidden (" .. vis .. "); shown again.")
                end
            else
                if game.keepBossBar then
                    game.keepBossBar(a)
                else
                    game.showBossBar(a)
                end
                if barFor(hudBars(hud), addr) then
                    D.shown[addr] = { actor = a, fname = fnameOf(a), name = name }
                    log("Down: " .. name .. "'s bar is up again while you wait.")
                end
            end
        end
    end

    -- Every DIAG_S while down in a fight: how it all stands, for the log (the next fix reads it).
    local function diag(pc, bosses)
        local parts = {}
        parts[#parts + 1] = "held " .. tostring(net.holdLooking) .. "/" .. tostring(net.holdWanted) .. "/" .. tostring(net.respawnHeld)
        parts[#parts + 1] = "watching " .. tostring(game.isSpectating and game.isSpectating())
        local names = {}
        for name in pairs(bosses) do
            names[#names + 1] = name
        end
        parts[#parts + 1] = "bosses [" .. table.concat(names, ", ") .. "]"
        pcall(function()
            local hud = FindFirstOf("PBZHUDLayout")
            if valid(hud) then
                parts[#parts + 1] = string.format("HUD vis %s op %.2f inVp %s", tostring(hud:GetVisibility()),
                    hud:GetRenderOpacity(), tostring(hud:IsInViewport()))
                local b = {}
                for _, bar in ipairs(hudBars(hud)) do
                    local who = select(2, pcall(function() return bar.Character:GetFName():ToString() end))
                    b[#b + 1] = tostring(who) .. ":" .. tostring(select(2, pcall(function() return bar:GetVisibility() end)))
                end
                parts[#parts + 1] = "bars [" .. table.concat(b, ", ") .. "]"
            else
                parts[#parts + 1] = "no HUD"
            end
        end)
        pcall(function()
            parts[#parts + 1] = "ear override " .. tostring(pc.bOverrideAudioListener) .. (D.ear and " (ours)" or "")
        end)
        log("Down (state): " .. table.concat(parts, " | "))
    end

    -- Up again: a bar put up here comes down unless its boss is still in a fight of this player's or a partner's.
    local function dropBars()
        for addr, s in pairs(D.shown) do
            local a = s.actor
            if valid(a) and a:GetAddress() == addr and fnameOf(a) == s.fname then
                local still = (net.partnerBosses or {})[s.name] or (net.hostBosses or {})[s.name]
                if game.isDead(a) or not still then
                    if game.isMirrorBar and game.isMirrorBar(a) then
                        game.hideBossBar(a)
                    end
                end
            end
        end
        D.shown = {}
    end

    ------------------------------------------------------------------ the ear

    local function earOnCamera(pc)
        if D.ear then
            return
        end
        local vt = nil
        pcall(function() vt = pc:GetViewTarget() end)
        local root = nil
        pcall(function() root = vt:K2_GetRootComponent() end)
        if not valid(root) then
            return
        end
        local was = {}
        pcall(function() was.on = pc.bOverrideAudioListener end)
        pcall(function()
            local c = pc.AudioListenerComponent
            local ok, got = pcall(function() return c:Get() end)
            was.comp = ok and got or c
        end)
        pcall(function()
            local l, r = pc.AudioListenerLocationOverride, pc.AudioListenerRotationOverride
            was.loc = { X = l.X, Y = l.Y, Z = l.Z }
            was.rot = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll }
        end)
        if pcall(function()
            pc:SetAudioListenerOverride(root, { X = 0.0, Y = 0.0, Z = 0.0 }, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
        end) then
            D.ear = was
            log("Down: the sound follows the camera on your partner (it was " .. (was.on == true and "on a part of the game's"
                or was.on == false and "the camera's" or "unread") .. ").")
        end
    end

    local function earBack(pc)
        local was = D.ear
        if not was then
            return
        end
        D.ear = nil
        local back = false
        if was.on == true and valid(was.comp) then
            back = pcall(function() pc:SetAudioListenerOverride(was.comp, was.loc or { X = 0.0, Y = 0.0, Z = 0.0 },
                was.rot or { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }) end)
        end
        if not back then
            pcall(function() pc:ClearAudioListenerOverride() end)
        end
    end

    -- Once a fall: how the game's sound stands, for the log. Names only, a few of each.
    local function tellSound(pc)
        local parts = {}
        pcall(function()
            parts[#parts + 1] = "listener override " .. tostring(pc.bOverrideAudioListener)
        end)
        local function names(class, words, most)
            local found = {}
            pcall(function()
                for _, o in ipairs(FindAllOf(class) or {}) do
                    if #found >= most then
                        break
                    end
                    local n = select(2, pcall(function() return o:GetFName():ToString() end))
                    if type(n) == "string" then
                        local low = n:lower()
                        for _, w in ipairs(words) do
                            if low:find(w, 1, true) then
                                found[#found + 1] = n
                                break
                            end
                        end
                    end
                end
            end)
            return found
        end
        local words = { "dead", "death", "die", "alive", "respawn", "revive", "mute", "duck" }
        for _, class in ipairs({ "AkStateValue", "AkSwitchValue", "AkRtpc", "AkAudioEvent" }) do
            local found = names(class, words, 12)
            if #found > 0 then
                parts[#parts + 1] = class .. ": " .. table.concat(found, ", ")
            end
        end
        log("Down: the game's sound: " .. table.concat(parts, " | ") .. ".")
    end

    ------------------------------------------------------------------ back for the boss's fall

    local function zhOr(en, zh)
        return (api.lang and api.lang.code == "zh") and zh or en
    end

    local function deathScreen(pawn)
        local ok, w = pcall(function() return pawn["Death Widget"] end)
        return (ok and valid(w)) and w or nil
    end

    -- True when this player was down in a fight, the boss at this address is that fight's last, and they're now up beside
    -- the partner: the caller lets the boss fall WIN_AFTER_S later.
    function D.reviveForWin(name, boss)
        if not D.revive or not net.enabled or net.arena or net.pvp then
            return false
        end
        local pc, pawn = api.getPlayer1()
        if not (valid(pc) and valid(pawn) and game.isDead(pawn) and net.deadSince ~= nil and net.holdLooking) then
            return false
        end
        if game.phaseAfter and game.phaseAfter(name) then
            return false            -- (another phase of it to come: not the fight's end)
        end
        local addr = valid(boss) and boss:GetAddress() or nil
        for other, a in pairs(fightBosses()) do
            if other ~= name and a:GetAddress() ~= addr then
                return false        -- (another boss of the fight still stands)
            end
        end
        local spot = nil
        pcall(function()
            local g = net.ghost
            if valid(g) and not net.ghostHidden then
                local l, yaw = g:K2_GetActorLocation(), math.rad(g:K2_GetActorRotation().Yaw)
                spot = { X = l.X - math.sin(yaw) * D.BESIDE_CM, Y = l.Y + math.cos(yaw) * D.BESIDE_CM, Z = l.Z + 30 }
            end
        end)
        if not spot then
            pcall(function()
                local l = pawn:K2_GetActorLocation()
                spot = { X = l.X, Y = l.Y, Z = l.Z + 30 }
            end)
        end
        local screen = deathScreen(pawn)
        local screenVis = nil
        pcall(function() screenVis = screen and screen:GetVisibility() end)
        -- (localcoop.lua's revivePlayer1, step by step: one that isn't there doesn't stop the rest.)
        local failed = {}
        local function step(what, fn)
            if not pcall(fn) then
                failed[#failed + 1] = what
            end
        end
        step("health", function() game.setHealth(pawn, select(2, game.getHealth(pawn)) or 100) end)
        step("Respawn", function() pawn["Death Component"]:Respawn() end)
        step("Recover Attributes", function() pawn["Respawn Recover Attributes"](pawn) end)
        step("Reset Hit State", function() pawn["Respawn Reset Hit State"](pawn) end)
        step("Reset Combat Logic", function() pawn["Respawn Reset Combat Logic"](pawn) end)
        step("Reset Dissolve", function() pawn:ResetDeathDissolveOnRespawn() end)
        step("Reset UI", function() pawn["Respawn Reset UI"](pawn) end)
        if spot then
            step("place", function() pawn:K2_SetActorLocation(spot, false, {}, true) end)
        end
        if game.isDead(pawn) then
            log("Down: bringing you back for " .. name .. "'s fall didn't take (" .. table.concat(failed, ", ")
                .. "): the respawn goes on as before.")
            return false
        end
        game.spectate(nil)
        net.watched = nil
        -- The death screen: kept held whatever the game's steps did with it (its tick's way on is the respawn at the bell and
        -- the world's refresh: given back, as coop.lua does once its player is up, it would send this player there now),
        -- out of sight if it's still up, and given its tick back at the next fall (D.look). The hold's flags down, so coop
        -- doesn't give it back meanwhile.
        if screen and valid(screen) then
            local up = select(2, pcall(function() return screen:IsInViewport() end)) == true
            pcall(function()
                screen.NotTick = true
                if up then
                    screen:SetVisibility(1)
                end
            end)
            D.frozen = { addr = screen:GetAddress(), vis = screenVis or 3, up = up }
            log("Down: the death screen " .. (up and "stayed up after the revive: held and put away." or "went with the revive: held all the same."))
        end
        net.holdLooking, net.holdWanted, net.respawnHeld = false, false, false
        log("Down: back on your feet beside your partner for " .. name .. "'s fall: its win and scene play for you too"
            .. (#failed > 0 and (" (steps not there: " .. table.concat(failed, ", ") .. ")") or "") .. ".")
        if api.status then
            api.status.notify("downwin", zhOr("the boss falls: you're back for its end.", "首领倒下了：你回来看它的结局。"), true)
        end
        D.revivedAt = os.clock()
        return true
    end

    ------------------------------------------------------------------ the look

    local function look()
        local now = os.clock()
        if now >= D.iniAt then
            D.iniAt = now + D.INI_S
            lookAtIni()
        end
        local pc, pawn = api.getPlayer1()
        if not (valid(pc) and valid(pawn)) then
            return
        end
        local down = net.enabled and net.deadSince ~= nil
        if down and D.wasDownAt ~= net.deadSince then
            -- A new fall. A death screen held and put away at the last revive: its own again.
            D.wasDownAt, D.told = net.deadSince, false
            if D.frozen then
                local w = deathScreen(pawn)
                if w and w:GetAddress() == D.frozen.addr then
                    pcall(function()
                        if D.frozen.up then
                            w:SetVisibility(D.frozen.vis)
                        end
                        w.NotTick = false
                    end)
                end
                D.frozen = nil
            end
        end
        -- Down in a fight: the respawn held for it, or a boss of the fight this player was in (or a partner's) still standing.
        -- (Not the hold alone: with the partner not seen fighting, coop lets the respawn go on after HOLD_GRACE_S, and the
        -- death screen plays the same, the fight going on without this player.)
        local bosses = down and fightBosses() or {}
        local held = down and (net.holdLooking == true or next(bosses) ~= nil)
        if held then
            if not D.told then
                D.told = true
                tellSound(pc)
                diag(pc, bosses)
                D.diagAt = now + D.DIAG_S
            end
            if now >= D.barAt then
                D.barAt = now + D.BAR_S
                keepBars(bosses)
            end
            if now >= (D.diagAt or 0) then
                D.diagAt = now + D.DIAG_S
                diag(pc, bosses)
            end
            if game.isSpectating() then
                earOnCamera(pc)
            else
                earBack(pc)
            end
        else
            earBack(pc)
            if not down and next(D.shown) ~= nil then
                dropBars()
            end
        end
    end

    LoopInGameThreadWithDelay(math.floor(D.LOOK_S * 1000), function()
        local ok, err = pcall(look)
        if not ok and err ~= D.lastError then
            D.lastError = err
            log("Down: " .. tostring(err))
        end
        return false
    end)

    return D
end
