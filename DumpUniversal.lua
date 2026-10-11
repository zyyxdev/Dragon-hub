print("[DUMPER v7.0] Iniciando...")

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local plr = Players.LocalPlayer

local targetParent = (gethui and gethui()) or CoreGui

local MAX_BUFFER = 800

local CATEGORIAS = {
    Dungeon = {"Dungeon", "Portal", "NextArea", "Wave", "Stage", "Lobby", "Match", "Queue", "Floor"},
    Skills  = {"ExecuteSkill", "SkillRemote", "LockedOn"},
    Drops   = {"ClaimItem", "WishService", "ItemDropService", "Wish"},
    Bosses  = {"Boss"},
    Orbs    = {"Weapon", "Orb"},
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

local State = {
    capturando = false,
    categoria = "Dungeon",
    hooks = {},
    buffer = {},
    total = 0,
    remotesEncontrados = 0,
    sessao = "Sessao",
}

local function log(cat, msg)
    print(string.format("[DUMPER/%s] %s", cat, msg))
end

local function pathBate(path, categoria)
    local lista = CATEGORIAS[categoria]
    if not lista then return true end
    for i = 1, #lista do
        if path:find(lista[i], 1, true) then return true end
    end
    return false
end

local function pathIgnorado(path)
    for k in pairs(IGNORAR) do
        if path:find(k, 1, true) then return true end
    end
    return false
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

local function captura(remote, metodo, args)
    if not State.capturando then return end
    if #State.buffer >= MAX_BUFFER then return end
    local ok, path = pcall(function() return remote:GetFullName() end)
    if not ok or not path then return end
    if pathIgnorado(path) then return end
    if not pathBate(path, State.categoria) then return end

    State.total = State.total + 1
    State.buffer[#State.buffer+1] = {
        path = path,
        metodo = metodo,
        args = args,
        t = os.clock(),
    }
end

local function instalarHookEm(remote)
    if State.hooks[remote] then return end
    local ok = pcall(function()
        if remote:IsA("RemoteFunction") then
            local orig = remote.InvokeServer
            local wrapper = function(self, ...)
                local args = {...}
                pcall(captura, remote, "InvokeServer", args)
                return orig(self, ...)
            end
            remote.InvokeServer = wrapper
            State.hooks[remote] = {orig = orig, wrapper = wrapper}
        else
            local orig = remote.FireServer
            local wrapper = function(self, ...)
                local args = {...}
                pcall(captura, remote, "FireServer", args)
                return orig(self, ...)
            end
            remote.FireServer = wrapper
            State.hooks[remote] = {orig = orig, wrapper = wrapper}
        end
    end)
    if not ok then
        log("ERRO", "Falha hook: "..remote.Name)
    end
end

local function removerTodosHooks()
    for remote, info in pairs(State.hooks) do
        pcall(function()
            if remote:IsA("RemoteFunction") then
                remote.InvokeServer = info.orig
            else
                remote.FireServer = info.orig
            end
        end)
    end
    State.hooks = {}
end

local function instalarHooks()
    removerTodosHooks()
    local remotes = listarRemotes()
    State.remotesEncontrados = #remotes
    local lista = CATEGORIAS[State.categoria]
    local instalados = 0
    for _, r in ipairs(remotes) do
        local ok, path = pcall(function() return r:GetFullName() end)
        if ok and path then
            if pathIgnorado(path) then goto continue end
            local bate = true
            if lista then
                bate = false
                for i = 1, #lista do
                    if path:find(lista[i], 1, true) then bate = true break end
                end
            end
            if bate then
                instalarHookEm(r)
                instalados = instalados + 1
            end
        end
        ::continue::
    end
    log("SUCCESS", string.format("Hooks instalados: %d/%d", instalados, #remotes))
    return instalados
end

local function ser(v, d)
    d = d or 0
    if d > 2 then return "..." end
    local t = typeof(v)
    if t == "Instance" then
        local ok, n = pcall(function() return v:GetFullName() end)
        return ok and n or "?"
    end
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
        if #v > 200 then v = v:sub(1, 200) .. "..." end
        return string.format("%q", v)
    end
    return "["..t.."] "..tostring(v)
end

local function salvarArquivo()
    if #State.buffer == 0 then
        log("INFO", "Buffer vazio")
        return false
    end

    local L = {}
    local function add(s) L[#L+1] = s or "" end

    add("=== DUMPER v7.0 ===")
    add("Player:   "..plr.Name)
    add("PlaceId:  "..game.PlaceId)
    add("JobId:    "..(game.JobId ~= "" and game.JobId or "privado"))
    add("Data:     "..os.date("%Y-%m-%d %H:%M:%S"))
    add("Sessao:   "..State.sessao)
    add("Categoria:"..State.categoria)
    add("Remotes:  "..State.remotesEncontrados)
    add("Eventos:  "..State.total)
    add("Buffer:   "..#State.buffer)
    add("")
    add("=== TRÁFEGO ===")
    add("")

    local t0 = State.buffer[1] and State.buffer[1].t or 0
    for i = 1, #State.buffer do
        local e = State.buffer[i]
        local delta = string.format("%.2f", e.t - t0)
        local argsStr = ""
        for j = 1, math.min(#e.args, 6) do
            argsStr = argsStr .. (j > 1 and " | " or "") .. ser(e.args[j])
        end
        add(string.format("[+%ss] %s -> %s(%s)", delta, e.path, e.metodo, argsStr))
    end

    local conteudo = table.concat(L, "\n")
    local nome = "Dump_"..State.sessao.."_"..os.time()..".txt"
    local ok = pcall(function()
        if writefile then writefile(nome, conteudo) end
    end)
    if ok then
        log("SUCCESS", "Salvo: "..nome)
        return true
    end
    pcall(function() setclipboard(conteudo) end)
    log("SUCCESS", "Copiado pro clipboard")
    return true
end

local old = targetParent:FindFirstChild("DumperV7")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "DumperV7"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
if syn and syn.protect_gui then
    pcall(function() syn.protect_gui(gui) end)
end
gui.Parent = targetParent

local T = {
    bg = Color3.fromRGB(0, 0, 0),
    panel = Color3.fromRGB(14, 14, 16),
    elev = Color3.fromRGB(24, 24, 28),
    accent = Color3.fromRGB(0, 255, 198),
    danger = Color3.fromRGB(255, 80, 80),
    warn = Color3.fromRGB(255, 180, 60),
    text = Color3.fromRGB(235, 235, 240),
    dim = Color3.fromRGB(130, 135, 145),
    muted = Color3.fromRGB(80, 85, 95),
}

local function safeUI(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then warn("[DUMPER/UI] "..tostring(err)) end
    end
end

local W, H = 300, 260
local main = Instance.new("Frame")
main.Size = UDim2.new(0, W, 0, H)
main.Position = UDim2.new(0.5, -W/2, 0.5, -H/2)
main.BackgroundColor3 = T.bg
main.BackgroundTransparency = 0.05
main.BorderSizePixel = 0
main.Active = true
main.Visible = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", main)
stroke.Color = T.accent
stroke.Thickness = 1
stroke.Transparency = 0.6

local homeBar = Instance.new("TextButton")
homeBar.Size = UDim2.new(0, 100, 0, 22)
homeBar.Position = UDim2.new(0.5, -50, 1, -30)
homeBar.BackgroundColor3 = T.panel
homeBar.BorderSizePixel = 0
homeBar.Text = "DUMPER"
homeBar.TextColor3 = T.accent
homeBar.Font = Enum.Font.GothamBold
homeBar.TextSize = 10
homeBar.AutoButtonColor = false
homeBar.ZIndex = 100
homeBar.Parent = gui
Instance.new("UICorner", homeBar).CornerRadius = UDim.new(1, 0)
homeBar.MouseButton1Click:Connect(safeUI(function()
    main.Visible = not main.Visible
end))

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 32)
header.BackgroundTransparency = 1
header.Parent = main

local titulo = Instance.new("TextLabel")
titulo.Size = UDim2.new(1, -80, 1, 0)
titulo.Position = UDim2.new(0, 14, 0, 0)
titulo.BackgroundTransparency = 1
titulo.Text = "DUMPER v7.0"
titulo.TextColor3 = T.accent
titulo.Font = Enum.Font.GothamBold
titulo.TextSize = 12
titulo.TextXAlignment = Enum.TextXAlignment.Left
titulo.Parent = header

local dot = Instance.new("Frame")
dot.Size = UDim2.new(0, 8, 0, 8)
dot.Position = UDim2.new(1, -68, 0.5, -4)
dot.BackgroundColor3 = T.muted
dot.BorderSizePixel = 0
dot.Parent = header
Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

local statusTxt = Instance.new("TextLabel")
statusTxt.Size = UDim2.new(0, 50, 1, 0)
statusTxt.Position = UDim2.new(1, -56, 0, 0)
statusTxt.BackgroundTransparency = 1
statusTxt.Text = "off"
statusTxt.TextColor3 = T.dim
statusTxt.Font = Enum.Font.GothamMedium
statusTxt.TextSize = 9
statusTxt.TextXAlignment = Enum.TextXAlignment.Left
statusTxt.Parent = header

local btnKill = Instance.new("TextButton")
btnKill.Size = UDim2.new(0, 22, 0, 22)
btnKill.Position = UDim2.new(1, -28, 0.5, -11)
btnKill.BackgroundColor3 = T.elev
btnKill.Text = "×"
btnKill.TextColor3 = T.danger
btnKill.Font = Enum.Font.GothamBold
btnKill.TextSize = 14
btnKill.BorderSizePixel = 0
btnKill.AutoButtonColor = false
btnKill.Parent = header
Instance.new("UICorner", btnKill).CornerRadius = UDim.new(0, 5)

local headerDrag, hStart, hPos = false, nil, nil
header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        headerDrag = true
        hStart = i.Position
        hPos = main.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if headerDrag and (i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - hStart
        main.Position = UDim2.new(
            hPos.X.Scale, hPos.X.Offset + d.X,
            hPos.Y.Scale, hPos.Y.Offset + d.Y
        )
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        headerDrag = false
    end
end)

local sessaoLabel = Instance.new("TextLabel")
sessaoLabel.Size = UDim2.new(1, -20, 0, 16)
sessaoLabel.Position = UDim2.new(0, 10, 0, 38)
sessaoLabel.BackgroundTransparency = 1
sessaoLabel.Text = "Nome da sessão"
sessaoLabel.TextColor3 = T.dim
sessaoLabel.Font = Enum.Font.GothamBold
sessaoLabel.TextSize = 9
sessaoLabel.TextXAlignment = Enum.TextXAlignment.Left
sessaoLabel.Parent = main

local inputSessao = Instance.new("TextBox")
inputSessao.Size = UDim2.new(1, -20, 0, 28)
inputSessao.Position = UDim2.new(0, 10, 0, 56)
inputSessao.BackgroundColor3 = T.elev
inputSessao.Text = "Sessao"
inputSessao.TextColor3 = T.text
inputSessao.Font = Enum.Font.GothamMedium
inputSessao.TextSize = 11
inputSessao.BorderSizePixel = 0
inputSessao.ClearTextOnFocus = false
inputSessao.Parent = main
Instance.new("UICorner", inputSessao).CornerRadius = UDim.new(0, 6)
local ipad = Instance.new("UIPadding", inputSessao)
ipad.PaddingLeft = UDim.new(0, 10)

local catLabel = Instance.new("TextLabel")
catLabel.Size = UDim2.new(1, -20, 0, 16)
catLabel.Position = UDim2.new(0, 10, 0, 90)
catLabel.BackgroundTransparency = 1
catLabel.Text = "Categoria"
catLabel.TextColor3 = T.dim
catLabel.Font = Enum.Font.GothamBold
catLabel.TextSize = 9
catLabel.TextXAlignment = Enum.TextXAlignment.Left
catLabel.Parent = main

local opcoes = {"Dungeon", "Skills", "Drops", "Bosses", "Orbs", "Toolbar", "Rebirth", "Tudo"}
local catIdx = 1

local catBtn = Instance.new("TextButton")
catBtn.Size = UDim2.new(1, -20, 0, 28)
catBtn.Position = UDim2.new(0, 10, 0, 108)
catBtn.BackgroundColor3 = T.elev
catBtn.Text = opcoes[catIdx]
catBtn.TextColor3 = T.text
catBtn.Font = Enum.Font.GothamMedium
catBtn.TextSize = 11
catBtn.BorderSizePixel = 0
catBtn.AutoButtonColor = false
catBtn.Parent = main
Instance.new("UICorner", catBtn).CornerRadius = UDim.new(0, 6)

catBtn.MouseButton1Click:Connect(safeUI(function()
    catIdx = catIdx + 1
    if catIdx > #opcoes then catIdx = 1 end
    catBtn.Text = opcoes[catIdx]
    State.categoria = opcoes[catIdx]
end))

local btnStart = Instance.new("TextButton")
btnStart.Size = UDim2.new(1, -20, 0, 38)
btnStart.Position = UDim2.new(0, 10, 0, 144)
btnStart.BackgroundColor3 = T.accent
btnStart.Text = "▶  INICIAR"
btnStart.TextColor3 = T.bg
btnStart.Font = Enum.Font.GothamBold
btnStart.TextSize = 12
btnStart.BorderSizePixel = 0
btnStart.AutoButtonColor = false
btnStart.Parent = main
Instance.new("UICorner", btnStart).CornerRadius = UDim.new(0, 6)

local btnSalvar = Instance.new("TextButton")
btnSalvar.Size = UDim2.new(1, -20, 0, 28)
btnSalvar.Position = UDim2.new(0, 10, 0, 188)
btnSalvar.BackgroundColor3 = T.elev
btnSalvar.Text = "💾  SALVAR DUMP"
btnSalvar.TextColor3 = T.text
btnSalvar.Font = Enum.Font.GothamMedium
btnSalvar.TextSize = 11
btnSalvar.BorderSizePixel = 0
btnSalvar.AutoButtonColor = false
btnSalvar.Parent = main
Instance.new("UICorner", btnSalvar).CornerRadius = UDim.new(0, 6)

local footTxt = Instance.new("TextLabel")
footTxt.Size = UDim2.new(1, -20, 0, 14)
footTxt.Position = UDim2.new(0, 10, 1, -20)
footTxt.BackgroundTransparency = 1
footTxt.Text = "0 eventos • 0 remotes"
footTxt.TextColor3 = T.muted
footTxt.Font = Enum.Font.GothamMedium
footTxt.TextSize = 9
footTxt.TextXAlignment = Enum.TextXAlignment.Left
footTxt.Parent = main

local function atualizarBtn()
    if State.capturando then
        btnStart.BackgroundColor3 = T.danger
        btnStart.Text = "■  PARAR"
        dot.BackgroundColor3 = T.danger
        statusTxt.Text = "REC"
        statusTxt.TextColor3 = T.danger
    else
        btnStart.BackgroundColor3 = T.accent
        btnStart.Text = "▶  INICIAR"
        dot.BackgroundColor3 = T.muted
        statusTxt.Text = "off"
        statusTxt.TextColor3 = T.dim
    end
end

btnStart.MouseButton1Click:Connect(safeUI(function()
    State.sessao = inputSessao.Text ~= "" and inputSessao.Text or "Sessao"
    State.capturando = not State.capturando
    if State.capturando then
        State.buffer = {}
        State.total = 0
        instalarHooks()
    else
        removerTodosHooks()
    end
    atualizarBtn()
end))

btnSalvar.MouseButton1Click:Connect(safeUI(function()
    salvarArquivo()
end))

btnKill.MouseButton1Click:Connect(safeUI(function()
    State.capturando = false
    removerTodosHooks()
    gui:Destroy()
end))

task.spawn(function()
    while gui.Parent do
        task.wait(0.5)
        footTxt.Text = string.format("%d eventos • %d remotes • %d buffer",
            State.total, State.remotesEncontrados, #State.buffer)
    end
end)

atualizarBtn()

print("[DUMPER v7.0] ✅ Pronto — hook individual, sem __namecall")
