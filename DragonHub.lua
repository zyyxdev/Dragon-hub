-- ════════════════════════════════════════════════════════════════
--           DRAGON BLOX HUB - VERSION 5.6 (AMOLED RAYFIELD)       
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
    M1_Delay        = 0.40,
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
    TempoMaxRecarga = 3.0,
    AposRecarga     = 0.5,
    Recarregando    = false,
}

local HitboxCfg = {
    Ativo         = false,
    Multiplicador = 1,
}

local NoclipAtivo = false
local SkillTap    = true
local Ativo       = true
local AutoFarm    = false
local AutoSkill   = false
local ShowESP     = false

-- ═══════════════════════════════════════════════
-- NOCLIP SYSTEM
-- ═══════════════════════════════════════════════
task.spawn(function()
    while Ativo do
        task.wait(0.2)
        if NoclipAtivo then
            local char = plr.Character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════════════
-- HITBOX EXPANDIDA & AIM ESTENDIDO (M1)
-- ═══════════════════════════════════════════════
local function aplicarHitbox()
    if not HitboxCfg.Ativo then return end
    local wm = WS:FindFirstChild("World Mobs")
    if not wm then return end
    for _, pasta in ipairs({wm:FindFirstChild("Mobs"), wm:FindFirstChild("Boss Mobs")}) do
        if pasta then
            for _, mob in ipairs(pasta:GetChildren()) do
                local hrp = mob:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local orig = hrp:FindFirstChild("__OrigSize")
                    if not orig then
                        orig = Instance.new("Vector3Value")
                        orig.Name = "__OrigSize"
                        orig.Value = hrp.Size
                        orig.Parent = hrp
                    end
                    hrp.Size = orig.Value * HitboxCfg.Multiplicador
                    hrp.Transparency = math.max(hrp.Transparency, 0.95)
                end
            end
        end
    end
end

local function m1Estendido(mobPos)
    local char = plr.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local dir = (mobPos - hrp.Position)
    local dist = dir.Magnitude
    local fakePos

    if dist > CombatCfg.M1_Range then
        fakePos = mobPos - dir.Unit * 10
    else
        fakePos = hrp.Position
    end

    local fakeCF = CFrame.new(fakePos, mobPos)
    local cam = workspace.CurrentCamera

    if SkillRemote then
        pcall(function()
            SkillRemote:FireServer({
                Began = true,
                CFrame = fakeCF,
                Aim = mobPos,
                Camera = cam and cam.CFrame or fakeCF,
                Type = 1,
            })
        end)
        task.wait(0.04)
        pcall(function()
            SkillRemote:FireServer({
                Began = false,
                CFrame = fakeCF,
                Aim = mobPos,
                Camera = cam and cam.CFrame or fakeCF,
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
-- GERENCIAMENTO DE KI (LEITURA)
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

-- ═══════════════════════════════════════════════
-- GERENCIAMENTO DE SKILLS (CORRIGIDO)
-- ═══════════════════════════════════════════════
local SkillList = {
    "UniqueSets_2_1",
    "UniqueSets_2_2",
    "UniqueSets_2_3",
    "Weapons_3_2",
    "Weapons_3_3",
}
local skillIdx = 0

local function proximaSkill()
    skillIdx = skillIdx + 1
    if skillIdx > #SkillList then skillIdx = 1 end
    return SkillList[skillIdx]
end

local ultimaSpecial = nil

local function usarSkill(skillId, slot, targetPos, mobNome)
    local char = plr.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    -- 1) Special só quando troca de skill
    if skillId ~= ultimaSpecial then
        if RE_ExecuteSkillSpecial then
            pcall(function()
                RE_ExecuteSkillSpecial:FireServer(plr.Name, skillId)
            end)
        end
        ultimaSpecial = skillId
        task.wait(0.08)
    end

    -- 2) Se NÃO é tap, segura por X segundos (Type 1 corrigido)
    if not SkillTap and SkillRemote then
        pcall(function()
            SkillRemote:FireServer({
                Began = true,
                CFrame = hrp.CFrame,
                Aim = targetPos or (hrp.Position + hrp.CFrame.LookVector * 10),
                Camera = workspace.CurrentCamera and workspace.CurrentCamera.CFrame or hrp.CFrame,
                Type = 1,
            })
        end)
        task.wait(0.15)
    end

    -- 3) Executa a skill no servidor
    local params = { HumCFrame = hrp.CFrame }
    if targetPos then params.targetPos = targetPos end
    if mobNome then params.Target = mobNome end

    if RE_ExecuteSkill then
        pcall(function()
            RE_ExecuteSkill:FireServer(skillId, params, slot or 1, true)
        end)
    end

    -- 4) Só manda Began=false se houve Began=true antes (Type 1)
    if not SkillTap and SkillRemote then
        task.wait(0.1)
        pcall(function()
            SkillRemote:FireServer({
                Began = false,
                CFrame = hrp.CFrame,
                Aim = targetPos or (hrp.Position + hrp.CFrame.LookVector * 10),
                Camera = workspace.CurrentCamera and workspace.CurrentCamera.CFrame or hrp.CFrame,
                Type = 1,
            })
        end)
    end
end

-- ═══════════════════════════════════════════════
-- AUTO LOCK-ON
-- ═══════════════════════════════════════════════
local LockConexao = nil
local LockAlvo = nil

local function pararLock()
    if LockConexao then
        LockConexao:Disconnect()
        LockConexao = nil
    end
    LockAlvo = nil
end

local function lockOn(nomeMob, mobModel)
    if RE_LockedOnChanged then
        pcall(function() RE_LockedOnChanged:FireServer(nomeMob or "") end)
    end
    pararLock()
    if not mobModel or not mobModel:FindFirstChild("HumanoidRootPart") then return end
    LockAlvo = mobModel
    LockConexao = RunService.RenderStepped:Connect(function()
        if not LockAlvo or not LockAlvo.Parent then pararLock() return end
        local hrp = LockAlvo:FindFirstChild("HumanoidRootPart")
        local hum = LockAlvo:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then pararLock() return end
        local cam = workspace.CurrentCamera
        if not cam then return end
        cam.CFrame = CFrame.lookAt(cam.CFrame.Position, hrp.Position)
    end)
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
    hpBar.BackgroundColor3 = Color3.fromRGB(20,20,20)
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
    local ultimoM1 = 0
    local ultimoSkill = 0
    local ultimoHitboxCheck = 0
    local alvoTravado = nil

    while Ativo do
        task.wait(0.1)

        -- Atualização de Hitbox local periodicamente
        if os.clock() - ultimoHitboxCheck >= 1.0 then
            aplicarHitbox()
            ultimoHitboxCheck = os.clock()
        end

        if not AutoFarm and not AutoSkill then
            alvoTravado = nil
            pararVoo()
            task.wait(0.5)
            continue
        end

        local mob = getMobMaisProximo()
        if not mob then
            pararVoo()
            continue
        end

        local char = plr.Character
        if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end

        -- LOCK-ON
        if CombatCfg.AutoLock and alvoTravado ~= mob.baseName then
            lockOn(mob.baseName, mob.model)
            alvoTravado = mob.baseName
        end

        -- SE LONGE: voa pra perto
        if mob.dist > CombatCfg.M1_Range then
            voarPara(mob.pos)
            task.wait(0.1)
            continue
        end

        -- SE PERTO: para e sincroniza CFrame
        pararVoo()
        hrp.CFrame = CFrame.new(hrp.Position, mob.pos)
        task.wait()

        -- M1 ESTENDIDO / AUTO FARM
        if AutoFarm and (os.clock() - ultimoM1) >= CombatCfg.M1_Delay then
            m1Estendido(mob.pos)
            ultimoM1 = os.clock()
        end

        -- SKILL (alternando)
        if AutoSkill and (os.clock() - ultimoSkill) >= CombatCfg.Skill_Delay then
            local s = proximaSkill()
            usarSkill(s, CombatCfg.Skill_Slot, mob.pos, mob.baseName)
            ultimoSkill = os.clock()
        end
    end
end)

-- ═══════════════════════════════════════════════
-- UI LIBRARY — RAYFIELD-STYLE (custom, AMOLED)
-- ═══════════════════════════════════════════════
local UI = {}

UI.Theme = {
    Bg        = Color3.fromRGB(0, 0, 0),
    Panel     = Color3.fromRGB(8, 8, 8),
    Elevated  = Color3.fromRGB(14, 14, 14),
    Border    = Color3.fromRGB(26, 26, 30),
    Accent    = Color3.fromRGB(255, 140, 30),
    Text      = Color3.fromRGB(235, 235, 240),
    TextDim   = Color3.fromRGB(150, 150, 160),
    Success   = Color3.fromRGB(80, 200, 120),
    Danger    = Color3.fromRGB(220, 60, 60),
    Off       = Color3.fromRGB(45, 45, 55),
}

local FONT      = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold
local FONT_MONO = Enum.Font.Code

local function I(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end

local function corner(o, r)
    return I("UICorner", {CornerRadius = r or UDim.new(0, 7)}, o)
end

local function pad(o, t, b, l, r)
    return I("UIPadding", {
        PaddingTop = UDim.new(0, t or 0),
        PaddingBottom = UDim.new(0, b or 0),
        PaddingLeft = UDim.new(0, l or 0),
        PaddingRight = UDim.new(0, r or 0),
    }, o)
end

-- ─── Window ─────────────────────────────
function UI.newWindow()
    local gui = I("ScreenGui", {
        Name = "DragonBloxHub_v5",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, CoreGui)

    local main = I("Frame", {
        Name = "Main",
        Size = UDim2.new(0, 480, 0, 360),
        Position = UDim2.new(0.5, -240, 0.5, -180),
        BackgroundColor3 = UI.Theme.Bg,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        Active = true,
    }, gui)
    corner(main, UDim.new(0, 10))
    I("UIStroke", {Color = UI.Theme.Border, Thickness = 1}, main)

    -- Header
    local header = I("Frame", {
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = UI.Theme.Panel,
        BorderSizePixel = 0,
    }, main)
    corner(header, UDim.new(0, 10))

    I("TextLabel", {
        Size = UDim2.new(1, -110, 1, 0),
        Position = UDim2.new(0, 14, 0, 0),
        BackgroundTransparency = 1,
        Text = "🐉   Dragon Blox Hub",
        TextColor3 = UI.Theme.Text,
        Font = FONT_BOLD,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, header)

    local btnClose = I("TextButton", {
        Size = UDim2.new(0, 22, 0, 22),
        Position = UDim2.new(1, -30, 0.5, -11),
        BackgroundColor3 = UI.Theme.Danger,
        Text = "×", TextColor3 = Color3.new(1,1,1),
        Font = FONT_BOLD, TextSize = 14,
        AutoButtonColor = false, BorderSizePixel = 0,
    }, header)
    corner(btnClose, UDim.new(0, 5))

    local btnMin = I("TextButton", {
        Size = UDim2.new(0, 22, 0, 22),
        Position = UDim2.new(1, -56, 0.5, -11),
        BackgroundColor3 = UI.Theme.Elevated,
        Text = "—", TextColor3 = UI.Theme.Text,
        Font = FONT_BOLD, TextSize = 12,
        AutoButtonColor = false, BorderSizePixel = 0,
    }, header)
    corner(btnMin, UDim.new(0, 5))

    -- Sidebar
    local sidebar = I("Frame", {
        Size = UDim2.new(0, 118, 1, -36),
        Position = UDim2.new(0, 0, 0, 36),
        BackgroundColor3 = UI.Theme.Panel,
        BorderSizePixel = 0,
    }, main)
    I("UIListLayout", {
        Padding = UDim.new(0, 3),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, sidebar)
    pad(sidebar, 8, 8, 8, 8)

    -- Content
    local content = I("Frame", {
        Size = UDim2.new(1, -118, 1, -36),
        Position = UDim2.new(0, 118, 0, 36),
        BackgroundColor3 = UI.Theme.Bg,
        BorderSizePixel = 0,
    }, main)

    -- Drag pela header
    local dragging, dragStart, startPos = false, nil, nil
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    -- Botão flutuante
    local float = I("TextButton", {
        Size = UDim2.new(0, 46, 0, 46),
        Position = UDim2.new(0, 20, 0.4, 0),
        BackgroundColor3 = UI.Theme.Bg,
        Text = "🐉", TextColor3 = UI.Theme.Accent,
        Font = FONT_BOLD, TextSize = 20,
        AutoButtonColor = false, Visible = false,
        Active = true, Draggable = true, BorderSizePixel = 0,
    }, gui)
    corner(float, UDim.new(1, 0))
    I("UIStroke", {Color = UI.Theme.Accent, Thickness = 1}, float)

    btnMin.MouseButton1Click:Connect(function()
        main.Visible = false; float.Visible = true
    end)
    float.MouseButton1Click:Connect(function()
        main.Visible = true; float.Visible = false
    end)
    btnClose.MouseButton1Click:Connect(function() gui:Destroy() end)

    return {gui = gui, frame = main, sidebar = sidebar, content = content, float = float, tabs = {}}
end

-- ─── Tab ─────────────────────────────
function UI.newTab(win, icon, name)
    local btn = I("TextButton", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = UI.Theme.Panel,
        TextColor3 = UI.Theme.TextDim,
        Font = FONT, TextSize = 11,
        Text = "  " .. icon .. "   " .. name,
        TextXAlignment = Enum.TextXAlignment.Left,
        BorderSizePixel = 0, AutoButtonColor = false,
    }, win.sidebar)
    corner(btn, UDim.new(0, 7))

    local frame = I("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = UI.Theme.Border,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        Visible = false,
    }, win.content)
    local layout = I("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, frame)
    pad(frame, 12, 12, 12, 12)
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        frame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 24)
    end)

    btn.MouseButton1Click:Connect(function()
        for _, t in pairs(win.tabs) do
            t.btn.BackgroundColor3 = UI.Theme.Panel
            t.btn.TextColor3 = UI.Theme.TextDim
            t.frame.Visible = false
        end
        btn.BackgroundColor3 = UI.Theme.Elevated
        btn.TextColor3 = UI.Theme.Accent
        frame.Visible = true
    end)

    local tab = {btn = btn, frame = frame}
    win.tabs[name] = tab
    return tab
end

-- ─── Section ─────────────────────────
function UI.section(tab, title)
    return I("TextLabel", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1,
        Text = title, TextColor3 = UI.Theme.Accent,
        Font = FONT_BOLD, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, tab.frame)
end

-- ─── Toggle (switch iOS) ─────────────
function UI.toggle(tab, opts)
    local state = opts.default or false

    local frame = I("TextButton", {
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = UI.Theme.Elevated,
        BorderSizePixel = 0, Text = "", AutoButtonColor = false,
    }, tab.frame)
    corner(frame, UDim.new(0, 8))

    I("TextLabel", {
        Size = UDim2.new(1, -70, 1, 0),
        Position = UDim2.new(0, 14, 0, 0),
        BackgroundTransparency = 1,
        Text = opts.name, TextColor3 = UI.Theme.Text,
        Font = FONT, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)

    local sw = I("Frame", {
        Size = UDim2.new(0, 42, 0, 24),
        Position = UDim2.new(1, -56, 0.5, -12),
        BackgroundColor3 = state and UI.Theme.Success or UI.Theme.Off,
        BorderSizePixel = 0,
    }, frame)
    corner(sw, UDim.new(1, 0))

    local knob = I("Frame", {
        Size = UDim2.new(0, 20, 0, 20),
        Position = state and UDim2.new(1, -22, 0.5, -10) or UDim2.new(0, 2, 0.5, -10),
        BackgroundColor3 = Color3.fromRGB(255,255,255),
        BorderSizePixel = 0,
    }, sw)
    corner(knob, UDim.new(1, 0))

    local function set(v)
        state = v
        sw.BackgroundColor3 = v and UI.Theme.Success or UI.Theme.Off
        knob.Position = v and UDim2.new(1, -22, 0.5, -10) or UDim2.new(0, 2, 0.5, -10)
    end

    frame.MouseButton1Click:Connect(function()
        set(not state)
        if opts.callback then opts.callback(state) end
    end)

    return {set = set}
end

-- ─── Slider (label + valor + track) ──
function UI.slider(tab, opts)
    local min = opts.min or 0
    local max = opts.max or 100
    local value = opts.default or min
    local suffix = opts.suffix or ""

    local frame = I("Frame", {
        Size = UDim2.new(1, 0, 0, 56),
        BackgroundColor3 = UI.Theme.Elevated,
        BorderSizePixel = 0,
    }, tab.frame)
    corner(frame, UDim.new(0, 8))

    I("TextLabel", {
        Size = UDim2.new(1, -90, 0, 22),
        Position = UDim2.new(0, 14, 0, 6),
        BackgroundTransparency = 1,
        Text = opts.name, TextColor3 = UI.Theme.Text,
        Font = FONT, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)

    local valLabel = I("TextLabel", {
        Size = UDim2.new(0, 80, 0, 22),
        Position = UDim2.new(1, -92, 0, 6),
        BackgroundTransparency = 1,
        Text = tostring(value) .. suffix,
        TextColor3 = UI.Theme.Accent,
        Font = FONT_BOLD, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, frame)

    local track = I("Frame", {
        Size = UDim2.new(1, -28, 0, 6),
        Position = UDim2.new(0, 14, 0, 38),
        BackgroundColor3 = UI.Theme.Border,
        BorderSizePixel = 0,
    }, frame)
    corner(track, UDim.new(1, 0))

    local fill = I("Frame", {
        Size = UDim2.new((value - min) / (max - min), 0, 1, 0),
        BackgroundColor3 = UI.Theme.Accent,
        BorderSizePixel = 0,
    }, track)
    corner(fill, UDim.new(1, 0))

    local dragging = false

    local function update(x)
        local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local val = math.floor(min + (max - min) * rel + 0.5)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        valLabel.Text = tostring(val) .. suffix
        value = val
        if opts.callback then opts.callback(val) end
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            update(input.Position.X)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            update(input.Position.X)
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    return {set = function(v)
        value = v
        local rel = (v - min) / (max - min)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        valLabel.Text = tostring(v) .. suffix
    end}
end

-- ─── Label (info read-only) ──────────
function UI.label(tab, opts)
    local l = I("TextLabel", {
        Size = UDim2.new(1, 0, 0, opts.height or 60),
        BackgroundColor3 = UI.Theme.Elevated,
        TextColor3 = UI.Theme.Text,
        Font = FONT_MONO, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        Text = opts.text or "",
    }, tab.frame)
    corner(l, UDim.new(0, 8))
    pad(l, 10, 10, 14, 14)
    return l
end

-- ═══════════════════════════════════════════════
-- APLICAÇÃO
-- ═══════════════════════════════════════════════
local win = UI.newWindow()
mainFrame = win.frame

local farmTab   = UI.newTab(win, "⚔", "Farm")
local statsTab  = UI.newTab(win, "📊", "Stats")
local miscTab   = UI.newTab(win, "🛠", "Misc")
local configTab = UI.newTab(win, "⚙", "Config")

-- ativa Farm
farmTab.btn.BackgroundColor3 = UI.Theme.Elevated
farmTab.btn.TextColor3 = UI.Theme.Accent
farmTab.frame.Visible = true

-- ─── FARM ────────────────────────────
UI.section(farmTab, "⚔   COMBATE")
UI.toggle(farmTab, {name = "Auto Farm (M1)", default = AutoFarm,   callback = function(v) AutoFarm = v end})
UI.toggle(farmTab, {name = "Auto Skill",      default = AutoSkill,  callback = function(v) AutoSkill = v end})
UI.toggle(farmTab, {name = "Auto Lock-On",    default = CombatCfg.AutoLock, callback = function(v) CombatCfg.AutoLock = v end})
UI.toggle(farmTab, {name = "Mostrar ESP",     default = ShowESP,    callback = function(v) ShowESP = v end})

UI.section(farmTab, "🎯   RANGES & DELAYS")
UI.slider(farmTab, {
    name = "M1 Range", min = 5, max = 50, default = CombatCfg.M1_Range, suffix = " studs",
    callback = function(v) CombatCfg.M1_Range = v end
})
UI.slider(farmTab, {
    name = "M1 Delay", min = 10, max = 100, default = 40, suffix = " ms",
    callback = function(v) CombatCfg.M1_Delay = v / 100 end
})
UI.slider(farmTab, {
    name = "Skill Delay", min = 3, max = 50, default = 12, suffix = " x0.1s",
    callback = function(v) CombatCfg.Skill_Delay = v / 10 end
})

-- ─── STATS ───────────────────────────
UI.section(statsTab, "📊   STATUS DO JOGADOR")
local statsLabel = UI.label(statsTab, {text = "Carregando...", height = 110})

-- ─── MISC ────────────────────────────
UI.section(miscTab, "🛠   UTILITÁRIOS")
UI.toggle(miscTab, {name = "Noclip", default = NoclipAtivo, callback = function(v) NoclipAtivo = v end})

UI.section(miscTab, "🎯   HITBOX")
UI.toggle(miscTab, {name = "Hitbox Expandida", default = HitboxCfg.Ativo, callback = function(v) HitboxCfg.Ativo = v end})
UI.slider(miscTab, {
    name = "Multiplicador Hitbox", min = 1, max = 5, default = HitboxCfg.Multiplicador,
    callback = function(v) HitboxCfg.Multiplicador = v end
})

UI.section(miscTab, "✈   MOVIMENTO")
UI.slider(miscTab, {
    name = "Velocidade de Voo", min = 50, max = 500, default = Config.FlySpeed, suffix = " studs/s",
    callback = function(v) Config.FlySpeed = v end
})
UI.toggle(miscTab, {name = "Forçar WalkSpeed", default = Config.OverrideSpeed, callback = function(v) Config.OverrideSpeed = v end})
UI.slider(miscTab, {
    name = "WalkSpeed", min = 16, max = 200, default = Config.WalkSpeed,
    callback = function(v) Config.WalkSpeed = v end
})

-- ─── CONFIG ──────────────────────────
UI.section(configTab, "⚡   SKILLS")
UI.toggle(configTab, {name = "Skills: Tap (não segurar)", default = SkillTap, callback = function(v) SkillTap = v end})

UI.section(configTab, "💠   KI / ENERGIA")
UI.slider(configTab, {
    name = "Ki mín. p/ recarregar", min = 10, max = 80, default = 30, suffix = "%",
    callback = function(v) KiCfg.LimiteRecarga = v / 100 end
})
UI.slider(configTab, {
    name = "Ki alvo pós-recarga", min = 50, max = 100, default = 90, suffix = "%",
    callback = function(v) KiCfg.AlvoRecarga = v / 100 end
})
UI.slider(configTab, {
    name = "Tempo máx. recarga", min = 1, max = 10, default = 3, suffix = " s",
    callback = function(v) KiCfg.TempoMaxRecarga = v end
})

-- ─── Stats loop ──────────────────────
task.spawn(function()
    while Ativo do
        local st = getStats()
        statsLabel.Text = string.format(
            "Força:        %d\nEnergia (Ki): %d\nDefesa:       %d\nVelocidade:   %d",
            st.Strength or 0, st.Energy or 0, st.Defense or 0, st.Speed or 0
        )
        task.wait(1)
    end
end)
