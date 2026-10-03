print("[DUMPER v4.1] Iniciando (modo seguro)...")

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local plr = Players.LocalPlayer

local targetParent
if gethui then targetParent = gethui()
elseif syn and syn.protect_gui then targetParent = CoreGui
else targetParent = CoreGui end

-- ESTADO
local State = {
    sessao = "Sessao",
    capturando = false,
    hookAtivo = false,

    logBuf = {},
    trfBuf = {},
    arquitetural = {},
    unicos = {},
    nomesCache = {},

    filtros = {
        skills = true,
        drops = true,
        bossEvent = true,
        swordOrb = true,
        toolbar = true,
        dungeon = true,
        ruido = false,
    },
}

local _nomecallOriginal = nil
local ultimoPath = {}
local RATE_LIMIT = 0.15
local MAX_UNICOS = 2000

-- ═══════════════════════════════════════════════
-- CACHE de GetFullName (evita custo repetido)
-- ═══════════════════════════════════════════════
local function getNome(inst)
    if State.nomesCache[inst] then return State.nomesCache[inst] end
    local ok, n = pcall(function() return inst:GetFullName() end)
    n = ok and n or "?"
    State.nomesCache[inst] = n
    return n
end

-- ═══════════════════════════════════════════════
-- RUIDO
-- ═══════════════════════════════════════════════
local RUIDO = {
    "Ping", "DataChanged", "PlayAnimation", "PlayEffect",
    "DamageLabel", "DamageNotifier", "Knockback", "RagdollData",
    "UpdateLocal", "Heartbeat", "changeAnimationClient",
    "GameAnalytics", "Postie",
}

local function ehRuido(path)
    if State.filtros.ruido then return false end
    for i = 1, #RUIDO do
        if path:find(RUIDO[i]) then return true end
    end
    return false
end

-- ═══════════════════════════════════════════════
-- CLASSIFICADOR
-- ═══════════════════════════════════════════════
local function classificar(path)
    if path:find("Dungeon") or path:find("dungeon")
    or path:find("NextArea") or path:find("Wave") or path:find("wave")
    or path:find("Stage") or path:find("stage")
    or path:find("LobbyService") or path:find("DungeonLobby") then
        return "DUNGEON"
    end
    if path:find("UpdatePlayerToolbar") or path:find("ToolService") then return "TOOLBAR" end
    if path:find("SkillRemote") then return "M1" end
    if path:find("ExecuteSkill") then return "SKILL" end
    if path:find("ItemSpawned") or path:find("ClaimItem")
    or path:find("WishService") or path:find("ItemDropService") then return "DROP" end
    if path:find("Boss") or path:find("Zaja") or path:find("Destroyer") then return "BOSS" end
    if path:find("Weapon") or path:find("Orb") then return "SWORD_ORB" end
    if path:find("Rebirth") or path:find("Prompt") then return "REBIRTH" end
    if path:find("LockedOn") then return "LOCK" end
    if path:find("Event") then return "EVENT" end
    return "OTHER"
end

local CORES = {
    M1 = "5FE8FF", SKILL = "C68AFF", DROP = "5FDC78",
    BOSS = "FF5C5C", SWORD_ORB = "FFE45C", REBIRTH = "FF9642",
    LOCK = "8AFF8A", TOOLBAR = "FF9AC6", DUNGEON = "00FFC6",
    EVENT = "9A9AA0", OTHER = "9A9AA0",
    INFO = "74B8FF", SUCCESS = "5FDC78", WARN = "FFB43C",
}

-- ═══════════════════════════════════════════════
-- SERIALIZADOR
-- ═══════════════════════════════════════════════
local function ser(v, d)
    d = d or 0
    if d > 2 then return "..." end
    local t = typeof(v)
    if t == "Instance" then return getNome(v)
    elseif t == "Vector3" then return string.format("V3(%.0f,%.0f,%.0f)", v.X, v.Y, v.Z)
    elseif t == "CFrame" then
        local p = v.Position
        return string.format("CF(%.0f,%.0f,%.0f)", p.X, p.Y, p.Z)
    elseif t == "table" then
        local p, n = {}, 0
        for k, vv in pairs(v) do
            n = n + 1
            if n > 6 then p[#p+1] = "..." break end
            p[#p+1] = tostring(k).."="..ser(vv, d+1)
        end
        return "{"..table.concat(p,",").."}"
    end
    return "["..t.."] "..tostring(v)
end

-- ═══════════════════════════════════════════════
-- BUFFERS
-- ═══════════════════════════════════════════════
local function addLog(cat, msg)
    table.insert(State.logBuf, {cat=cat, msg=msg, hora=os.date("%H:%M:%S")})
    if #State.logBuf > 300 then table.remove(State.logBuf, 1) end
end

local function addTrafego(cat, path, args)
    if cat == "EVENT" and (args == "" or args == nil) then return end
    local chave = cat.."|"..path.."|"..args
    if State.unicos[chave] then
        State.unicos[chave].count = State.unicos[chave].count + 1
        State.unicos[chave].ultimo = os.date("%H:%M:%S")
        return
    end
    local entry = {cat=cat, path=path, args=args, count=1,
        primeiro=os.date("%H:%M:%S"), ultimo=os.date("%H:%M:%S")}
    State.unicos[chave] = entry
    table.insert(State.trfBuf, entry)
    if #State.trfBuf > MAX_UNICOS then
        local rem = table.remove(State.trfBuf, 1)
        for k, v in pairs(State.unicos) do if v == rem then State.unicos[k] = nil break end end
    end
end

-- ═══════════════════════════════════════════════
-- HOOK __namecall — INSTALA SÓ QUANDO CAPTURAR
-- ═══════════════════════════════════════════════
local function instalarHook()
    if State.hookAtivo then return end
    if not hookmetamethod then addLog("WARN", "Executor sem hookmetamethod"); return end

    _nomecallOriginal = hookmetamethod(game, "__namecall", function(self, ...)
        local n = select("#", ...)
        if State.capturando then
            local m = getnamecallmethod()
            if m == "FireServer" or m == "InvokeServer" then
                local args = {...}
                local ok, path = pcall(function() return self:GetFullName() end)
                if ok and not ehRuido(path) then
                    local agora = os.clock()
                    if not ultimoPath[path] or (agora - ultimoPath[path]) >= RATE_LIMIT then
                        ultimoPath[path] = agora
                        local cat = classificar(path)
                        local aceito = false
                        if cat == "M1" and State.filtros.skills then aceito = true end
                        if cat == "SKILL" and State.filtros.skills then aceito = true end
                        if cat == "DROP" and State.filtros.drops then aceito = true end
                        if cat == "BOSS" and State.filtros.bossEvent then aceito = true end
                        if cat == "SWORD_ORB" and State.filtros.swordOrb then aceito = true end
                        if cat == "TOOLBAR" and State.filtros.toolbar then aceito = true end
                        if cat == "REBIRTH" or cat == "LOCK" or cat == "EVENT" then aceito = true end
                        if cat == "DUNGEON" and State.filtros.dungeon then aceito = true end

                        if aceito then
                            local parts = {}
                            for i = 1, math.min(n, 6) do
                                parts[#parts+1] = ser(args[i])
                            end
                            addTrafego(cat, path:gsub("ReplicatedStorage%.", "RS."), table.concat(parts, " | "))
                        end
                    end
                end
            end
        end
        return _nomecallOriginal(self, ...)
    end)
    State.hookAtivo = true
    addLog("SUCCESS", "Hook __namecall instalado")
end

local function removerHook()
    if not State.hookAtivo then return end
    if _nomecallOriginal and hookmetamethod then
        pcall(function() hookmetamethod(game, "__namecall", _nomecallOriginal) end)
    end
    _nomecallOriginal = nil
    State.hookAtivo = false
    addLog("INFO", "Hook removido")
end

-- ═══════════════════════════════════════════════
-- SCANNER — só Workspace, 3s, com yield
-- ═══════════════════════════════════════════════
task.spawn(function()
    local conhecidos = {}
    while true do
        task.wait(3)
        if State.capturando then
            local wm = WS:FindFirstChild("World Mobs")
            local ps = WS:FindFirstChild("PartStorage")

            -- Mobs de evento
            if wm and State.filtros.bossEvent then
                local ev = wm:FindFirstChild("Event Mobs")
                if ev then
                    for _, obj in ipairs(ev:GetChildren()) do
                        if not conhecidos[obj] then
                            conhecidos[obj] = true
                            local hrp = obj:FindFirstChild("HumanoidRootPart")
                            if hrp then
                                addLog("BOSS", string.format("%s | V3(%.0f,%.0f,%.0f)",
                                    obj:GetFullName(), hrp.Position.X, hrp.Position.Y, hrp.Position.Z))
                            end
                        end
                    end
                end
            end

            -- Drops
            if ps and State.filtros.drops then
                for _, obj in ipairs(ps:GetChildren()) do
                    if not conhecidos[obj] then
                        conhecidos[obj] = true
                        local base = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
                        if base then
                            addLog("DROP", string.format("%s | V3(%.0f,%.0f,%.0f)",
                                obj:GetFullName(), base.Position.X, base.Position.Y, base.Position.Z))
                        end
                    end
                end
            end

            -- Dungeon: portais no Workspace
            if State.filtros.dungeon then
                for _, obj in ipairs(WS:GetChildren()) do
                    local nm = obj.Name:lower()
                    if (nm:find("dungeon") or nm:find("portal") or nm:find("gate") or nm:find("lobby"))
                    and not conhecidos[obj] then
                        conhecidos[obj] = true
                        local pos = obj:IsA("BasePart") and obj.Position
                            or (obj.PrimaryPart and obj.PrimaryPart.Position)
                        if pos then
                            addLog("DUNGEON", string.format("%s | V3(%.0f,%.0f,%.0f)",
                                obj:GetFullName(), pos.X, pos.Y, pos.Z))
                        end
                    end
                end
            end

            -- Limpa cache se ficou grande
            if #State.trfBuf > MAX_UNICOS * 0.8 then
                State.nomesCache = {}
            end
        end
    end
end)

-- ═══════════════════════════════════════════════
-- SCAN ARQUITETURAL (manual, mais leve)
-- ═══════════════════════════════════════════════
local function scanArquitetural()
    addLog("INFO", "Scan iniciado...")
    task.spawn(function()
        local t0 = os.clock()
        local total = 0
        local function varrer(inst, path, depth)
            if depth > 6 or not inst then return end
            task.wait()  -- yield pra não travar
            local ok, ch = pcall(function() return inst:GetChildren() end)
            if not ok then return end
            for _, c in ipairs(ch) do
                local cls = c.ClassName
                if cls == "RemoteEvent" or cls == "RemoteFunction"
                or cls == "UnreliableRemoteEvent" or cls == "ModuleScript" then
                    table.insert(State.arquitetural, "["..cls.."] "..path.."."..c.Name)
                    total = total + 1
                end
                if cls == "Folder" or cls == "Model" then
                    varrer(c, path.."."..c.Name, depth + 1)
                end
            end
        end
        pcall(function() varrer(RS, "RS", 0) end)
        addLog("SUCCESS", string.format("Scan: %.2fs — %d itens", os.clock() - t0, total))
    end)
end

-- ═══════════════════════════════════════════════
-- SALVAR
-- ═══════════════════════════════════════════════
local function salvarArquivo()
    local L = {
        "═══ DUMP v4.1 — Sessão: "..State.sessao.." ═══",
        "Player: "..plr.Name,
        "PlaceId: "..game.PlaceId,
        "Data: "..os.date("%Y-%m-%d %H:%M:%S"),
        "Total único: "..#State.trfBuf,
        "",
    }

    local porCat = {}
    for _, t in ipairs(State.trfBuf) do
        porCat[t.cat] = porCat[t.cat] or {}
        table.insert(porCat[t.cat], t)
    end

    for _, cat in ipairs({"DUNGEON","M1","SKILL","DROP","BOSS","SWORD_ORB",
                          "TOOLBAR","REBIRTH","LOCK","EVENT","OTHER"}) do
        if porCat[cat] then
            table.insert(L, "")
            table.insert(L, "### "..cat.." ("..#porCat[cat]..")")
            for _, t in ipairs(porCat[cat]) do
                if t.count > 1 then
                    table.insert(L, string.format("[%s~%s](x%d) %s | %s",
                        t.primeiro, t.ultimo, t.count, t.path, t.args))
                else
                    table.insert(L, string.format("[%s] %s | %s",
                        t.primeiro, t.path, t.args))
                end
            end
        end
    end

    table.insert(L, "")
    table.insert(L, "═══ ARQUITETURAL ═══")
    for _, linha in ipairs(State.arquitetural) do table.insert(L, linha) end

    local conteudo = table.concat(L, "\n")
    local nome = "Dump_"..State.sessao.."_"..os.time()..".txt"
    local ok = pcall(function() if writefile then writefile(nome, conteudo) end end)
    if ok then return "Salvo: "..nome.." ("..#conteudo.."b)"
    else pcall(function() setclipboard(conteudo) end); return "Clipboard ("..#conteudo.."b)" end
end

-- ═══════════════════════════════════════════════
-- UI
-- ═══════════════════════════════════════════════
local old = targetParent:FindFirstChild("DumperFinal")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "DumperFinal"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
if syn and syn.protect_gui then syn.protect_gui(gui) end
gui.Parent = targetParent

local T = {
    bg = Color3.fromRGB(0,0,0),
    panel = Color3.fromRGB(10,10,12),
    elev = Color3.fromRGB(18,18,22),
    border = Color3.fromRGB(30,30,36),
    accent = Color3.fromRGB(0,255,198),
    text = Color3.fromRGB(230,230,235),
    success = Color3.fromRGB(80,200,120),
    danger = Color3.fromRGB(220,60,60),
    info = Color3.fromRGB(74,158,255),
}

local main = Instance.new("Frame", gui)
main.Size = UDim2.new(0, 480, 0, 520)
main.Position = UDim2.new(0, 20, 0, 60)
main.BackgroundColor3 = T.bg
main.BackgroundTransparency = 0.1
main.BorderSizePixel = 0
main.Active = true
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
local mstk = Instance.new("UIStroke", main) mstk.Color = T.border mstk.Thickness = 1

local header = Instance.new("Frame", main)
header.Size = UDim2.new(1, 0, 0, 40)
header.BackgroundColor3 = T.panel
header.BorderSizePixel = 0
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)

local titulo = Instance.new("TextLabel", header)
titulo.Size = UDim2.new(1, -100, 1, 0)
titulo.Position = UDim2.new(0, 14, 0, 0)
titulo.BackgroundTransparency = 1
titulo.Text = "  🐉  DUMPER v4.1"
titulo.TextColor3 = T.accent
titulo.Font = Enum.Font.GothamBold
titulo.TextSize = 13
titulo.TextXAlignment = Enum.TextXAlignment.Left

local btnMin = Instance.new("TextButton", header)
btnMin.Size = UDim2.new(0, 24, 0, 24)
btnMin.Position = UDim2.new(1, -60, 0.5, -12)
btnMin.BackgroundColor3 = T.elev
btnMin.Text = "—" btnMin.TextColor3 = T.text
btnMin.Font = Enum.Font.GothamBold btnMin.TextSize = 14 btnMin.BorderSizePixel = 0
Instance.new("UICorner", btnMin).CornerRadius = UDim.new(0, 6)

local btnKill = Instance.new("TextButton", header)
btnKill.Size = UDim2.new(0, 24, 0, 24)
btnKill.Position = UDim2.new(1, -32, 0.5, -12)
btnKill.BackgroundColor3 = T.danger
btnKill.Text = "×" btnKill.TextColor3 = Color3.new(1,1,1)
btnKill.Font = Enum.Font.GothamBold btnKill.TextSize = 14 btnKill.BorderSizePixel = 0
Instance.new("UICorner", btnKill).CornerRadius = UDim.new(0, 6)

local input = Instance.new("TextBox", main)
input.Size = UDim2.new(1, -24, 0, 32)
input.Position = UDim2.new(0, 12, 0, 50)
input.BackgroundColor3 = T.elev
input.Text = "Sessao"
input.PlaceholderText = "Nome da sessão..."
input.TextColor3 = T.text
input.Font = Enum.Font.Gotham input.TextSize = 12 input.BorderSizePixel = 0
Instance.new("UICorner", input).CornerRadius = UDim.new(0, 6)
local ipad = Instance.new("UIPadding", input) ipad.PaddingLeft = UDim.new(0, 10)

local function mkBtn(x, w, cor, txt, cb)
    local b = Instance.new("TextButton", main)
    b.Size = UDim2.new(0, w, 0, 34)
    b.Position = UDim2.new(0, x, 0, 90)
    b.BackgroundColor3 = cor b.Text = txt
    b.TextColor3 = Color3.new(1,1,1) b.Font = Enum.Font.GothamBold
    b.TextSize = 11 b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(cb)
    return b
end

mkBtn(12, 108, T.info, "📁 SCAN", function()
    State.sessao = input.Text ~= "" and input.Text or State.sessao
    scanArquitetural()
end)

local btnCap = mkBtn(126, 108, T.success, "▶ CAPTURAR", function()
    State.sessao = input.Text ~= "" and input.Text or State.sessao
    State.capturando = not State.capturando
    if State.capturando then
        btnCap.BackgroundColor3 = T.danger
        btnCap.Text = "■ PARAR"
        instalarHook()
    else
        btnCap.BackgroundColor3 = T.success
        btnCap.Text = "▶ CAPTURAR"
        removerHook()
    end
end)

mkBtn(240, 108, T.accent, "💾 SALVAR", function()
    addLog("SUCCESS", salvarArquivo())
end)

mkBtn(354, 114, Color3.fromRGB(120,60,180), "🗑 LIMPAR", function()
    State.trfBuf = {} State.unicos = {} State.logBuf = {}
    State.nomesCache = {}
    addLog("INFO", "Buffers limpos")
end)

local filtroFrame = Instance.new("Frame", main)
filtroFrame.Size = UDim2.new(1, -24, 0, 84)
filtroFrame.Position = UDim2.new(0, 12, 0, 132)
filtroFrame.BackgroundColor3 = T.panel
filtroFrame.BorderSizePixel = 0
Instance.new("UICorner", filtroFrame).CornerRadius = UDim.new(0, 6)
local fl = Instance.new("UIListLayout", filtroFrame)
fl.FillDirection = Enum.FillDirection.Horizontal
fl.Padding = UDim.new(0, 4) fl.Wraps = true
local fp = Instance.new("UIPadding", filtroFrame)
fp.PaddingLeft = UDim.new(0, 6) fp.PaddingTop = UDim.new(0, 4)

local function mkFiltro(nome, key, cor)
    local b = Instance.new("TextButton", filtroFrame)
    b.Size = UDim2.new(0, 68, 0, 24)
    b.BackgroundColor3 = State.filtros[key] and (cor or T.success) or T.elev
    b.Text = nome b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold b.TextSize = 9 b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    b.MouseButton1Click:Connect(function()
        State.filtros[key] = not State.filtros[key]
        b.BackgroundColor3 = State.filtros[key] and (cor or T.success) or T.elev
    end)
end

mkFiltro("Dungeon", "dungeon", Color3.fromRGB(0,255,198))
mkFiltro("Skills", "skills", Color3.fromRGB(120,60,180))
mkFiltro("Drops", "drops", Color3.fromRGB(80,200,120))
mkFiltro("Boss", "bossEvent", Color3.fromRGB(220,60,60))
mkFiltro("Sword/Orb", "swordOrb", Color3.fromRGB(255,200,60))
mkFiltro("Toolbar", "toolbar", Color3.fromRGB(255,150,200))
mkFiltro("Ruído", "ruido", Color3.fromRGB(120,120,120))

local logFrame = Instance.new("Frame", main)
logFrame.Size = UDim2.new(1, -24, 1, -230)
logFrame.Position = UDim2.new(0, 12, 0, 224)
logFrame.BackgroundColor3 = T.panel
logFrame.BorderSizePixel = 0
Instance.new("UICorner", logFrame).CornerRadius = UDim.new(0, 8)

local logScroll = Instance.new("ScrollingFrame", logFrame)
logScroll.Size = UDim2.new(1, -8, 1, -8)
logScroll.Position = UDim2.new(0, 4, 0, 4)
logScroll.BackgroundTransparency = 1
logScroll.BorderSizePixel = 0
logScroll.ScrollBarThickness = 3
logScroll.ScrollBarImageColor3 = T.border
logScroll.CanvasSize = UDim2.new(0, 0, 0, 0)

local logText = Instance.new("TextLabel", logScroll)
logText.Size = UDim2.new(1, -4, 0, 0)
logText.Position = UDim2.new(0, 2, 0, 2)
logText.BackgroundTransparency = 1
logText.TextColor3 = T.text
logText.Font = Enum.Font.Code logText.TextSize = 10
logText.TextXAlignment = Enum.TextXAlignment.Left
logText.TextYAlignment = Enum.TextYAlignment.Top
logText.TextWrapped = true logText.RichText = true
logText.AutomaticSize = Enum.AutomaticSize.Y

local flut = Instance.new("TextButton", gui)
flut.Size = UDim2.new(0, 46, 0, 46)
flut.Position = UDim2.new(0, 20, 0.4, 0)
flut.BackgroundColor3 = T.bg
flut.Text = "🐉" flut.TextColor3 = T.accent
flut.Font = Enum.Font.GothamBold flut.TextSize = 20
flut.BorderSizePixel = 0 flut.Visible = false
flut.Active = true flut.Draggable = true
Instance.new("UICorner", flut).CornerRadius = UDim.new(1, 0)
local fstk = Instance.new("UIStroke", flut) fstk.Color = T.accent fstk.Thickness = 1

local drag, dStart, sStart = false, nil, nil
header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        drag = true dStart = i.Position sStart = main.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if drag and (i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dStart
        main.Position = UDim2.new(sStart.X.Scale, sStart.X.Offset + d.X,
            sStart.Y.Scale, sStart.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then drag = false end
end)

btnMin.MouseButton1Click:Connect(function()
    main.Visible = false flut.Visible = true
end)
flut.MouseButton1Click:Connect(function()
    main.Visible = true flut.Visible = false
end)

btnKill.MouseButton1Click:Connect(function()
    State.capturando = false
    removerHook()
    gui:Destroy()
    print("[DUMPER v4.1] Encerrado")
end)

task.spawn(function()
    while gui.Parent do
        task.wait(0.8)
        local linhas = {}
        local iniT = math.max(1, #State.trfBuf - 30)
        for i = iniT, #State.trfBuf do
            local t = State.trfBuf[i]
            local cor = CORES[t.cat] or CORES.OTHER
            local suf = t.count > 1 and (" (x"..t.count..")") or ""
            table.insert(linhas, string.format(
                "<font color='#888'>[%s]</font> <font color='#%s'>[%s]</font> <font color='#AAA'>%s</font><font color='#5FDC78'>%s</font>",
                t.primeiro, cor, t.cat, t.path:sub(-38), suf))
        end
        local iniL = math.max(1, #State.logBuf - 20)
        for i = iniL, #State.logBuf do
            local l = State.logBuf[i]
            local cor = CORES[l.cat] or CORES.INFO
            table.insert(linhas, string.format(
                "<font color='#666'>[%s]</font> <font color='#%s'>[%s]</font> <font color='#CCC'>%s</font>",
                l.hora, cor, l.cat, l.msg:sub(1, 70)))
        end
        logText.Text = #linhas == 0 and "<font color='#666'>Aguardando...</font>"
            or table.concat(linhas, "\n")
        logScroll.CanvasSize = UDim2.new(0, 0, 0, logText.AbsoluteSize.Y + 10)
        logScroll.CanvasPosition = Vector2.new(0, math.max(0, logScroll.CanvasSize.Y.Offset))
    end
end)

task.spawn(function()
    while gui.Parent do
        task.wait(1)
        titulo.Text = string.format("  🐉  DUMPER v4.1 | %d únicos | %s",
            #State.trfBuf, State.capturando and "🔴 REC" or "⚪")
    end
end)

print("[DUMPER v4.1] ✅ Pronto (seguro). CAPTURAR instala hook, PARAR remove.")