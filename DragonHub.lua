-- [SERVIÇOS]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local VIM = game:GetService("VirtualInputManager")
local plr = Players.LocalPlayer

local function safe(fn)
    local ok, err = pcall(fn)
    if not ok then warn("[DBH] " .. tostring(err)) end
    return ok
end

-- [REMOTES]
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
local ToolbarRemote        = KnitSVC and KnitSVC.ToolService and KnitSVC.ToolService.RE.UpdatePlayerToolbarSelection
local LockedOnRemote       = KnitSVC and KnitSVC.SkillManager and KnitSVC.SkillManager.RE and KnitSVC.SkillManager.RE.LockedOnChanged
local SkillRemote          = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("SkillRemote")

local Ativo = true

-- [CONFIG]
local Config = {
    FarmAtivo = false,
    AlvoModo = "todos",
    AutoTransform = false,
    TransformMode = "SSJAngel",
    AutoRebirth = false,
    ESPMobs = false,
    ESPItems = false,
    AutoRegen = false,
    AutoLock = true,
    Noclip = true,
    HitboxExpandida = false,
    HitboxMulti = 2,
    AutoCollect = false,
    ColetarComum = false,
    ColetarIncomum = true,
    ColetarRaro = true,
    ColetarEpico = true,
    ColetarLendario = true,
    ColetaCooldown = 3,
    KiMin = 0.3,
    SafeHeight = 100,
    WalkSpeed = 16,
    FlySpeed = 250,
    AttackRange = 8,
    SkillDelay = 1.5,
    TrackerAuto = true,
    SkillMode = "off",
    SkillSingle = "UniqueSets_2_1",
    SkillCombo = "dps",
}

local function farmLigado()
    return Config.FarmAtivo == true
end

-- [SKILLS]
local SKILLS = {
    ["UniqueSets_2_1"] = { nome = "UniqueSets_2_1", hold = "Hold_Kamehameha", release = "Release_Kamehameha", pause = 3, slot = 1 },
    ["UniqueSets_2_2"] = { nome = "UniqueSets_2_2", pause = 1, slot = 1 },
    ["UniqueSets_2_3"] = { nome = "UniqueSets_2_3", hold = "Hold_SpiritBomb", release = "Release_SpiritBomb", pause = 0.1, slot = 1 },
    ["Weapons_3_2"] = { nome = "Weapons_3_2", pause = 0.7, slot = 2 },
    ["Weapons_3_3"] = { nome = "Weapons_3_3", pause = 0.5, slot = 2 },
}

local COMBOS = {
    dps = { "UniqueSets_2_1", "UniqueSets_2_3", "UniqueSets_2_2", "Weapons_3_2", "Weapons_3_3" },
    default = { "UniqueSets_2_1", "UniqueSets_2_2", "UniqueSets_2_3" },
    kame = { "UniqueSets_2_1" },
    spirit = { "UniqueSets_2_3" },
    arma = { "Weapons_3_2", "Weapons_3_3" },
    burst = { "UniqueSets_2_1", "UniqueSets_2_3" },
}

local comboIdx = 1
local slotAtual = 1

local BossTimers = {
    Karrot = 299, Zero = 59, ["Brawly X01"] = 300,
    Zaja = 600, Destroyer = 600, Puriza = 420,
    ["Puriza Minion"] = 60, _default = 180,
}

local function getCategoria(mob)
    if not mob or not mob.Parent then return nil end
    local p = mob.Parent.Name
    if p == "Mobs"       then return "mobs"  end
    if p == "Boss Mobs"  then return "boss"  end
    if p == "Event Mobs" then return "event" end
    return nil
end

local emRegen = false
local ultimaAcao = 0
local alvoTravado = nil
local LockConexao = nil
local LockAlvo = nil

local function podeAgir()
    local agora = tick()
    if agora - ultimaAcao < 0.05 then return false end
    ultimaAcao = agora
    return true
end

-- [LOCK-ON]
local function pararLock()
    if LockConexao then LockConexao:Disconnect(); LockConexao = nil end
    LockAlvo = nil
end

local function lockOn(mobModel)
    if LockedOnRemote then
        safe(function() LockedOnRemote:FireServer(mobModel) end)
    end
    pararLock()
    if not mobModel or not mobModel:FindFirstChild("HumanoidRootPart") then return end
    LockAlvo = mobModel
    LockConexao = RunService.RenderStepped:Connect(function()
        if not LockAlvo or not LockAlvo.Parent then pararLock() return end
        local mh = LockAlvo:FindFirstChild("HumanoidRootPart")
        local hum = LockAlvo:FindFirstChildOfClass("Humanoid")
        if not mh or not hum or hum.Health <= 0 then pararLock() return end
        local cam = workspace.CurrentCamera
        if cam then cam.CFrame = CFrame.lookAt(cam.CFrame.Position, mh.Position) end
    end)
end

-- [VOO]
local vooBv, vooBg
local function voarPara(destino, velocidade)
    local myChar = plr.Character
    if not myChar then return end
    local hrp = myChar:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    velocidade = velocidade or Config.FlySpeed

    if not vooBv or vooBv.Parent ~= hrp then
        vooBv = Instance.new("BodyVelocity")
        vooBv.Name = "__dbh_v"
        vooBv.MaxForce = Vector3.new(4e4, 4e4, 4e4)
        vooBv.P = 1250
        vooBv.Parent = hrp
    end
    if not vooBg or vooBg.Parent ~= hrp then
        vooBg = Instance.new("BodyGyro")
        vooBg.Name = "__dbh_g"
        vooBg.MaxTorque = Vector3.new(4e4, 4e4, 4e4)
        vooBg.P = 3000
        vooBg.D = 100
        vooBg.Parent = hrp
    end

    local dir = destino - hrp.Position
    local dist = dir.Magnitude
    local spd
    if dist > 30 then spd = velocidade
    elseif dist > 10 then spd = velocidade * 0.5
    else spd = velocidade * 0.2 end

    vooBv.Velocity = dir.Unit * spd
    vooBg.CFrame = CFrame.new(hrp.Position, destino)
end

-- [M1]
local function atacar(alvo)
    if not SkillRemote or not plr.Character or not podeAgir() then return end
    if not alvo or not alvo:FindFirstChild("HumanoidRootPart") then return end
    local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local mhrp = alvo.HumanoidRootPart
    local cframe = hrp.CFrame
    local aim = mhrp.Position
    local camCF = CFrame.lookAt(hrp.Position, aim)
    safe(function()
        SkillRemote:FireServer({ Began = true, CFrame = cframe, Aim = aim, Camera = camCF, Type = 1, SkillId = "1" })
    end)
    task.wait(0.05)
    safe(function()
        SkillRemote:FireServer({ Began = false, CFrame = cframe, Aim = aim, Camera = camCF, Type = 1, SkillId = "1" })
    end)
end

-- [SKILL]
local function usarSkill(skill, alvo)
    if not ExecuteSkill or not alvo or not alvo.Parent then return end
    if not alvo:FindFirstChild("HumanoidRootPart") then return end
    local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    if skill.slot and skill.slot ~= slotAtual then
        if ToolbarRemote then
            safe(function() ToolbarRemote:FireServer(skill.slot) end)
            slotAtual = skill.slot
            task.wait(0.25)
        end
    end

    local tpos = alvo.HumanoidRootPart.Position
    safe(function() ExecuteSkill_Special:FireServer(plr.Name, skill.nome) end)

    local cfg = { targetPos = tpos, HumCFrame = hrp.CFrame, ResumeOnTimePassed = skill.pause or 0.5 }
    if skill.hold then cfg.HoldAnimation = skill.hold end
    if skill.release then cfg.ReleaseAnimation = skill.release end

    safe(function() ExecuteSkill:FireServer(skill.nome, cfg, 1, true) end)
    task.wait(skill.pause or 0.5)
    safe(function() ExecuteSkill:FireServer(skill.nome, cfg, 1, false) end)
end

-- [KI]
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

-- [REGEN]
local function iniciarRegen()
    if emRegen then return end
    emRegen = true

    local myChar = plr.Character
    if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then
        emRegen = false; return
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

        local inicio = os.clock()
        pcall(function() VIM:SendKeyEvent(true, Enum.KeyCode.C, false, game) end)

        while emRegen and Ativo and hrp.Parent do
            hrp.CFrame = CFrame.new(posSegura)
            local cur, max = getKi()
            local pct = max and max > 0 and (cur/max) or 0
            if pct >= 0.95 then break end
            if (os.clock() - inicio) > 8 then break end
            task.wait(0.15)
        end

        pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.C, false, game) end)
        bv:Destroy()
        emRegen = false
    end)
end

local function pararRegen()
    if not emRegen then return end
    emRegen = false
    pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.C, false, game) end)
end

-- [MOBS]
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
    local modo = Config.AlvoModo or "todos"
    local closest, minD = nil, math.huge
    for _, mob in ipairs(mobs) do
        if mob and mob.Parent and mob:FindFirstChild("HumanoidRootPart") and mob.Humanoid.Health > 0 then
            local cat = getCategoria(mob)
            if cat then
                local valido = (modo == "todos") or (modo == cat)
                if valido then
                    local d = (mob.HumanoidRootPart.Position - myPos).Magnitude
                    if d < minD then minD = d; closest = mob end
                end
            end
        end
    end
    return closest
end

-- [HITBOX]
local function expandirHitbox()
    if not Config.HitboxExpandida then return end
    local wm = WS:FindFirstChild("World Mobs")
    if not wm then return end
    for _, p in ipairs({wm:FindFirstChild("Mobs"), wm:FindFirstChild("Boss Mobs"), wm:FindFirstChild("Event Mobs")}) do
        if p then
            for _, m in ipairs(p:GetChildren()) do
                local hrp = m:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local orig = hrp:FindFirstChild("__OrigSize")
                    if not orig then
                        orig = Instance.new("Vector3Value")
                        orig.Name = "__OrigSize"
                        orig.Value = hrp.Size
                        orig.Parent = hrp
                    end
                    hrp.Size = orig.Value * Config.HitboxMulti
                    hrp.Transparency = math.max(hrp.Transparency, 0.95)
                end
            end
        end
    end
end

-- [AUTOCOLLECT] cooldown + histerese + por-item
local coletando = false
local ultimoColetado = 0
local tentativasItem = {}

local function extrairInfo(item)
    local id = tonumber(item.Name:match("ItemDrop_(%d+)")) or 0
    local nome = item.Name
    local rar = nil
    local sv = item:FindFirstChild("ItemName") or item:FindFirstChild("Name")
    if sv and sv:IsA("StringValue") then nome = sv.Value end
    local rv = item:FindFirstChild("Rarity")
    if rv and rv:IsA("StringValue") then rar = rv.Value end
    return id, nome, rar
end

local function tentarColetar()
    if coletando then return end
    if not Config.AutoCollect then return end
    if os.clock() - ultimoColetado < (Config.ColetaCooldown or 3) then return end

    local c = plr.Character
    if not c then return end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local ps = WS:FindFirstChild("PartStorage")
    if not ps then return end

    local maisProximo, menorDist = nil, math.huge
    for _, item in ipairs(ps:GetChildren()) do
        if item.Name:find("ItemDrop_") then
            local jaTentei = tentativasItem[item]
            if not (jaTentei and os.clock() - jaTentei < 5) then
                local base = item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")
                if base then
                    local d = (base.Position - hrp.Position).Magnitude
                    if d < menorDist then menorDist = d; maisProximo = item end
                end
            end
        end
    end

    if not maisProximo then return end

    local id, itemName, rar = extrairInfo(maisProximo)
    local low = itemName:lower()
    local permitido = true
    if low:find("expmat") and not Config.ColetarComum then permitido = false end
    if low:find("powerscroll") and not Config.ColetarEpico then permitido = false end
    if low:find("wish") and not Config.ColetarLendario then permitido = false end
    if not permitido then return end

    coletando = true
    tentativasItem[maisProximo] = os.clock()

    local char = plr.Character
    if char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end

    local base = maisProximo.PrimaryPart or maisProximo:FindFirstChildWhichIsA("BasePart")
    if not base then coletando = false; return end

    local tentativas = 0
    while Config.AutoCollect and coletando and tentativas < 40 do
        local d = (base.Position - hrp.Position).Magnitude
        if d < 5 then break end
        if d > 10 then voarPara(base.Position, Config.FlySpeed)
        elseif d > 5 then voarPara(base.Position, Config.FlySpeed * 0.3) end
        task.wait(0.12)
        tentativas = tentativas + 1
    end

    if not Config.AutoCollect then coletando = false; return end

    hrp.CFrame = CFrame.new(base.Position + Vector3.new(0, 3, 0))
    task.wait(0.3)

    pcall(function() VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game) end)
    task.wait(0.5)
    pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)

    task.wait(0.2)
    local cam = workspace.CurrentCamera
    if cam then
        local vp = cam.ViewportSize
        pcall(function() VIM:SendMouseButtonEvent(vp.X/2, vp.Y/2, 0, true, game, 0) end)
        task.wait(0.1)
        pcall(function() VIM:SendMouseButtonEvent(vp.X/2, vp.Y/2, 0, false, game, 0) end)
    end

    ultimoColetado = os.clock()
    task.wait(0.3)
    coletando = false
end

-- [ESP GUI]
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
    nome.TextColor3 = (mob.Parent and mob.Parent.Name == "Boss Mobs") and Color3.fromRGB(255, 100, 100)
        or (mob.Parent and mob.Parent.Name == "Event Mobs") and Color3.fromRGB(180, 130, 255)
        or Color3.fromRGB(255, 210, 130)
    espCache[mob] = bb
end

local function removerESP(mob)
    if espCache[mob] then espCache[mob]:Destroy(); espCache[mob] = nil end
end

local function getItemLabel(item)
    local id = item.Name:match("ItemDrop_(%d+)") or "?"
    local itemName = nil
    local cor = Color3.fromRGB(220, 220, 220)

    local sv = item:FindFirstChild("ItemName") or item:FindFirstChild("Name")
    if sv and sv:IsA("StringValue") then itemName = sv.Value end

    if not itemName then
        for _, c in ipairs(item:GetDescendants()) do
            if c:IsA("StringValue") and c.Value ~= "" and not c.Name:match("^%d+$") then
                itemName = c.Value; break
            end
        end
    end

    if not itemName then return "🆔 "..id.." (desconhecido)", cor end

    local low = itemName:lower()
    if low:find("premium") then
        return "💠 Premium Wish (ID "..id..")", Color3.fromRGB(200, 120, 255)
    elseif low:find("standard") then
        return "💠 Standard Wish (ID "..id..")", Color3.fromRGB(255, 220, 80)
    elseif low:find("wish") or low:find("legendary") then
        return "🌟 "..itemName.." (ID "..id..")", Color3.fromRGB(255, 100, 100)
    elseif low:find("powerscroll") or low:find("epic") then
        return "📜 "..itemName.." (ID "..id..")", Color3.fromRGB(200, 120, 255)
    elseif low:find("orb") or low:find("rare") then
        return "🔮 "..itemName.." (ID "..id..")", Color3.fromRGB(120, 200, 255)
    elseif low:find("expmat") or low:find("common") then
        return "📗 "..itemName.." (ID "..id..")", Color3.fromRGB(120, 220, 120)
    end
    return "📦 "..itemName.." (ID "..id..")", cor
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
                        bb.Size = UDim2.new(0, 180, 0, 34)
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
                        local txt, cor = getItemLabel(item)
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

-- [UI]
local oldGui = CoreGui:FindFirstChild("DragonBloxHub")
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "DragonBloxHub"
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.IgnoreGuiInset = true
gui.Parent = CoreGui

local P = {
    bg = Color3.fromRGB(8, 8, 10),
    panel = Color3.fromRGB(14, 14, 18),
    elev = Color3.fromRGB(22, 22, 28),
    stroke = Color3.fromRGB(40, 40, 48),
    accent = Color3.fromRGB(0, 200, 255),
    accent2 = Color3.fromRGB(120, 220, 255),
    text = Color3.fromRGB(230, 235, 240),
    textDim = Color3.fromRGB(130, 135, 145),
    success = Color3.fromRGB(80, 220, 140),
    danger = Color3.fromRGB(255, 90, 90),
    off = Color3.fromRGB(45, 45, 55),
}

local homeBar = Instance.new("TextButton")
homeBar.Size = UDim2.new(0, 200, 0, 30)
homeBar.Position = UDim2.new(0.5, 0, 1, -8)
homeBar.AnchorPoint = Vector2.new(0.5, 1)
homeBar.BackgroundTransparency = 1
homeBar.Text = ""
homeBar.AutoButtonColor = false
homeBar.Active = true
homeBar.ZIndex = 50
homeBar.Parent = gui

local barVisual = Instance.new("Frame", homeBar)
barVisual.Size = UDim2.new(0, 140, 0, 5)
barVisual.Position = UDim2.new(0.5, 0, 0.5, 0)
barVisual.AnchorPoint = Vector2.new(0.5, 0.5)
barVisual.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
barVisual.BackgroundTransparency = 0.3
barVisual.BorderSizePixel = 0
barVisual.ZIndex = 51
barVisual.Active = false
Instance.new("UICorner", barVisual).CornerRadius = UDim.new(1, 0)

local janela = Instance.new("Frame")
janela.Size = UDim2.new(0, 440, 0, 340)
janela.Position = UDim2.new(0.5, -220, 0.5, -170)
janela.BackgroundColor3 = P.bg
janela.BackgroundTransparency = 0.1
janela.BorderSizePixel = 0
janela.Active = true
janela.Visible = false
janela.Parent = gui
Instance.new("UICorner", janela).CornerRadius = UDim.new(0, 12)
local jStroke = Instance.new("UIStroke", janela)
jStroke.Color = P.stroke
jStroke.Thickness = 1
jStroke.Transparency = 0.4

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 36)
header.BackgroundColor3 = P.panel
header.BackgroundTransparency = 0.2
header.BorderSizePixel = 0
header.Parent = janela
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)

local titulo = Instance.new("TextButton")
titulo.Size = UDim2.new(1, -60, 1, 0)
titulo.Position = UDim2.new(0, 16, 0, 0)
titulo.BackgroundTransparency = 1
titulo.Text = "🐉 Dragon Blox"
titulo.TextColor3 = P.text
titulo.TextSize = 13
titulo.Font = Enum.Font.GothamBold
titulo.TextXAlignment = Enum.TextXAlignment.Left
titulo.Parent = header

local btnMin = Instance.new("TextButton")
btnMin.Size = UDim2.new(0, 22, 0, 22)
btnMin.Position = UDim2.new(1, -54, 0.5, -11)
btnMin.BackgroundColor3 = P.elev
btnMin.Text = "—"
btnMin.TextColor3 = P.text
btnMin.TextSize = 13
btnMin.Font = Enum.Font.GothamBold
btnMin.BorderSizePixel = 0
btnMin.AutoButtonColor = false
btnMin.Parent = header
Instance.new("UICorner", btnMin).CornerRadius = UDim.new(0, 5)

local btnKill = Instance.new("TextButton")
btnKill.Size = UDim2.new(0, 22, 0, 22)
btnKill.Position = UDim2.new(1, -28, 0.5, -11)
btnKill.BackgroundColor3 = P.danger
btnKill.Text = "×"
btnKill.TextColor3 = Color3.new(1, 1, 1)
btnKill.TextSize = 13
btnKill.Font = Enum.Font.GothamBold
btnKill.BorderSizePixel = 0
btnKill.AutoButtonColor = false
btnKill.Parent = header
Instance.new("UICorner", btnKill).CornerRadius = UDim.new(0, 5)

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -20, 0, 32)
tabBar.Position = UDim2.new(0, 10, 0, 40)
tabBar.BackgroundColor3 = P.panel
tabBar.BackgroundTransparency = 0.3
tabBar.BorderSizePixel = 0
tabBar.Parent = janela
Instance.new("UICorner", tabBar).CornerRadius = UDim.new(0, 8)

local tabLayout = Instance.new("UIListLayout", tabBar)
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 3)
tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center

local contentArea = Instance.new("Frame")
contentArea.Size = UDim2.new(1, -20, 1, -86)
contentArea.Position = UDim2.new(0, 10, 0, 78)
contentArea.BackgroundTransparency = 1
contentArea.Parent = janela

local abas = {}
local overlayAberto = nil

local function fecharOverlay()
    if overlayAberto then overlayAberto:Destroy(); overlayAberto = nil end
end

local function criarAba(nome, display)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 78, 0, 26)
    btn.BackgroundColor3 = P.elev
    btn.BackgroundTransparency = 1
    btn.Text = display
    btn.TextColor3 = P.textDim
    btn.TextSize = 10
    btn.Font = Enum.Font.GothamBold
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Parent = tabBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3
    scroll.ScrollBarImageColor3 = P.stroke
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Visible = false
    scroll.Parent = contentArea

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 5)
    layout.Parent = scroll
    Instance.new("UIPadding", scroll).PaddingBottom = UDim.new(0, 15)

    abas[nome] = { botao = btn, frame = scroll }

    local function ativar()
        fecharOverlay()
        for _, a in pairs(abas) do
            a.frame.Visible = false
            a.botao.BackgroundTransparency = 1
            a.botao.TextColor3 = P.textDim
        end
        scroll.Visible = true
        btn.BackgroundTransparency = 0
        btn.BackgroundColor3 = P.elev
        btn.TextColor3 = P.accent
    end

    btn.MouseButton1Click:Connect(ativar)
    abas[nome].ativar = ativar
    return scroll
end

local function criarSecao(parent, texto)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 20)
    lbl.BackgroundTransparency = 1
    lbl.Text = texto
    lbl.TextColor3 = P.accent2
    lbl.TextSize = 10
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = parent
end

local function criarToggle(parent, texto, default, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 34)
    frame.BackgroundColor3 = P.elev
    frame.BackgroundTransparency = 0.2
    frame.BorderSizePixel = 0
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -70, 1, 0)
    label.Position = UDim2.new(0, 14, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = texto
    label.TextColor3 = P.text
    label.TextSize = 11
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local sw = Instance.new("Frame")
    sw.Size = UDim2.new(0, 36, 0, 20)
    sw.Position = UDim2.new(1, -48, 0.5, -10)
    sw.BackgroundColor3 = default and P.accent or P.off
    sw.BorderSizePixel = 0
    sw.Parent = frame
    Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = default and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    knob.BackgroundColor3 = Color3.new(1, 1, 1)
    knob.BorderSizePixel = 0
    knob.Parent = sw
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local state = default
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.Parent = frame

    btn.MouseButton1Click:Connect(function()
        state = not state
        sw.BackgroundColor3 = state and P.accent or P.off
        knob.Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
        if callback then callback(state) end
    end)
end

local function criarSlider(parent, texto, min, max, default, step, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 48)
    frame.BackgroundColor3 = P.elev
    frame.BackgroundTransparency = 0.2
    frame.BorderSizePixel = 0
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -20, 0, 18)
    label.Position = UDim2.new(0, 14, 0, 4)
    label.BackgroundTransparency = 1
    label.Text = texto .. ": " .. default
    label.TextColor3 = P.text
    label.TextSize = 11
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local barBg = Instance.new("Frame")
    barBg.Size = UDim2.new(1, -28, 0, 6)
    barBg.Position = UDim2.new(0, 14, 1, -18)
    barBg.BackgroundColor3 = P.stroke
    barBg.BorderSizePixel = 0
    barBg.Parent = frame
    Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)

    local pct = (default - min) / (max - min)
    local barFill = Instance.new("Frame")
    barFill.Size = UDim2.new(pct, 0, 1, 0)
    barFill.BackgroundColor3 = P.accent
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
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if not dragging then return end
        if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
            local pos = i.Position
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

local function criarBotao(parent, texto, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 32)
    btn.BackgroundColor3 = P.elev
    btn.BackgroundTransparency = 0.2
    btn.Text = texto
    btn.TextColor3 = P.text
    btn.TextSize = 11
    btn.Font = Enum.Font.GothamMedium
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = true
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
    btn.MouseButton1Click:Connect(callback)
end

local function criarLabel(parent, texto, altura)
    altura = altura or 60
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, altura)
    lbl.BackgroundColor3 = P.elev
    lbl.BackgroundTransparency = 0.4
    lbl.Text = texto
    lbl.TextColor3 = P.text
    lbl.TextSize = 10
    lbl.Font = Enum.Font.Code
    lbl.TextWrapped = true
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextYAlignment = Enum.TextYAlignment.Top
    lbl.Parent = parent
    Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 8)
    local p = Instance.new("UIPadding", lbl)
    p.PaddingLeft = UDim.new(0, 12)
    p.PaddingTop = UDim.new(0, 8)
    p.PaddingRight = UDim.new(0, 12)
    return lbl
end

-- [DROPDOWN v2] overlay fora do scroll (não corta mais)
local function criarDropdown(parent, texto, opcoes, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 40)
    frame.BackgroundColor3 = P.elev
    frame.BackgroundTransparency = 0.2
    frame.BorderSizePixel = 0
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = texto .. ": " .. tostring(opcoes[1] or "?")
    btn.TextColor3 = P.text
    btn.TextSize = 11
    btn.Font = Enum.Font.GothamMedium
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.Parent = frame
    local bPad = Instance.new("UIPadding", btn)
    bPad.PaddingLeft = UDim.new(0, 12)

    btn.MouseButton1Click:Connect(function()
        if overlayAberto then fecharOverlay(); return end

        local ov = Instance.new("Frame")
        ov.Name = "__dbhDropOverlay"
        ov.BackgroundColor3 = P.panel
        ov.BorderSizePixel = 0
        ov.ZIndex = 500
        ov.Parent = janela

        local absBtn = btn.AbsolutePosition
        local absJan = janela.AbsolutePosition
        local tamBtn = btn.AbsoluteSize
        local alt = math.min(#opcoes * 28, 200)

        ov.Position = UDim2.new(0, absBtn.X - absJan.X, 0, absBtn.Y - absJan.Y + tamBtn.Y + 2)
        ov.Size = UDim2.new(0, tamBtn.X, 0, alt)
        Instance.new("UICorner", ov).CornerRadius = UDim.new(0, 8)
        local stk = Instance.new("UIStroke", ov)
        stk.Color = P.accent; stk.Thickness = 1

        local ls = Instance.new("ScrollingFrame", ov)
        ls.Size = UDim2.new(1, 0, 1, 0)
        ls.BackgroundTransparency = 1
        ls.BorderSizePixel = 0
        ls.ScrollBarThickness = 3
        ls.CanvasSize = UDim2.new(0, 0, 0, #opcoes * 28)
        Instance.new("UIListLayout", ls)

        for _, opt in ipairs(opcoes) do
            local ob = Instance.new("TextButton", ls)
            ob.Size = UDim2.new(1, 0, 0, 28)
            ob.BackgroundTransparency = 1
            ob.Text = tostring(opt)
            ob.TextColor3 = P.text
            ob.TextSize = 11
            ob.Font = Enum.Font.GothamMedium
            ob.TextXAlignment = Enum.TextXAlignment.Left
            ob.ZIndex = 501
            local op = Instance.new("UIPadding", ob)
            op.PaddingLeft = UDim.new(0, 12)
            ob.MouseButton1Click:Connect(function()
                btn.Text = texto .. ": " .. tostring(opt)
                fecharOverlay()
                if callback then callback(opt) end
            end)
        end
        overlayAberto = ov
    end)
end

-- [ABA FARM]
local farmTab = criarAba("farm", "⚔ Farm")
criarSecao(farmTab, "Farm")
criarToggle(farmTab, "Farm Ativo", false, function(v) Config.FarmAtivo = v end)
criarDropdown(farmTab, "Alvo", {"Todos", "Só Mobs", "Só Boss", "Só Event"}, function(v)
    local map = { ["Todos"] = "todos", ["Só Mobs"] = "mobs", ["Só Boss"] = "boss", ["Só Event"] = "event" }
    Config.AlvoModo = map[v] or "todos"
end)
criarToggle(farmTab, "Auto Transform", false, function(v) Config.AutoTransform = v end)
criarToggle(farmTab, "Auto Regen", false, function(v) Config.AutoRegen = v end)

criarSecao(farmTab, "Auto Skills (só com Farm Ativo)")
criarDropdown(farmTab, "Modo", {"off", "single", "combo"}, function(v) Config.SkillMode = v end)
criarDropdown(farmTab, "Skill Única", {
    "UniqueSets_2_1", "UniqueSets_2_2", "UniqueSets_2_3", "Weapons_3_2", "Weapons_3_3"
}, function(v) Config.SkillSingle = v end)
criarDropdown(farmTab, "Combo", {
    "dps", "default", "kame", "spirit", "arma", "burst"
}, function(v) Config.SkillCombo = v end)

criarSecao(farmTab, "Combate Avançado")
criarToggle(farmTab, "Auto Lock-On", true, function(v) Config.AutoLock = v end)
criarToggle(farmTab, "Noclip com farm", true, function(v) Config.Noclip = v end)
criarToggle(farmTab, "Hitbox Expandida", false, function(v) Config.HitboxExpandida = v end)
criarSlider(farmTab, "Multiplicador Hitbox", 1, 5, 2, 1, function(v) Config.HitboxMulti = v end)
criarSecao(farmTab, "Visual")
criarToggle(farmTab, "ESP Mobs", false, function(v) Config.ESPMobs = v end)
criarToggle(farmTab, "ESP Itens", false, function(v) Config.ESPItems = v end)
criarSecao(farmTab, "Movimento")
criarBotao(farmTab, "🌌 Voo Nativo (5s)", function()
    if SuperFlight then
        safe(function() SuperFlight:FireServer(true) end)
        task.wait(5)
        safe(function() SuperFlight:FireServer(false) end)
    end
end)

-- [ABA COLLECT]
local collectTab = criarAba("collect", "💎 Collect")
criarSecao(collectTab, "Auto Coletar")
criarToggle(collectTab, "Auto Coletar", false, function(v) Config.AutoCollect = v end)
criarSlider(collectTab, "Cooldown entre coletas (s)", 1, 15, 3, 1, function(v) Config.ColetaCooldown = v end)
criarSecao(collectTab, "Filtro de Raridade")
criarToggle(collectTab, "Comum (ExpMat)", false, function(v) Config.ColetarComum = v end)
criarToggle(collectTab, "Incomum", true, function(v) Config.ColetarIncomum = v end)
criarToggle(collectTab, "Raro (Orbs)", true, function(v) Config.ColetarRaro = v end)
criarToggle(collectTab, "Épico (Scrolls)", true, function(v) Config.ColetarEpico = v end)
criarToggle(collectTab, "Lendário (Wish)", true, function(v) Config.ColetarLendario = v end)

-- [ABA REBIRTH]
local rebirthTab = criarAba("rebirth", "🔄 Rebirth")
criarSecao(rebirthTab, "Auto Rebirth")
criarToggle(rebirthTab, "Auto Rebirth", false, function(v) Config.AutoRebirth = v end)
criarBotao(rebirthTab, "🔄 Forçar Rebirth Agora", function()
    if not PromptRemote or not RequestRebirth then
        warn("[DBH] Rebirth remotes não encontrados"); return
    end
    safe(function()
        PromptRemote:FireServer({
            UniqueTag = "HudRebirth",
            Title = "Rebirth",
            LeftButton = "Details",
            MiddleButton = "Confirm",
            Prompt = "HudRebirth",
            RightButton = "Cancel",
            Description = "Confirm Rebirth?",
        }, "Confirm")
    end)
    task.wait(0.5)
    safe(function() RequestRebirth:InvokeServer(true) end)
    print("[DBH] Rebirth forçado")
end)
local infoRebirth = criarLabel(rebirthTab, "Aguardando...", 60)

task.spawn(function()
    while Ativo do
        task.wait(2)
        local stats = plr:FindFirstChild("Stats")
        if stats then
            local reb = stats:FindFirstChild("Rebirth")
            if reb then
                infoRebirth.Text = "Rebirth atual: " .. reb.Value
                if Config.AutoRebirth then
                    safe(function()
                        if PromptRemote then
                            PromptRemote:FireServer({
                                UniqueTag = "HudRebirth",
                                Title = "Rebirth " .. reb.Value .. " -> " .. (reb.Value + 1),
                                LeftButton = "Details",
                                MiddleButton = "Confirm",
                                Prompt = "HudRebirth",
                                RightButton = "Cancel",
                                Description = "Confirm Rebirth?",
                            }, "Confirm")
                        end
                    end)
                    task.wait(0.5)
                    safe(function() if RequestRebirth then RequestRebirth:InvokeServer(true) end end)
                    task.wait(2)
                end
            else
                infoRebirth.Text = "Stats.Rebirth não encontrado"
            end
        else
            infoRebirth.Text = "Player.Stats não encontrado"
        end
    end
end)

-- [ABA TRACKER]
local trackerTab = criarAba("tracker", "⏱ Tracker")
criarSecao(trackerTab, "Detecção")
criarToggle(trackerTab, "Auto-detectar bosses", true, function(v) Config.TrackerAuto = v end)

criarSecao(trackerTab, "Timers Ativos")
local timerLabel = criarLabel(trackerTab, "Nenhum boss em respawn.", 100)

criarSecao(trackerTab, "Voar até Boss")
local bossInput = Instance.new("TextBox", trackerTab)
bossInput.Size = UDim2.new(1, 0, 0, 32)
bossInput.BackgroundColor3 = P.elev
bossInput.BackgroundTransparency = 0.2
bossInput.BorderSizePixel = 0
bossInput.Text = ""
bossInput.PlaceholderText = "Nome do boss..."
bossInput.TextColor3 = P.text
bossInput.Font = Enum.Font.GothamMedium
bossInput.TextSize = 11
bossInput.ClearTextOnFocus = false
Instance.new("UICorner", bossInput).CornerRadius = UDim.new(0, 8)
local biPad = Instance.new("UIPadding", bossInput)
biPad.PaddingLeft = UDim.new(0, 12)

criarBotao(trackerTab, "✈️ Ir para o boss", function()
    local nome = bossInput.Text:lower():gsub("%s+", "")
    if nome == "" then return end
    local wm = WS:FindFirstChild("World Mobs")
    if not wm then return end
    local achou = false
    for _, pasta in ipairs(wm:GetChildren()) do
        for _, mob in ipairs(pasta:GetChildren()) do
            if mob:IsA("Model") then
                local mobNome = mob.Name:gsub("%-?%d+$", ""):lower():gsub("%s+", "")
                if mobNome == nome then
                    local hrp = mob:FindFirstChild("HumanoidRootPart")
                    if hrp then voarPara(hrp.Position); achou = true; return end
                end
            end
        end
    end
    if not achou then warn("[DBH] Boss '"..nome.."' não encontrado") end
end)

task.spawn(function()
    while Ativo do
        task.wait(1)
        if Config.TrackerAuto then
            local wm = WS:FindFirstChild("World Mobs")
            if wm then
                local vivos = {}
                for _, pasta in ipairs(wm:GetChildren()) do
                    if pasta.Name == "Boss Mobs" or pasta.Name == "Event Mobs" then
                        for _, mob in ipairs(pasta:GetChildren()) do
                            if mob:IsA("Model") then
                                local base = mob.Name:gsub("%-?%d+$", "")
                                vivos[base] = true
                                _G.bossVistos = _G.bossVistos or {}
                                _G.bossVistos[base] = true
                            end
                        end
                    end
                end
                _G.bossEstado = _G.bossEstado or {}
                for nome in pairs(_G.bossVistos or {}) do
                    if not vivos[nome] and not _G.bossEstado[nome] then
                        local tempo = BossTimers[nome] or BossTimers._default
                        _G.bossEstado[nome] = {morreuEm = os.clock(), respawnEm = tempo}
                        _G.bossVistos[nome] = nil
                    end
                end
            end
        end
    end
end)

task.spawn(function()
    while Ativo do
        task.wait(1)
        local agora = os.clock()
        local linhas = {}
        local total = 0
        _G.bossEstado = _G.bossEstado or {}
        for nome, info in pairs(_G.bossEstado) do
            local passado = agora - info.morreuEm
            local restante = info.respawnEm - passado
            if restante > 0 then
                linhas[#linhas+1] = string.format("%-15s %d:%02d", nome, math.floor(restante/60), math.floor(restante%60))
                total = total + 1
            else
                _G.bossEstado[nome] = nil
            end
        end
        if total == 0 then timerLabel.Text = "Nenhum boss em respawn."
        else table.sort(linhas); timerLabel.Text = table.concat(linhas, "\n") end
    end
end)

-- [ABA CONFIG]
local configTab = criarAba("config", "⚙ Config")
criarSecao(configTab, "Movimento")
criarSlider(configTab, "WalkSpeed", 16, 200, 16, 1, function(v) Config.WalkSpeed = v end)
criarSlider(configTab, "FlySpeed", 50, 500, 250, 10, function(v) Config.FlySpeed = v end)
criarSlider(configTab, "Attack Range", 5, 20, 8, 1, function(v) Config.AttackRange = v end)
criarSecao(configTab, "Combate")
criarSlider(configTab, "Skill Delay (x0.1s)", 5, 50, 15, 5, function(v) Config.SkillDelay = v * 0.1 end)
criarSecao(configTab, "Sobrevivência")
criarSlider(configTab, "Ki pra Regen (%)", 10, 50, 30, 5, function(v) Config.KiMin = v / 100 end)
criarSlider(configTab, "Altura Segura", 40, 300, 100, 10, function(v) Config.SafeHeight = v end)
criarSecao(configTab, "Sistema")
criarBotao(configTab, "🔴 MATAR SCRIPT", function()
    Ativo = false
    for k, v in pairs(Config) do if type(v) == "boolean" then Config[k] = false end end
    gui:Destroy()
    espGui:Destroy()
end)

-- [ABA SOBRE]
local sobreTab = criarAba("sobre", "ℹ Sobre")
criarSecao(sobreTab, "Info")
criarLabel(sobreTab, "🐉 Dragon Blox Hub\n\nzyyx & elliot\nv5.1", 80)
local infoServidor = criarLabel(sobreTab, "Carregando...", 100)

task.spawn(function()
    while Ativo and gui.Parent do
        local jobId = game.JobId ~= "" and game.JobId:sub(1, 8) .. "..." or "Privado"
        local ping = math.floor(plr:GetNetworkPing() * 1000)
        infoServidor.Text =
            "Hora: " .. os.date("%H:%M:%S") ..
            "\nData: " .. os.date("%d/%m/%Y") ..
            "\nServidor: " .. jobId ..
            "\nJogadores: " .. #Players:GetPlayers() ..
            "\nPing: " .. ping .. " ms"
        task.wait(2)
    end
end)

abas.farm.ativar()

-- [INTERAÇÕES]
homeBar.MouseButton1Click:Connect(function()
    fecharOverlay()
    janela.Visible = not janela.Visible
end)

local dragging = false
local dragStart, startPos
titulo.MouseButton1Down:Connect(function()
    dragging = true
    dragStart = UserInputService:GetMouseLocation()
    startPos = janela.Position
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)
UserInputService.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local cur = UserInputService:GetMouseLocation()
        local delta = cur - dragStart
        janela.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

btnMin.MouseButton1Click:Connect(function()
    fecharOverlay()
    janela.Visible = false
end)

btnKill.MouseButton1Click:Connect(function()
    Ativo = false
    for k, v in pairs(Config) do if type(v) == "boolean" then Config[k] = false end end
    gui:Destroy()
    espGui:Destroy()
end)

-- [LOOP FARM]
task.spawn(function()
    while Ativo and task.wait(0.08) do
        if farmLigado() and not emRegen then
            local alvo = getAlvo()
            if alvo then
                if Config.AutoLock and alvoTravado ~= alvo.Name then
                    lockOn(alvo)
                    alvoTravado = alvo.Name
                end
                local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local mpos = alvo.HumanoidRootPart.Position
                    local dist = (mpos - hrp.Position).Magnitude
                    local zonaConforto = Config.AttackRange + 4
                    if dist > zonaConforto then voarPara(mpos, Config.FlySpeed)
                    elseif dist > 3 then voarPara(mpos, Config.FlySpeed * 0.3)
                    else
                        if vooBv then vooBv.Velocity = Vector3.zero end
                        atacar(alvo)
                    end
                end
            else
                alvoTravado = nil
                pararLock()
            end
        else
            alvoTravado = nil
        end
    end
end)

-- [NOCLIP]
task.spawn(function()
    while Ativo do
        task.wait(0.3)
        if farmLigado() and Config.Noclip then
            local char = plr.Character
            if char then
                for _, p in ipairs(char:GetDescendants()) do
                    if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
                end
            end
        end
    end
end)

-- [HITBOX]
task.spawn(function()
    while Ativo do
        task.wait(1)
        expandirHitbox()
    end
end)

-- [AUTOCOLLECT]
task.spawn(function()
    while Ativo do
        task.wait(1)
        if Config.AutoCollect and not farmLigado() then
            tentarColetar()
        end
    end
end)

-- [REGEN] independente do farm
task.spawn(function()
    while Ativo and task.wait(1) do
        if Config.AutoRegen then
            local curr, max = getKi()
            if curr and max then
                local ratio = curr / max
                if ratio < Config.KiMin and not emRegen then iniciarRegen()
                elseif ratio > 0.9 and emRegen then pararRegen() end
            end
        elseif emRegen then
            pararRegen()
        end
    end
end)

-- [SKILLS LOOP] só com farm ligado
task.spawn(function()
    while Ativo and task.wait(Config.SkillDelay) do
        if farmLigado() and Config.SkillMode ~= "off" and not emRegen then
            local alvo = getAlvo()
            if alvo and alvo.Parent then
                if Config.SkillMode == "single" then
                    local sk = SKILLS[Config.SkillSingle]
                    if sk then usarSkill(sk, alvo) end
                elseif Config.SkillMode == "combo" then
                    local lista = COMBOS[Config.SkillCombo]
                    if lista and #lista > 0 then
                        local nome = lista[comboIdx]
                        comboIdx = comboIdx + 1
                        if comboIdx > #lista then comboIdx = 1 end
                        local sk = SKILLS[nome]
                        if sk then usarSkill(sk, alvo) end
                    end
                end
            end
        end
    end
end)

-- [TRANSFORM]
task.spawn(function()
    while Ativo and task.wait(5) do
        if Config.AutoTransform and SelectMode then
            safe(function() SelectMode:FireServer(Config.TransformMode) end)
        end
    end
end)

task.spawn(function()
    while Ativo do
        plr.CharacterAdded:Wait()
        task.wait(3)
        if Config.AutoTransform and SelectMode then
            safe(function() SelectMode:FireServer(Config.TransformMode) end)
        end
    end
end)

-- [WALKSPEED]
task.spawn(function()
    while Ativo and task.wait(0.5) do
        if plr.Character and plr.Character:FindFirstChild("Humanoid") then
            plr.Character.Humanoid.WalkSpeed = Config.WalkSpeed
        end
    end
end)

-- [ESP MOBS]
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
            for m in pairs(espCache) do if not vivos[m] then removerESP(m) end end
        else
            for m in pairs(espCache) do removerESP(m) end
        end
    end
end)

-- [ESP ITENS]
task.spawn(function()
    while Ativo and task.wait(0.5) do
        if Config.ESPItems then atualizarDropESP()
        else for i, bb in pairs(dropESP) do bb:Destroy(); dropESP[i] = nil end end
    end
end)

print("[DBH] ✅ v5.1 Carregado")