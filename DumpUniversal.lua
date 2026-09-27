-- ════════════════════════════════════════════════════════════════
--           DRAGON BLOX — DUMPER FINAL (v2.0 - DEDUP)
-- ════════════════════════════════════════════════════════════════
-- Captura arquitetural + tráfego + workspace em 1 script.
-- Otimizado: rate-limit, batch de logs, sem hook duplo, dedup.
-- ════════════════════════════════════════════════════════════════

print("[DUMPER] Iniciando...")

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local plr = Players.LocalPlayer

-- Parent seguro
local targetParent
if gethui then
    targetParent = gethui()
elseif syn and syn.protect_gui then
    targetParent = CoreGui
else
    local ok = pcall(function() local _ = CoreGui.Name end)
    targetParent = ok and CoreGui or plr:WaitForChild("PlayerGui")
end

-- ═══════════════════════════════════════════════
-- ESTADO
-- ═══════════════════════════════════════════════
local State = {
    sessao = "Sessao",
    capturando = false,
    hookAtivo = false,
    scanning = false,

    -- Buffers
    logBuf = {},         -- buffer de logs pra flush em batch
    trfBuf = {},         -- tráfego capturado
    arquitetural = {},   -- paths arquiteturais
    workspaceScan = {},  -- items/bosses vistos

    -- Filtros
    filtros = {
        skills = true,
        drops = true,
        bossEvent = true,
        swordOrb = true,
        toolbar = true,      -- novo filtro toolbar ativado por padrão
        ruido = false,       -- se true, loga TUDO
    },
}

local _nomecallOriginal = nil
local ultimoPath = {}
local RATE_LIMIT = 0.1  -- 10 logs/s por path no máximo
local MAX_TRF = 2000

-- ═══════════════════════════════════════════════
-- FILTRO DE RUÍDO (nunca loga)
-- ═══════════════════════════════════════════════
local RUIDO_KEYWORDS = {
    "Ping", "DataChanged", "PlayAnimation", "PlayEffect",
    "DamageLabel", "DamageNotifier", "Knockback", "RagdollData",
    "UpdateLocal", "Heartbeat", "changeAnimationClient",
    "GameAnalytics", "Postie",
}

local function ehRuido(path)
    if State.filtros.ruido then return false end
    for _, kw in ipairs(RUIDO_KEYWORDS) do
        if path:find(kw) then return true end
    end
    return false
end

-- ═══════════════════════════════════════════════
-- CLASSIFICADOR DE LOG (cor por tipo)
-- ═══════════════════════════════════════════════
local function classificar(path)
    if path:find("SkillRemote") then return "M1" end
    if path:find("ExecuteSkill") then return "SKILL" end
    if path:find("ItemSpawned") or path:find("ClaimItem") or path:find("WishService") then return "DROP" end
    if path:find("Boss") or path:find("Zaja") or path:find("Destroyer") or path:find("Event") then return "BOSS" end
    if path:find("Weapon") or path:find("Orb") then return "SWORD_ORB" end
    if path:find("Rebirth") or path:find("Prompt") then return "REBIRTH" end
    if path:find("LockedOn") then return "LOCK" end
    if path:find("ToolService") or path:find("UpdatePlayerToolbar") then return "TOOLBAR" end
    return "OTHER"
end

local CORES = {
    M1 = "5FE8FF",
    SKILL = "C68AFF",
    DROP = "5FDC78",
    BOSS = "FF5C5C",
    SWORD_ORB = "FFE45C",
    REBIRTH = "FF9642",
    LOCK = "8AFF8A",
    TOOLBAR = "FFD700",
    OTHER = "9A9AA0",
    ERROR = "FF5C5C",
    INFO = "74B8FF",
    SUCCESS = "5FDC78",
    WARN = "FFB43C",
}

-- ═══════════════════════════════════════════════
-- SERIALIZADOR
-- ═══════════════════════════════════════════════
local function ser(v, d)
    d = d or 0
    if d > 3 then return "..." end
    local t = typeof(v)
    if t == "Instance" then
        local ok, f = pcall(game.GetFullName, v)
        return ok and f or v.Name
    elseif t == "Vector3" then
        return string.format("V3(%.0f,%.0f,%.0f)", v.X, v.Y, v.Z)
    elseif t == "CFrame" then
        local p = v.Position
        return string.format("CF(%.0f,%.0f,%.0f)", p.X, p.Y, p.Z)
    elseif t == "table" then
        local p, n = {}, 0
        for k, vv in pairs(v) do
            n = n + 1
            if n > 10 then p[#p+1] = "..." break end
            p[#p+1] = tostring(k).."="..ser(vv, d+1)
        end
        return "{"..table.concat(p,",").."}"
    else
        return "["..t.."] "..tostring(v)
    end
end

-- ═══════════════════════════════════════════════
-- LOG BUFFER (com batching pra evitar lag)
-- ═══════════════════════════════════════════════
local function addLog(cat, msg)
    table.insert(State.logBuf, {
        cat = cat,
        msg = msg,
        hora = os.date("%H:%M:%S"),
        t = os.clock(),
    })
    if #State.logBuf > 500 then
        table.remove(State.logBuf, 1)
    end
end

-- ═══════════════════════════════════════════════
-- DEDUP (evita repetir o mesmo evento)
-- ═══════════════════════════════════════════════
local vistos = {}

local function addTrafego(cat, path, args)
    local chave = cat.."|"..path.."|"..args
    
    -- Se já viu, incrementa contador e atualiza timestamp
    if vistos[chave] then
        vistos[chave].count = vistos[chave].count + 1
        vistos[chave].ultimo = os.date("%H:%M:%S")
        return
    end
    
    -- Primeira vez: registra
    local entry = {
        cat = cat,
        path = path,
        args = args,
        count = 1,
        primeiro = os.date("%H:%M:%S"),
        ultimo = os.date("%H:%M:%S"),
    }
    vistos[chave] = entry
    table.insert(State.trfBuf, entry)
    
    if #State.trfBuf > MAX_TRF then
        table.remove(State.trfBuf, 1)
    end
end

-- ═══════════════════════════════════════════════
-- HOOK __namecall
-- ═══════════════════════════════════════════════
if hookmetamethod then
    _nomecallOriginal = hookmetamethod(game, "__namecall", function(self, ...)
        -- Captura args ANTES do pcall (varargs não herdam em closures)
        local n = select("#", ...)
        local capturedArgs = {...}

        if State.capturando then
            pcall(function()
                local m = getnamecallmethod()
                if m ~= "FireServer" and m ~= "Fire" and m ~= "InvokeServer" then
                    return
                end

                local okp, path = pcall(game.GetFullName, self)
                if not okp then return end
                if ehRuido(path) then return end

                -- Rate limit
                local agora = os.clock()
                if ultimoPath[path] and (agora - ultimoPath[path]) < RATE_LIMIT then
                    return
                end
                ultimoPath[path] = agora

                -- Classifica e checa filtro
                local cat = classificar(path)
                local aceito = false
                if cat == "M1" and State.filtros.skills then aceito = true end
                if cat == "SKILL" and State.filtros.skills then aceito = true end
                if cat == "DROP" and State.filtros.drops then aceito = true end
                if cat == "BOSS" and State.filtros.bossEvent then aceito = true end
                if cat == "SWORD_ORB" and State.filtros.swordOrb then aceito = true end
                if cat == "REBIRTH" then aceito = true end
                if cat == "LOCK" and State.filtros.skills then aceito = true end
                if cat == "TOOLBAR" and State.filtros.toolbar then aceito = true end
                if State.filtros.ruido then aceito = true end

                if not aceito then return end

                -- Serializa args
                local parts = {}
                for i = 1, math.min(n, 8) do
                    parts[#parts+1] = ser(capturedArgs[i])
                end
                local linha = path:gsub("ReplicatedStorage%.", "RS.")
                addTrafego(cat, linha, table.concat(parts, " | "))
            end)
        end

        return _nomecallOriginal(self, ...)
    end)
    State.hookAtivo = true
    print("[DUMPER] Hook __namecall ativado")
end

-- ═══════════════════════════════════════════════
-- SCANNER DE WORKSPACE (drops + boss event)
-- ═══════════════════════════════════════════════
task.spawn(function()
    local conhecidos = {}
    while true do
        task.wait(1)

        if State.capturando then
            -- 1) Drops no chão
            for _, obj in ipairs(WS:GetDescendants()) do
                if (obj:IsA("BasePart") or obj:IsA("Model")) and not conhecidos[obj] then
                    conhecidos[obj] = true
                    local nome = obj.Name
                    local parentNome = obj.Parent and obj.Parent.Name or ""
                    local parentPai = obj.Parent and obj.Parent.Parent and obj.Parent.Parent.Name or ""

                    -- Filtra só coisas relevantes
                    local ehDropReal = 
                        parentNome == "PartStorage"
                        or parentNome == "ShootingStar"
                        or parentNome:find("ItemDrop")
                        or parentNome == "Pad"
                        or parentPai == "PartStorage"
                        or parentPai == "ShootingStar"
                        or nome:find("Orb")
                        or nome:find("Star")
                        or nome:find("DragonBall")
                        or nome:find("Meteor")

                    if ehDropReal and State.filtros.drops then
                        local pos = obj:IsA("BasePart") and obj.Position
                            or (obj.PrimaryPart and obj.PrimaryPart.Position)
                        if pos then
                            addLog("DROP", string.format("%s | Pai: %s | V3(%.0f,%.0f,%.0f)",
                                nome, parentNome, pos.X, pos.Y, pos.Z))
                        end
                    end

                    -- 2) Boss de evento
                    local nomeLower = nome:lower()
                    if (nomeLower:find("zaja") or nomeLower:find("destroyer")
                        or nomeLower:find("eventboss") or nomeLower:find("raidboss"))
                        and State.filtros.bossEvent then
                        local hrp = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
                        local pos = hrp and hrp.Position or Vector3.zero
                        addLog("BOSS", string.format("%s | Pai: %s | V3(%.0f,%.0f,%.0f)",
                            obj:GetFullName(), parentNome, pos.X, pos.Y, pos.Z))
                    end
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════════════
-- SCAN ARQUITETURAL
-- ═══════════════════════════════════════════════
local function scanArquitetural()
    if State.scanning then return end
    State.scanning = true
    State.arquitetural = {}

    addLog("INFO", "Iniciando scan arquitetural...")

    task.spawn(function()
        local t0 = os.clock()
        local total = 0

        local function varrer(inst, path, depth)
            if depth > 8 or not inst then return end
            local ok, children = pcall(function() return inst:GetChildren() end)
            if not ok then return end

            for _, child in ipairs(children) do
                local cls = child.ClassName
                local nome = child.Name
                local childPath = path.."."..nome

                if cls ~= "Folder" then
                    if cls == "RemoteEvent" or cls == "RemoteFunction"
                    or cls == "UnreliableRemoteEvent"
                    or cls == "ModuleScript" or cls == "Script"
                    or cls == "LocalScript" then
                        table.insert(State.arquitetural, "["..cls.."] "..childPath)
                        total = total + 1
                    end
                end

                if cls == "Folder" or cls == "Model" then
                    varrer(child, childPath, depth + 1)
                end
            end
        end

        pcall(function() varrer(RS, "RS", 0) end)
        pcall(function() varrer(WS, "WS", 0) end)

        local dur = os.clock() - t0
        addLog("SUCCESS", string.format("Scan: %.2fs — %d itens", dur, total))
        State.scanning = false
    end)
end

-- ═══════════════════════════════════════════════
-- SALVAR ARQUIVO
-- ═══════════════════════════════════════════════
local function salvarArquivo()
    local L = {}
    table.insert(L, "═══════════════════════════════════════")
    table.insert(L, "  DUMP FINAL — Sessão: "..State.sessao)
    table.insert(L, "═══════════════════════════════════════")
    table.insert(L, "Player: "..plr.Name)
    table.insert(L, "PlaceId: "..game.PlaceId)
    table.insert(L, "Data: "..os.date("%Y-%m-%d %H:%M:%S"))
    table.insert(L, "Total tráfego: "..#State.trfBuf)
    table.insert(L, "Total arquitetural: "..#State.arquitetural)
    table.insert(L, "")

    -- Agrupa tráfego por categoria
    local porCat = {}
    for _, t in ipairs(State.trfBuf) do
        porCat[t.cat] = porCat[t.cat] or {}
        table.insert(porCat[t.cat], t)
    end

    table.insert(L, "═══ TRÁFEGO POR CATEGORIA ═══")
    for _, cat in ipairs({"M1", "SKILL", "DROP", "BOSS", "SWORD_ORB", "REBIRTH", "LOCK", "TOOLBAR", "OTHER"}) do
        if porCat[cat] then
            table.insert(L, "")
            table.insert(L, "### "..cat.." ("..#porCat[cat]..")")
            for _, t in ipairs(porCat[cat]) do
                if t.count > 1 then
                    table.insert(L, string.format("[%s ~ %s] (x%d) %s | %s",
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
    for _, linha in ipairs(State.arquitetural) do
        table.insert(L, linha)
    end

    local conteudo = table.concat(L, "\n")
    local nome = "Dump_"..State.sessao.."_"..os.time()..".txt"

    local ok = pcall(function() if writefile then writefile(nome, conteudo) end end)
    if ok then
        return "Salvo: "..nome.." ("..#conteudo.." bytes)"
    else
        pcall(function() if setclipboard then setclipboard(conteudo) end end)
        return "Salvo no clipboard ("..#conteudo.." bytes)"
    end
end

-- ═══════════════════════════════════════════════
-- UI — AMOLED CLEAN
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
    bg = Color3.fromRGB(0, 0, 0),
    panel = Color3.fromRGB(10, 10, 12),
    elev = Color3.fromRGB(18, 18, 22),
    border = Color3.fromRGB(30, 30, 36),
    accent = Color3.fromRGB(255, 140, 30),
    text = Color3.fromRGB(230, 230, 235),
    dim = Color3.fromRGB(140, 140, 150),
    success = Color3.fromRGB(80, 200, 120),
    danger = Color3.fromRGB(220, 60, 60),
    warn = Color3.fromRGB(255, 180, 60),
    info = Color3.fromRGB(74, 158, 255),
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

-- Header
local header = Instance.new("Frame", main)
header.Size = UDim2.new(1, 0, 0, 40)
header.BackgroundColor3 = T.panel
header.BorderSizePixel = 0
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)

local titulo = Instance.new("TextLabel", header)
titulo.Size = UDim2.new(1, -100, 1, 0)
titulo.Position = UDim2.new(0, 14, 0, 0)
titulo.BackgroundTransparency = 1
titulo.Text = "  🐉  DRAGON DUMPER"
titulo.TextColor3 = T.accent
titulo.Font = Enum.Font.GothamBold
titulo.TextSize = 13
titulo.TextXAlignment = Enum.TextXAlignment.Left

-- Botões header
local btnMin = Instance.new("TextButton", header)
btnMin.Size = UDim2.new(0, 24, 0, 24)
btnMin.Position = UDim2.new(1, -60, 0.5, -12)
btnMin.BackgroundColor3 = T.elev
btnMin.Text = "—"
btnMin.TextColor3 = T.text
btnMin.Font = Enum.Font.GothamBold
btnMin.TextSize = 14
btnMin.BorderSizePixel = 0
Instance.new("UICorner", btnMin).CornerRadius = UDim.new(0, 6)

local btnKill = Instance.new("TextButton", header)
btnKill.Size = UDim2.new(0, 24, 0, 24)
btnKill.Position = UDim2.new(1, -32, 0.5, -12)
btnKill.BackgroundColor3 = T.danger
btnKill.Text = "×"
btnKill.TextColor3 = Color3.new(1,1,1)
btnKill.Font = Enum.Font.GothamBold
btnKill.TextSize = 14
btnKill.BorderSizePixel = 0
Instance.new("UICorner", btnKill).CornerRadius = UDim.new(0, 6)

-- Sessão input
local input = Instance.new("TextBox", main)
input.Size = UDim2.new(1, -24, 0, 32)
input.Position = UDim2.new(0, 12, 0, 50)
input.BackgroundColor3 = T.elev
input.Text = "Sessao"
input.PlaceholderText = "Nome da sessão..."
input.TextColor3 = T.text
input.Font = Enum.Font.Gotham
input.TextSize = 12
input.BorderSizePixel = 0
Instance.new("UICorner", input).CornerRadius = UDim.new(0, 6)
local ipad = Instance.new("UIPadding", input)
ipad.PaddingLeft = UDim.new(0, 10)

-- Botões de ação
local function mkActionBtn(x, w, cor, txt, cb)
    local b = Instance.new("TextButton", main)
    b.Size = UDim2.new(0, w, 0, 34)
    b.Position = UDim2.new(0, x, 0, 90)
    b.BackgroundColor3 = cor
    b.Text = txt
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(cb)
    return b
end

mkActionBtn(12, 108, T.info, "📁 SCAN", function()
    State.sessao = input.Text ~= "" and input.Text or State.sessao
    scanArquitetural()
end)

local btnCap = mkActionBtn(126, 108, T.success, "▶ CAPTURAR", function()
    State.sessao = input.Text ~= "" and input.Text or State.sessao
    State.capturando = not State.capturando
    if State.capturando then
        btnCap.BackgroundColor3 = T.danger
        btnCap.Text = "■ PARAR"
        addLog("SUCCESS", "Captura INICIADA")
    else
        btnCap.BackgroundColor3 = T.success
        btnCap.Text = "▶ CAPTURAR"
        addLog("INFO", "Captura PARADA")
    end
end)

mkActionBtn(240, 108, T.accent, "💾 SALVAR", function()
    local msg = salvarArquivo()
    addLog("SUCCESS", msg)
end)

mkActionBtn(354, 114, Color3.fromRGB(120, 60, 180), "🗑 LIMPAR", function()
    State.trfBuf = {}
    State.logBuf = {}
    addLog("INFO", "Buffers limpos")
end)

-- Filtros
local filtroFrame = Instance.new("Frame", main)
filtroFrame.Size = UDim2.new(1, -24, 0, 30)
filtroFrame.Position = UDim2.new(0, 12, 0, 132)
filtroFrame.BackgroundColor3 = T.panel
filtroFrame.BorderSizePixel = 0
Instance.new("UICorner", filtroFrame).CornerRadius = UDim.new(0, 6)

local filtrosUI = Instance.new("UIListLayout", filtroFrame)
filtrosUI.FillDirection = Enum.FillDirection.Horizontal
filtrosUI.Padding = UDim.new(0, 4)
local fpad = Instance.new("UIPadding", filtroFrame)
fpad.PaddingLeft = UDim.new(0, 6)
fpad.PaddingTop = UDim.new(0, 3)

local function mkFiltro(nome, key)
    local b = Instance.new("TextButton", filtroFrame)
    b.Size = UDim2.new(0, 58, 0, 24) -- Diminuido levemente a width para caber mais botoes
    b.BackgroundColor3 = State.filtros[key] and T.success or T.elev
    b.Text = nome
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 9
    b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    b.MouseButton1Click:Connect(function()
        State.filtros[key] = not State.filtros[key]
        b.BackgroundColor3 = State.filtros[key] and T.success or T.elev
    end)
end

mkFiltro("Skills", "skills")
mkFiltro("Drops", "drops")
mkFiltro("Boss", "bossEvent")
mkFiltro("Sword/Orb", "swordOrb")
mkFiltro("Toolbar", "toolbar") -- Novo filtro visível na UI
mkFiltro("Ruído", "ruido")

-- Log ao vivo
local logFrame = Instance.new("Frame", main)
logFrame.Size = UDim2.new(1, -24, 1, -290)
logFrame.Position = UDim2.new(0, 12, 0, 172)
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
logText.Font = Enum.Font.Code
logText.TextSize = 10
logText.TextXAlignment = Enum.TextXAlignment.Left
logText.TextYAlignment = Enum.TextYAlignment.Top
logText.TextWrapped = true
logText.RichText = true
logText.AutomaticSize = Enum.AutomaticSize.Y

-- Flutuante (minimizado)
local flut = Instance.new("TextButton", gui)
flut.Size = UDim2.new(0, 46, 0, 46)
flut.Position = UDim2.new(0, 20, 0.4, 0)
flut.BackgroundColor3 = T.bg
flut.Text = "🐉"
flut.TextColor3 = T.accent
flut.Font = Enum.Font.GothamBold
flut.TextSize = 20
flut.BorderSizePixel = 0
flut.Visible = false
flut.Active = true
flut.Draggable = true
Instance.new("UICorner", flut).CornerRadius = UDim.new(1, 0)
local fstk = Instance.new("UIStroke", flut) fstk.Color = T.accent fstk.Thickness = 1

-- Drag header
local drag, dStart, sStart = false, nil, nil
header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        drag = true; dStart = i.Position; sStart = main.Position
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
    main.Visible = false
    flut.Visible = true
end)
flut.MouseButton1Click:Connect(function()
    main.Visible = true
    flut.Visible = false
end)

-- Kill switch
btnKill.MouseButton1Click:Connect(function()
    State.capturando = false
    if _nomecallOriginal and hookmetamethod then
        pcall(function() hookmetamethod(game, "__namecall", _nomecallOriginal) end)
    end
    gui:Destroy()
    print("[DUMPER] Encerrado e hook restaurado")
end)

-- ═══════════════════════════════════════════════
-- LOOPS
-- ═══════════════════════════════════════════════
-- Render do log (batch a cada 0.5s)
task.spawn(function()
    while gui.Parent do
        task.wait(0.5)

        -- Junta logs + tráfego recente
        local linhas = {}

        -- Últimos 30 tráfegos
        local iniT = math.max(1, #State.trfBuf - 30)
        for i = iniT, #State.trfBuf do
            local t = State.trfBuf[i]
            local cor = CORES[t.cat] or CORES.OTHER
            local suf = t.count > 1 and (" (x"..t.count..")") or ""
            table.insert(linhas, string.format(
                "<font color='#888'>[%s]</font> <font color='#%s'>[%s]</font> <font color='#AAA'>%s%s</font>",
                t.primeiro, cor, t.cat, t.path:sub(-40), suf))
        end

        -- Últimos 20 logs
        local iniL = math.max(1, #State.logBuf - 20)
        for i = iniL, #State.logBuf do
            local l = State.logBuf[i]
            local cor = CORES[l.cat] or CORES.INFO
            table.insert(linhas, string.format(
                "<font color='#666'>[%s]</font> <font color='#%s'>[%s]</font> <font color='#CCC'>%s</font>",
                l.hora, cor, l.cat, l.msg))
        end

        if #linhas == 0 then
            logText.Text = "<font color='#666'>Aguardando eventos...</font>"
        else
            logText.Text = table.concat(linhas, "\n")
        end

        logScroll.CanvasSize = UDim2.new(0, 0, 0, logText.AbsoluteSize.Y + 10)
        logScroll.CanvasPosition = Vector2.new(0, math.max(0, logScroll.CanvasSize.Y.Offset))
    end
end)

-- Status counter
task.spawn(function()
    while gui.Parent do
        task.wait(1)
        titulo.Text = string.format("  🐉  DRAGON DUMPER | %d trf | %d arq | %s",
            #State.trfBuf, #State.arquitetural,
            State.capturando and "🔴 REC" or "⚪")
    end
end)

print("[DUMPER] ✅ Pronto. Digite sessão → SCAN → CAPTURAR → ações no jogo → SALVAR")
