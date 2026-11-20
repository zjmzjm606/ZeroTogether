-- One boss bar a boss. A patch on Phantom Pact 1.7.4, not part of the mod itself.
--
-- Online, a boss fight's bar can come twice: the game's own, as this world starts the fight (or a phase brings the boss in
-- anew, or its scene does), and the one the mod puts up for the partner's fight on its copy (pbz.lua's showBossBar, and
-- keepBossBar putting it back each second when it can't see it). The mod takes a bar down where it knows to (coop.lua's
-- mirrorOn), but not every way two can come.
--
-- So, twice a second while a bar is up: the HUD's bars are grouped by the boss they show (its class: the same boss in this
-- world twice, a copy and the game's own body, has one class); in a group of two or more with a co-op bar in it (a mirror
-- the mod put up, or a body of a partner's fight), one stays and the others are collapsed. The one that stays: the body the
-- mod keeps in step with the partner's (its health is the fight's), else the game's own, else the first; a dead body's bar
-- never while another's is alive. A bar collapsed here comes back as soon as it's the only one of its boss again. Not in a
-- PvP match (its foes' bars are the mod's own) and not a ghost twin (six players: two of a boss on purpose). A group with
-- no co-op bar in it is the game's own two-boss fight, and left alone.

return function(api)
    local log, valid, game = api.log, api.valid, api.game
    local coop = api.coop
    local net = coop.net

    local LOOK_S = 0.5
    local COLLAPSED = 1

    local bb = { hidden = {}, said = {} }   -- hidden: bar address -> { vis, who }: collapsed here, with its own visibility

    local function barsOf(hud)
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

    -- The bodies of partners' fights here, by address: the copies the mod pairs with a partner's boss.
    local function partnerBodies()
        local out = {}
        for _, set in ipairs({ net.partnerBosses or {}, net.hostBosses or {} }) do
            for name in pairs(set) do
                local a = coop.enemyActor(name)
                if valid(a) then
                    out[a:GetAddress()] = true
                end
            end
        end
        return out
    end

    local function restore(addr, bar, why)
        local h = bb.hidden[addr]
        bb.hidden[addr] = nil
        if h and valid(bar) then
            pcall(function() bar:SetVisibility(h.vis) end)
            if why then
                log("Boss bars: " .. why)
            end
        end
    end

    local function look()
        if not net.enabled or net.arena then
            -- (Co-op off, or a match: whatever was collapsed here goes back as it was. The match's foe bars are its own.)
            if next(bb.hidden) then
                local hud = FindFirstOf("PBZHUDLayout")
                for _, bar in ipairs(valid(hud) and barsOf(hud) or {}) do
                    restore(bar:GetAddress(), bar)
                end
                bb.hidden = {}
            end
            return
        end
        if not (game.bossFightActive and game.bossFightActive()) and next(bb.hidden) == nil then
            return              -- (no fight, nothing to put back: no search at all)
        end
        local hud = FindFirstOf("PBZHUDLayout")
        if not valid(hud) then
            return              -- (no HUD, mid-load: its bars went with it)
        end
        local partners = partnerBodies()
        local groups, seen = {}, {}
        for _, bar in ipairs(barsOf(hud)) do
            local addr = bar:GetAddress()
            seen[addr] = true
            local who, vis = nil, nil
            pcall(function() who = bar.Character end)
            pcall(function() vis = bar:GetVisibility() end)
            local mine = bb.hidden[addr]
            if mine and not (valid(who) and who:GetAddress() == mine.who) then
                restore(addr, bar)      -- (the HUD's pool gave the bar to another body: its own again)
                mine = nil
            end
            -- Only bars on screen, or collapsed here; one with no body yet (its Init to come) is left be.
            if valid(who) and (mine or (vis ~= COLLAPSED and vis ~= 2)) then
                local cls = nil
                pcall(function() cls = who:GetClass():GetFName():ToString() end)
                local whoAddr = who:GetAddress()
                if cls and not (game.bossTwin and game.bossTwin(who, whoAddr)) then
                    local g = groups[cls] or {}
                    groups[cls] = g
                    g[#g + 1] = {
                        bar = bar, addr = addr, who = who, whoAddr = whoAddr, vis = mine and mine.vis or vis,
                        dead = game.isDead(who), paired = partners[whoAddr] == true,
                        mirror = game.isMirrorBar and game.isMirrorBar(who) or false,
                    }
                end
            end
        end
        for addr in pairs(bb.hidden) do
            if not seen[addr] then
                bb.hidden[addr] = nil   -- (gone from the HUD: nothing to put back)
            end
        end
        for cls, g in pairs(groups) do
            local coopBar = false
            for _, e in ipairs(g) do
                coopBar = coopBar or e.mirror or e.paired
            end
            if #g >= 2 and coopBar then
                -- The one that stays: alive first; then the body kept in step with the partner's; then the game's own.
                local function rank(e)
                    return (e.dead and 0 or 4) + (e.paired and 2 or 0) + (e.mirror and 0 or 1)
                end
                local keep = g[1]
                for _, e in ipairs(g) do
                    if rank(e) > rank(keep) then
                        keep = e
                    end
                end
                for _, e in ipairs(g) do
                    if e ~= keep and not bb.hidden[e.addr] then
                        if pcall(function() e.bar:SetVisibility(COLLAPSED) end) then
                            bb.hidden[e.addr] = { vis = e.vis or 4, who = e.whoAddr }
                            local key = cls .. "|" .. e.whoAddr
                            if not bb.said[key] then
                                bb.said[key] = true
                                log(string.format("Boss bars: %s had %d bars; one kept (%s), a %s one put away.", cls, #g,
                                    keep.paired and "the partner's fight" or keep.mirror and "a mirror" or "the game's own",
                                    e.dead and "dead body's" or e.mirror and "mirror" or "second"))
                            end
                        end
                    elseif e == keep and bb.hidden[e.addr] then
                        restore(e.addr, e.bar, cls .. ": the bar kept now was put away before: shown again.")
                    end
                end
            else
                for _, e in ipairs(g) do
                    if bb.hidden[e.addr] then
                        restore(e.addr, e.bar, cls .. ": the only bar of its boss again: shown.")
                    end
                end
            end
        end
    end

    LoopInGameThreadWithDelay(math.floor(LOOK_S * 1000), function()
        local ok, err = pcall(look)
        if not ok and err ~= bb.lastError then
            bb.lastError = err
            log("Boss bars: " .. tostring(err))
        end
        return false
    end)

    return bb
end
