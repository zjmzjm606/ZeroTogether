-- Names and health of the other players. A patch on Phantom Pact 1.7.4, not part of the mod itself.
--
-- Each player's own name is PlayerName in PhantomPact.ini (up to 16 letters, Chinese too; empty: "Host" / "Player 2"...),
-- told to the others as "NAME <hex>" (hex: any UTF-8 crosses the link as plain letters, spaces and all). The ini is read
-- again every few seconds, so a name changed there, with the game running, reaches everyone within that. An older
-- Phantom Pact has no NAME handler and leaves it.
--
-- What shows (each PC its own choice, read from the ini as well):
--   Nameplates = On   over each other player's figure: their name in their colour (the host purple, player 2 green...;
--                     red while they're down) and their health under it.
-- Each bar is one widget of plain boxes: a thin dark frame, the empty track (always there, so a bar half gone shows
-- its other half), a light trail that stays where the health was for a moment after a blow and then runs down to it,
-- the fill, and a faint shine along its top. Up to 60 m off, fading from 45 m.
--   PartyBars = On    down the left of the screen: this player first, then each other player: name, health and 血气
--                     (the game's ShaChi, the bar under health) in numbers, and a bar of each. Grey while they're on
--                     another map, in a scene, or gone quiet. A partner's 血气 comes as "QI <now> <most>", sent when it
--                     moves (a 50th of its most at least), four times a second at most, and every 3 s regardless.
-- Both hide in a scene of this player's own and in a PvP match (F6), which has its own bars. The widgets sit at the bottom
-- of the viewport's order, so the game's own menus cover them.

return function(api)
    local log, valid = api.log, api.valid
    local coop = api.coop
    local net = coop.net
    local hud = api.hud
    local game = api.game

    local C = {
        MAX_CHARS = 16,
        INI_S = 3.0,                -- the ini looked at again this often
        RESEND_S = 10.0,            -- this player's name told again this often (one who joined late, a lost line)
        LOOK_S = 0.1,               -- whether anything may show (a scene, a match) asked this often; places every frame
        SCREEN_S = 1.0,             -- the window's size asked this often
        CHECK_S = 0.5,              -- whether a widget is still on the screen asked this often
        RETRY_S = 1.0,              -- a widget that couldn't be made is tried again after this
        FRESH_S = 3.0,              -- a player heard from longer ago than this has gone quiet
        FONT = "/Engine/EngineFonts/Roboto.Roboto",     -- (its fallback face draws Chinese: pbz.lua's game.arabicFont)
        TEX = "nameplate/bar.png",  -- a white strip, tinted
        Z = 1,                      -- under the game's own menus
        LIFT_CM = 120,              -- above the figure's middle: over its head
        NEAR_CM = 4500, FAR_CM = 6000,
        BAR_W = 100, BAR_H = 6, NAME_PT = 13, NAME_UP = 13,
        LIST_X = 34, LIST_TOP = 0.32, LIST_ROW = 56, LIST_BAR_W = 180, LIST_BAR_H = 8, LIST_PT = 13, LIST_BAR_DOWN = 16,
        QI_H = 5, QI_DOWN = 27,     -- the 血气 bar: under the health one
        TRAIL_WAIT_S = 0.45, TRAIL_SPEED = 0.8,     -- the trail waits this long after a fall, then runs this much of a
                                                    -- bar a second
        QI_S = 0.25, QI_RESEND_S = 3.0,
        -- (Linear, as the game takes colours: arenaui.lua's LOOK.)
        CRIMSON = { R = 0.60, G = 0.021, B = 0.025, A = 1 },
        GOLD = { R = 0.85, G = 0.42, B = 0.03, A = 1 },
        FRAME = { R = 0, G = 0, B = 0, A = 0.85 },
        TRACK = { R = 0.045, G = 0.04, B = 0.035, A = 0.92 },        -- the empty part
        TRAIL_HP = { R = 0.95, G = 0.62, B = 0.32, A = 0.95 },
        TRAIL_QI = { R = 1.0, G = 0.85, B = 0.45, A = 0.9 },
        SHINE = { R = 1, G = 1, B = 1, A = 0.16 },
        BACK = { R = 0, G = 0, B = 0, A = 0.6 },
        DOWN = { R = 1.0, G = 0.25, B = 0.2, A = 1 },
        GREY = { R = 0.45, G = 0.45, B = 0.45, A = 1 },
        WHITE = { R = 1, G = 1, B = 1, A = 1 },
        INK = { R = 0, G = 0, B = 0, A = 1 },
    }

    local np = { over = true, list = true, mine = nil, sentName = nil, sendAt = 0, iniAt = 0, lookAt = 0, ok = false,
        added = false, qiAt = 0, qiSent = nil, myQi = nil, myQiMax = nil }
    local parts = {}                -- key -> { widget, map, last, madeAt, checkAt }
    local failedAt = {}             -- key -> when it couldn't be made
    local view = { scale = 1, w = 1920, h = 1080, at = -1e9 }

    -- A map going takes every widget with it: forgotten untouched (a gone widget can read as valid a while, and touching it
    -- crashes the game: arenaui.lua's usable).
    pcall(function()
        RegisterLoadMapPreHook(function()
            parts = {}
        end)
    end)

    ------------------------------------------------------------------ names

    local function zh()
        return api.lang ~= nil and api.lang.code == "zh"
    end

    -- A name as it may be shown: one line, no control letters, valid UTF-8, at most MAX_CHARS letters; nil if nothing's left.
    local function clean(s)
        if type(s) ~= "string" then
            return nil
        end
        s = s:gsub("%c", " ")
        s = s:gsub("^%s+", "")
        s = s:gsub("%s+$", "")
        if s == "" then
            return nil
        end
        if utf8 and utf8.len then
            local n = utf8.len(s)
            if not n then
                return nil
            end
            if n > C.MAX_CHARS then
                s = s:sub(1, utf8.offset(s, C.MAX_CHARS + 1) - 1)
            end
        elseif #s > C.MAX_CHARS * 3 then
            return nil
        end
        return s
    end

    local function hex(s)
        return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end))
    end

    local function unhex(h)
        return (h:gsub("%x%x", function(x) return string.char(tonumber(x, 16)) end))
    end

    -- The other player's place in the party: their number, or with two players the host 1 and the guest 2.
    local function slotOf(p)
        if net.party then
            return p.number or 1
        end
        return coop.isHost() and 2 or 1
    end

    local function nameOf(p, slot)
        if p.ppName then
            return p.ppName
        end
        if slot == 1 then
            return zh() and "主机" or "Host"
        end
        return (zh() and "玩家 " or "Player ") .. slot
    end

    local function colourOf(slot)
        local pl = coop.players and coop.players[slot]
        return pl and pl.tint or C.WHITE
    end

    coop.handlers.NAME = function(rest, from)
        local p = coop.peerOf(from)
        if rest == "-" then
            p.ppName = nil
            return
        end
        local h = (rest or ""):match("^(%x+)$")
        if not h or #h % 2 == 1 or #h > C.MAX_CHARS * 8 then
            return
        end
        local name = clean(unhex(h))
        if name and name ~= p.ppName then
            p.ppName = name
            log("Nameplates: player " .. slotOf(p) .. " is called " .. name .. ".")
        end
    end

    -- A partner's 血气: "QI <now> <most>".
    coop.handlers.QI = function(rest, from)
        local cur, most = (rest or ""):match("^(%d+) (%d+)$")
        cur, most = tonumber(cur), tonumber(most)
        if cur and most and most > 0 and most < 1e6 then
            local p = coop.peerOf(from)
            p.ppQi, p.ppQiMax, p.ppQiAt = math.min(cur, most), most, os.clock()
        end
    end

    -- This player's 血气: the game's ShaChi on their body (the HUD's bar under health).
    local function readQi(pawn)
        local cur, most = nil, nil
        pcall(function()
            local set = pawn.AttributeSetBase
            cur, most = set.Shachi.CurrentValue, set.Shachi_Max.CurrentValue
        end)
        if type(cur) == "number" and type(most) == "number" and cur == cur and most > 0 then
            return math.max(0, math.min(cur, most)), most
        end
        return nil
    end

    -- Read QI_S apart; told when it moved a 50th of its most, its most changed, or QI_RESEND_S went by.
    local function sendQi(now, pawn)
        if now < np.qiAt then
            return
        end
        np.qiAt = now + C.QI_S
        local cur, most = readQi(pawn)
        np.myQi, np.myQiMax = cur, most
        if not cur then
            return
        end
        local last = np.qiSent
        if not last or math.abs(cur - last[1]) >= math.max(1, most * 0.02) or most ~= last[2]
            or now - last[3] >= C.QI_RESEND_S then
            coop.sendEvent("QI", string.format("%d %d", math.floor(cur + 0.5), math.floor(most + 0.5)))
            np.qiSent = { cur, most, now }
        end
    end

    -- Someone (re)started sync or joined: they know no name yet. Told at the next look.
    for _, kind in ipairs({ "S", "J" }) do
        local was = coop.handlers[kind]
        if was then
            coop.handlers[kind] = function(...)
                np.sendAt = 0
                return was(...)
            end
        end
    end

    -- PhantomPact.ini's lines for this, once a second at most; nil when it can't be read (the panel writing it that moment).
    local function readIni()
        local f = io.open(api.modDir() .. "PhantomPact.ini", "rb")
        if not f then
            return nil
        end
        local text = f:read("a") or ""
        f:close()
        text = text:gsub("^\239\187\191", "")          -- (Notepad's UTF-8 mark)
        local s = {}
        for line in text:gmatch("[^\r\n]+") do
            local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
            if key and not line:match("^%s*[;#]") then
                s[key:lower()] = value
            end
        end
        return s
    end

    local function onOff(v, default)
        return ((v or default):lower() ~= "off")
    end

    local function lookAtIni()
        local s = readIni()
        if not s then
            return
        end
        -- (The lines put in once, at the end, for a player to find: the panel's own save, which leaves every other line be.)
        if not np.added and s.playername == nil and api.panel and api.panel.kit and api.panel.kit.save then
            np.added = true
            pcall(api.panel.kit.save, { PlayerName = "", Nameplates = "On", PartyBars = "On" })
            log("Nameplates: PlayerName, Nameplates and PartyBars added at the end of PhantomPact.ini.")
        end
        np.added = true
        local name = clean(s.playername)
        if name ~= np.mine then
            np.mine = name
            log("Nameplates: your name is " .. (name or "(none: the others see your number)") .. ".")
        end
        np.over, np.list = onOff(s.nameplates, "on"), onOff(s.partybars, "on")
    end

    local function sendName(now)
        if not net.enabled then
            np.sentName, np.sendAt = nil, 0
            return
        end
        if np.mine == nil then
            if np.sentName ~= nil then
                coop.sendEvent("NAME", "-")
                np.sentName = nil
            end
            return
        end
        if np.mine ~= np.sentName or now >= np.sendAt then
            coop.sendEvent("NAME", hex(np.mine))
            np.sentName, np.sendAt = np.mine, now + C.RESEND_S
        end
    end

    ------------------------------------------------------------------ widgets

    local function measure(pc)
        if os.clock() - view.at < C.SCREEN_S then
            return view.scale > 0
        end
        local ok = pcall(function()
            local lib = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
            local size, scale = lib:GetViewportSize(pc), lib:GetViewportScale(pc)
            view.scale, view.w, view.h = scale, size.X / scale, size.Y / scale
        end)
        if ok then
            view.at = os.clock()
        end
        return ok and view.scale > 0
    end

    -- A bar: the one-image widget, its picture off, five boxes in its canvas, each a UMG Image of the white strip tinted:
    -- frame, track (the empty part), trail, fill, shine, drawn in that order. The trail, fill and shine start at the bar's
    -- left end and grow right (their width is the share). spec: { w, h, fill colour, trail colour }.
    local function makeBar(key, spec)
        local w, h, fillColour, trailColour = spec[1], spec[2], spec[3] or C.CRIMSON, spec[4] or C.TRAIL_HP
        local widget = hud.newImage(C.TEX, w + 8, h + 8, C.Z)
        if not widget then
            return nil
        end
        local tex = hud.texture(C.TEX)
        local slots = {}
        local shineH = math.max(1, math.floor(h * 0.4 + 0.5))
        local ok = pcall(function()
            widget:SetVisibility(2)
            widget.Circle:SetVisibility(1)
            local class = StaticFindObject("/Script/UMG.Image")
            local root = widget.WidgetTree.RootWidget
            local function box(name, colour, left, bw, bh, dy)
                local img = StaticConstructObject(class, widget.WidgetTree, FName("PPBar_" .. key .. "_" .. name))
                local slot = root:AddChild(img)
                slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
                slot:SetAlignment({ X = left and 0 or 0.5, Y = 0.5 })
                slot:SetAutoSize(false)
                slot:SetPosition({ X = left and -w / 2 or 0, Y = dy or 0 })
                slot:SetSize({ X = bw, Y = bh })
                if valid(tex) then
                    pcall(function() img:SetBrushFromTexture(tex, false) end)
                end
                img:SetColorAndOpacity(colour)
                slots[name] = slot
            end
            box("frame", C.FRAME, false, w + 2, h + 2)
            box("track", C.TRACK, false, w, h)
            box("trail", trailColour, true, w, h)
            box("fill", fillColour, true, w, h)
            box("shine", C.SHINE, true, w, shineH, -(h - shineH) / 2)
        end)
        if not ok then
            pcall(function() widget:RemoveFromParent() end)
            return nil
        end
        return { widget = widget, isBar = true, slots = slots, w = w, h = h, shineH = shineH, frac = nil, trail = nil,
            sized = { fill = w, trail = w, shine = w } }
    end

    -- A line of text: the same one-image widget, its picture off, a TextBlock in its canvas (arenaui.lua's textPart).
    -- left: the text starts at the widget's place; else it's centred there.
    local function makeText(key, left)
        local widget = hud.newImage(C.TEX, 400, 60, C.Z + 1)
        if not widget then
            return nil
        end
        local ok = pcall(function()
            widget:SetVisibility(2)
            widget.Circle:SetVisibility(1)
            local tb = StaticConstructObject(StaticFindObject("/Script/UMG.TextBlock"), widget.WidgetTree, FName("PPName_" .. key))
            local slot = widget.WidgetTree.RootWidget:AddChild(tb)
            slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
            slot:SetAlignment({ X = left and 0 or 0.5, Y = 0.5 })
            slot:SetPosition({ X = 0, Y = 0 })
            slot:SetAutoSize(true)
            tb:SetJustification(left and 0 or 1)
        end)
        if not ok then
            pcall(function() widget:RemoveFromParent() end)
            return nil
        end
        return { widget = widget, isText = true }
    end

    -- The part by key: made when missing (not more than once a RETRY_S after a failure), dropped untouched when it's of
    -- another map, or no longer on the screen.
    local function get(key, make, arg)
        local p = parts[key]
        local now = os.clock()
        if p and (p.map ~= net.localMap or (now >= p.checkAt and not api.status.onScreen(p.widget))) then
            parts[key], p = nil, nil
        end
        if p then
            if now >= p.checkAt then
                p.checkAt = now + C.CHECK_S
            end
            return p
        end
        if now - (failedAt[key] or -1e9) < C.RETRY_S then
            return nil
        end
        p = make(key, arg)
        if not p then
            failedAt[key] = now
            return nil
        end
        p.map, p.last, p.madeAt, p.checkAt = net.localMap, {}, now, now + C.CHECK_S
        parts[key] = p
        return p
    end

    -- The bar at frac: the fill and shine at once; the trail held at the old value TRAIL_WAIT_S after a fall, then run
    -- down at TRAIL_SPEED; a rise takes the trail with it. Each box resized only when it moved half a unit.
    local function setBar(p, frac, now)
        frac = math.max(0, math.min(1, frac or 0))
        if p.frac == nil then
            p.frac, p.trail = frac, frac        -- (a new bar starts where the value is: no trail from nothing)
        end
        if frac < p.frac - 0.0005 then
            p.dropAt = now
        end
        p.frac = frac
        if frac >= p.trail then
            p.trail = frac
        elseif now - (p.dropAt or -1e9) >= C.TRAIL_WAIT_S then
            p.trail = math.max(frac, p.trail - C.TRAIL_SPEED * (now - (p.trailAt or now)))
        end
        p.trailAt = now
        for name, width in pairs({ fill = p.w * frac, shine = p.w * frac, trail = p.w * p.trail }) do
            if math.abs(width - (p.sized[name] or -1)) >= 0.5 then
                local slot = p.slots[name]
                local hh = name == "shine" and p.shineH or p.h
                if pcall(function() slot:SetSize({ X = width, Y = hh }) end) then
                    p.sized[name] = width
                end
            end
        end
    end

    local function setText(p, text, pt, colour)
        if p.text == text and p.pt == pt and p.colour == colour then
            return
        end
        pcall(function()
            local tb = p.widget.WidgetTree.RootWidget:GetChildAt(1)
            if p.pt ~= pt then
                local f = tb.Font
                local font = StaticFindObject(C.FONT)
                if valid(font) then
                    f.FontObject = font
                end
                f.TypefaceFontName = FName("Bold")
                f.Size = pt
                pcall(function()
                    f.OutlineSettings.OutlineSize = 1
                    f.OutlineSettings.OutlineColor = C.INK
                end)
                tb:SetFont(f)
                pcall(function()
                    tb:SetShadowOffset({ X = 1, Y = 1 })
                    tb:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.8 })
                end)
                p.pt = pt
            end
            if p.text ~= text then
                tb:SetText(FText(text))
                p.text = text
            end
            if p.colour ~= colour then
                tb:SetColorAndOpacity({ SpecifiedColor = colour, ColorUseRule = 0 })
                p.colour = colour
            end
        end)
    end

    -- Placed at x, y (screen units), w x h for a strip (its middle there), at opacity a; shown once it can be laid out. Each
    -- call only when what it sets has moved (arenaui.lua's put).
    local function place(p, x, y, w, h, a)
        local last = p.last
        if not last.x or math.abs(x - last.x) >= 0.5 or math.abs(y - last.y) >= 0.5 then
            if pcall(function() p.widget:SetPositionInViewport({ X = x, Y = y }, false) end) then
                last.x, last.y = x, y
            end
        end
        local ready = true
        if w then
            if not (last.fw and math.abs(w - last.fw) < 0.5 and math.abs(h - last.fh) < 0.5) then
                if hud.fit(p.widget, w, h) then
                    last.fw, last.fh = w, h
                else
                    ready = false
                end
            end
        else
            ready = os.clock() - p.madeAt > 0.05     -- (a new one isn't laid out in its first frame)
        end
        a = a or 1
        if not last.a or math.abs(a - last.a) >= 0.01 then
            if pcall(function() p.widget:SetRenderOpacity(a) end) then
                last.a = a
            end
        end
        local on = ready and a > 0.01
        if last.shown ~= on then
            hud.show(p.widget, on)
            last.shown = on
        end
    end

    local function hide(p)
        if p.last.shown ~= false then
            if p.map == net.localMap and valid(p.widget) then
                hud.show(p.widget, false)
            end
            p.last.shown = false
        end
    end

    local function hideAll()
        for _, p in pairs(parts) do
            hide(p)
        end
    end

    ------------------------------------------------------------------ what shows

    local function stateOf(p)
        local t = p.target
        if t == nil or p.partnerGone or p.lastRemoteAt == nil or os.clock() - p.lastRemoteAt > C.FRESH_S then
            return "gone"
        end
        if t.Map ~= nil and net.localMap ~= nil and t.Map ~= net.localMap then
            return "away"
        end
        if t.Hp ~= nil and t.Hp <= 0 then
            return "down"
        end
        if t.Cine then
            return "scene"
        end
        return "up"
    end

    local function healthOf(p)
        local t = p.target
        if not (t and t.Hp and t.MaxHp and t.MaxHp > 0) then
            return nil
        end
        return math.max(0, math.min(1, t.Hp / t.MaxHp)), t.Hp, t.MaxHp
    end

    -- A bar, its middle at x, y, w x h, frac of it filled: health (crimson, "_p") unless told another part and colours.
    local function drawBar(drawn, key, x, y, w, h, frac, a, part, colour, trail)
        part = part or "_p"
        local bar = get(key .. part, makeBar, { w, h, colour or C.CRIMSON, trail or C.TRAIL_HP })
        if bar then
            setBar(bar, frac, os.clock())
            place(bar, x, y, nil, nil, a)
            drawn[key .. part] = true
        end
    end

    -- Over their figure.
    local function drawOver(drawn, p, slot, pc, cam)
        local state = stateOf(p)
        if not (state == "up" or state == "down") or not valid(p.ghost) or p.ghostHidden then
            return
        end
        local l = p.ghost:K2_GetActorLocation()
        local z = l.Z + C.LIFT_CM
        local dx, dy, dz = l.X - cam.X, l.Y - cam.Y, z - cam.Z
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        if dist > C.FAR_CM or dx * cam.fx + dy * cam.fy + dz * cam.fz < 30 then
            return              -- (too far, or behind the camera: the projection would put it in front, mirrored)
        end
        local at = {}
        if not (pcall(function() pc:ProjectWorldLocationToScreen({ X = l.X, Y = l.Y, Z = z }, at, false) end)
            and at.X and at.Y) then
            return
        end
        local x, y = at.X / view.scale, at.Y / view.scale
        if x < -200 or x > view.w + 200 or y < -200 or y > view.h + 200 then
            return
        end
        local a = dist <= C.NEAR_CM and 1 or math.max(0, 1 - (dist - C.NEAR_CM) / (C.FAR_CM - C.NEAR_CM))
        local key = "o" .. slot
        local name = get(key .. "_n", makeText, false)
        if name then
            setText(name, nameOf(p, slot), C.NAME_PT, state == "down" and C.DOWN or colourOf(slot))
            place(name, x, y - C.NAME_UP, nil, nil, a)
            drawn[key .. "_n"] = true
        end
        drawBar(drawn, key, x, y, C.BAR_W, C.BAR_H, state == "down" and 0 or healthOf(p), a)
    end

    local WORDS = {
        down = { "倒地", "down" }, away = { "在其他区域", "elsewhere" }, scene = { "过场中", "in a scene" },
        gone = { "无响应", "no answer" },
    }

    local function number(v)
        return math.floor(v + 0.5)
    end

    -- A row of the list: { key, name, colour, state, hp, most, qi, qiMost }.
    local function partnerRow(p, slot)
        if p.target == nil then
            return nil          -- (never heard from: nothing to say yet)
        end
        local state = stateOf(p)
        local _, hp, most = healthOf(p)
        return { key = "l" .. slot, name = nameOf(p, slot), state = state,
            colour = state == "up" and colourOf(slot) or state == "down" and C.DOWN or C.GREY,
            hp = hp, most = most, qi = p.ppQi, qiMost = p.ppQiMax }
    end

    local function ownSlot()
        if net.party then
            return net.slot or 1
        end
        return coop.isHost() and 1 or 2
    end

    local function ownRow(pawn)
        local slot = ownSlot()
        local hp, most = nil, nil
        pcall(function() hp, most = game.getHealth(pawn) end)
        local down = game.isDead(pawn) or (hp ~= nil and hp <= 0)
        local name = np.mine or (slot == 1 and (zh() and "主机" or "Host")) or ((zh() and "玩家 " or "Player ") .. slot)
        return { key = "lme", name = name .. (zh() and "（你）" or " (you)"), state = down and "down" or "up",
            colour = down and C.DOWN or colourOf(slot), hp = hp, most = most, qi = np.myQi, qiMost = np.myQiMax }
    end

    -- Down the left of the screen, row i: the name, health and 血气 in numbers, a bar of each.
    local function drawRow(drawn, r, i)
        local x, y = C.LIST_X, view.h * C.LIST_TOP + (i - 1) * C.LIST_ROW
        local words = WORDS[r.state]
        local said
        if words and r.state ~= "down" then
            said = zh() and words[1] or words[2]
        else
            local bits = {}
            if r.state == "down" then
                bits[#bits + 1] = zh() and words[1] or words[2]
            elseif r.hp and r.most and r.most > 0 then
                bits[#bits + 1] = string.format("%s %d/%d", zh() and "血量" or "HP", number(r.hp), number(r.most))
            end
            if r.qi and r.qiMost then
                bits[#bits + 1] = string.format("%s %d/%d", zh() and "血气" or "Qi", number(r.qi), number(r.qiMost))
            end
            said = table.concat(bits, "   ")
        end
        local name = get(r.key .. "_n", makeText, true)
        if name then
            setText(name, r.name .. "   " .. said, C.LIST_PT, r.colour)
            place(name, x, y, nil, nil, 1)
            drawn[r.key .. "_n"] = true
        end
        local dim = (r.state == "up" or r.state == "down") and 1 or 0.5
        local mid = x + C.LIST_BAR_W / 2
        local hpFrac = (r.state ~= "down" and r.hp and r.most and r.most > 0) and math.max(0, math.min(1, r.hp / r.most)) or 0
        drawBar(drawn, r.key, mid, y + C.LIST_BAR_DOWN, C.LIST_BAR_W, C.LIST_BAR_H, hpFrac, dim)
        if r.qi and r.qiMost and r.qiMost > 0 then
            drawBar(drawn, r.key, mid, y + C.QI_DOWN, C.LIST_BAR_W, C.QI_H, math.max(0, math.min(1, r.qi / r.qiMost)), dim,
                "_q", C.GOLD, C.TRAIL_QI)
        end
    end

    -- Every frame while co-op runs (coop.lua's frameTicks).
    local function frame()
        local now = os.clock()
        if now >= np.lookAt then
            np.lookAt = now + C.LOOK_S
            local quiet = now < (net.quietUntil or 0)
            np.ok = not quiet and not net.arena and not (game.inCutscene and game.inCutscene())
        end
        local drawn = {}
        local pc, pawn = api.getPlayer1()
        if valid(pawn) then
            sendQi(now, pawn)
        end
        if np.ok and (np.over or np.list) and valid(pc) and valid(pawn) and measure(pc) then
            local cam = nil
            if np.over then
                pcall(function()
                    local cm = pc.PlayerCameraManager
                    local c, r = cm:GetCameraLocation(), cm:GetCameraRotation()
                    local yaw, pitch = math.rad(r.Yaw), math.rad(r.Pitch)
                    cam = { X = c.X, Y = c.Y, Z = c.Z, fx = math.cos(pitch) * math.cos(yaw),
                        fy = math.cos(pitch) * math.sin(yaw), fz = math.sin(pitch) }
                end)
            end
            local list = {}
            for _, p in ipairs(coop.partners()) do
                list[#list + 1] = { p = p, slot = slotOf(p) }
            end
            table.sort(list, function(a, b) return a.slot < b.slot end)
            local rows = { ownRow(pawn) }
            for _, e in ipairs(list) do
                if cam then
                    drawOver(drawn, e.p, e.slot, pc, cam)
                end
                rows[#rows + 1] = partnerRow(e.p, e.slot)
            end
            if np.list then
                for i, r in ipairs(rows) do
                    drawRow(drawn, r, i)
                end
            end
        end
        for key, p in pairs(parts) do
            if not drawn[key] then
                hide(p)
            end
        end
    end
    coop.frameTicks.nameplates = frame

    -- The ini and this player's name, co-op or not; and with co-op off (no frames), nothing left on the screen.
    LoopInGameThreadWithDelay(500, function()
        local now = os.clock()
        local ok, err = pcall(function()
            if now >= np.iniAt then
                np.iniAt = now + C.INI_S
                lookAtIni()
            end
            sendName(now)
            if not net.enabled then
                hideAll()
            end
        end)
        if not ok and err ~= np.lastError then
            np.lastError = err
            log("Nameplates: " .. tostring(err))
        end
        return false
    end)

    log("Nameplates: names and health over the other players and down the left (PlayerName, Nameplates, PartyBars in PhantomPact.ini).")
    return np
end
