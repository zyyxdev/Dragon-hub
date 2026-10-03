local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local plr = Players.LocalPlayer

local function safe(fn)
    local ok, err = pcall(fn)
    if not ok then warn("[DBH] " .. tostring(err)) end
    return ok
end

local KnitSVC
safe(function()
    local Knit = RS.Packages._Index["sleitnick_knit@1.4.7"].knit
    KnitSVC = Knit.Services
end)

local ExecuteSkill         = KnitSVC and KnitSVC.SkillManagerV2 and KnitSVC.SkillManagerV2.RE.ExecuteSkill
local ExecuteSkill_Special = KnitSVC and KnitSVC.SkillManagerV2 and KnitSVC.SkillManagerV2.RE.ExecuteSkill_Special
local RequestRebirth       = KnitSVC and KnitSVC.PlayerLevelService and KnitSVC.PlayerLevelService.RF.RequestRebirth
local PromptRemote         = KnitSVC and KnitSVC.PromptService and KnitSVC.PromptService.RE.Prompt
local SuperFlight          = KnitSVC and KnitSVC.FlightService and KnitSVC.FlightService.RE.SuperFlight
local SelectMode           = KnitSVC and KnitSVC.ModeTransformService and KnitSVC.ModeTransformService.RE.SelectMode
local SkillRemote          = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("SkillRemote")

local Ativo = true

local Config = {
    AutoFarm = false,
    AutoBoss = false,
    AutoSkills = false,
    AutoTransform = false,
    TransformMode = "SSJAngel",
    AutoRebirth = false,
    RebirthMultiplier = 3,
    ESPMobs = false,
    ESPItems = false,
    AutoCollect = false,
    AutoRegen = false,
    KiMin = 0.3,
    SafeHeight = 100,
    WalkSpeed = 16,
    FlySpeed = 250,
    AttackRange = 8,
    SkillDelay = 1.5,
}

local SKILLS = {
    { nome = "UniqueSets_2_1", hold = "Hold_Kamehameha", release = "Release_Kamehameha", pause = 3 },
    { nome = "UniqueSets_2_3", hold = "Hold_SpiritBomb", release = "Release_SpiritBomb", pause = 0.1 },
    { nome = "UniqueSets_2_2", pause = 1 },
}

local BOSS_KEYWORDS = {
    "coolest","droid","jinbu","atom","turles","boku","apejaw","kataba",
    "yeti","opa","brolo","gero","nash","frieza","cell","buu","beerus",
    "jiren","broly","zaja","boss"
}

local function isBoss(mob)
    if not mob then return false end
    local n = mob.Name:lower()
    for _, kw in ipairs(BOSS_KEYWORDS) do
        if n:find(kw) then return true end
    end
    return false
end

local emRegen = false
local ultimaAcao = 0

local function podeAgir()
    local agora = tick()
    if agora - ultimaAcao < 0.05 then return false end
    ultimaAcao = agora
    return true
end

local function voarPara(destino, velocidade)
    local myChar = plr.Character
    if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then return end
    local hrp = myChar.HumanoidRootPart
    velocidade = velocidade or Config.FlySpeed

    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    bv.Velocity = Vector3.new(0, 0, 0)
    bv.Parent = hrp

    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    bg.P = 9e4
    bg.CFrame = hrp.CFrame
    bg.Parent = hrp

    task.spawn(function()
        local t = 0
        while t < 20 and Ativo and hrp.Parent do
            local dir = destino - hrp.Position
            if dir.Magnitude < 15 then break end
            bv.Velocity = dir.Unit * velocidade
            bg.CFrame = CFrame.new(hrp.Position, destino)
            t = t + 0.1
            task.wait(0.1)
        end
        bv:Destroy()
        bg:Destroy()
    end)
end

local function atacar(alvo)
    if not SkillRemote or not plr.Character or not podeAgir() then return end
    if not alvo or not alvo:FindFirstChild("HumanoidRootPart") then return end
    local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local mhrp = alvo.HumanoidRootPart
    hrp.CFrame = mhrp.CFrame * CFrame.new(0, 0, Config.AttackRange)

    local cframe = hrp.CFrame
    local aim = mhrp.Position
    local camCF = workspace.CurrentCamera.CFrame

    safe(function()
        SkillRemote:FireServer({
            Began = true, CFrame = cframe, Aim = aim,
            Camera = camCF, Type = 1, SkillId = "1"
        })
    end)
    task.wait(0.05)
    safe(function()
        SkillRemote:FireServer({
            Began = false, CFrame = cframe, Aim = aim,
            Camera = camCF, Type = 1, SkillId = "1"
        })
    end)
end

local function usarSkill(skill, alvo)
    if not ExecuteSkill or not alvo or not alvo.Parent then return end
    if not alvo:FindFirstChild("HumanoidRootPart") then return end
    local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local tpos = alvo.HumanoidRootPart.Position
    safe(function() ExecuteSkill_Special:FireServer(plr.Name, skill.nome) end)

    local cfg = { targetPos = tpos, HumCFrame = hrp.CFrame, ResumeOnTimePassed = skill.pause or 0.5 }
    if skill.hold then cfg.HoldAnimation = skill.hold end
    if skill.release then cfg.ReleaseAnimation = skill.release end

    safe(function() ExecuteSkill:FireServer(skill.nome, cfg, 1, true) end)
    task.wait(skill.pause or 0.5)
    safe(function() ExecuteSkill:FireServer(skill.nome, cfg, 1, false) end)
end

local function getKi()
    local char = plr.Character
    if not char then return nil, nil end
    local status = char:FindFirstChild("Status")
    if not status then return nil, nil end
    local curr = status:FindFirstChild("CurrentEnergy")
    local max = status:FindFirstChild("MaxEnergy")
    if not curr or not max then return nil, nil end
    return curr.Value, max.Value
end

local function iniciarRegen()
    if emRegen then return end
    emRegen = true

    local myChar = plr.Character
    if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then
        emRegen = false
        return
    end
    local hrp = myChar.HumanoidRootPart
    local posOrig = hrp.Position
    local posSegura = Vector3.new(posOrig.X, posOrig.Y + Config.SafeHeight, posOrig.Z)

    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    bv.Velocity = Vector3.new(0, 0, 0)
    bv.Parent = hrp

    task.spawn(function()
        local t = 0
        while t < 5 and emRegen and Ativo and hrp.Parent do
            local dir = posSegura - hrp.Position
            if dir.Magnitude < 10 then break end
            bv.Velocity = dir.Unit * 200
            t = t + 0.1
            task.wait(0.1)
        end
        bv.Velocity = Vector3.new(0, 0, 0)
        while emRegen and Ativo and hrp.Parent do
            hrp.CFrame = CFrame.new(posSegura)
            task.wait(0.2)
        end
        bv:Destroy()
    end)
end

local function pararRegen()
    if not emRegen then return end
    emRegen = false
end

local mobs = {}
local function registrarMob(mob)
    if not mob:IsA("Model") then return end
    if not mob:FindFirstChild("Humanoid") then return end
    if not mob:FindFirstChild("HumanoidRootPart") then return end
    if table.find(mobs, mob) then return end
    table.insert(mobs, mob)
end

task.spawn(function()
    while Ativo do
        local worldMobs = workspace:FindFirstChild("World Mobs")
        if worldMobs then
            for _, child in pairs(worldMobs:GetDescendants()) do
                if child:IsA("Model") and child:FindFirstChild("Humanoid") and child:FindFirstChild("HumanoidRootPart") then
                    registrarMob(child)
                end
            end
        end
        for i = #mobs, 1, -1 do
            local m = mobs[i]
            if not m or not m.Parent or not m:FindFirstChild("Humanoid") or m.Humanoid.Health <= 0 then
                table.remove(mobs, i)
            end
        end
        task.wait(1.5)
    end
end)

local function getAlvo()
    local myChar = plr.Character
    if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then return nil end
    local myPos = myChar.HumanoidRootPart.Position
    local closest, minD = nil, math.huge
    for _, mob in ipairs(mobs) do
        if mob and mob.Parent and mob:FindFirstChild("HumanoidRootPart") and mob.Humanoid.Health > 0 then
            local d = (mob.HumanoidRootPart.Position - myPos).Magnitude
            local valido = false
            if Config.AutoFarm and not Config.AutoBoss then
                valido = not isBoss(mob)
            elseif Config.AutoBoss and not Config.AutoFarm then
                valido = isBoss(mob)
            elseif Config.AutoFarm and Config.AutoBoss then
                valido = true
            end
            if valido and d < minD then minD = d; closest = mob end
        end
    end
    return closest
end

local function calcularRequisito(reb) return (reb * 3000000) + 2000000 end
local function checarRebirth()
    local stats = plr:FindFirstChild("Stats")
    if not stats then return false, nil end
    local reb = stats:FindFirstChild("Rebirth")
    local str = stats:FindFirstChild("Strength")
    local ki = stats:FindFirstChild("Ki")
    if not reb or not str or not ki then return false, nil end
    local r = reb.Value
    local total = str.Value + ki.Value
    local minimo = calcularRequisito(r)
    local alvo = minimo * Config.RebirthMultiplier
    return total >= alvo, { rebirth = r, total = total, minimo = minimo, alvo = alvo }
end

local espGui = Instance.new("ScreenGui")
espGui.Name = "DBH_ESP"
espGui.ResetOnSpawn = false
espGui.Parent = CoreGui

local espCache = {}
local dropESP = {}

local function criarESP(mob)
    local hrp = mob:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0, 140, 0, 30)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Adornee = hrp
    bb.Parent = espGui

    local nome = Instance.new("TextLabel", bb)
    nome.Size = UDim2.new(1, 0, 1, 0)
    nome.BackgroundTransparency = 1
    nome.Text = mob.Name
    nome.TextStrokeTransparency = 0.5
    nome.TextSize = 12
    nome.Font = Enum.Font.GothamBold
    nome.TextColor3 = (mob.Parent and mob.Parent.Name == "Boss Mobs") and Color3.fromRGB(255, 80, 80)
        or (mob.Parent and mob.Parent.Name == "Event Mobs") and Color3.fromRGB(200, 80, 255)
        or Color3.fromRGB(255, 200, 80)

    espCache[mob] = bb
end

local function removerESP(mob)
    if espCache[mob] then espCache[mob]:Destroy(); espCache[mob] = nil end
end

local function getItemLabel(itemName)
    if itemName:find("Wish") then return "💠 "..itemName, Color3.fromRGB(120, 200, 255)
    elseif itemName:find("ExpMat") then return "📗 "..itemName, Color3.fromRGB(120, 220, 120)
    elseif itemName:find("PowerScroll") then return "📜 "..itemName, Color3.fromRGB(255, 220, 100)
    elseif itemName:find("Orb") then return "🔮 "..itemName, Color3.fromRGB(200, 120, 255)
    else return "📦 "..itemName, Color3.fromRGB(220, 220, 220) end
end

local function atualizarDropESP()
    local ps = WS:FindFirstChild("PartStorage")
    local vistos = {}
    if ps then
        for _, item in ipairs(ps:GetChildren()) do
            if item.Name:find("ItemDrop_") then
                vistos[item] = true
                if not dropESP[item] then
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

                        dropESP[item] = bb
                    end
                end
            end
        end
    end
    for item, bb in pairs(dropESP) do
        if not vistos[item] then bb:Destroy(); dropESP[item] = nil end
    end
end

local oldGui = CoreGui:FindFirstChild("DragonBloxHub")
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "DragonBloxHub"
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.IgnoreGuiInset = true
gui.Parent = CoreGui

local COR = {
    Fundo = Color3.fromRGB(15, 12, 25),
    Painel = Color3.fromRGB(30, 22, 45),
    AbaAtiva = Color3.fromRGB(255, 140, 30),
    AbaInativa = Color3.fromRGB(45, 35, 65),
    Texto = Color3.fromRGB(255, 240, 220),
    TextoSub = Color3.fromRGB(170, 170, 190),
    Botao = Color3.fromRGB(55, 40, 80),
    BotaoLigado = Color3.fromRGB(255, 180, 40),
}

local homeBar = Instance.new("TextButton")
homeBar.Size = UDim2.new(0, 200, 0, 24)
homeBar.Position = UDim2.new(0.5, 0, 1, -30)
homeBar.AnchorPoint = Vector2.new(0.5, 1)
homeBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
homeBar.BackgroundTransparency = 0.7
homeBar.Text = ""
homeBar.AutoButtonColor = false
homeBar.Active = true
homeBar.ZIndex = 50
homeBar.Parent = gui
Instance.new("UICorner", homeBar).CornerRadius = UDim.new(1, 0)
local hbInner = Instance.new("Frame")
hbInner.Size = UDim2.new(0.7, 0, 0, 6)
hbInner.Position = UDim2.new(0.5, 0, 0.5, 0)
hbInner.AnchorPoint = Vector2.new(0.5, 0.5)
hbInner.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
hbInner.BackgroundTransparency = 0.2
hbInner.BorderSizePixel = 0
hbInner.ZIndex = 51
hbInner.Parent = homeBar
Instance.new("UICorner", hbInner).CornerRadius = UDim.new(1, 0)

local janela = Instance.new("Frame")
janela.Size = UDim2.new(0, 540, 0, 420)
janela.Position = UDim2.new(0.5, -270, 0.5, -210)
janela.BackgroundColor3 = COR.Fundo
janela.BackgroundTransparency = 0.15
janela.BorderSizePixel = 0
janela.Active = true
janela.Visible = false
janela.Parent = gui
Instance.new("UICorner", janela).CornerRadius = UDim.new(0, 14)
local jStroke = Instance.new("UIStroke") jStroke.Color = COR.AbaAtiva jStroke.Thickness = 1.5 jStroke.Transparency = 0.3 jStroke.Parent = janela

local titulo = Instance.new("TextButton")
titulo.Size = UDim2.new(1, 0, 0, 42)
titulo.BackgroundColor3 = COR.Painel
titulo.BackgroundTransparency = 0.2
titulo.TextColor3 = COR.Texto
titulo.Text = "🐉  DRAGON BLOX HUB"
titulo.TextSize = 16
titulo.Font = Enum.Font.GothamBold
titulo.TextXAlignment = Enum.TextXAlignment.Left
titulo.BorderSizePixel = 0
titulo.AutoButtonColor = false
titulo.Parent = janela
Instance.new("UICorner", titulo).CornerRadius = UDim.new(0, 14)
local tPad = Instance.new("UIPadding") tPad.PaddingLeft = UDim.new(0, 18) tPad.Parent = titulo

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 110, 1, -42)
sidebar.Position = UDim2.new(0, 0, 0, 42)
sidebar.BackgroundColor3 = COR.Painel
sidebar.BackgroundTransparency = 0.3
sidebar.BorderSizePixel = 0
sidebar.Parent = janela
local sbLayout = Instance.new("UIListLayout") sbLayout.SortOrder = Enum.SortOrder.LayoutOrder sbLayout.Padding = UDim.new(0, 5) sbLayout.Parent = sidebar
local sbPad = Instance.new("UIPadding") sbPad.PaddingTop = UDim.new(0, 10) sbPad.PaddingLeft = UDim.new(0, 7) sbPad.PaddingRight = UDim.new(0, 7) sbPad.Parent = sidebar

local contentArea = Instance.new("Frame")
contentArea.Size = UDim2.new(1, -110, 1, -42)
contentArea.Position = UDim2.new(0, 110, 0, 42)
contentArea.BackgroundColor3 = COR.Fundo
contentArea.BackgroundTransparency = 0.3
contentArea.BorderSizePixel = 0
contentArea.Parent = janela

local resizeHandle = Instance.new("TextButton")
resizeHandle.Size = UDim2.new(0, 24, 0, 24)
resizeHandle.Position = UDim2.new(1, -24, 1, -24)
resizeHandle.BackgroundColor3 = COR.AbaAtiva
resizeHandle.BackgroundTransparency = 0.5
resizeHandle.Text = "◢"
resizeHandle.TextColor3 = Color3.fromRGB(255, 255, 255)
resizeHandle.TextSize = 14
resizeHandle.Font = Enum.Font.GothamBold
resizeHandle.BorderSizePixel = 0
resizeHandle.ZIndex = 5
resizeHandle.Parent = janela
Instance.new("UICorner", resizeHandle).CornerRadius = UDim.new(0, 4)

local abas = {}

local function criarAba(nome, display)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 34)
    btn.BackgroundColor3 = COR.AbaInativa
    btn.BackgroundTransparency = 0.3
    btn.Text = display
    btn.TextColor3 = COR.TextoSub
    btn.TextSize = 12
    btn.Font = Enum.Font.GothamBold
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Parent = sidebar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -20, 1, -20)
    scroll.Position = UDim2.new(0, 10, 0, 10)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = COR.AbaAtiva
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Visible = false
    scroll.Parent = contentArea

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 6)
    layout.Parent = scroll
    local pad = Instance.new("UIPadding") pad.PaddingBottom = UDim.new(0, 20) pad.Parent = scroll

    abas[nome] = { botao = btn, frame = scroll }

    local function ativar()
        for _, a in pairs(abas) do
            a.frame.Visible = false
            a.botao.BackgroundColor3 = COR.AbaInativa
            a.botao.TextColor3 = COR.TextoSub
        end
        scroll.Visible = true
        btn.BackgroundColor3 = COR.AbaAtiva
        btn.TextColor3 = Color3.fromRGB(20, 15, 30)
    end

    btn.MouseButton1Click:Connect(ativar)
    abas[nome].ativar = ativar
    return scroll
end

local function criarToggle(parent, texto, default, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -8, 0, 38)
    frame.BackgroundColor3 = COR.Botao
    frame.BackgroundTransparency = 0.35
    frame.BorderSizePixel = 0
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -80, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = texto
    label.TextColor3 = COR.Texto
    label.TextSize = 12
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 58, 0, 26)
    btn.Position = UDim2.new(1, -66, 0.5, -13)
    btn.BackgroundColor3 = default and COR.BotaoLigado or Color3.fromRGB(70, 70, 90)
    btn.Text = default and "ON" or "OFF"
    btn.TextColor3 = default and Color3.fromRGB(20, 15, 30) or COR.Texto
    btn.TextSize = 11
    btn.Font = Enum.Font.GothamBold
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Parent = frame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 13)

    local state = default
    btn.MouseButton1Click:Connect(function()
        state = not state
        btn.BackgroundColor3 = state and COR.BotaoLigado or Color3.fromRGB(70, 70, 90)
        btn.Text = state and "ON" or "OFF"
        btn.TextColor3 = state and Color3.fromRGB(20, 15, 30) or COR.Texto
        if callback then callback(state) end
    end)
end

local function criarBotao(parent, texto, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -8, 0, 38)
    btn.BackgroundColor3 = COR.Botao
    btn.BackgroundTransparency = 0.25
    btn.Text = texto
    btn.TextColor3 = COR.Texto
    btn.TextSize = 12
    btn.Font = Enum.Font.Gotham
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = true
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    btn.MouseButton1Click:Connect(callback)
end

local function criarSlider(parent, texto, min, max, default, step, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -8, 0, 56)
    frame.BackgroundColor3 = COR.Botao
    frame.BackgroundTransparency = 0.35
    frame.BorderSizePixel = 0
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -20, 0, 20)
    label.Position = UDim2.new(0, 12, 0, 6)
    label.BackgroundTransparency = 1
    label.Text = texto .. ": " .. default
    label.TextColor3 = COR.Texto
    label.TextSize = 12
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local barBg = Instance.new("Frame")
    barBg.Size = UDim2.new(1, -24, 0, 14)
    barBg.Position = UDim2.new(0, 12, 1, -22)
    barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
    barBg.BorderSizePixel = 0
    barBg.Parent = frame
    Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)

    local barFill = Instance.new("Frame")
    local pct = (default - min) / (max - min)
    barFill.Size = UDim2.new(pct, 0, 1, 0)
    barFill.BackgroundColor3 = COR.AbaAtiva
    barFill.BorderSizePixel = 0
    barFill.Parent = barBg
    Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

    local dragBtn = Instance.new("TextButton")
    dragBtn.Size = UDim2.new(1, 0, 3, 0)
    dragBtn.Position = UDim2.new(0, 0, -1, 0)
    dragBtn.BackgroundTransparency = 1
    dragBtn.Text = ""
    dragBtn.Parent = barBg

    local dragging = false
    dragBtn.MouseButton1Down:Connect(function() dragging = true end)
    dragBtn.MouseButton1Up:Connect(function() dragging = false end)
    dragBtn.MouseLeave:Connect(function() dragging = false end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local pos = input.Position
            local abs = barBg.AbsolutePosition
            local size = barBg.AbsoluteSize
            local rel = math.clamp((pos.X - abs.X) / size.X, 0, 1)
            local valor = min + (max - min) * rel
            valor = math.floor(valor / step + 0.5) * step
            barFill.Size = UDim2.new(rel, 0, 1, 0)
            label.Text = texto .. ": " .. valor
            if callback then callback(valor) end
        end
    end)
end

local function criarSecao(parent, texto)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -8, 0, 28)
    lbl.BackgroundTransparency = 1
    lbl.Text = "▸ " .. texto
    lbl.TextColor3 = COR.AbaAtiva
    lbl.TextSize = 12
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = parent
end

local function criarLabel(parent, texto, altura)
    altura = altura or 80
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -8, 0, altura)
    lbl.BackgroundColor3 = COR.Botao
    lbl.BackgroundTransparency = 0.5
    lbl.Text = texto
    lbl.TextColor3 = COR.Texto
    lbl.TextSize = 11
    lbl.Font = Enum.Font.Code
    lbl.TextWrapped = true
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextYAlignment = Enum.TextYAlignment.Top
    lbl.Parent = parent
    Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 6)
    local p = Instance.new("UIPadding") p.PaddingLeft = UDim.new(0, 10) p.PaddingTop = UDim.new(0, 8) p.PaddingRight = UDim.new(0, 10) p.Parent = lbl
    return lbl
end

local farmTab = criarAba("farm", "⚔️ Farm")

criarSecao(farmTab, "Farm")
criarToggle(farmTab, "Auto Farm (Mobs)", false, function(v) Config.AutoFarm = v end)
criarToggle(farmTab, "Auto Boss", false, function(v) Config.AutoBoss = v end)
criarToggle(farmTab, "Auto Skills", false, function(v) Config.AutoSkills = v end)
criarToggle(farmTab, "Auto Transform", false, function(v) Config.AutoTransform = v end)
criarToggle(farmTab, "Auto Regen", false, function(v) Config.AutoRegen = v end)

criarSecao(farmTab, "Visual")
criarToggle(farmTab, "ESP Mobs", false, function(v) Config.ESPMobs = v end)
criarToggle(farmTab, "ESP Itens (drops)", false, function(v) Config.ESPItems = v end)

criarSecao(farmTab, "Movimento")
criarBotao(farmTab, "🌌 Voo Nativo (5s)", function()
    if SuperFlight then
        safe(function() SuperFlight:FireServer(true) end)
        task.wait(5)
        safe(function() SuperFlight:FireServer(false) end)
    end
end)

local rebirthTab = criarAba("rebirth", "🔄 Rebirth")

criarSecao(rebirthTab, "Auto Rebirth")
criarToggle(rebirthTab, "Ativar", false, function(v)
    Config.AutoRebirth = v
    if not v then return end
    task.spawn(function()
        while Ativo and Config.AutoRebirth do
            local pronto = checarRebirth()
            if pronto and RequestRebirth then
                safe(function()
                    if PromptRemote then
                        PromptRemote:FireServer({
                            UniqueTag = "HudRebirth",
                            Prompt = "HudRebirth",
                            MiddleButton = "Confirm",
                            RightButton = "Cancel",
                        }, "Confirm")
                    end
                end)
                task.wait(0.5)
                safe(function() RequestRebirth:InvokeServer(true) end)
                task.wait(8)
            end
            task.wait(10)
        end
    end)
end)

criarSlider(rebirthTab, "Acumular (x requisito)", 1, 10, 3, 1, function(v) Config.RebirthMultiplier = v end)
criarBotao(rebirthTab, "🔄 Forçar Rebirth Agora", function()
    if RequestRebirth then safe(function() RequestRebirth:InvokeServer(true) end) end
end)

local infoRebirth = criarLabel(rebirthTab, "Rebirth: --\nStats: --\nAlvo: --", 80)

task.spawn(function()
    while Ativo do
        local _, info = checarRebirth()
        if info then
            infoRebirth.Text = "Rebirth: " .. info.rebirth ..
                "\nSeus stats: " .. info.total ..
                "\nAlvo (" .. Config.RebirthMultiplier .. "x): " .. info.alvo
        end
        task.wait(3)
    end
end)

local configTab = criarAba("config", "⚙️ Config")

criarSecao(configTab, "Movimento")
criarSlider(configTab, "WalkSpeed", 16, 200, 16, 1, function(v) Config.WalkSpeed = v end)
criarSlider(configTab, "FlySpeed", 50, 500, 250, 10, function(v) Config.FlySpeed = v end)
criarSlider(configTab, "Attack Range", 5, 20, 8, 1, function(v) Config.AttackRange = v end)

criarSecao(configTab, "Combate")
criarSlider(configTab, "Skill Delay x0.1s", 5, 50, 15, 5, function(v) Config.SkillDelay = v * 0.1 end)

criarSecao(configTab, "Sobrevivência")
criarSlider(configTab, "Ki pra Regen (%)", 10, 50, 30, 5, function(v) Config.KiMin = v / 100 end)
criarSlider(configTab, "Altura Segura (studs)", 40, 300, 100, 10, function(v) Config.SafeHeight = v end)

criarSecao(configTab, "Sistema")
criarBotao(configTab, "🔴 MATAR SCRIPT", function()
    Ativo = false
    for k, v in pairs(Config) do
        if type(v) == "boolean" then Config[k] = false end
    end
    gui:Destroy()
    espGui:Destroy()
end)

local sobreTab = criarAba("sobre", "ℹ️ Sobre")

criarSecao(sobreTab, "Criadores")
criarLabel(sobreTab, "🐉 DRAGON BLOX HUB\n\nzyyx & elliot\n\nv5.0 - 2026", 100)

criarSecao(sobreTab, "Servidor")
local infoServidor = criarLabel(sobreTab, "Carregando...", 120)

task.spawn(function()
    while Ativo and gui.Parent do
        local jobId = game.JobId ~= "" and game.JobId:sub(1, 8) .. "..." or "Privado"
        local ping = math.floor(plr:GetNetworkPing() * 1000)
        infoServidor.Text =
            "Hora: " .. os.date("%H:%M:%S") ..
            "\nData: " .. os.date("%d/%m/%Y") ..
            "\nServidor: " .. jobId ..
            "\nJogadores: " .. #Players:GetPlayers() ..
            "\nPing: " .. ping .. " ms" ..
            "\nFPS: " .. math.floor(workspace:GetRealPhysicsFPS())
        task.wait(2)
    end
end)

abas.farm.ativar()

homeBar.MouseButton1Click:Connect(function()
    janela.Visible = not janela.Visible
end)

local dragging = false
local dragStart = nil
local startPos = nil

titulo.MouseButton1Down:Connect(function()
    dragging = true
    dragStart = UserInputService:GetMouseLocation()
    startPos = janela.Position
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
        resizing = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging then
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local current = UserInputService:GetMouseLocation()
            local delta = current - dragStart
            janela.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
                                        startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end
end)

local resizing = false
local resizeStartPos = nil
local sizeStart = nil

resizeHandle.MouseButton1Down:Connect(function()
    resizing = true
    resizeStartPos = UserInputService:GetMouseLocation()
    sizeStart = janela.AbsoluteSize
end)

UserInputService.InputChanged:Connect(function(input)
    if resizing then
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local current = UserInputService:GetMouseLocation()
            local delta = current - resizeStartPos
            local newX = math.clamp(sizeStart.X + delta.X, 400, 900)
            local newY = math.clamp(sizeStart.Y + delta.Y, 300, 700)
            janela.Size = UDim2.new(0, newX, 0, newY)
        end
    end
end)

task.spawn(function()
    while Ativo and task.wait(0.3) do
        if (Config.AutoFarm or Config.AutoBoss) and not emRegen then
            local alvo = getAlvo()
            if alvo then
                atacar(alvo)
            end
        end
    end
end)

task.spawn(function()
    while Ativo and task.wait(1) do
        if Config.AutoRegen and (Config.AutoFarm or Config.AutoBoss) then
            local curr, max = getKi()
            if curr and max then
                local ratio = curr / max
                if ratio < Config.KiMin and not emRegen then
                    iniciarRegen()
                elseif ratio > 0.9 and emRegen then
                    pararRegen()
                end
            end
        elseif emRegen then
            pararRegen()
        end
    end
end)

task.spawn(function()
    local idx = 1
    while Ativo and task.wait(Config.SkillDelay) do
        if Config.AutoSkills and not emRegen then
            local alvo = getAlvo()
            if alvo and alvo.Parent then
                usarSkill(SKILLS[idx], alvo)
                idx = idx + 1
                if idx > #SKILLS then idx = 1 end
            end
        end
    end
end)

task.spawn(function()
    while Ativo and task.wait(5) do
        if Config.AutoTransform and SelectMode then
            safe(function() SelectMode:FireServer(Config.TransformMode) end)
        end
    end
end)

task.spawn(function()
    while Ativo and task.wait(0.5) do
        if plr.Character and plr.Character:FindFirstChild("Humanoid") then
            plr.Character.Humanoid.WalkSpeed = Config.WalkSpeed
        end
    end
end)

task.spawn(function()
    while Ativo and task.wait(0.4) do
        if Config.ESPMobs then
            local vivos = {}
            local wm = WS:FindFirstChild("World Mobs")
            if wm then
                for _, p in ipairs(wm:GetChildren()) do
                    for _, m in ipairs(p:GetChildren()) do
                        if m:IsA("Model") and m:FindFirstChild("HumanoidRootPart") then
                            vivos[m] = true
                            if not espCache[m] then criarESP(m) end
                        end
                    end
                end
            end
            for m in pairs(espCache) do
                if not vivos[m] then removerESP(m) end
            end
        else
            for m in pairs(espCache) do removerESP(m) end
        end
    end
end)

task.spawn(function()
    while Ativo and task.wait(0.5) do
        if Config.ESPItems then
            atualizarDropESP()
        else
            for i, bb in pairs(dropESP) do bb:Destroy(); dropESP[i] = nil end
        end
    end
end)

print("[DBH] ✅ Carregado")