-- [CORE]
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local plr = Players.LocalPlayer
local Ativo = true

local CONFIG_FILE = "DBH_boss_timers.json"

-- [TIMERS PADRÃO]
local BossTimers = {
    Karrot = 299,
    Zero = 59,
    ["Brawly X01"] = 300,
    Zaja = 600,
    Destroyer = 600,
    Puriza = 420,
    ["Puriza Minion"] = 60,
    _default = 180,
}

-- [PERSISTÊNCIA]
local function carregarTimers()
    if not readfile then return end
    local ok, conteudo = pcall(readfile, CONFIG_FILE)
    if not ok or not conteudo then return end
    local decode = HttpService and HttpService:JSONDecode(conteudo)
    if type(decode) == "table" then
        for k, v in pairs(decode) do
            if type(v) == "number" and v > 0 then
                BossTimers[k] = v
            end
        end
    end
end

local function salvarTimers()
    if not writefile then return end
    local encode = HttpService and HttpService:JSONEncode(BossTimers)
    pcall(writefile, CONFIG_FILE, encode)
end

local HttpService = game:GetService("HttpService")
carregarTimers()

-- [ESP GUI]
local espGui = Instance.new("ScreenGui")
espGui.Name = "DBH_Tracker"
espGui.ResetOnSpawn = false
espGui.Parent = CoreGui

-- [ESTADO BOSS]
local bossEstado = {}

-- [ESP ITEMS]
local itemESP = {}

local function getItemLabel(itemName)
    if itemName:find("Wish") then return "💠 "..itemName, Color3.fromRGB(120, 200, 255)
    elseif itemName:find("ExpMat") then return "📗 "..itemName, Color3.fromRGB(120, 220, 120)
    elseif itemName:find("PowerScroll") then return "📜 "..itemName, Color3.fromRGB(255, 220, 100)
    elseif itemName:find("Orb") then return "🔮 "..itemName, Color3.fromRGB(200, 120, 255)
    else return "📦 "..itemName, Color3.fromRGB(220, 220, 220) end
end

local function atualizarItemESP()
    local ps = WS:FindFirstChild("PartStorage")
    local vistos = {}
    if ps then
        for _, item in ipairs(ps:GetChildren()) do
            if item.Name:find("ItemDrop_") then
                vistos[item] = true
                if not itemESP[item] then
                    local base = item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")
                    if base then
                        local bb = Instance.new("BillboardGui")
                        bb.Size = UDim2.new(0, 160, 0, 34)
                        bb.StudsOffset = Vector3.new(0, 4, 0)
                        bb.AlwaysOnTop = true
                        bb.Adornee = base
                        bb.Parent = espGui
                        
                        local lbl = Instance.new("TextLabel", bb)
                        lbl.Size = UDim2.new(1, 0, 1, 0)
                        lbl.BackgroundTransparency = 1
                        lbl.TextStrokeTransparency = 0.5
                        lbl.Font = Enum.Font.GothamBold
                        lbl.TextSize = 12
                        
                        local tipoItem = item:FindFirstChild("ItemName") and item.ItemName.Value or item.Name
                        local txt, cor = getItemLabel(tipoItem)
                        lbl.Text = txt
                        lbl.TextColor3 = cor
                        
                        itemESP[item] = bb
                    end
                end
            end
        end
    end
    for item, bb in pairs(itemESP) do
        if not vistos[item] then bb:Destroy(); itemESP[item] = nil end
    end
end

-- [ESP BOSS + TIMER]
local bossESP = {}

local function criarBossESP(mob, isBoss)
    local hrp = mob:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0, 180, 0, 60)
    bb.StudsOffset = Vector3.new(0, 4, 0)
    bb.AlwaysOnTop = true
    bb.Adornee = hrp
    bb.Parent = espGui
    
    local nome = Instance.new("TextLabel", bb)
    nome.Size = UDim2.new(1, 0, 0, 18)
    nome.BackgroundTransparency = 1
    nome.Text = mob.Name
    nome.TextStrokeTransparency = 0.5
    nome.TextSize = 12
    nome.Font = Enum.Font.GothamBold
    nome.TextColor3 = isBoss and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 200, 80)
    
    local hpBg = Instance.new("Frame", bb)
    hpBg.Size = UDim2.new(1, -10, 0, 5)
    hpBg.Position = UDim2.new(0, 5, 0, 20)
    hpBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    hpBg.BorderSizePixel = 0
    
    local hpFill = Instance.new("Frame", hpBg)
    hpFill.Size = UDim2.new(1, 0, 1, 0)
    hpFill.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
    hpFill.BorderSizePixel = 0
    
    local timer = Instance.new("TextLabel", bb)
    timer.Size = UDim2.new(1, 0, 0, 14)
    timer.Position = UDim2.new(0, 0, 0, 30)
    timer.BackgroundTransparency = 1
    timer.TextColor3 = Color3.fromRGB(255, 140, 30)
    timer.TextSize = 10
    timer.Font = Enum.Font.Code
    timer.Text = ""
    
    bossESP[mob] = {bb = bb, hpFill = hpFill, timer = timer, isBoss = isBoss}
end

local function removerBossESP(mob)
    if bossESP[mob] then bossESP[mob].bb:Destroy(); bossESP[mob] = nil end
end

local function atualizarBossESP()
    local vivos = {}
    local wm = WS:FindFirstChild("World Mobs")
    if not wm then return end
    
    for _, pasta in ipairs(wm:GetChildren()) do
        if pasta:IsA("Folder") or pasta:IsA("Model") then
            for _, mob in ipairs(pasta:GetChildren()) do
                if mob:IsA("Model") and mob:FindFirstChild("HumanoidRootPart") then
                    local isBoss = (pasta.Name == "Boss Mobs" or pasta.Name == "Event Mobs")
                    vivos[mob] = true
                    if not bossESP[mob] then criarBossESP(mob, isBoss) end
                    
                    local c = bossESP[mob]
                    local hum = mob:FindFirstChildOfClass("Humanoid")
                    if c and hum then
                        local pct = hum.Health / math.max(hum.MaxHealth, 1)
                        c.hpFill.Size = UDim2.new(pct, 0, 1, 0)
                        c.hpFill.BackgroundColor3 = pct > 0.5 and Color3.fromRGB(80, 200, 120)
                            or pct > 0.2 and Color3.fromRGB(255, 200, 80)
                            or Color3.fromRGB(220, 60, 60)
                        c.timer.Text = string.format("%d / %d", math.floor(hum.Health), math.floor(hum.MaxHealth))
                    end
                end
            end
        end
    end
    
    for mob in pairs(bossESP) do
        if not vivos[mob] then
            if bossESP[mob].isBoss then
                local base = mob.Name:gsub("%-?%d+$", "")
                local tempo = BossTimers[base] or BossTimers._default
                bossEstado[base] = {morreuEm = os.clock(), respawnEm = tempo}
            end
            removerBossESP(mob)
        end
    end
end

-- [UI]
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
    off = Color3.fromRGB(45, 45, 55),
}

local gui = Instance.new("ScreenGui", CoreGui)
gui.Name = "DBH_Tracker_UI"
gui.ResetOnSpawn = false

local function I(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end
local function corner(o, r)
    return I("UICorner", {CornerRadius = r or UDim.new(0, 7)}, o)
end

local main = I("Frame", {
    Size = UDim2.new(0, 380, 0, 380),
    Position = UDim2.new(0.5, -190, 0.5, -190),
    BackgroundColor3 = T.bg,
    BackgroundTransparency = 0.15,
    BorderSizePixel = 0,
    Active = true,
}, gui)
corner(main, UDim.new(0, 10))
I("UIStroke", {Color = T.border, Thickness = 1}, main)

local header = I("Frame", {Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.panel, BorderSizePixel = 0}, main)
corner(header, UDim.new(0, 10))
I("TextLabel", {
    Size = UDim2.new(1, -70, 1, 0),
    Position = UDim2.new(0, 12, 0, 0),
    BackgroundTransparency = 1,
    Text = "🎯 Tracker",
    TextColor3 = T.accent,
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local btnMin = I("TextButton", {
    Size = UDim2.new(0, 20, 0, 20),
    Position = UDim2.new(1, -48, 0.5, -10),
    BackgroundColor3 = T.elev,
    Text = "—",
    TextColor3 = T.text,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    AutoButtonColor = false,
    BorderSizePixel = 0,
}, header)
corner(btnMin, UDim.new(0, 5))

local btnKill = I("TextButton", {
    Size = UDim2.new(0, 20, 0, 20),
    Position = UDim2.new(1, -24, 0.5, -10),
    BackgroundColor3 = T.danger,
    Text = "×",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    AutoButtonColor = false,
    BorderSizePixel = 0,
}, header)
corner(btnKill, UDim.new(0, 5))

-- Sidebar
local side = I("Frame", {Size = UDim2.new(0, 90, 1, -50), Position = UDim2.new(0, 0, 0, 36), BackgroundColor3 = T.panel, BorderSizePixel = 0}, main)
I("UIListLayout", {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder}, side)
I("UIPadding", {PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6)}, side)

local content = I("Frame", {Size = UDim2.new(1, -90, 1, -50), Position = UDim2.new(0, 90, 0, 36), BackgroundColor3 = T.bg, BorderSizePixel = 0}, main)

local tabs = {}
local function novaAba(icon, name)
    local b = I("TextButton", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = T.panel,
        TextColor3 = T.dim,
        Font = Enum.Font.Gotham,
        TextSize = 10,
        Text = " "..icon.."  "..name,
        TextXAlignment = Enum.TextXAlignment.Left,
        BorderSizePixel = 0,
        AutoButtonColor = false,
    }, side)
    corner(b, UDim.new(0, 6))
    
    local f = I("ScrollingFrame", {
        Size = UDim2.new(1, -12, 1, -12),
        Position = UDim2.new(0, 6, 0, 6),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = T.border,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        Visible = false,
    }, content)
    local ll = I("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, f)
    I("UIPadding", {PaddingBottom = UDim.new(0, 10)}, f)
    ll:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        f.CanvasSize = UDim2.new(0, 0, 0, ll.AbsoluteContentSize.Y + 15)
    end)
    
    b.MouseButton1Click:Connect(function()
        for _, t in pairs(tabs) do
            t.btn.BackgroundColor3 = T.panel
            t.btn.TextColor3 = T.dim
            t.frame.Visible = false
        end
        b.BackgroundColor3 = T.elev
        b.TextColor3 = T.accent
        f.Visible = true
    end)
    
    local tab = {btn = b, frame = f}
    tabs[name] = tab
    return tab
end

local function section(parent, txt)
    return I("TextLabel", {
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        Text = txt,
        TextColor3 = T.accent,
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, parent.frame)
end

local function mkToggle(parent, texto, default, cb)
    local f = I("TextButton", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = T.elev,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
    }, parent.frame)
    corner(f, UDim.new(0, 7))
    I("TextLabel", {
        Size = UDim2.new(1, -60, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Text = texto,
        TextColor3 = T.text,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, f)
    local sw = I("Frame", {
        Size = UDim2.new(0, 36, 0, 20),
        Position = UDim2.new(1, -46, 0.5, -10),
        BackgroundColor3 = default and T.success or T.off,
        BorderSizePixel = 0,
    }, f)
    corner(sw, UDim.new(1, 0))
    local kn = I("Frame", {
        Size = UDim2.new(0, 16, 0, 16),
        Position = default and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, sw)
    corner(kn, UDim.new(1, 0))
    local st = default
    f.MouseButton1Click:Connect(function()
        st = not st
        sw.BackgroundColor3 = st and T.success or T.off
        kn.Position = st and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
        cb(st)
    end)
end

-- Aba ESP
local espTab = novaAba("👁", "ESP")
local Config = { ESPItems = true, ESPBosses = true }
section(espTab, "👁 ESP")
mkToggle(espTab, "Itens no chão", true, function(v) Config.ESPItems = v end)
mkToggle(espTab, "Bosses", true, function(v) Config.ESPBosses = v end)

-- Aba Timers
local timersTab = novaAba("⏱", "Timers")
section(timersTab, "⏱ TEMPO DE RESPAWN")
I("TextLabel", {
    Size = UDim2.new(1, 0, 0, 30),
    BackgroundTransparency = 1,
    Text = "Clique no valor pra editar.\nSalva automaticamente.",
    TextColor3 = T.dim,
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
}, timersTab.frame)

local listaTimers = {
    "Karrot", "Zero", "Brawly X01", "Zaja", "Destroyer", "Puriza", "Puriza Minion"
}

local inputsTimer = {}

for _, nome in ipairs(listaTimers) do
    local linha = I("Frame", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = T.elev,
        BorderSizePixel = 0,
    }, timersTab.frame)
    corner(linha, UDim.new(0, 6))
    
    I("TextLabel", {
        Size = UDim2.new(0.5, 0, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Text = nome,
        TextColor3 = T.text,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, linha)
    
    local input = I("TextBox", {
        Size = UDim2.new(0.4, 0, 0, 20),
        Position = UDim2.new(0.55, 0, 0.5, -10),
        BackgroundColor3 = T.panel,
        Text = tostring(BossTimers[nome] or BossTimers._default),
        TextColor3 = T.accent,
        Font = Enum.Font.Code,
        TextSize = 11,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        PlaceholderText = "segundos",
    }, linha)
    corner(input, UDim.new(0, 5))
    
    input.FocusLost:Connect(function()
        local v = tonumber(input.Text)
        if v and v > 0 then
            BossTimers[nome] = v
            input.TextColor3 = T.success
            salvarTimers()
            task.wait(0.5)
            input.TextColor3 = T.accent
        else
            input.Text = tostring(BossTimers[nome] or BossTimers._default)
        end
    end)
    
    inputsTimer[nome] = input
end

-- Botão resetar
local btnReset = I("TextButton", {
    Size = UDim2.new(1, 0, 0, 28),
    BackgroundColor3 = T.danger,
    Text = "Resetar todos",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    BorderSizePixel = 0,
}, timersTab.frame)
corner(btnReset, UDim.new(0, 6))
btnReset.MouseButton1Click:Connect(function()
    BossTimers = {
        Karrot = 299,
        Zero = 59,
        ["Brawly X01"] = 300,
        Zaja = 600,
        Destroyer = 600,
        Puriza = 420,
        ["Puriza Minion"] = 60,
        _default = 180,
    }
    for nome, input in pairs(inputsTimer) do
        input.Text = tostring(BossTimers[nome] or BossTimers._default)
    end
    salvarTimers()
end)

-- Aba Timers Ativos
local ativosTab = novaAba("🕐", "Ativos")
section(ativosTab, "🕐 EM RESPAWN")
local timerLabel = I("TextLabel", {
    Size = UDim2.new(1, 0, 0, 150),
    BackgroundColor3 = T.elev,
    TextColor3 = T.text,
    Font = Enum.Font.Code,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true,
    Text = "Nenhum boss morreu ainda.",
}, ativosTab.frame)
corner(timerLabel, UDim.new(0, 7))
I("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6)}, timerLabel)

-- Ativa primeira aba
espTab.btn.BackgroundColor3 = T.elev
espTab.btn.TextColor3 = T.accent
espTab.frame.Visible = true

-- Botão flutuante
local float = I("TextButton", {
    Size = UDim2.new(0, 46, 0, 46),
    Position = UDim2.new(0, 20, 0.4, 0),
    BackgroundColor3 = T.bg,
    Text = "🎯",
    TextColor3 = T.accent,
    Font = Enum.Font.GothamBold,
    TextSize = 20,
    AutoButtonColor = false,
    Visible = false,
    Active = true,
    Draggable = true,
    BorderSizePixel = 0,
}, gui)
corner(float, UDim.new(1, 0))
I("UIStroke", {Color = T.accent, Thickness = 1}, float)

btnMin.MouseButton1Click:Connect(function() main.Visible = false; float.Visible = true end)
float.MouseButton1Click:Connect(function() main.Visible = true; float.Visible = false end)
btnKill.MouseButton1Click:Connect(function()
    Ativo = false
    gui:Destroy()
    espGui:Destroy()
end)

-- drag
local drag, ds, ss = false, nil, nil
header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        drag = true; ds = i.Position; ss = main.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - ds
        main.Position = UDim2.new(ss.X.Scale, ss.X.Offset + d.X, ss.Y.Scale, ss.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        drag = false
    end
end)

-- [LOOPS]
task.spawn(function()
    while Ativo do
        task.wait(0.4)
        if Config.ESPItems then atualizarItemESP()
        else for i, bb in pairs(itemESP) do bb:Destroy(); itemESP[i] = nil end end
        
        if Config.ESPBosses then atualizarBossESP()
        else for m in pairs(bossESP) do removerBossESP(m) end end
    end
end)

task.spawn(function()
    while Ativo do
        task.wait(1)
        local agora = os.clock()
        local linhas = {}
        local total = 0
        for nome, info in pairs(bossEstado) do
            local passado = agora - info.morreuEm
            local restante = info.respawnEm - passado
            if restante > 0 then
                local min = math.floor(restante / 60)
                local seg = math.floor(restante % 60)
                linhas[#linhas+1] = string.format("%-18s %d:%02d", nome, min, seg)
                total = total + 1
            else
                bossEstado[nome] = nil
            end
        end
        if total == 0 then
            timerLabel.Text = "Nenhum boss em respawn."
        else
            table.sort(linhas)
            timerLabel.Text = table.concat(linhas, "\n")
        end
    end
end)

print("[Tracker v2] ✅ Carregado. Timers salvos em "..CONFIG_FILE)