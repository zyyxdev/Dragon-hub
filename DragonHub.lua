-- ════════════════════════════════════════════════════════════════
--                   DRAGON BLOX HUB - VERSION 5.3                
-- ════════════════════════════════════════════════════════════════

local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local plr = Players.LocalPlayer

local mainFrame = nil

-- ═══════════════════════════════════════════════
-- BUSCA SEGURA DE REMOTES
-- ═══════════════════════════════════════════════
local function obterRemote(nome)
    local encontrado = RS:FindFirstChild(nome, true)
    if encontrado and encontrado:IsA("RemoteEvent") then
        return encontrado
    end
    return nil
end

local RE_ExecuteSkill        = obterRemote("ExecuteSkill")
local RE_ExecuteSkillSpecial = obterRemote("ExecuteSkill_Special")
local RE_LockedOnChanged     = obterRemote("LockedOnChanged")
local SkillRemote            = obterRemote("SkillRemote")

-- ═══════════════════════════════════════════════
-- CONFIGURAÇÕES LOCAIS
-- ═══════════════════════════════════════════════
local CombatCfg = {
    M1_Delay        = 0.35,
    M1_Range        = 12,
    Skill_Delay     = 1.2,
    Skill_Range     = 30,
    Skill_Slot      = 1,
    AutoLock        = true,
}

local Config = {
    FlySpeed = 100,
    WalkSpeed = 16,
    OverrideSpeed = false,
}

local KiCfg = {
    LimiteRecarga   = 0.30,
    AlvoRecarga     = 0.90,
    AposRecarga     = 0.5,
    TempoMaxRecarga = 3.0,
    Recarregando    = false,
}

local Ativo = true
local AutoFarm = false
local AutoSkill = false
local ShowESP = false

-- ═══════════════════════════════════════════════
-- ATAQUE M1 DIRETO VIA REMOTE (SEM VIRTUAL INPUT)
-- ═══════════════════════════════════════════════
local function m1Direto(alvoPos)
    local char = plr.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local cam = workspace.CurrentCamera
    local camCF = cam and cam.CFrame or hrp.CFrame

    if SkillRemote then
        -- Began=true (inicia M1)
        pcall(function()
            SkillRemote:FireServer({
                Began = true,
                CFrame = hrp.CFrame,
                Aim = alvoPos or (hrp.Position + hrp.CFrame.LookVector * 10),
                Camera = camCF,
                Type = 1,
            })
        end)

        task.wait(0.08)

        -- Began=false (finaliza M1)
        pcall(function()
            SkillRemote:FireServer({
                Began = false,
                CFrame = hrp.CFrame,
                Aim = alvoPos or (hrp.Position + hrp.CFrame.LookVector * 10),
                Camera = camCF,
                Type = 1,
            })
        end)
    end
end

-- ═══════════════════════════════════════════════
-- LEITURA DE STATS COM TIMEOUT
-- ═══════════════════════════════════════════════
local PlayerStatsHandler = nil
task.spawn(function()
    pcall(function()
        local handlers = RS:WaitForChild("Handlers", 3)
        if handlers then
            local statHandler = handlers:WaitForChild("PlayerStatsHandler", 3)
            if statHandler then
                PlayerStatsHandler = require(statHandler)
            end
        end
    end)
end)

local function getStats()
    local result = {Strength = 0, Energy = 0, Defense = 0, Speed = 0}
    if PlayerStatsHandler then
        pcall(function()
            result.Strength = PlayerStatsHandler.GetStrength and PlayerStatsHandler.GetStrength(plr) or 0
            result.Energy   = PlayerStatsHandler.GetKi and PlayerStatsHandler.GetKi(plr) or 0
            result.Defense  = PlayerStatsHandler.GetDefense and PlayerStatsHandler.GetDefense(plr) or 0
            result.Speed    = PlayerStatsHandler.GetSpeed and PlayerStatsHandler.GetSpeed(plr) or 0
        end)
    else
        local statsObj = plr:FindFirstChild("Stats") or plr:FindFirstChild("Data") or plr:FindFirstChild("leaderstats")
        if statsObj then
            for k, _ in pairs(result) do
                local val = statsObj:FindFirstChild(k)
                if val then result[k] = val.Value end
            end
        end
    end
    return result
end

-- ═══════════════════════════════════════════════
-- MOVIMENTAÇÃO E VOO
-- ═══════════════════════════════════════════════
local function pararVoo()
    local char = plr.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local bv = hrp:FindFirstChild("__DBHVel")
    if bv then bv:Destroy() end
    local bg = hrp:FindFirstChild("__DBHGyro")
    if bg then bg:Destroy() end
end

local function voarPara(pos, speed)
    local char = plr.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    speed = speed or Config.FlySpeed or 100

    local bv = hrp:FindFirstChild("__DBHVel") or Instance.new("BodyVelocity")
    bv.Name = "__DBHVel"
    bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    bv.Parent = hrp

    local bg = hrp:FindFirstChild("__DBHGyro") or Instance.new("BodyGyro")
    bg.Name = "__DBHGyro"
    bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    bg.P = 10000
    bg.Parent = hrp

    local dir = (pos - hrp.Position)
    if dir.Magnitude > 8 then
        bv.Velocity = dir.Unit * speed
        bg.CFrame = CFrame.new(hrp.Position, pos)
    else
        bv.Velocity = Vector3.zero
        pararVoo()
    end
end

-- ═══════════════════════════════════════════════
-- DETECÇÃO DE MOBS
-- ═══════════════════════════════════════════════
local function getMobMaisProximo()
    local char = plr.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local myPos = hrp.Position

    local maisProximo, minD = nil, math.huge

    local function checar(pasta, isBoss)
        if not pasta then return end
        for _, mob in ipairs(pasta:GetChildren()) do
            if mob:IsA("Model") and mob:FindFirstChild("HumanoidRootPart") then
                local hum = mob:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    local d = (mob.HumanoidRootPart.Position - myPos).Magnitude
                    if d < minD then
                        minD = d
                        maisProximo = {
                            model = mob,
                            fullName = mob.Name,
                            baseName = mob.Name:gsub("%-?%d+$", ""),
                            pos = mob.HumanoidRootPart.Position,
                            dist = d,
                            isBoss = isBoss,
                            hp = hum.Health,
                            maxHp = hum.MaxHealth,
                        }
                    end
                end
            end
        end
    end

    local wm = WS:FindFirstChild("World Mobs")
    if wm then
        checar(wm:FindFirstChild("Mobs"), false)
        checar(wm:FindFirstChild("Boss Mobs"), true)
    end

    return maisProximo
end

-- ═══════════════════════════════════════════════
-- GERENCIAMENTO DE KI
-- ═══════════════════════════════════════════════
local function getKiAtual()
    local char = plr.Character
    if not char then return 0, 0 end
    local status = char:FindFirstChild("Status")
    if not status then return 0, 0 end
    local cur = status:FindFirstChild("CurrentEnergy")
    local max = status:FindFirstChild("MaxEnergy")
    if not cur or not max then return 0, 0 end
    return cur.Value, max.Value
end

local function recarregarKi()
    if KiCfg.Recarregando then return end
    KiCfg.Recarregando = true

    local char = plr.Character
    if not char then KiCfg.Recarregando = false return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then KiCfg.Recarregando = false return end

    local mob = getMobMaisProximo()
    if mob and mob.dist < 40 then
        local fuga = hrp.Position + (hrp.Position - mob.pos).Unit * 40
        voarPara(fuga, 100)
        task.wait(0.5)
    end

    local ancoraCF = hrp.CFrame
    local cam = workspace.CurrentCamera
    local camCF = cam and cam.CFrame or ancoraCF
    local inicio = os.clock()

    task.spawn(function()
        while KiCfg.Recarregando and Ativo do
            local cur, max = getKiAtual()
            local pct = max > 0 and (cur / max) or 0

            if pct >= KiCfg.AlvoRecarga then break end
            if (os.clock() - inicio) >= KiCfg.TempoMaxRecarga then break end

            if SkillRemote then
                pcall(function()
                    SkillRemote:FireServer({
                        Began = true,
                        CFrame = ancoraCF,
                        Aim = hrp.Position + hrp.CFrame.LookVector * 10,
                        Camera = camCF,
                        Type = 1,
                    })
                end)
            end

            task.wait(0.15)
        end

        if SkillRemote then
            pcall(function()
                SkillRemote:FireServer({
                    Began = false,
                    CFrame = ancoraCF,
                    Aim = hrp.Position + hrp.CFrame.LookVector * 10,
                    Camera = camCF,
                    Type = 1,
                })
            end)
        end
    end)

    local timeout = os.clock() + KiCfg.TempoMaxRecarga + 1
    while KiCfg.Recarregando and Ativo and os.clock() < timeout do
        local cur, max = getKiAtual()
        if max > 0 and (cur / max) >= KiCfg.AlvoRecarga then break end
        task.wait(0.2)
    end

    KiCfg.Recarregando = false
    task.wait(KiCfg.AposRecarga)
end

-- ═══════════════════════════════════════════════
-- SKILLS
-- ═══════════════════════════════════════════════
local SkillList = {
    "UniqueSets_2_1",
    "UniqueSets_2_2",
    "UniqueSets_2_3",
    "Weapons_3_2",
    "Weapons_3_3",
}
local skillIndex = 1

local function usarSkill(skillId, slot, targetPos, mobNome)
    local char = plr.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local params = { HumCFrame = hrp.CFrame }
    if targetPos then params.targetPos = targetPos end
    if mobNome then params.Target = mobNome end

    if RE_ExecuteSkillSpecial then
        pcall(function() RE_ExecuteSkillSpecial:FireServer(plr.Name, skillId) end)
    end
    task.wait(0.03)

    if SkillRemote then
        pcall(function()
            SkillRemote:FireServer({
                Began = true,
                CFrame = hrp.CFrame,
                Aim = targetPos or (hrp.Position + hrp.CFrame.LookVector * 10),
                Camera = workspace.CurrentCamera and workspace.CurrentCamera.CFrame or hrp.CFrame,
                Type = 2,
            })
        end)
        task.wait(0.1)
        pcall(function()
            SkillRemote:FireServer({
                Began = false,
                CFrame = hrp.CFrame,
                Aim = targetPos or (hrp.Position + hrp.CFrame.LookVector * 10),
                Camera = workspace.CurrentCamera and workspace.CurrentCamera.CFrame or hrp.CFrame,
                Type = 2,
            })
        end)
    end

    if RE_ExecuteSkill then
        pcall(function() RE_ExecuteSkill:FireServer(skillId, params, slot or 1, true) end)
    end
end

local function proximaSkill()
    skillIndex = skillIndex + 1
    if skillIndex > #SkillList then skillIndex = 1 end
    return SkillList[skillIndex]
end

-- ═══════════════════════════════════════════════
-- AUTO LOCK-ON
-- ═══════════════════════════════════════════════
local LockAtivo = false
local LockConexao = nil
local LockAlvo = nil

local function lockOn(nomeMob, mobModel)
    if RE_LockedOnChanged then
        pcall(function() RE_LockedOnChanged:FireServer(nomeMob or "") end)
    end

    if mobModel and mobModel:FindFirstChild("HumanoidRootPart") then
        LockAlvo = mobModel
        LockAtivo = true

        if LockConexao then LockConexao:Disconnect() end
        LockConexao = RunService.RenderStepped:Connect(function()
            if not LockAtivo or not LockAlvo then return end
            local meuChar = plr.Character
            if not meuChar or not meuChar:FindFirstChild("HumanoidRootPart") then return end
            local alvoHrp = LockAlvo:FindFirstChild("HumanoidRootPart")
            if not alvoHrp or not LockAlvo:FindFirstChildOfClass("Humanoid") 
            or LockAlvo:FindFirstChildOfClass("Humanoid").Health <= 0 then
                LockAtivo = false
                return
            end
            workspace.CurrentCamera.CFrame = CFrame.lookAt(
                workspace.CurrentCamera.CFrame.Position,
                alvoHrp.Position
            )
        end)
    else
        LockAtivo = false
        LockAlvo = nil
        if LockConexao then
            LockConexao:Disconnect()
            LockConexao = nil
        end
    end
end

-- ═══════════════════════════════════════════════
-- ESP SYSTEM
-- ═══════════════════════════════════════════════
local espGui = Instance.new("ScreenGui")
espGui.Name = "DBH_ESP"
espGui.ResetOnSpawn = false
espGui.Parent = CoreGui

local espCache = {}

local function criarESP(mob)
    local hrp = mob:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local bb = Instance.new("BillboardGui")
    bb.Name = "DBH_ESP"
    bb.Size = UDim2.new(0, 120, 0, 40)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Adornee = hrp
    bb.Parent = espGui

    local nome = Instance.new("TextLabel", bb)
    nome.Size = UDim2.new(1, 0, 0, 18)
    nome.BackgroundTransparency = 1
    nome.TextColor3 = mob:FindFirstChild("Humanoid") and 
        (mob.Parent and mob.Parent.Name == "Boss Mobs" and Color3.fromRGB(255,80,80) or Color3.fromRGB(255,200,80))
        or Color3.new(1,1,1)
    nome.TextStrokeTransparency = 0.5
    nome.TextSize = 12
    nome.Font = Enum.Font.GothamBold
    nome.Text = mob.Name

    local hpBar = Instance.new("Frame", bb)
    hpBar.Size = UDim2.new(1, -10, 0, 6)
    hpBar.Position = UDim2.new(0, 5, 0, 20)
    hpBar.BackgroundColor3 = Color3.fromRGB(40,40,40)
    hpBar.BorderSizePixel = 0

    local hpFill = Instance.new("Frame", hpBar)
    hpFill.Size = UDim2.new(1, 0, 1, 0)
    hpFill.BackgroundColor3 = Color3.fromRGB(80,200,120)
    hpFill.BorderSizePixel = 0

    espCache[mob] = {bb=bb, hpFill=hpFill}
end

local function removerESP(mob)
    local c = espCache[mob]
    if c and c.bb then c.bb:Destroy() end
    espCache[mob] = nil
end

task.spawn(function()
    while Ativo do
        task.wait(0.3)
        if not ShowESP then
            for mob in pairs(espCache) do removerESP(mob) end
            continue
        end

        local vivos = {}
        local wm = WS:FindFirstChild("World Mobs")
        if wm then
            for _, pasta in ipairs({wm:FindFirstChild("Mobs"), wm:FindFirstChild("Boss Mobs")}) do
                if pasta then
                    for _, mob in ipairs(pasta:GetChildren()) do
                        if mob:IsA("Model") and mob:FindFirstChild("HumanoidRootPart") then
                            vivos[mob] = true
                            if not espCache[mob] then criarESP(mob) end
                            local c = espCache[mob]
                            local hum = mob:FindFirstChildOfClass("Humanoid")
                            if c and hum then
                                local pct = hum.Health / math.max(hum.MaxHealth, 1)
                                c.hpFill.Size = UDim2.new(pct, 0, 1, 0)
                                c.hpFill.BackgroundColor3 = pct > 0.5 and Color3.fromRGB(80,200,120)
                                    or pct > 0.2 and Color3.fromRGB(255,200,80)
                                    or Color3.fromRGB(220,60,60)
                            end
                        end
                    end
                end
            end
        end

        for mob in pairs(espCache) do
            if not vivos[mob] then removerESP(mob) end
        end
    end
end)

-- ═══════════════════════════════════════════════
-- LOOP DE COMBATE
-- ═══════════════════════════════════════════════
task.spawn(function()
    local ultimoSkill = 0
    local ultimoM1 = 0
    local alvoTravado = nil

    while Ativo do
        task.wait(0.05)

        if not AutoFarm and not AutoSkill then
            alvoTravado = nil
            continue
        end

        local cur, max = getKiAtual()
        local pct = max > 0 and (cur / max) or 1
        if pct < KiCfg.LimiteRecarga and AutoSkill then
            lockOn("")
            pararVoo()
            recarregarKi()
            ultimoSkill = os.clock()
            continue
        end

        local mob = getMobMaisProximo()
        if not mob then
            continue
        end

        local char = plr.Character
        if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end

        if mob.dist > CombatCfg.M1_Range then
            voarPara(mob.pos)
            continue
        end

        if CombatCfg.AutoLock and alvoTravado ~= mob.baseName then
            lockOn(mob.baseName, mob.model)
            alvoTravado = mob.baseName
            task.wait(0.05)
        end

        pararVoo()
        hrp.CFrame = CFrame.new(hrp.Position, mob.pos)

        -- Executa ataque M1 via Remote
        if AutoFarm and (os.clock() - ultimoM1) >= CombatCfg.M1_Delay then
            m1Direto(mob.pos)
            ultimoM1 = os.clock()
        end

        -- Executa ataque de Skill
        if AutoSkill and (os.clock() - ultimoSkill) >= CombatCfg.Skill_Delay then
            local skillAtual = proximaSkill()
            usarSkill(skillAtual, CombatCfg.Skill_Slot, mob.pos, mob.baseName)
            ultimoSkill = os.clock()
        end
    end
end)

-- ═══════════════════════════════════════════════
-- INTERFACE GRÁFICA (UI)
-- ═══════════════════════════════════════════════
local gui = Instance.new("ScreenGui")
gui.Name = "DragonBloxHub_v5"
gui.ResetOnSpawn = false
gui.Parent = CoreGui

local toggleBtn = Instance.new("TextButton", gui)
toggleBtn.Size = UDim2.new(0, 45, 0, 45)
toggleBtn.Position = UDim2.new(0, 15, 0.4, 0)
toggleBtn.BackgroundColor3 = Color3.fromRGB(255, 140, 30)
toggleBtn.Text = "DBH"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 14
toggleBtn.Active = true
toggleBtn.Draggable = true
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 22)

mainFrame = Instance.new("Frame", gui)
mainFrame.Size = UDim2.new(0, 420, 0, 320)
mainFrame.Position = UDim2.new(0.5, -210, 0.4, -160)
mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Visible = true
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

toggleBtn.MouseButton1Click:Connect(function()
    mainFrame.Visible = not mainFrame.Visible
end)

local header = Instance.new("Frame", mainFrame)
header.Size = UDim2.new(1, 0, 0, 35)
header.BackgroundColor3 = Color3.fromRGB(25, 25, 34)
header.BorderSizePixel = 0
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel", header)
title.Size = UDim2.new(1, -10, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Dragon Blox Hub v5.3"
title.TextColor3 = Color3.fromRGB(255, 140, 30)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left

local navBar = Instance.new("Frame", mainFrame)
navBar.Size = UDim2.new(0, 100, 1, -35)
navBar.Position = UDim2.new(0, 0, 0, 35)
navBar.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
navBar.BorderSizePixel = 0

local navLayout = Instance.new("UIListLayout", navBar)
navLayout.SortOrder = Enum.SortOrder.LayoutOrder
navLayout.Padding = UDim.new(0, 2)

local contentContainer = Instance.new("Frame", mainFrame)
contentContainer.Size = UDim2.new(1, -105, 1, -40)
contentContainer.Position = UDim2.new(0, 105, 0, 38)
contentContainer.BackgroundTransparency = 1

local tabs = {}

local function createTab(name)
    local tabBtn = Instance.new("TextButton", navBar)
    tabBtn.Size = UDim2.new(1, 0, 0, 32)
    tabBtn.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    tabBtn.TextColor3 = Color3.fromRGB(160, 160, 170)
    tabBtn.Font = Enum.Font.Gotham
    tabBtn.TextSize = 11
    tabBtn.Text = name
    tabBtn.BorderSizePixel = 0

    local container = Instance.new("ScrollingFrame", contentContainer)
    container.Size = UDim2.new(1, 0, 1, 0)
    container.BackgroundTransparency = 1
    container.Visible = false
    container.CanvasSize = UDim2.new(0, 0, 0, 0)
    container.ScrollBarThickness = 4

    local layout = Instance.new("UIListLayout", container)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 6)

    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        container.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
    end)

    tabBtn.MouseButton1Click:Connect(function()
        for _, t in pairs(tabs) do
            t.btn.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
            t.btn.TextColor3 = Color3.fromRGB(160, 160, 170)
            t.container.Visible = false
        end
        tabBtn.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
        tabBtn.TextColor3 = Color3.fromRGB(255, 140, 30)
        container.Visible = true
    end)

    local tabData = {btn = tabBtn, container = container}
    tabs[name] = tabData
    return container
end

local farmTab   = createTab("Farm")
local statsTab  = createTab("Stats")
local miscTab   = createTab("Misc")
local configTab = createTab("Config")

tabs["Farm"].btn.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
tabs["Farm"].btn.TextColor3 = Color3.fromRGB(255, 140, 30)
tabs["Farm"].container.Visible = true

local function mkToggle(parent, text, default, cb)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(1, -8, 0, 28)
    btn.BackgroundColor3 = default and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(40, 40, 48)
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 11
    btn.Text = text .. ": " .. (default and "LIGADO" or "DESLIGADO")
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

    local st = default
    btn.MouseButton1Click:Connect(function()
        st = not st
        btn.BackgroundColor3 = st and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(40, 40, 48)
        btn.Text = text .. ": " .. (st and "LIGADO" or "DESLIGADO")
        cb(st)
    end)
end

local function mkSlider(parent, label, min, max, default, cb)
    local f = Instance.new("Frame", parent)
    f.Size = UDim2.new(1, -8, 0, 40)
    f.BackgroundTransparency = 1

    local l = Instance.new("TextLabel", f)
    l.Size = UDim2.new(1, 0, 0, 14)
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.fromRGB(220, 220, 225)
    l.TextSize = 11
    l.Font = Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = label .. ": " .. default

    local bar = Instance.new("Frame", f)
    bar.Size = UDim2.new(1, 0, 0, 12)
    bar.Position = UDim2.new(0, 0, 0, 22)
    bar.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
    bar.BorderSizePixel = 0
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame", bar)
    fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(255, 140, 30)
    fill.BorderSizePixel = 0
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local dragging = false

    local function setFromX(x)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local val = math.floor(min + (max - min) * rel)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        l.Text = label .. ": " .. val
        cb(val)
    end

    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromX(i.Position.X)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            setFromX(i.Position.X)
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- CONTEÚDO DAS ABAS
mkToggle(farmTab, "Auto Farm (M1)", AutoFarm, function(v) AutoFarm = v end)
mkToggle(farmTab, "Auto Skill", AutoSkill, function(v) AutoSkill = v end)
mkToggle(farmTab, "Auto Lock-On", CombatCfg.AutoLock, function(v) CombatCfg.AutoLock = v end)
mkToggle(farmTab, "Mostrar ESP", ShowESP, function(v) ShowESP = v end)

mkSlider(farmTab, "M1 Range", 5, 50, CombatCfg.M1_Range, function(v) CombatCfg.M1_Range = v end)
mkSlider(farmTab, "M1 Delay (x0.01s)", 10, 100, 35, function(v) CombatCfg.M1_Delay = v / 100 end)
mkSlider(farmTab, "Skill Delay (x0.1s)", 3, 50, 12, function(v) CombatCfg.Skill_Delay = v / 10 end)

local statsLabel = Instance.new("TextLabel", statsTab)
statsLabel.Size = UDim2.new(1, -8, 0, 100)
statsLabel.BackgroundTransparency = 1
statsLabel.TextColor3 = Color3.fromRGB(220, 220, 225)
statsLabel.Font = Enum.Font.Gotham
statsLabel.TextSize = 12
statsLabel.TextXAlignment = Enum.TextXAlignment.Left
statsLabel.TextYAlignment = Enum.TextYAlignment.Top
statsLabel.Text = "Carregando estatísticas..."

task.spawn(function()
    while Ativo do
        local st = getStats()
        statsLabel.Text = string.format("Força: %d\nEnergia (Ki): %d\nDefesa: %d\nVelocidade: %d", 
            st.Strength or 0, st.Energy or 0, st.Defense or 0, st.Speed or 0)
        task.wait(1)
    end
end)

mkSlider(miscTab, "Velocidade de Voo", 50, 500, Config.FlySpeed, function(v) Config.FlySpeed = v end)
mkToggle(miscTab, "Forçar WalkSpeed", Config.OverrideSpeed, function(v) Config.OverrideSpeed = v end)
mkSlider(miscTab, "WalkSpeed", 16, 200, Config.WalkSpeed, function(v) Config.WalkSpeed = v end)

task.spawn(function()
    while Ativo do
        if Config.OverrideSpeed then
            local char = plr.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum.WalkSpeed = Config.WalkSpeed end
            end
        end
        task.wait(0.5)
    end
end)

mkSlider(configTab, "Ki mín. p/ recarregar (%)", 10, 80, 30, function(v) KiCfg.LimiteRecarga = v / 100 end)
mkSlider(configTab, "Ki alvo pós-recarga (%)", 50, 100, 90, function(v) KiCfg.AlvoRecarga = v / 100 end)
mkSlider(configTab, "Tempo máx. recarga (s)", 1, 10, 3, function(v) KiCfg.TempoMaxRecarga = v end)
