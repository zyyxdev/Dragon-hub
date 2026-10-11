print("[DUMPER v7.5] Iniciando...")

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HapticService = game:GetService("HapticService")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local plr = Players.LocalPlayer

local targetParent = (gethui and gethui()) or CoreGui

local STATE_FILE = "dumper_v75_state.txt"
local AUTO_FILE = "dumper_v75_auto.lua"
local PLACE_FILE = "dumper_v75_mainplace.txt"

local function NC(fn)
    return fn
end

local CATEGORIAS = {
    Dungeon = {"Dungeon", "Portal", "NextArea", "Wave", "Stage", "Lobby", "Match", "Queue", "Floor", "Boss"},
    Skills  = {"ExecuteSkill", "SkillRemote", "LockedOn"},
    Drops   = {"ClaimItem", "WishService", "ItemDropService", "Wish", "Orb"},
    Toolbar = {"Toolbar", "ToolService", "UpdatePlayerToolbar"},
    Rebirth = {"Rebirth", "Prompt"},
    Tudo    = nil,
}

local IGNORAR = {
    Ping = true, DataChanged = true, PlayAnimation = true, PlayEffect = true,
    DamageLabel = true, DamageNotifier = true, Knockback = true,
    RagdollData = true, UpdateLocal = true, Heartbeat = true,
    changeAnimationClient = true, GameAnalytics = true, Postie = true,
}

local MAX_BUFFER = 5000

local State = {
    sessao = "Sessao",
    capturando = false,
    categoria = "Dungeon",
    hooksSet = {},
    buffer = {},
    contadorBruto = 0,
    remotesEncontrados = 0,
    hookMetodo = "__namecall",
    _silencioso = true,
    catAtiva = "captura",
    filtroLogCat = "todos",
    nomesCache = setmetatable({}, {__mode = "k"}),
    resumido = false,
    nomecallInstalado = false,
    nomecallOriginal = nil,
    nomecallHook = nil,
    recvHooked = false,
    signalToRemote = setmetatable({}, {__mode = "k"}),
    connectOriginal = nil,
    connectHook = nil,
    stealthMode = true,
    placeMain = nil,
    emDungeon = false,
}

local function log(cat, msg)
    print(string.format("[DUMPER/%s] %s", cat, msg))
end

local _ultimoHaptic = 0
local _hapticSuportado = nil
local function haptic(tipo)
    tipo = tipo or "sucesso"
    if _hapticSuportado == nil then
        _hapticSuportado = pcall(function()
            return HapticService:IsMotorSupported(Enum.UserInputType.Touch, Enum.VibrationMotor.Small)
        end) and HapticService:IsMotorSupported(Enum.UserInputType.Touch, Enum.VibrationMotor.Small)
    end
    if not _hapticSuportado then return end
    local agora = tick()
    if agora - _ultimoHaptic < 0.2 then return end
    _ultimoHaptic = agora
    pcall(function()
        HapticService:SetMotor(Enum.UserInputType.Touch, Enum.VibrationMotor.Small, tipo == "erro" and 0.6 or 0.3)
        task.delay(0.06, function()
            pcall(function()
                HapticService:SetMotor(Enum.UserInputType.Touch, Enum.VibrationMotor.Small, 0)
            end)
        end)
    end)
end

local function getNome(inst)
    local c = State.nomesCache[inst]
    if c then return c end
    local ok, n = pcall(function() return inst:GetFullName() end)
    n = ok and n or "?"
    State.nomesCache[inst] = n
    return n
end

local function pathIgnorado(path)
    for k in pairs(IGNORAR) do
        if path:find(k, 1, true) then return true end
    end
    return false
end

local function classificar(path)
    if path:find("Dungeon") or path:find("dungeon")
    or path:find("NextArea") or path:find("Wave") or path:find("Stage")
    or path:find("Lobby") or path:find("Match") or path:find("Queue")
    or path:find("Floor") then return "DUNGEON" end
    if path:find("UpdatePlayerToolbar") or path:find("ToolService") then return "TOOLBAR" end
    if path:find("SkillRemote") then return "M1" end
    if path:find("ExecuteSkill") then return "SKILL" end
    if path:find("ClaimItem") or path:find("WishService")
    or path:find("ItemDropService") then return "DROP" end
    if path:find("Boss") then return "BOSS" end
    if path:find("Weapon") or path:find("Orb") then return "SWORD_ORB" end
    if path:find("Rebirth") or path:find("Prompt") then return "REBIRTH" end
    if path:find("LockedOn") then return "LOCK" end
    return "OTHER"
end

local CAT_INFO = {
    DUNGEON   = { icone = "🎮", nome = "Dungeon" },
    M1        = { icone = "🖱", nome = "M1" },
    SKILL     = { icone = "⚔", nome = "Skills" },
    DROP      = { icone = "💰", nome = "Drops" },
    BOSS      = { icone = "👹", nome = "Bosses" },
    SWORD_ORB = { icone = "🔮", nome = "Orbs" },
    TOOLBAR   = { icone = "🎒", nome = "Toolbar" },
    REBIRTH   = { icone = "🔄", nome = "Rebirth" },
    LOCK      = { icone = "🔒", nome = "Lock" },
    OTHER     = { icone = "❔", nome = "Outros" },
}

local function ser(v, d)
    d = d or 0
    if d > 2 then return "..." end
    local t = typeof(v)
    if t == "Instance" then return getNome(v) end
    if t == "Vector3" then
        return string.format("V3(%.0f,%.0f,%.0f)", v.X, v.Y, v.Z)
    end
    if t == "CFrame" then
        local p = v.Position
        return string.format("CF(%.0f,%.0f,%.0f)", p.X, p.Y, p.Z)
    end
    if t == "table" then
        local p, n = {}, 0
        for k, vv in pairs(v) do
            n = n + 1
            if n > 6 then p[#p+1] = "..." break end
            p[#p+1] = tostring(k).."="..ser(vv, d+1)
        end
        return "{"..table.concat(p,",").."}"
    end
    if t == "string" then
        if #v > 200 then v = v:sub(1, 200).."..." end
        return string.format("%q", v)
    end
    return "["..t.."] "..tostring(v)
end

local function serializarArgs(args, n)
    local parts = {}
    local max = math.min(n or #args, 6)
    for i = 1, max do
        parts[#parts+1] = ser(args[i])
    end
    return table.concat(parts, " | ")
end

local function captura(remote, metodo, args, n)
    if not State.capturando then return end
    if #State.buffer >= MAX_BUFFER then return end
    local ok, path = pcall(function() return remote:GetFullName() end)
    if not ok or not path then return end
    if pathIgnorado(path) then return end

    State.contadorBruto = State.contadorBruto + 1
    local cat = classificar(path)
    local argsSer = serializarArgs(args, n)
    State.buffer[#State.buffer+1] = {
        cat = cat,
        path = path:gsub("ReplicatedStorage%.", "RS."),
        metodo = metodo,
        argsSer = argsSer,
    }
end

local function instalarNomecall()
    if State.nomecallInstalado then return end
    if not (hookmetamethod and getnamecallmethod and getrawmetatable) then
        log("ERRO", "sem hookmetamethod/getnamecallmethod")
        return false
    end
    local mt = getrawmetatable(game)
    if not mt then return false end

    State.nomecallOriginal = mt.__namecall
    setreadonly(mt, false)
    State.nomecallHook = function(self, ...)
        if State.capturando then
            local alvo = State.hooksSet[self]
            if alvo then
                local metodo = getnamecallmethod()
                if metodo == "FireServer" or metodo == "InvokeServer" then
                    local n = select("#", ...)
                    local args = {...}
                    pcall(captura, self, metodo.."→", args, n)
                end
            end
        end
        return State.nomecallOriginal(self, ...)
    end
    mt.__namecall = State.nomecallHook
    setreadonly(mt, true)

    State.nomecallInstalado = true
    return true
end

local function removerNomecall()
    if not State.nomecallInstalado then return end
    pcall(function()
        local mt = getrawmetatable(game)
        if not mt then return end
        setreadonly(mt, false)
        mt.__namecall = State.nomecallOriginal
        setreadonly(mt, true)
    end)
    State.nomecallInstalado = false
    State.nomecallHook = nil
    State.nomecallOriginal = nil
end

local function instalarConnectOnce()
    if State.recvHooked then return end
    if not hookfunction then return end

    local sample = nil
    for r in pairs(State.hooksSet) do sample = r break end
    if not sample then return end

    local ok, signal = pcall(function() return sample.OnClientEvent end)
    if not ok or not signal then return end

    local origConnect = signal.Connect
    if not origConnect then return end

    State.connectOriginal = origConnect
    State.connectHook = function(self, fn)
        local remote = State.signalToRemote[self]
        if not remote then
            return origConnect(self, fn)
        end
        local wrapped = function(...)
            if State.capturando then
                local n = select("#", ...)
                local args = {...}
                pcall(captura, remote, "OnClientEvent←", args, n)
            end
            return fn(...)
        end
        return origConnect(self, wrapped)
    end

    pcall(function()
        hookfunction(origConnect, State.connectHook)
        State.recvHooked = true
    end)
end

local function removerConnect()
    if not State.recvHooked then return end
    pcall(function()
        if hookfunction and State.connectHook and State.connectOriginal then
            hookfunction(State.connectHook, State.connectOriginal)
        end
    end)
    State.recvHooked = false
    State.connectHook = nil
    State.connectOriginal = nil
end

local function listarRemotes()
    local out = {}
    for _, d in ipairs(RS:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") then
            out[#out+1] = d
        end
    end
    return out
end

local function estaEmDungeon()
    if not State.placeMain then return false end
    return game.PlaceId ~= State.placeMain
end

local function instalarHooks()
    State.hooksSet = {}
    State.signalToRemote = setmetatable({}, {__mode = "k"})

    local remotes = listarRemotes()
    State.remotesEncontrados = #remotes
    local lista = CATEGORIAS[State.categoria]
    local instalados = 0

    for _, r in ipairs(remotes) do
        local ok, path = pcall(function() return r:GetFullName() end)
        if ok and path and not pathIgnorado(path) then
            local bate = true
            if lista then
                bate = false
                for i = 1, #lista do
                    if path:find(lista[i], 1, true) then bate = true break end
                end
            end
            if bate then
                State.hooksSet[r] = path
                instalados = instalados + 1
                pcall(function()
                    State.signalToRemote[r.OnClientEvent] = r
                end)
            end
        end
    end

    if State.stealthMode and not estaEmDungeon() then
        log("INFO", string.format("STEALTH: main place (PlaceId %d). Hooks desligados.", game.PlaceId))
        log("INFO", "Ativa quando entrar na dungeon (PlaceId diferente).")
        return instalados
    end

    instalarNomecall()
    instalarConnectOnce()

    log("SUCCESS", string.format("Alvos: %d/%d | PlaceId: %d", instalados, #remotes, game.PlaceId))
    return instalados
end

local function removerHooks()
    removerNomecall()
    removerConnect()
    State.hooksSet = {}
    State.signalToRemote = setmetatable({}, {__mode = "k"})
end

local function checarStealth()
    if not State.capturando then return end
    if not State.stealthMode then return end
    local emDg = estaEmDungeon()
    if emDg ~= State.emDungeon then
        State.emDungeon = emDg
        if emDg then
            log("SUCCESS", "DUNGEON DETECTADA (PlaceId "..game.PlaceId..") — ativando hooks")
            instalarHooks()
        else
            log("INFO", "Voltou pro main place — desativando hooks")
            removerHooks()
            instalarHooks()
        end
    end
end

local function salvarPlaceMain()
    if not writefile then return end
    if State.placeMain then return end
    if State.capturando then return end
    if not isfile or not isfile(PLACE_FILE) then
        State.placeMain = game.PlaceId
        pcall(writefile, PLACE_FILE, tostring(game.PlaceId))
        return
    end
end

local function carregarPlaceMain()
    if not readfile or not isfile then
        State.placeMain = game.PlaceId
        return
    end
    if not isfile(PLACE_FILE) then
        State.placeMain = game.PlaceId
        pcall(writefile, PLACE_FILE, tostring(game.PlaceId))
        return
    end
    local ok, conteudo = pcall(readfile, PLACE_FILE)
    if ok and conteudo then
        State.placeMain = tonumber(conteudo)
    else
        State.placeMain = game.PlaceId
    end
end

local function salvarEstado()
    if not writefile then return end
    local linhas = {}
    linhas[#linhas+1] = "v=7.5"
    linhas[#linhas+1] = "ativo=" .. (State.capturando and "1" or "0")
    linhas[#linhas+1] = "sessao=" .. (State.sessao or "Sessao"):gsub("[\n\r]", "")
    linhas[#linhas+1] = "categoria=" .. (State.categoria or "Tudo")
    linhas[#linhas+1] = "contador=" .. tostring(State.contadorBruto or 0)
    linhas[#linhas+1] = "placeMain=" .. tostring(State.placeMain or "")
    linhas[#linhas+1] = "---BUFFER---"
    for i = 1, #State.buffer do
        local e = State.buffer[i]
        local argStr = (e.argsSer or ""):gsub("[\n\r\t]", " ")
        linhas[#linhas+1] = table.concat({e.cat or "OTHER", e.path or "", e.metodo or "FireServer→", argStr}, "\t")
    end
    pcall(writefile, STATE_FILE, table.concat(linhas, "\n"))
end

local function carregarEstado()
    if not readfile or not isfile then return false end
    if not isfile(STATE_FILE) then return false end
    local ok, conteudo = pcall(readfile, STATE_FILE)
    if not ok or not conteudo then return false end
    local header = {}
    local buffer = {}
    local inBuffer = false
    for linha in conteudo:gmatch("[^\n]+") do
        if linha == "---BUFFER---" then
            inBuffer = true
        elseif inBuffer then
            local cat, path, metodo, argStr = linha:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
            if cat and path then
                buffer[#buffer+1] = {
                    cat = cat, path = path, metodo = metodo or "FireServer→",
                    argsSer = argStr or "",
                }
            end
        else
            local k, v = linha:match("^(%w+)=(.*)$")
            if k then header[k] = v end
        end
    end
    if header.ativo ~= "1" then return false end
    State.sessao = header.sessao or State.sessao
    State.categoria = header.categoria or State.categoria
    State.contadorBruto = tonumber(header.contador) or 0
    State.buffer = buffer
    if header.placeMain and header.placeMain ~= "" then
        State.placeMain = tonumber(header.placeMain)
    end
    State.capturando = true
    State.resumido = true
    return true
end

local function limparEstado()
    if not delfile then return end
    pcall(delfile, STATE_FILE)
    State.resumido = false
end

local function salvarArquivo()
    if #State.buffer == 0 then
        log("INFO", "Buffer vazio")
        return false
    end

    local L = {}
    local function add(s) table.insert(L, s or "") end

    add("╔══════════════════════════════════════════════════════╗")
    add("║        🐉 DUMPER v7.5 — RELATÓRIO DE SESSÃO          ║")
    add("╚══════════════════════════════════════════════════════╝")
    add("")
    add("┌─ 📋 METADATA ────────────────────────────────────────")
    add("│ Player:       "..plr.Name)
    add("│ PlaceId:      "..game.PlaceId)
    add("│ PlaceMain:    "..tostring(State.placeMain))
    add("│ JobId:        "..(game.JobId ~= "" and game.JobId or "privado"))
    add("│ Data:         "..os.date("%Y-%m-%d %H:%M:%S"))
    add("│ Sessão:       "..State.sessao)
    add("│ Categoria:    "..State.categoria)
    add("│ Hook:         "..State.hookMetodo)
    add("│ Stealth:      "..(State.stealthMode and "ON" or "OFF"))
    add("│ Remotes:      "..State.remotesEncontrados)
    add("│ Bruto:        "..State.contadorBruto.." chamadas")
    add("│ Eventos:      "..#State.buffer.." no buffer")
    add("└──────────────────────────────────────────────────────")
    add("")
    add("╔══════════════════════════════════════════════════════╗")
    add("║              📡 TRÁFEGO SEQUENCIAL                   ║")
    add("║         → cliente envia  |  ← servidor envia         ║")
    add("╚══════════════════════════════════════════════════════╝")
    add("")

    for i = 1, #State.buffer do
        local e = State.buffer[i]
        local info = CAT_INFO[e.cat] or CAT_INFO.OTHER
        add(string.format("┃ [%04d] %s %s", i, info.icone, e.cat))
        add(string.format("┃   ▸ %s", e.path))
        add(string.format("┃   ▸ %s", e.metodo))
        add(string.format("┃   ↳ %s", e.argsSer))
        add("┃")
    end

    add("╔══════════════════════════════════════════════════════╗")
    add("║  Fim do dump — "..os.date("%Y-%m-%d %H:%M:%S").."            ║")
    add("╚══════════════════════════════════════════════════════╝")

    local conteudo = table.concat(L, "\n")
    local nome = "Dump_"..State.sessao.."_"..os.time()..".txt"
    local ok = pcall(function() if writefile then writefile(nome, conteudo) end end)
    if ok then
        log("SUCCESS", "Salvo: "..nome)
        limparEstado()
        return true
    end
    pcall(function() setclipboard(conteudo) end)
    log("SUCCESS", "Clipboard")
    limparEstado()
    return true
end

local old = targetParent:FindFirstChild("DumperFinal")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "DumperFinal"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
if syn and syn.protect_gui then
    pcall(function() syn.protect_gui(gui) end)
end
gui.Parent = targetParent

local T = {
    bg         = Color3.fromRGB(0, 0, 0),
    panel      = Color3.fromRGB(10, 10, 12),
    elev       = Color3.fromRGB(20, 20, 24),
    elevHover  = Color3.fromRGB(30, 30, 36),
    border     = Color3.fromRGB(38, 38, 46),
    accent     = Color3.fromRGB(0, 255, 198),
    accent2    = Color3.fromRGB(0, 180, 140),
    text       = Color3.fromRGB(240, 240, 245),
    textDim    = Color3.fromRGB(140, 145, 155),
    textMuted  = Color3.fromRGB(90, 95, 105),
    success    = Color3.fromRGB(80, 220, 140),
    danger     = Color3.fromRGB(255, 90, 90),
    warn       = Color3.fromRGB(255, 180, 60),
    info       = Color3.fromRGB(90, 170, 255),
}

local function safeUI(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then print("[DUMPER/UI-ERRO] "..tostring(err)) end
    end
end

local viewport = workspace.CurrentCamera.ViewportSize
local W = math.min(420, viewport.X * 0.92)
local H = math.min(560, viewport.Y * 0.88)

local main = Instance.new("Frame")
main.Size = UDim2.new(0, W, 0, H)
main.Position = UDim2.new(0.5, -W/2, 0.5, -H/2)
main.BackgroundColor3 = T.bg
main.BackgroundTransparency = 0.08
main.BorderSizePixel = 0
main.Active = true
main.Visible = false
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 14)
local mStroke = Instance.new("UIStroke", main)
mStroke.Color = T.border
mStroke.Thickness = 1
mStroke.Transparency = 0.4

local homeBar = Instance.new("TextButton")
homeBar.Size = UDim2.new(0, 160, 0, 26)
homeBar.Position = UDim2.new(0.5, -80, 1, -34)
homeBar.BackgroundColor3 = T.bg
homeBar.BackgroundTransparency = 0.5
homeBar.BorderSizePixel = 0
homeBar.Text = ""
homeBar.AutoButtonColor = false
homeBar.Active = true
homeBar.ZIndex = 100
homeBar.Parent = gui
Instance.new("UICorner", homeBar).CornerRadius = UDim.new(1, 0)
local hbStroke = Instance.new("UIStroke", homeBar)
hbStroke.Color = T.accent
hbStroke.Thickness = 1
hbStroke.Transparency = 0.5

local hbBar = Instance.new("Frame")
hbBar.Size = UDim2.new(0, 120, 0, 5)
hbBar.Position = UDim2.new(0.5, -60, 0.5, -2.5)
hbBar.BackgroundColor3 = T.accent
hbBar.BackgroundTransparency = 0.1
hbBar.BorderSizePixel = 0
hbBar.Parent = homeBar
Instance.new("UICorner", hbBar).CornerRadius = UDim.new(1, 0)

local function pulsarHomeBar()
    TweenService:Create(hbBar, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
        BackgroundTransparency = 0.6
    }):Play()
    task.delay(0.15, function()
        TweenService:Create(hbBar, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
            BackgroundTransparency = 0.1
        }):Play()
    end)
end

homeBar.MouseButton1Click:Connect(safeUI(function()
    haptic("sucesso")
    pulsarHomeBar()
    main.Visible = not main.Visible
end))

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 42)
header.BackgroundTransparency = 1
header.Parent = main

local titulo = Instance.new("TextLabel")
titulo.Size = UDim2.new(1, -140, 1, 0)
titulo.Position = UDim2.new(0, 18, 0, 0)
titulo.BackgroundTransparency = 1
titulo.Text = "🐉  DUMPER v7.5"
titulo.TextColor3 = T.accent
titulo.Font = Enum.Font.GothamBold
titulo.TextSize = 14
titulo.TextXAlignment = Enum.TextXAlignment.Left
titulo.Parent = header

local statusDot = Instance.new("Frame")
statusDot.Size = UDim2.new(0, 8, 0, 8)
statusDot.Position = UDim2.new(1, -116, 0.5, -4)
statusDot.BackgroundColor3 = T.textMuted
statusDot.BorderSizePixel = 0
statusDot.Parent = header
Instance.new("UICorner", statusDot).CornerRadius = UDim.new(1, 0)

local statusTxt = Instance.new("TextLabel")
statusTxt.Size = UDim2.new(0, 70, 1, 0)
statusTxt.Position = UDim2.new(1, -104, 0, 0)
statusTxt.BackgroundTransparency = 1
statusTxt.Text = "parado"
statusTxt.TextColor3 = T.textDim
statusTxt.Font = Enum.Font.GothamMedium
statusTxt.TextSize = 10
statusTxt.TextXAlignment = Enum.TextXAlignment.Left
statusTxt.Parent = header

local btnMin = Instance.new("TextButton")
btnMin.Size = UDim2.new(0, 26, 0, 26)
btnMin.Position = UDim2.new(1, -68, 0.5, -13)
btnMin.BackgroundColor3 = T.elev
btnMin.Text = "—"
btnMin.TextColor3 = T.text
btnMin.Font = Enum.Font.GothamBold
btnMin.TextSize = 14
btnMin.BorderSizePixel = 0
btnMin.AutoButtonColor = false
btnMin.Parent = header
Instance.new("UICorner", btnMin).CornerRadius = UDim.new(0, 6)

local btnKill = Instance.new("TextButton")
btnKill.Size = UDim2.new(0, 26, 0, 26)
btnKill.Position = UDim2.new(1, -36, 0.5, -13)
btnKill.BackgroundColor3 = T.elev
btnKill.Text = "×"
btnKill.TextColor3 = T.danger
btnKill.Font = Enum.Font.GothamBold
btnKill.TextSize = 16
btnKill.BorderSizePixel = 0
btnKill.AutoButtonColor = false
btnKill.Parent = header
Instance.new("UICorner", btnKill).CornerRadius = UDim.new(0, 6)

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 118, 1, -78)
sidebar.Position = UDim2.new(0, 12, 0, 50)
sidebar.BackgroundColor3 = T.panel
sidebar.BackgroundTransparency = 0.35
sidebar.BorderSizePixel = 0
sidebar.Parent = main
Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0, 10)

local sbList = Instance.new("UIListLayout", sidebar)
sbList.Padding = UDim.new(0, 4)
sbList.SortOrder = Enum.SortOrder.LayoutOrder
local sbPad = Instance.new("UIPadding", sidebar)
sbPad.PaddingTop = UDim.new(0, 6)
sbPad.PaddingLeft = UDim.new(0, 6)
sbPad.PaddingRight = UDim.new(0, 6)

local sidebarItens = {}
local atualizarSidebar, atualizarConteudo

local function criarItemSidebar(id, icone, nome, subtituloFn)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 52)
    btn.BackgroundColor3 = T.elev
    btn.BackgroundTransparency = 0.5
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.Parent = sidebar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

    local ic = Instance.new("TextLabel")
    ic.Size = UDim2.new(0, 26, 0, 26)
    ic.Position = UDim2.new(0, 8, 0, 6)
    ic.BackgroundTransparency = 1
    ic.Text = icone
    ic.TextSize = 16
    ic.Parent = btn

    local nm = Instance.new("TextLabel")
    nm.Size = UDim2.new(1, -40, 0, 16)
    nm.Position = UDim2.new(0, 38, 0, 8)
    nm.BackgroundTransparency = 1
    nm.Text = nome
    nm.TextColor3 = T.text
    nm.TextSize = 11
    nm.Font = Enum.Font.GothamBold
    nm.TextXAlignment = Enum.TextXAlignment.Left
    nm.Parent = btn

    local sub = Instance.new("TextLabel")
    sub.Size = UDim2.new(1, -14, 0, 14)
    sub.Position = UDim2.new(0, 10, 0, 32)
    sub.BackgroundTransparency = 1
    sub.Text = "—"
    sub.TextColor3 = T.textMuted
    sub.TextSize = 9
    sub.Font = Enum.Font.GothamMedium
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.Parent = btn

    sidebarItens[id] = { btn = btn, sub = sub, subFn = subtituloFn }

    btn.MouseButton1Click:Connect(safeUI(function()
        haptic("sucesso")
        State.catAtiva = id
        if atualizarSidebar then atualizarSidebar() end
        if atualizarConteudo then atualizarConteudo() end
    end))

    return btn
end

local content = Instance.new("Frame")
content.Size = UDim2.new(1, -142, 1, -78)
content.Position = UDim2.new(0, 130, 0, 50)
content.BackgroundColor3 = T.panel
content.BackgroundTransparency = 0.35
content.BorderSizePixel = 0
content.Parent = main
Instance.new("UICorner", content).CornerRadius = UDim.new(0, 10)

local painelCaptura = Instance.new("Frame")
painelCaptura.Size = UDim2.new(1, 0, 1, 0)
painelCaptura.BackgroundTransparency = 1
painelCaptura.Parent = content

local inputSessao = Instance.new("TextBox")
inputSessao.Size = UDim2.new(1, -24, 0, 36)
inputSessao.Position = UDim2.new(0, 12, 0, 12)
inputSessao.BackgroundColor3 = T.elev
inputSessao.Text = "Sessao"
inputSessao.PlaceholderText = "Nome da sessão..."
inputSessao.TextColor3 = T.text
inputSessao.PlaceholderColor3 = T.textMuted
inputSessao.Font = Enum.Font.GothamMedium
inputSessao.TextSize = 12
inputSessao.BorderSizePixel = 0
inputSessao.ClearTextOnFocus = false
inputSessao.Parent = painelCaptura
Instance.new("UICorner", inputSessao).CornerRadius = UDim.new(0, 8)
local ip = Instance.new("UIPadding", inputSessao)
ip.PaddingLeft = UDim.new(0, 12)

local btnCap = Instance.new("TextButton")
btnCap.Size = UDim2.new(1, -24, 0, 48)
btnCap.Position = UDim2.new(0, 12, 0, 58)
btnCap.BackgroundColor3 = T.accent
btnCap.Text = "▶  INICIAR CAPTURA"
btnCap.TextColor3 = T.bg
btnCap.Font = Enum.Font.GothamBold
btnCap.TextSize = 13
btnCap.BorderSizePixel = 0
btnCap.AutoButtonColor = false
btnCap.Parent = painelCaptura
Instance.new("UICorner", btnCap).CornerRadius = UDim.new(0, 8)

local resumoLabel = Instance.new("TextLabel")
resumoLabel.Size = UDim2.new(1, -24, 0, 20)
resumoLabel.Position = UDim2.new(0, 12, 0, 112)
resumoLabel.BackgroundTransparency = 1
resumoLabel.Text = ""
resumoLabel.TextColor3 = T.success
resumoLabel.Font = Enum.Font.GothamBold
resumoLabel.TextSize = 10
resumoLabel.TextXAlignment = Enum.TextXAlignment.Left
resumoLabel.Parent = painelCaptura

local btnStealth = Instance.new("TextButton")
btnStealth.Size = UDim2.new(1, -24, 0, 32)
btnStealth.Position = UDim2.new(0, 12, 0, 136)
btnStealth.BackgroundColor3 = T.elev
btnStealth.Text = "🥷  Stealth: ON (só hooka na dungeon)"
btnStealth.TextColor3 = T.success
btnStealth.Font = Enum.Font.GothamBold
btnStealth.TextSize = 10
btnStealth.BorderSizePixel = 0
btnStealth.AutoButtonColor = false
btnStealth.Parent = painelCaptura
Instance.new("UICorner", btnStealth).CornerRadius = UDim.new(0, 8)

local btnTeleporte = Instance.new("TextButton")
btnTeleporte.Size = UDim2.new(1, -24, 0, 30)
btnTeleporte.Position = UDim2.new(0, 12, 0, 174)
btnTeleporte.BackgroundColor3 = T.elev
btnTeleporte.Text = "🔗  Auto-teleporte"
btnTeleporte.TextColor3 = T.warn
btnTeleporte.Font = Enum.Font.GothamBold
btnTeleporte.TextSize = 10
btnTeleporte.BorderSizePixel = 0
btnTeleporte.AutoButtonColor = false
btnTeleporte.Parent = painelCaptura
Instance.new("UICorner", btnTeleporte).CornerRadius = UDim.new(0, 8)

local btnSilencioso = Instance.new("TextButton")
btnSilencioso.Size = UDim2.new(1, -24, 0, 30)
btnSilencioso.Position = UDim2.new(0, 12, 0, 210)
btnSilencioso.BackgroundColor3 = T.elev
btnSilencioso.Text = "🔇  Modo silencioso"
btnSilencioso.TextColor3 = T.text
btnSilencioso.Font = Enum.Font.GothamBold
btnSilencioso.TextSize = 10
btnSilencioso.BorderSizePixel = 0
btnSilencioso.AutoButtonColor = false
btnSilencioso.Parent = painelCaptura
Instance.new("UICorner", btnSilencioso).CornerRadius = UDim.new(0, 8)

local feedTitulo = Instance.new("TextLabel")
feedTitulo.Size = UDim2.new(1, -24, 0, 20)
feedTitulo.Position = UDim2.new(0, 12, 0, 246)
feedTitulo.BackgroundTransparency = 1
feedTitulo.Text = "FLUXO RECENTE"
feedTitulo.TextColor3 = T.textDim
feedTitulo.TextSize = 9
feedTitulo.Font = Enum.Font.GothamBold
feedTitulo.TextXAlignment = Enum.TextXAlignment.Left
feedTitulo.Parent = painelCaptura

local feedScroll = Instance.new("ScrollingFrame")
feedScroll.Size = UDim2.new(1, -24, 1, -276)
feedScroll.Position = UDim2.new(0, 12, 0, 268)
feedScroll.BackgroundColor3 = T.bg
feedScroll.BackgroundTransparency = 0.5
feedScroll.BorderSizePixel = 0
feedScroll.ScrollBarThickness = 3
feedScroll.ScrollBarImageColor3 = T.border
feedScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
feedScroll.Parent = painelCaptura
Instance.new("UICorner", feedScroll).CornerRadius = UDim.new(0, 8)
local fpad = Instance.new("UIPadding", feedScroll)
fpad.PaddingLeft = UDim.new(0, 10)
fpad.PaddingTop = UDim.new(0, 8)
fpad.PaddingRight = UDim.new(0, 10)
fpad.PaddingBottom = UDim.new(0, 8)

local feedText = Instance.new("TextLabel")
feedText.Size = UDim2.new(1, 0, 0, 0)
feedText.BackgroundTransparency = 1
feedText.TextColor3 = T.text
feedText.Font = Enum.Font.Code
feedText.TextSize = 10
feedText.TextXAlignment = Enum.TextXAlignment.Left
feedText.TextYAlignment = Enum.TextYAlignment.Top
feedText.TextWrapped = true
feedText.Text = ""
feedText.Parent = feedScroll

local painelFiltros = Instance.new("Frame")
painelFiltros.Size = UDim2.new(1, 0, 1, 0)
painelFiltros.BackgroundTransparency = 1
painelFiltros.Visible = false
painelFiltros.Parent = content

local filtrosScroll = Instance.new("ScrollingFrame")
filtrosScroll.Size = UDim2.new(1, -24, 1, -24)
filtrosScroll.Position = UDim2.new(0, 12, 0, 12)
filtrosScroll.BackgroundTransparency = 1
filtrosScroll.BorderSizePixel = 0
filtrosScroll.ScrollBarThickness = 3
filtrosScroll.ScrollBarImageColor3 = T.border
filtrosScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
filtrosScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
filtrosScroll.Parent = painelFiltros
local flList = Instance.new("UIListLayout", filtrosScroll)
flList.Padding = UDim.new(0, 4)

local catBtns = {}

local function criarSeletorCategoria(nome)
    local f = Instance.new("TextButton")
    f.Size = UDim2.new(1, 0, 0, 44)
    f.BackgroundColor3 = (State.categoria == nome) and T.elevHover or T.elev
    f.BackgroundTransparency = 0.3
    f.Text = ""
    f.AutoButtonColor = false
    f.BorderSizePixel = 0
    f.Parent = filtrosScroll
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)

    local nm = Instance.new("TextLabel")
    nm.Size = UDim2.new(1, -40, 1, 0)
    nm.Position = UDim2.new(0, 16, 0, 0)
    nm.BackgroundTransparency = 1
    nm.Text = nome
    nm.TextColor3 = (State.categoria == nome) and T.accent or T.text
    nm.TextSize = 12
    nm.Font = Enum.Font.GothamBold
    nm.TextXAlignment = Enum.TextXAlignment.Left
    nm.Parent = f

    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 10, 0, 10)
    dot.Position = UDim2.new(1, -22, 0.5, -5)
    dot.BackgroundColor3 = (State.categoria == nome) and T.accent or T.textMuted
    dot.BorderSizePixel = 0
    dot.Parent = f
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    catBtns[nome] = { btn = f, dot = dot, label = nm }

    f.MouseButton1Click:Connect(safeUI(function()
        haptic("sucesso")
        State.categoria = nome
        for c, ref in pairs(catBtns) do
            local ativo = (c == nome)
            ref.btn.BackgroundColor3 = ativo and T.elevHover or T.elev
            ref.label.TextColor3 = ativo and T.accent or T.text
            ref.dot.BackgroundColor3 = ativo and T.accent or T.textMuted
        end
        if State.capturando then instalarHooks() end
        if atualizarSidebar then atualizarSidebar() end
    end))
end

criarSeletorCategoria("Dungeon")
criarSeletorCategoria("Skills")
criarSeletorCategoria("Drops")
criarSeletorCategoria("Toolbar")
criarSeletorCategoria("Rebirth")
criarSeletorCategoria("Tudo")

local painelLogs = Instance.new("Frame")
painelLogs.Size = UDim2.new(1, 0, 1, 0)
painelLogs.BackgroundTransparency = 1
painelLogs.Visible = false
painelLogs.Parent = content

local logTabs = Instance.new("Frame")
logTabs.Size = UDim2.new(1, -24, 0, 60)
logTabs.Position = UDim2.new(0, 12, 0, 12)
logTabs.BackgroundTransparency = 1
logTabs.Parent = painelLogs
local ltLayout = Instance.new("UIListLayout", logTabs)
ltLayout.FillDirection = Enum.FillDirection.Horizontal
ltLayout.Padding = UDim.new(0, 4)
ltLayout.Wraps = true
ltLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

local filtroLogBtns = {}
local function criarTabLog(cat, label)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 52, 0, 26)
    b.BackgroundColor3 = T.elev
    b.BackgroundTransparency = 0.3
    b.Text = label
    b.TextColor3 = T.textDim
    b.Font = Enum.Font.GothamBold
    b.TextSize = 9
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Parent = logTabs
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    filtroLogBtns[cat] = b
    b.MouseButton1Click:Connect(safeUI(function()
        haptic("sucesso")
        State.filtroLogCat = cat
        for c, bt in pairs(filtroLogBtns) do
            bt.BackgroundColor3 = (c == cat) and T.accent2 or T.elev
            bt.TextColor3 = (c == cat) and T.bg or T.textDim
        end
    end))
end

criarTabLog("todos", "todos")
criarTabLog("DUNGEON", "dungeon")
criarTabLog("SKILL", "skill")
criarTabLog("DROP", "drop")
criarTabLog("BOSS", "boss")
criarTabLog("M1", "m1")

local logsScroll = Instance.new("ScrollingFrame")
logsScroll.Size = UDim2.new(1, -24, 1, -86)
logsScroll.Position = UDim2.new(0, 12, 0, 78)
logsScroll.BackgroundColor3 = T.bg
logsScroll.BackgroundTransparency = 0.5
logsScroll.BorderSizePixel = 0
logsScroll.ScrollBarThickness = 3
logsScroll.ScrollBarImageColor3 = T.border
logsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
logsScroll.Parent = painelLogs
Instance.new("UICorner", logsScroll).CornerRadius = UDim.new(0, 8)
local lp = Instance.new("UIPadding", logsScroll)
lp.PaddingLeft = UDim.new(0, 10)
lp.PaddingTop = UDim.new(0, 8)
lp.PaddingRight = UDim.new(0, 10)
lp.PaddingBottom = UDim.new(0, 8)

local logsText = Instance.new("TextLabel")
logsText.Size = UDim2.new(1, 0, 0, 0)
logsText.BackgroundTransparency = 1
logsText.TextColor3 = T.text
logsText.Font = Enum.Font.Code
logsText.TextSize = 10
logsText.TextXAlignment = Enum.TextXAlignment.Left
logsText.TextYAlignment = Enum.TextYAlignment.Top
logsText.TextWrapped = true
logsText.Text = ""
logsText.Parent = logsScroll

local painelArquivo = Instance.new("Frame")
painelArquivo.Size = UDim2.new(1, 0, 1, 0)
painelArquivo.BackgroundTransparency = 1
painelArquivo.Visible = false
painelArquivo.Parent = content

local function mkBotaoAcao(y, icone, nome, desc, cor, corFeedback, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -24, 0, 54)
    b.Position = UDim2.new(0, 12, 0, y)
    b.BackgroundColor3 = T.elev
    b.BackgroundTransparency = 0.3
    b.Text = ""
    b.AutoButtonColor = false
    b.BorderSizePixel = 0
    b.Parent = painelArquivo
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)

    local ic = Instance.new("TextLabel")
    ic.Size = UDim2.new(0, 32, 0, 32)
    ic.Position = UDim2.new(0, 12, 0.5, -16)
    ic.BackgroundTransparency = 1
    ic.Text = icone
    ic.TextSize = 20
    ic.Parent = b

    local nm = Instance.new("TextLabel")
    nm.Size = UDim2.new(1, -70, 0, 18)
    nm.Position = UDim2.new(0, 54, 0, 8)
    nm.BackgroundTransparency = 1
    nm.Text = nome
    nm.TextColor3 = cor
    nm.TextSize = 12
    nm.Font = Enum.Font.GothamBold
    nm.TextXAlignment = Enum.TextXAlignment.Left
    nm.Parent = b

    local ds = Instance.new("TextLabel")
    ds.Size = UDim2.new(1, -70, 0, 16)
    ds.Position = UDim2.new(0, 54, 0, 28)
    ds.BackgroundTransparency = 1
    ds.Text = desc
    ds.TextColor3 = T.textMuted
    ds.TextSize = 9
    ds.Font = Enum.Font.GothamMedium
    ds.TextXAlignment = Enum.TextXAlignment.Left
    ds.Parent = b

    local origCor = T.elev
    b.MouseButton1Click:Connect(safeUI(function()
        haptic("sucesso")
        TweenService:Create(b, TweenInfo.new(0.08), { BackgroundColor3 = corFeedback }):Play()
        task.delay(0.15, function()
            TweenService:Create(b, TweenInfo.new(0.3), { BackgroundColor3 = origCor }):Play()
        end)
        if cb then cb() end
    end))
end

mkBotaoAcao(12, "🔧", "Reinstalar Hooks", "Aplica categoria atual", T.info, T.info, function()
    if State.capturando then
        instalarHooks()
    else
        log("INFO", "Inicie captura primeiro")
    end
end)

mkBotaoAcao(74, "💾", "Salvar Dump", "Gera .txt e limpa estado", T.accent, T.success, function()
    State.sessao = inputSessao.Text ~= "" and inputSessao.Text or State.sessao
    salvarArquivo()
end)

mkBotaoAcao(136, "🗑", "Limpar Buffers", "Apaga tráfego + estado", T.warn, T.warn, function()
    State.buffer = {}
    State.contadorBruto = 0
    limparEstado()
    log("INFO", "Buffers limpos")
end)

mkBotaoAcao(198, "🔴", "Resetar Estado", "Força início fresco", T.danger, T.danger, function()
    limparEstado()
    State.resumido = false
    log("INFO", "Estado resetado")
end)

mkBotaoAcao(260, "📍", "Resetar PlaceMain", "Esquece place principal", T.danger, T.danger, function()
    if delfile then pcall(delfile, PLACE_FILE) end
    State.placeMain = game.PlaceId
    log("INFO", "PlaceMain resetado para "..game.PlaceId)
end)

local painelDiag = Instance.new("Frame")
painelDiag.Size = UDim2.new(1, 0, 1, 0)
painelDiag.BackgroundTransparency = 1
painelDiag.Visible = false
painelDiag.Parent = content

local diagText = Instance.new("TextLabel")
diagText.Size = UDim2.new(1, -24, 1, -80)
diagText.Position = UDim2.new(0, 12, 0, 12)
diagText.BackgroundColor3 = T.bg
diagText.BackgroundTransparency = 0.5
diagText.Text = "Toque em 'Rodar diagnóstico'."
diagText.TextColor3 = T.text
diagText.Font = Enum.Font.Code
diagText.TextSize = 10
diagText.TextXAlignment = Enum.TextXAlignment.Left
diagText.TextYAlignment = Enum.TextYAlignment.Top
diagText.TextWrapped = true
diagText.Parent = painelDiag
Instance.new("UICorner", diagText).CornerRadius = UDim.new(0, 8)
local dp = Instance.new("UIPadding", diagText)
dp.PaddingLeft = UDim.new(0, 12)
dp.PaddingTop = UDim.new(0, 10)

local btnDiag = Instance.new("TextButton")
btnDiag.Size = UDim2.new(1, -24, 0, 36)
btnDiag.Position = UDim2.new(0, 12, 1, -48)
btnDiag.BackgroundColor3 = T.elev
btnDiag.Text = "🩺  Rodar diagnóstico"
btnDiag.TextColor3 = T.text
btnDiag.Font = Enum.Font.GothamBold
btnDiag.TextSize = 11
btnDiag.BorderSizePixel = 0
btnDiag.AutoButtonColor = false
btnDiag.Parent = painelDiag
Instance.new("UICorner", btnDiag).CornerRadius = UDim.new(0, 8)

local footer = Instance.new("Frame")
footer.Size = UDim2.new(1, -24, 0, 26)
footer.Position = UDim2.new(0, 12, 1, -34)
footer.BackgroundTransparency = 1
footer.Parent = main

local footTxt = Instance.new("TextLabel")
footTxt.Size = UDim2.new(1, 0, 1, 0)
footTxt.BackgroundTransparency = 1
footTxt.Text = "0 bruto • 0 buffer • PlaceId: 0"
footTxt.TextColor3 = T.textMuted
footTxt.Font = Enum.Font.GothamMedium
footTxt.TextSize = 10
footTxt.TextXAlignment = Enum.TextXAlignment.Left
footTxt.Parent = footer

criarItemSidebar("captura", "📡", "Captura", function()
    if State.resumido then return "▶ resumido" end
    if State.capturando then return "REC • "..State.contadorBruto end
    return State.contadorBruto > 0 and (State.contadorBruto.." bruto") or "parado"
end)
criarItemSidebar("filtros", "🎛", "Categoria", function()
    return State.categoria
end)
criarItemSidebar("logs", "📊", "Logs", function()
    return #State.buffer.." buffer"
end)
criarItemSidebar("arquivo", "📁", "Arquivo", function()
    return #State.buffer > 0 and (#State.buffer.." eventos") or "vazio"
end)
criarItemSidebar("diag", "🩺", "Diagnóstico", function()
    if State.stealthMode and not State.emDungeon then return "stealth" end
    return State.capturando and "hook on" or "hook off"
end)

atualizarSidebar = function()
    for id, item in pairs(sidebarItens) do
        local ativo = (State.catAtiva == id)
        item.btn.BackgroundColor3 = ativo and T.elevHover or T.elev
        item.btn.BackgroundTransparency = ativo and 0.2 or 0.6
        local sub = item.subFn and item.subFn() or "—"
        item.sub.Text = sub
        item.sub.TextColor3 = ativo and T.accent or T.textMuted
    end
end

atualizarConteudo = function()
    painelCaptura.Visible = (State.catAtiva == "captura")
    painelFiltros.Visible = (State.catAtiva == "filtros")
    painelLogs.Visible = (State.catAtiva == "logs")
    painelArquivo.Visible = (State.catAtiva == "arquivo")
    painelDiag.Visible = (State.catAtiva == "diag")
end

local function atualizarBtnCap()
    if State.capturando then
        btnCap.BackgroundColor3 = T.danger
        btnCap.Text = "■  PARAR CAPTURA"
        statusDot.BackgroundColor3 = T.danger
        statusTxt.Text = "gravando"
        statusTxt.TextColor3 = T.danger
    else
        btnCap.BackgroundColor3 = T.accent
        btnCap.Text = "▶  INICIAR CAPTURA"
        statusDot.BackgroundColor3 = T.textMuted
        statusTxt.Text = "parado"
        statusTxt.TextColor3 = T.textDim
    end
    if State.resumido then
        resumoLabel.Text = "▶ RETOMADO | "..#State.buffer.." eventos"
    else
        resumoLabel.Text = ""
    end
    atualizarSidebar()
end

btnCap.MouseButton1Click:Connect(safeUI(function()
    haptic("sucesso")
    State.sessao = inputSessao.Text ~= "" and inputSessao.Text or State.sessao
    State.capturando = not State.capturando
    if State.capturando then
        if not State.resumido then
            State.buffer = {}
            State.contadorBruto = 0
        end
        print("[DUMPER] 🔴 CAPTURA INICIADA | PlaceId: "..game.PlaceId)
        instalarHooks()
        salvarEstado()
    else
        print("[DUMPER] ⚪ CAPTURA PARADA")
        removerHooks()
        salvarEstado()
    end
    atualizarBtnCap()
end))

btnStealth.MouseButton1Click:Connect(safeUI(function()
    haptic("sucesso")
    State.stealthMode = not State.stealthMode
    if State.stealthMode then
        btnStealth.Text = "🥷  Stealth: ON (só hooka na dungeon)"
        btnStealth.TextColor3 = T.success
        if State.capturando then
            removerHooks()
            instalarHooks()
        end
    else
        btnStealth.Text = "🥷  Stealth: OFF (hooka sempre)"
        btnStealth.TextColor3 = T.warn
        if State.capturando then
            instalarHooks()
        end
    end
end))

btnTeleporte.MouseButton1Click:Connect(safeUI(function()
    haptic("sucesso")
    salvarEstado()
    local fonte = nil
    if getscript then
        local ok, s = pcall(getscript)
        if ok and type(s) == "string" and #s > 500 then fonte = s end
    end
    if not fonte and getgenv and getgenv().getscript then
        local ok, s = pcall(getgenv().getscript)
        if ok and type(s) == "string" and #s > 500 then fonte = s end
    end
    if not fonte then
        warn("[DUMPER] getscript indisponível. Use auto-exec do Delta.")
        btnTeleporte.Text = "⚠  Use auto-exec do Delta"
        btnTeleporte.TextColor3 = T.danger
        return
    end
    local ok = pcall(writefile, AUTO_FILE, fonte)
    if not ok then
        warn("[DUMPER] Falha ao salvar fonte")
        return
    end
    local queueFn = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
    if queueFn then
        pcall(queueFn, 'loadfile("'..AUTO_FILE..'")()')
        btnTeleporte.Text = "✅  Auto-teleporte armado"
        btnTeleporte.TextColor3 = T.success
        log("SUCCESS", "Auto-teleporte armado")
    else
        warn("[DUMPER] queue_on_teleport indisponível")
        btnTeleporte.Text = "⚠  Use auto-exec do Delta"
        btnTeleporte.TextColor3 = T.danger
    end
end))

btnSilencioso.MouseButton1Click:Connect(safeUI(function()
    haptic("sucesso")
    State._silencioso = not State._silencioso
    btnSilencioso.Text = State._silencioso and "🔇  Modo silencioso" or "🔊  Modo verboso"
    btnSilencioso.TextColor3 = State._silencioso and T.text or T.warn
end))

btnMin.MouseButton1Click:Connect(safeUI(function()
    haptic("sucesso")
    main.Visible = false
end))

btnKill.MouseButton1Click:Connect(safeUI(function()
    haptic("erro")
    salvarEstado()
    State.capturando = false
    removerHooks()
    gui:Destroy()
    print("[DUMPER v7.5] Encerrado")
end))

btnDiag.MouseButton1Click:Connect(safeUI(function()
    haptic("sucesso")
    local total = 0
    for _ in pairs(State.hooksSet) do total = total + 1 end
    local info = {}
    table.insert(info, "Executor:    "..tostring(identifyexecutor and identifyexecutor() or "?"))
    table.insert(info, "Nomecall:    "..tostring(State.nomecallInstalado))
    table.insert(info, "Stealth:     "..tostring(State.stealthMode))
    table.insert(info, "PlaceMain:   "..tostring(State.placeMain))
    table.insert(info, "PlaceAtual:  "..game.PlaceId)
    table.insert(info, "EmDungeon:   "..tostring(State.emDungeon))
    table.insert(info, "Categoria:   "..State.categoria)
    table.insert(info, "Alvos:       "..total)
    table.insert(info, "Bruto:       "..State.contadorBruto)
    table.insert(info, "Buffer:      "..#State.buffer)
    table.insert(info, "Resumido:    "..tostring(State.resumido))
    diagText.Text = table.concat(info, "\n")
end))

local dragging, dStart, sStart = false, nil, nil
header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dStart = i.Position
        sStart = main.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dStart
        main.Position = UDim2.new(
            sStart.X.Scale, sStart.X.Offset + d.X,
            sStart.Y.Scale, sStart.Y.Offset + d.Y
        )
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

local _ultimoCount = -1
local _ultimaCat = nil
local _ultimoSidebar = -1

task.spawn(function()
    while gui.Parent do
        task.wait(1.2)
        footTxt.Text = string.format("%d bruto • %d buffer • PlaceId: %d",
            State.contadorBruto, #State.buffer, game.PlaceId)

        if #State.buffer == _ultimoCount and State.catAtiva == _ultimaCat then
            if State.contadorBruto ~= _ultimoSidebar then
                atualizarSidebar()
                _ultimoSidebar = State.contadorBruto
            end
            continue
        end
        _ultimoCount = #State.buffer
        _ultimaCat = State.catAtiva

        if painelCaptura.Visible then
            local linhas = {}
            local ini = math.max(1, #State.buffer - 12)
            for i = ini, #State.buffer do
                local e = State.buffer[i]
                local info = CAT_INFO[e.cat] or CAT_INFO.OTHER
                table.insert(linhas, string.format("%s %s — %s %s",
                    info.icone, e.cat, e.metodo, e.path:sub(-32)))
            end
            feedText.Text = #linhas == 0 and "Aguardando..." or table.concat(linhas, "\n")
            feedScroll.CanvasSize = UDim2.new(0, 0, 0, feedText.TextBounds.Y + 20)
        end

        if painelLogs.Visible then
            local linhasL = {}
            local filtro = State.filtroLogCat
            local ini2 = math.max(1, #State.buffer - 40)
            for i = ini2, #State.buffer do
                local e = State.buffer[i]
                if filtro == "todos" or e.cat == filtro then
                    local info = CAT_INFO[e.cat] or CAT_INFO.OTHER
                    table.insert(linhasL, string.format("%s %s  %s\n",
                        info.icone, e.metodo, e.path))
                end
            end
            logsText.Text = #linhasL == 0 and "Sem entradas." or table.concat(linhasL, "")
            logsScroll.CanvasSize = UDim2.new(0, 0, 0, logsText.TextBounds.Y + 20)
        end

        if State.contadorBruto ~= _ultimoSidebar then
            atualizarSidebar()
            _ultimoSidebar = State.contadorBruto
        end
    end
end)

task.spawn(function()
    while gui.Parent do
        task.wait(10)
        if State.capturando then
            salvarEstado()
        end
    end
end)

task.spawn(function()
    while gui.Parent do
        task.wait(2)
        pcall(checarStealth)
    end
end)

carregarPlaceMain()
local resumiu = carregarEstado()
if resumiu then
    log("SUCCESS", "Estado retomado | "..#State.buffer.." eventos | PlaceId "..game.PlaceId)
    instalarHooks()
end

if not State.placeMain then
    State.placeMain = game.PlaceId
    pcall(writefile, PLACE_FILE, tostring(game.PlaceId))
end

atualizarSidebar()
atualizarConteudo()
atualizarBtnCap()

print("[DUMPER v7.5] ✅ Pronto — stealth mode ativo")
