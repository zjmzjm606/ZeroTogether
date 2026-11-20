-- ZeroTogether: the way out of a stuck moment.
--
-- "Sometimes picking something up freezes the game": a loot card the game put up and never finished, no button on it to
-- focus, so no key confirms it, and the player stands behind it for good (pbz.lua's game.closeStuckCards tells of one).
-- The mod looked for such a card only after a boss copy's death (coop.lua's bring.cardsLater). Now:
--
--   * A card up with no button for STUCK_S in a row is closed the game's way (game.closeStuckCards: only when the
--     backpack holds no card any more, so the item is in the bag already). Looked at every LOOK_S.
--   * ResetKey (F10, PhantomPact.ini) puts the player back in control at once, whatever held them:
--       - every loot card up is closed (its own back key), and the partner's finds' card queue is let go;
--       - the controls are given back (game input, no cursor, keys flushed), unless one of the mod's panels is open;
--       - in online co-op, a pause left on is lifted (online, the game never pauses for anything of its own);
--       - the player's own animation stopped (a pickup or a door's that never ended);
--       - a door opened here by word within DOOR_CM is made passable (blockers.passableNear: one that didn't move here).

return function(api)
    local log = api.log
    local valid = api.valid
    local game = api.game
    local C = { LOOK_S = 1.0, STUCK_S = 3.0, DOOR_CM = 800, CARD = "W_pickupgear_C" }
    local R = { keyWas = false, firstSeen = {} }

    local function zh()
        return api.lang ~= nil and api.lang.code == "zh"
    end

    local function say(en, cn)
        if api.status and api.status.notify then
            pcall(api.status.notify, "rescue", zh() and cn or en, true)
        end
    end

    local function addressOf(o)
        local ok, a = pcall(function() return o:GetAddress() end)
        return ok and a or tostring(o)
    end

    local function cards()
        local out = {}
        for _, w in ipairs(FindAllOf(C.CARD) or {}) do
            local ok, up = pcall(function() return valid(w) and w:IsVisible() end)
            if ok and up then
                out[#out + 1] = w
            end
        end
        return out
    end

    local function hasButton(w)
        local ok, yes = pcall(function() return valid(w.CurrentFocusButton) end)
        return ok and yes
    end

    -- A card with no button, up STUCK_S in a row: closed the game's way.
    local function watch()
        local now = os.clock()
        local seen = {}
        for _, w in ipairs(cards()) do
            if not hasButton(w) then
                local a = addressOf(w)
                seen[a] = R.firstSeen[a] or now
            end
        end
        R.firstSeen = seen
        for _, since in pairs(seen) do
            if now - since >= C.STUCK_S and game.closeStuckCards then
                local _, pawn = api.getPlayer1()
                local ok, n = pcall(game.closeStuckCards, pawn)
                if ok and type(n) == "number" and n > 0 then
                    R.firstSeen = {}
                end
                break
            end
        end
    end

    local function panelOpen()
        for _, p in ipairs({ api.panel, api.onlinepanel, api.pvppanel }) do
            if type(p) == "table" and p.open then
                return true
            end
        end
        return false
    end

    function R.reset()
        local pc, pawn = api.getPlayer1()
        local done = {}

        -- Cards: each one up, closed by its own back key; the partner's finds' queue let go.
        local closed = 0
        for _, w in ipairs(cards()) do
            if pcall(function() w:ClickBackKey() end) then
                closed = closed + 1
            end
        end
        pcall(function()
            game.tipsWanted, game.cardTries = false, 0
            if game.cardCalm then
                game.cardCalm.from = nil
            end
        end)
        R.firstSeen = {}
        if closed > 0 then
            done[#done + 1] = closed .. " card(s) closed"
        end

        -- Controls.
        if valid(pc) and not panelOpen() then
            local kit = api.panel and api.panel.kit
            if kit and kit.blockPlay then
                pcall(kit.blockPlay, pc, false)
            end
            pcall(function() pc:ResetIgnoreInputFlags() end)
            pcall(function() pc:SetIgnoreMoveInput(false) end)
            pcall(function() pc:SetIgnoreLookInput(false) end)
            local linked = false
            pcall(function() linked = api.coop.linked() == true end)
            if linked then
                pcall(function()
                    local gs = api.gs()
                    if gs:IsGamePaused(pc) then
                        gs:SetGamePaused(pc, false)
                        done[#done + 1] = "unpaused"
                    end
                end)
            end
            done[#done + 1] = "controls given back"
        end

        -- Own animation.
        if valid(pawn) then
            local okA = pcall(function()
                local anim = pawn.Mesh:GetAnimInstance()
                if valid(anim) then
                    anim:StopAllMontages(0.2)
                end
            end)
            if okA then
                done[#done + 1] = "animation stopped"
            end
        end

        -- Doors near, opened here by word.
        if valid(pawn) and api.blockers and api.blockers.passableNear then
            local ok, n = pcall(api.blockers.passableNear, pawn, C.DOOR_CM)
            if ok and type(n) == "number" and n > 0 then
                done[#done + 1] = n .. " door(s) made passable"
            end
        end

        log("Reset key: " .. (#done > 0 and table.concat(done, ", ") or "nothing to do") .. ".")
        say("reset: controls back" .. (closed > 0 and (", " .. closed .. " card(s) closed") or "") .. ".",
            "已重置：操作已恢复" .. (closed > 0 and ("，关闭了 " .. closed .. " 个物品卡") or "") .. "。")
    end

    local function keyName()
        local np = api.nameplates
        return (np and type(np.resetKey) == "string" and np.resetKey) or "F10"
    end

    local lookAt = 0
    LoopInGameThreadWithDelay(100, function()
        pcall(function()
            local pc = api.getPlayer1()
            local down = false
            if valid(pc) then
                down = pc:IsInputKeyDown({ KeyName = FName(keyName()) }) == true
            end
            if down and not R.keyWas then
                local ok, err = pcall(R.reset)
                if not ok then
                    log("Reset key failed: " .. tostring(err))
                end
            end
            R.keyWas = down
            local now = os.clock()
            if now - lookAt >= C.LOOK_S then
                lookAt = now
                watch()
            end
        end)
        return false
    end)

    log("Rescue: stuck loot cards are closed by themselves; " .. keyName() .. " resets the controls.")
    return R
end
