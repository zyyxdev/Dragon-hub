print("[DUMPER v3] Iniciando...")

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local plr = Players.LocalPlayer

local targetParent
if gethui then
    targetParent = gethui()
elseif syn and syn.protect_gui then
    targetParent = CoreGui
else
    local ok = pcall(function() local _ = CoreGui.Name end)
    targetParent = ok and CoreGui or plr:WaitForChild("PlayerGui")
end

-- ESTADO
local State = {
    sessao = "Sessao",
    capturando = false,
    hookAtivo = false,
    scanning = false,
    
    logBuf = {},
    trfBuf = {},
    arquitetural = {},
    unicos = {},        -- [hash] = entry
    
    filtros = {
        skills = true,
        drops = true,
        bossEvent = true,
        swordOrb = true,
        toolbar = true,
        ruido = false,
    },
}

local _nomecallOriginal = nil
local ultimoPath = {}
local RATE_LIMIT = 0.1
local MAX_UNICOS = 3000

--FILTRO DE RUÍDO
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
-- CLASSIFICADOR
-- ═══════════════════════════════════════════════
local function classificar(path)
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
    M1 = "5FE8FF",
    SKILL = "C68AFF",
    DROP = "5FDC78",
    BOSS = "FF5C5C",
    SWORD_ORB = "FFE45C",
    REBIRTH = "FF9642",
    LOCK = "8AFF8A",
    TOOLBAR = "FF9AC6",
    EVENT = "9A9AA0",
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
            if n > 8 then p[#p+1] = "..." break end
            p[#p+1] = tostring(k).."="..ser(vv, d+1)
        end
        return "{"..table.concat(p,",").."}"
    else
        return "["..t.."] "..tostring(v)
    end
end

-- ═══════════════════════════════════════════════
-- BUFFERS
-- ═══════════════════════════════════════════════
local function addLog(cat, msg)
    table.insert(State.logBuf, {
        cat = cat, msg = msg,
        hora = os.date("%H:%M:%S"), t = os.clock(),
    })
    if #State.logBuf > 500 then
        table.remove(State.logBuf, 1)
    end
end

-- DEDUP: mesma chave só conta uma vez
local function addTrafego(cat, path, args)
    -- Ignora "Event" sem args (ruído puro)
    if cat == "EVENT" and (args == "" or args == nil) then return end
    
    local chave = cat.."|"..path.."|"..args
    
    if State.unicos[chave] then
        State.unicos[chave].count = State.unicos[chave].count + 1
        State.unicos[chave].ultimo = os.date("%H:%M:%S")
        return
    end
    
    local entry = {
        cat = cat, path = path, args = args,
        count = 1,
        primeiro = os.date("%H:%M:%S"),
        ultimo = os.date("%H:%M:%S"),
    }
    State.unicos[chave] = entry
    table.insert(State.trfBuf, entry)
    
    if #State.trfBuf > MAX_UNICOS then
        local removido = table.remove(State.trfBuf, 1)
        -- Encontra e remove do mapa unicos
        for k, v in pairs(State.unicos) do
            if v == removido then State.unicos[k] = nil break end
        end
    end
end

-- ═══════════════════════════════════════════════
-- HOOK __namecall
-- ═══════════════════════════════════════════════
if hookmetamethod then
    _nomecallOriginal = hookmetamethod(game, "__namecall", function(self, ...)
        local n = select("#", ...)
        local capturedArgs = {...}
        
        if State.capturando then
            pcall(function()
                local m = getnamecallmethod()
                if m ~= "FireServer" and m ~= "Fire" and m ~= "InvokeServer" then return end
                
                local okp, path = pcall(game.GetFullName, self)
                if not okp then return end
                if ehRuido(path) then return end
                
                local agora = os.clock()
                if ultimoPath[path] and (agora - ultimoPath[path]) < RATE_LIMIT then return end
                ultimoPath[path] = agora
                
                local cat = classificar(path)
                local aceito = false
                if cat == "M1" and State.filtros.skills then aceito = true end
                if cat == "SKILL" and State.filtros.skills then aceito = true end
                if cat == "DROP" and State.filtros.drops then aceito = true end
                if cat == "BOSS" and State.filtros.bossEvent then aceito = true end
                if cat == "SWORD_ORB" and State.filtros.swordOrb then aceito = true end
                if cat == "TOOLBAR" and State.filtros.toolbar then aceito = true end
                if cat == "REBIRTH" then aceito = true end
                if cat == "LOCK" and State.filtros.skills then aceito = true end
                if cat == "EVENT" then aceito = true end
                if State.filtros.ruido then aceito = true end
                
                if not aceito then return end
                
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
    print("[DUMPER v3] Hook ativado")
end

-- ═══════════════════════════════════════════════
-- SCANNER DE WORKSPACE (1s, global)
-- ═══════════════════════════════════════════════
task.spawn(function()
    local conhecidos = {}
    while true do
        task.wait(1)  -- era 5s, agora 1s
        
        if State.capturando then
            -- Varre TUDO (não só Workspace) por objetos novos
            for _, obj in ipairs(game:GetDescendants()) do
                if (obj:IsA("BasePart") or obj:IsA("Model") or obj:IsA("MeshPart")) 
                and not conhecidos[obj] then
                    conhecidos[obj] = true
                    
                    local nome = obj.Name
                    local nomeLower = nome:lower()
                    local parentNome = obj.Parent and obj.Parent.Name or ""
                    local gpNome = obj.Parent and obj.Parent.Parent and obj.Parent.Parent.Name or ""
                    
                    -- 1) ITEM / ESFERA / DROP
                    local ehItem = 
                        parentNome == "PartStorage"
                        or parentNome == "ShootingStar"
                        or parentNome:find("ItemDrop")
                        or parentNome == "Pad"
                        or gpNome == "PartStorage"
                        or gpNome == "ShootingStar"
                        or nomeLower:find("orb")
                        or nomeLower:find("sphere")
                        or nomeLower:find("star")
                        or nomeLower:find("dragonball")
                        or nomeLower:find("wish")
                        or nomeLower:find("meteor")
                        or nomeLower:find("esfera")
                        or nomeLower:find("drop")
                        or nomeLower:find("item")
                    
                    if ehItem and State.filtros.drops then
                        local pos = obj:IsA("BasePart") and obj.Position
                            or (obj.PrimaryPart and obj.PrimaryPart.Position)
                        if pos then
                            addLog("DROP", string.format("%s | Pai: %s | V3(%.0f,%.0f,%.0f)",
                                obj:GetFullName(), parentNome, pos.X, pos.Y, pos.Z))
                        end
                    end
                    
                    -- 2) BOSS (event + normal)
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
    table.insert(L, "  DUMP v3 — Sessão: "..State.sessao)
    table.insert(L, "═══════════════════════════════════════")
    table.insert(L, "Player: "..plr.Name)
    table.insert(L, "PlaceId: "..game.PlaceId)
    table.insert(L, "Data: "..os.date("%Y-%m-%d %H:%M:%S"))
    table.insert(L, "Total único: "..#State.trfBuf)
    table.insert(L, "Total arquitetural: "..#State.arquitetural)
    table.insert(L, "")
    
    -- Agrupa por categoria
    local porCat = {}
    for _, t in ipairs(State.trfBuf) do
        porCat[t.cat] = porCat[t.cat] or {}
        table.insert(porCat[t.cat], t)
    end
    
    table.insert(L, "═══ TRÁFEGO POR CATEGORIA ═══")
    for _, cat in ipairs({"M1", "SKILL", "DROP", "BOSS", "SWORD_ORB", 
                          "TOOLBAR", "REBIRTH", "LOCK", "EVENT", "OTHER"}) do
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
main.Size = UDim2.new(0, 480, 0, 540)
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
titulo.Text = "  🐉  DUMPER v3"
titulo.TextColor3 = T.accent
titulo.Font = Enum.Font.GothamBold
titulo.TextSize = 13
titulo.TextXAlignment = Enum.TextXAlignment.Left

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
    State.unicos = {}
    State.logBuf = {}
    addLog("INFO", "Buffers limpos")
end)

-- Filtros
local filtroFrame = Instance.new("Frame", main)
filtroFrame.Size = UDim2.new(1, -24, 0, 56)
filtroFrame.Position = UDim2.new(0, 12, 0, 132)
filtroFrame.BackgroundColor3 = T.panel
filtroFrame.BorderSizePixel = 0
Instance.new("UICorner", filtroFrame).CornerRadius = UDim.new(0, 6)

local filtrosUI = Instance.new("UIListLayout", filtroFrame)
filtrosUI.FillDirection = Enum.FillDirection.Horizontal
filtrosUI.Padding = UDim.new(0, 4)
filtrosUI.Wraps = true
local fpad = Instance.new("UIPadding", filtroFrame)
fpad.PaddingLeft = UDim.new(0, 6)
fpad.PaddingTop = UDim.new(0, 4)

local function mkFiltro(nome, key, cor)
    local b = Instance.new("TextButton", filtroFrame)
    b.Size = UDim2.new(0, 68, 0, 24)
    b.BackgroundColor3 = State.filtros[key] and (cor or T.success) or T.elev
    b.Text = nome
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 9
    b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    b.MouseButton1Click:Connect(function()
        State.filtros[key] = not State.filtros[key]
        b.BackgroundColor3 = State.filtros[key] and (cor or T.success) or T.elev
    end)
end

mkFiltro("Skills", "skills", Color3.fromRGB(120, 60, 180))
mkFiltro("Drops", "drops", Color3.fromRGB(80, 200, 120))
mkFiltro("Boss", "bossEvent", Color3.fromRGB(220, 60, 60))
mkFiltro("Sword/Orb", "swordOrb", Color3.fromRGB(255, 200, 60))
mkFiltro("Toolbar", "toolbar", Color3.fromRGB(255, 150, 200))
mkFiltro("Ruído", "ruido", Color3.fromRGB(120, 120, 120))

-- Log ao vivo
local logFrame = Instance.new("Frame", main)
logFrame.Size = UDim2.new(1, -24, 1, -290)
logFrame.Position = UDim2.new(0, 12, 0, 196)
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

-- Flutuante
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

-- Drag
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
    main.Visible = false; flut.Visible = true
end)
flut.MouseButton1Click:Connect(function()
    main.Visible = true; flut.Visible = false
end)

btnKill.MouseButton1Click:Connect(function()
    State.capturando = false
    if _nomecallOriginal and hookmetamethod then
        pcall(function() hookmetamethod(game, "__namecall", _nomecallOriginal) end)
    end
    gui:Destroy()
    print("[DUMPER v3] Encerrado e hook restaurado")
end)

-- ═══════════════════════════════════════════════
-- LOOPS
-- ═══════════════════════════════════════════════
-- Render
task.spawn(function()
    while gui.Parent do
        task.wait(0.5)
        local linhas = {}
        
        -- Últimos 30 tráfegos
        local iniT = math.max(1, #State.trfBuf - 30)
        for i = iniT, #State.trfBuf do
            local t = State.trfBuf[i]
            local cor = CORES[t.cat] or CORES.OTHER
            local suf = t.count > 1 and (" (x"..t.count..")") or ""
            table.insert(linhas, string.format(
                "<font color='#888'>[%s]</font> <font color='#%s'>[%s]</font> <font color='#AAA'>%s</font><font color='#5FDC78'>%s</font>",
                t.primeiro, cor, t.cat, t.path:sub(-38), suf))
        end
        
        -- Últimos 20 logs
        local iniL = math.max(1, #State.logBuf - 20)
        for i = iniL, #State.logBuf do
            local l = State.logBuf[i]
            local cor = CORES[l.cat] or CORES.INFO
            table.insert(linhas, string.format(
                "<font color='#666'>[%s]</font> <font color='#%s'>[%s]</font> <font color='#CCC'>%s</font>",
                l.hora, cor, l.cat, l.msg:sub(1, 70)))
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

-- Header counter
task.spawn(function()
    while gui.Parent do
        task.wait(1)
        titulo.Text = string.format("  🐉  DUMPER v3 | %d únicos | %s",
            #State.trfBuf,
            State.capturando and "🔴 REC" or "⚪")
    end
end)

print("[DUMPER v3] ✅ Pronto. Digite sessão → SCAN → CAPTURAR → ações → SALVAR")