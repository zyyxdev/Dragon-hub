
     DRAGON BLOX HUB
    
    Criadores: zyyx & elliot
    Versão: 5.0.0
    Data: 2026
    
    Recursos:
      • Auto Farm com navegação inteligente por áreas
      • Auto Boss, Auto Skills, Auto Transform
      • Auto Rebirth com acumulador
      • Auto Collect (esferas + itens)
      • Auto Quest
      • Auto Regen
      • Anti-detecção (Stealth, delays randomizados)
      • Interface customizada com glassmorphism
    
    Uso:
      1. Cole no Delta Executor
      2. Toque na barra branca no rodapé
      3. Configure as funções na aba Farm
      4. Ative o que quiser

print("[DBH] ═══════════════════════════════════════════════")
print("[DBH] Dragon Blox Hub v5 - Iniciando...")
print("[DBH] ═══════════════════════════════════════════════")

-- ═══════════════════════════════════════════════════════════════
-- SERVIÇOS
-- ═══════════════════════════════════════════════════════════════
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local RS = game:GetService("ReplicatedStorage")
local plr = Players.LocalPlayer

print("[DBH] 1/8 Serviços OK")

-- ═══════════════════════════════════════════════════════════════
-- ANTI-DETECÇÃO: wrapper seguro
-- ═══════════════════════════════════════════════════════════════
local function safe(fn)
    local ok, err = pcall(fn)
    if not ok then warn("[DBH-safe] " .. tostring(err)) end
    return ok
end

-- ═══════════════════════════════════════════════════════════════
-- REMOTES (mapeados via dumps)
-- ═══════════════════════════════════════════════════════════════
local SkillRemote = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("SkillRemote")

local KnitSVC
safe(function()
    local Knit = RS.Packages._Index["sleitnick_knit@1.4.7"].knit
    KnitSVC = Knit.Services
end)

local ExecuteSkill         = KnitSVC and KnitSVC.SkillManagerV2 and KnitSVC.SkillManagerV2.RE.ExecuteSkill
local ExecuteSkill_Special = KnitSVC and KnitSVC.SkillManagerV2 and KnitSVC.SkillManagerV2.RE.ExecuteSkill_Special
local ClaimItem            = KnitSVC and KnitSVC.ItemDropService and KnitSVC.ItemDropService.RF.ClaimItem
local RequestRebirth       = KnitSVC and KnitSVC.PlayerLevelService and KnitSVC.PlayerLevelService.RF.RequestRebirth
local DialogAnswer         = KnitSVC and KnitSVC.DialogService and KnitSVC.DialogService.RF.Answer
local OnEventEffect        = KnitSVC and KnitSVC.PeriodicEventService and KnitSVC.PeriodicEventService.RE.onEventEffect
local ItemSpawned          = KnitSVC and KnitSVC.ItemDropService and KnitSVC.ItemDropService.RE.ItemSpawned
local SuperFlight          = KnitSVC and KnitSVC.FlightService and KnitSVC.FlightService.RE.SuperFlight
local SelectMode           = KnitSVC and KnitSVC.ModeTransformService and KnitSVC.ModeTransformService.RE.SelectMode
local PromptRemote         = KnitSVC and KnitSVC.PromptService and KnitSVC.PromptService.RE.Prompt

print("[DBH] 2/8 Remotes: SR=" .. tostring(SkillRemote ~= nil) ..
      " ES=" .. tostring(ExecuteSkill ~= nil) ..
      " CI=" .. tostring(ClaimItem ~= nil) ..
      " RR=" .. tostring(RequestRebirth ~= nil))

-- ═══════════════════════════════════════════════════════════════
-- CONFIG
-- ═══════════════════════════════════════════════════════════════
local Ativo = true

local Config = {
    -- Farm
    AutoFarm = false,
    AutoBoss = false,
    GatherMode = false,
    BringMob = false,
    FastAttack = false,
    StickToMob = false,
    AutoSkills = false,
    AutoTransform = false,
    TransformMode = "SSJAngel",
    
    -- Navegação de áreas
    AutoTour = false,
    AreaSelecionada = nil,
    EsperaSpawn = 3,
    RaioArea = 3000,
    
    -- Rebirth
    AutoRebirth = false,
    RebirthMultiplier = 3,
    
    -- Coleta
    AutoCollect = false,
    AutoQuest = false,
    SelectedQuest = nil,
    
    -- Regen
    AutoRegen = false,
    KiMin = 0.3,
    SafeHeight = 100,
    
    -- Movimento
    WalkSpeed = 16,
    FlySpeed = 250,
    BringMobRange = 120,
    GatherRadius = 200,
    AttackRange = 8,
    AttackDelay = 0.15,
    SkillDelay = 1.5,
    
    -- Anti-detecção
    Stealth = false,
}

-- IDs de combo descobertos nos dumps
local COMBO_IDS = {102, 106, 111, 113, 116, 117}
local comboIdx = 1
local skillSeq = 1

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

print("[DBH] 3/8 Config OK")

-- ═══════════════════════════════════════════════════════════════
-- ANTI-DETECÇÃO: delays randomizados
-- ═══════════════════════════════════════════════════════════════
local emRegen = false
local ultimaAcao = 0

local function podeAgir()
    local agora = tick()
    if agora - ultimaAcao < 0.05 then return false end
    ultimaAcao = agora
    return true
end

-- ═══════════════════════════════════════════════════════════════
-- VOO SUAVE
-- ═══════════════════════════════════════════════════════════════
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

-- ═══════════════════════════════════════════════════════════════
-- STICK TO MOB
-- ═══════════════════════════════════════════════════════════════
local stickAtivo = false
local stickAlvo = nil

local function stickarNoMob(mob)
    if stickAtivo then return end
    stickAtivo = true
    stickAlvo = mob

    task.spawn(function()
        while stickAtivo and Ativo and stickAlvo and stickAlvo.Parent do
            local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
            local mhrp = stickAlvo and stickAlvo:FindFirstChild("HumanoidRootPart")
            if hrp and mhrp then
                hrp.CFrame = mhrp.CFrame * CFrame.new(0, 0, Config.AttackRange)
            else
                break
            end
            task.wait(0.1)
        end
        stickAtivo = false
        stickAlvo = nil
    end)
end

local function pararStick()
    stickAtivo = false
    stickAlvo = nil
end

-- ═══════════════════════════════════════════════════════════════
-- GATHER MODE
-- ═══════════════════════════════════════════════════════════════
local function gatherMobs()
    local myChar = plr.Character
    if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then return 0 end
    local myHrp = myChar.HumanoidRootPart
    local myPos = myHrp.Position

    local juntados = 0
    for _, mob in ipairs(mobs) do
        if mob and mob.Parent and mob:FindFirstChild("HumanoidRootPart") and mob.Humanoid.Health > 0 then
            local d = (mob.HumanoidRootPart.Position - myPos).Magnitude
            if d <= Config.GatherRadius then
                local angulo = math.random() * math.pi * 2
                local offset = Vector3.new(math.cos(angulo) * 6, 0, math.sin(angulo) * 6)
                mob.HumanoidRootPart.CFrame = CFrame.new(myPos + offset) * mob.HumanoidRootPart.CFrame.Rotation
                juntados = juntados + 1
            end
        end
    end
    return juntados
end

-- ═══════════════════════════════════════════════════════════════
-- ATAQUE
-- ═══════════════════════════════════════════════════════════════
local function atacar(alvo)
    if not SkillRemote or not plr.Character or not podeAgir() then return end
    if not alvo or not alvo:FindFirstChild("HumanoidRootPart") then return end
    local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local mhrp = alvo.HumanoidRootPart
    hrp.CFrame = mhrp.CFrame * CFrame.new(0, 0, Config.AttackRange)

    local cframe = hrp.CFrame
    local aim = mhrp.Position
    local skillId = COMBO_IDS[comboIdx]
    comboIdx = comboIdx + 1
    if comboIdx > #COMBO_IDS then comboIdx = 1 end

    safe(function()
        SkillRemote:FireServer({Began=true, CFrame=cframe, Aim=aim,
            Camera=workspace.CurrentCamera.CFrame, Type=1, SkillId=skillId})
    end)
    task.wait(0.05)
    safe(function()
        SkillRemote:FireServer({Began=false, CFrame=cframe, Aim=aim,
            Camera=workspace.CurrentCamera.CFrame, Type=1, SkillId=skillId})
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

    safe(function() ExecuteSkill:FireServer(skill.nome, cfg, skillSeq, true) end)
    task.wait(skill.pause or 0.5)
    safe(function() ExecuteSkill:FireServer(skill.nome, cfg, skillSeq, false) end)
    skillSeq = skillSeq + 1
end

-- ═══════════════════════════════════════════════════════════════
-- KI / REGEN
-- ═══════════════════════════════════════════════════════════════
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
    pararStick()

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

-- ═══════════════════════════════════════════════════════════════
-- MOBS TRACKING
-- ═══════════════════════════════════════════════════════════════
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

print("[DBH] 4/8 Core OK")

-- ═══════════════════════════════════════════════════════════════
-- NAVEGAÇÃO POR ÁREAS DE SPAWN
-- ═══════════════════════════════════════════════════════════════
local areas = {}
local areaAtual = nil
local areaIdx = 0

local function descobrirAreas()
    areas = {}
    local worldMobs = workspace:FindFirstChild("World Mobs")
    if not worldMobs then return end

    local myChar = plr.Character
    if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then return end
    local myPos = myChar.HumanoidRootPart.Position

    for _, categoria in pairs(worldMobs:GetChildren()) do
        if categoria:IsA("Folder") or categoria:IsA("Model") then
            for _, subArea in pairs(categoria:GetChildren()) do
                if subArea:IsA("Folder") or subArea:IsA("Model") then
                    local ancora = subArea:FindFirstChildWhichIsA("BasePart", true)
                    
                    -- Se não tem BasePart direto, tenta pegar do HumanoidRootPart de algum mob
                    if not ancora then
                        for _, desc in pairs(subArea:GetDescendants()) do
                            if desc:IsA("Model") and desc:FindFirstChild("HumanoidRootPart") then
                                ancora = desc.HumanoidRootPart
                                break
                            end
                        end
                    end

                    if ancora then
                        local d = (ancora.Position - myPos).Magnitude
                        if d < Config.RaioArea then
                            table.insert(areas, {
                                nome = subArea.Name,
                                categoria = categoria.Name,
                                pos = ancora.Position,
                                distancia = d,
                            })
                        end
                    end
                end
            end
        end
    end

    table.sort(areas, function(a, b) return a.distancia < b.distancia end)
    print("[DBH] Áreas descobertas: " .. #areas)
    for _, a in ipairs(areas) do
        print("  " .. a.categoria .. " ▸ " .. a.nome .. " (" .. math.floor(a.distancia) .. " studs)")
    end
    return areas
end

local function irParaArea(area)
    if not area then return false end
    areaAtual = area
    print("[DBH] Navegando para: " .. area.nome)
    voarPara(area.pos, Config.FlySpeed * 0.8)
    return true
end

local function mobsNaArea(area, raio)
    raio = raio or 150
    if not area then return 0 end
    local count = 0
    for _, mob in ipairs(mobs) do
        if mob and mob.Parent and mob:FindFirstChild("HumanoidRootPart") and mob.Humanoid.Health > 0 then
            local d = (mob.HumanoidRootPart.Position - area.pos).Magnitude
            if d <= raio then count = count + 1 end
        end
    end
    return count
end

-- Tour automático
task.spawn(function()
    while Ativo do
        task.wait(2)
        if (Config.AutoFarm or Config.AutoBoss) and not emRegen then
            if #areas == 0 then
                descobrirAreas()
            end
            if #areas > 0 then
                if Config.AreaSelecionada then
                    if areaAtual ~= Config.AreaSelecionada then
                        irParaArea(Config.AreaSelecionada)
                    end
                elseif Config.AutoTour then
                    local n = mobsNaArea(areaAtual, 200)
                    if n == 0 then
                        areaIdx = areaIdx + 1
                        if areaIdx > #areas then
                            areaIdx = 1
                            descobrirAreas()
                        end
                        local proxima = areas[areaIdx]
                        if proxima then
                            irParaArea(proxima)
                            task.wait(Config.EsperaSpawn)
                        end
                    end
                end
            end
        end
    end
end)

-- Atualiza label de área
task.spawn(function()
    while Ativo do
        task.wait(2)
        if areaAtual and _G.DBH_UpdateAreaLabel then
            _G.DBH_UpdateAreaLabel(areaAtual.nome, mobsNaArea(areaAtual, 200), #areas)
        end
    end
end)

print("[DBH] 5/8 Navegação de áreas OK")

-- ═══════════════════════════════════════════════════════════════
-- QUESTS
-- ═══════════════════════════════════════════════════════════════
local questsList = {}
local function atualizarQuests()
    questsList = {}
    local npcFolder = workspace:FindFirstChild("NPC")
    local questsFolder = npcFolder and npcFolder:FindFirstChild("Quests")
    if not questsFolder then return end
    for _, npc in pairs(questsFolder:GetChildren()) do
        local num = tonumber(npc.Name:match("QuestNPCMain(%d+)_")) or 0
        local nome = npc.Name:match("QuestNPCMain%d+_(.+)") or npc.Name
        local hrp = npc:FindFirstChild("HumanoidRootPart")
        table.insert(questsList, {
            nome = npc.Name, numero = num,
            display = num .. ". " .. nome,
            group = "NPCQuest_" .. nome,
            pos = hrp and hrp.Position or nil,
        })
    end
    table.sort(questsList, function(a, b) return a.numero < b.numero end)
end
atualizarQuests()

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

-- ═══════════════════════════════════════════════════════════════
-- UI
-- ═══════════════════════════════════════════════════════════════
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
    Vermelho = Color3.fromRGB(220, 60, 60),
    Verde = Color3.fromRGB(80, 200, 120),
}

-- ─── Home Bar ───
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
local hbCorner = Instance.new("UICorner") hbCorner.CornerRadius = UDim.new(1, 0) hbCorner.Parent = homeBar
local hbInner = Instance.new("Frame")
hbInner.Size = UDim2.new(0.7, 0, 0, 6)
hbInner.Position = UDim2.new(0.5, 0, 0.5, 0)
hbInner.AnchorPoint = Vector2.new(0.5, 0.5)
hbInner.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
hbInner.BackgroundTransparency = 0.2
hbInner.BorderSizePixel = 0
hbInner.ZIndex = 51
hbInner.Parent = homeBar
local hbInnerCorner = Instance.new("UICorner") hbInnerCorner.CornerRadius = UDim.new(1, 0) hbInnerCorner.Parent = hbInner

-- ─── Janela ───
local janela = Instance.new("Frame")
janela.Size = UDim2.new(0, 560, 0, 440)
janela.Position = UDim2.new(0.5, -280, 0.5, -220)
janela.BackgroundColor3 = COR.Fundo
janela.BackgroundTransparency = 0.15
janela.BorderSizePixel = 0
janela.Active = true
janela.Visible = false
janela.Parent = gui
local jCorner = Instance.new("UICorner") jCorner.CornerRadius = UDim.new(0, 14) jCorner.Parent = janela
local jStroke = Instance.new("UIStroke") jStroke.Color = COR.AbaAtiva jStroke.Thickness = 1.5 jStroke.Transparency = 0.3 jStroke.Parent = janela

-- Título (draggable)
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
local tCorner = Instance.new("UICorner") tCorner.CornerRadius = UDim.new(0, 14) tCorner.Parent = titulo
local tPad = Instance.new("UIPadding") tPad.PaddingLeft = UDim.new(0, 18) tPad.Parent = titulo

-- Sidebar
local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 120, 1, -42)
sidebar.Position = UDim2.new(0, 0, 0, 42)
sidebar.BackgroundColor3 = COR.Painel
sidebar.BackgroundTransparency = 0.3
sidebar.BorderSizePixel = 0
sidebar.Parent = janela
local sbLayout = Instance.new("UIListLayout") sbLayout.SortOrder = Enum.SortOrder.LayoutOrder sbLayout.Padding = UDim.new(0, 5) sbLayout.Parent = sidebar
local sbPad = Instance.new("UIPadding") sbPad.PaddingTop = UDim.new(0, 10) sbPad.PaddingLeft = UDim.new(0, 7) sbPad.PaddingRight = UDim.new(0, 7) sbPad.Parent = sidebar

-- Conteúdo
local contentArea = Instance.new("Frame")
contentArea.Size = UDim2.new(1, -120, 1, -42)
contentArea.Position = UDim2.new(0, 120, 0, 42)
contentArea.BackgroundColor3 = COR.Fundo
contentArea.BackgroundTransparency = 0.3
contentArea.BorderSizePixel = 0
contentArea.Parent = janela

-- Resize handle
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
local rhCorner = Instance.new("UICorner") rhCorner.CornerRadius = UDim.new(0, 4) rhCorner.Parent = resizeHandle

-- ═══════════════════════════════════════════════════════════════
-- COMPONENTES UI
-- ═══════════════════════════════════════════════════════════════
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
    local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 6) c.Parent = btn

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
    local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 6) c.Parent = frame

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
    local c2 = Instance.new("UICorner") c2.CornerRadius = UDim.new(0, 13) c2.Parent = btn

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
    local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 6) c.Parent = btn
    btn.MouseButton1Click:Connect(callback)
end

local function criarSlider(parent, texto, min, max, default, step, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -8, 0, 56)
    frame.BackgroundColor3 = COR.Botao
    frame.BackgroundTransparency = 0.35
    frame.BorderSizePixel = 0
    frame.Parent = parent
    local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 6) c.Parent = frame

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
    local c3 = Instance.new("UICorner") c3.CornerRadius = UDim.new(1, 0) c3.Parent = barBg

    local barFill = Instance.new("Frame")
    local pct = (default - min) / (max - min)
    barFill.Size = UDim2.new(pct, 0, 1, 0)
    barFill.BackgroundColor3 = COR.AbaAtiva
    barFill.BorderSizePixel = 0
    barFill.Parent = barBg
    local c4 = Instance.new("UICorner") c4.CornerRadius = UDim.new(1, 0) c4.Parent = barFill

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
    local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 6) c.Parent = lbl
    local p = Instance.new("UIPadding") p.PaddingLeft = UDim.new(0, 10) p.PaddingTop = UDim.new(0, 8) p.PaddingRight = UDim.new(0, 10) p.Parent = lbl
    return lbl
end

local function criarDropdown(parent, texto, opcoes, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -8, 0, 40)
    frame.BackgroundColor3 = COR.Botao
    frame.BackgroundTransparency = 0.35
    frame.BorderSizePixel = 0
    frame.ClipsDescendants = false
    frame.ZIndex = 2
    frame.Parent = parent
    local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 6) c.Parent = frame

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = texto .. ": " .. (opcoes[1] or "?")
    btn.TextColor3 = COR.Texto
    btn.TextSize = 12
    btn.Font = Enum.Font.Gotham
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.Parent = frame
    local bPad = Instance.new("UIPadding") bPad.PaddingLeft = UDim.new(0, 12) bPad.Parent = btn

    local lista = Instance.new("Frame")
    lista.Size = UDim2.new(1, 0, 0, math.min(#opcoes * 28, 200))
    lista.Position = UDim2.new(0, 0, 1, 4)
    lista.BackgroundColor3 = COR.Painel
    lista.BorderSizePixel = 0
    lista.Visible = false
    lista.ZIndex = 50
    lista.Parent = frame
    local lc = Instance.new("UICorner") lc.CornerRadius = UDim.new(0, 6) lc.Parent = lista

    local lscroll = Instance.new("ScrollingFrame")
    lscroll.Size = UDim2.new(1, 0, 1, 0)
    lscroll.BackgroundTransparency = 1
    lscroll.BorderSizePixel = 0
    lscroll.ScrollBarThickness = 3
    lscroll.CanvasSize = UDim2.new(0, 0, 0, #opcoes * 28)
    lscroll.Parent = lista
    local ll = Instance.new("UIListLayout") ll.Parent = lscroll

    for _, opt in ipairs(opcoes) do
        local ob = Instance.new("TextButton")
        ob.Size = UDim2.new(1, 0, 0, 28)
        ob.BackgroundTransparency = 1
        ob.Text = tostring(opt)
        ob.TextColor3 = COR.Texto
        ob.TextSize = 12
        ob.Font = Enum.Font.Gotham
        ob.TextXAlignment = Enum.TextXAlignment.Left
        ob.Parent = lscroll
        local opad = Instance.new("UIPadding") opad.PaddingLeft = UDim.new(0, 12) opad.Parent = ob
        ob.MouseButton1Click:Connect(function()
            btn.Text = texto .. ": " .. tostring(opt)
            lista.Visible = false
            if callback then callback(opt) end
        end)
    end

    btn.MouseButton1Click:Connect(function()
        lista.Visible = not lista.Visible
    end)
    
    return btn
end

print("[DBH] 6/8 Componentes UI OK")

-- ═══════════════════════════════════════════════════════════════
-- ABA FARM
-- ═══════════════════════════════════════════════════════════════
local farmTab = criarAba("farm", "⚔️ Farm")

criarSecao(farmTab, "Farm Principal")
criarToggle(farmTab, "Auto Farm", false, function(v) Config.AutoFarm = v end)
criarToggle(farmTab, "Auto Boss", false, function(v) Config.AutoBoss = v end)
criarToggle(farmTab, "Gather Mode (junta mobs)", false, function(v) Config.GatherMode = v end)
criarToggle(farmTab, "Stick to Mob (cola no alvo)", false, function(v) Config.StickToMob = v end)

criarSecao(farmTab, "Combate")
criarToggle(farmTab, "Bring Mob", false, function(v) Config.BringMob = v end)
criarToggle(farmTab, "Fast Attack", false, function(v) Config.FastAttack = v end)
criarToggle(farmTab, "Auto Skills", false, function(v) Config.AutoSkills = v end)
criarToggle(farmTab, "Auto Transform", false, function(v) Config.AutoTransform = v end)

criarSecao(farmTab, "Navegação de Áreas")
criarToggle(farmTab, "Auto Tour (percorre áreas)", false, function(v) 
    Config.AutoTour = v
    if v then
        descobrirAreas()
        areaIdx = 0
    end
end)

criarBotao(farmTab, "🔄 Re-escaneiar Áreas", function()
    descobrirAreas()
end)

local areasBtn = criarDropdown(farmTab, "Ir para Área", {"(Nenhuma)"}, function(opt)
    if opt == "(Nenhuma)" then
        Config.AreaSelecionada = nil
        return
    end
    for _, a in ipairs(areas) do
        if (a.categoria .. " ▸ " .. a.nome) == opt then
            Config.AreaSelecionada = a
            irParaArea(a)
            break
        end
    end
end)

-- Atualiza lista de áreas periodicamente
task.spawn(function()
    while Ativo do
        task.wait(15)
        if #areas == 0 then
            descobrirAreas()
        end
    end
end)

local infoArea = criarLabel(farmTab, "Área atual: nenhuma\nMobs: 0 | Total áreas: 0", 60)

_G.DBH_UpdateAreaLabel = function(nome, mobsCount, totalAreas)
    infoArea.Text = "Área atual: " .. nome .. 
                   "\nMobs na área: " .. mobsCount .. 
                   " | Total: " .. totalAreas
end

criarSecao(farmTab, "Sobrevivência")
criarToggle(farmTab, "Auto Regen (sobe + recupera)", false, function(v) Config.AutoRegen = v end)

criarSecao(farmTab, "Voo")
criarBotao(farmTab, "🌌 Voo Nativo (5s)", function()
    if SuperFlight then
        safe(function() SuperFlight:FireServer(true) end)
        task.wait(5)
        safe(function() SuperFlight:FireServer(false) end)
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- ABA REBIRTH
-- ═══════════════════════════════════════════════════════════════
local rebirthTab = criarAba("rebirth", "🔄 Rebirth")
criarSecao(rebirthTab, "Auto Rebirth")

criarToggle(rebirthTab, "Auto Rebirth (acumula antes)", false, function(v)
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

-- ═══════════════════════════════════════════════════════════════
-- ABA QUESTS
-- ═══════════════════════════════════════════════════════════════
local questTab = criarAba("quest", "📜 Quests")
criarSecao(questTab, "Seletor")

local opcoesQuests = {}
for _, q in ipairs(questsList) do table.insert(opcoesQuests, q.display) end
if #opcoesQuests == 0 then opcoesQuests = {"(nenhuma)"} end

criarDropdown(questTab, "Quest", opcoesQuests, function(opt)
    for _, q in ipairs(questsList) do
        if q.display == opt then Config.SelectedQuest = q break end
    end
end)

criarBotao(questTab, "✈️ Voar até o NPC", function()
    if Config.SelectedQuest and Config.SelectedQuest.pos then
        voarPara(Config.SelectedQuest.pos)
    end
end)

criarBotao(questTab, "✅ Aceitar Quest", function()
    if not Config.SelectedQuest or not DialogAnswer then return end
    local q = Config.SelectedQuest
    if q.pos then voarPara(q.pos) task.wait(2) end
    safe(function() DialogAnswer:InvokeServer(q.group, 1, q.nome) end)
    task.wait(0.5)
    safe(function() DialogAnswer:InvokeServer(q.group, 2, q.nome) end)
end)

criarToggle(questTab, "Auto Aceitar Quest", false, function(v) Config.AutoQuest = v end)

-- ═══════════════════════════════════════════════════════════════
-- ABA COLETA
-- ═══════════════════════════════════════════════════════════════
local collectTab = criarAba("collect", "💎 Coleta")
criarSecao(collectTab, "Coleta Automática")
criarToggle(collectTab, "Auto Coletar (esferas + itens)", false, function(v) Config.AutoCollect = v end)

criarSecao(collectTab, "Info")
local infoCollect = criarLabel(collectTab, "Aguardando eventos...", 60)

criarBotao(collectTab, "📊 Ver Stats", function()
    local stats = plr:FindFirstChild("Stats")
    if not stats then return end
    local function g(n) 
        local v = stats:FindFirstChild(n)
        return v and tostring(v.Value) or "?" 
    end
    infoCollect.Text = "Level: " .. g("Level") .. " | Rebirth: " .. g("Rebirth") ..
        "\nStrength: " .. g("Strength") .. " | Ki: " .. g("Ki")
end)

criarBotao(collectTab, "🗺️ Contar Mobs", function()
    local c = 0
    for _, m in ipairs(mobs) do
        if m and m.Parent and m:FindFirstChild("Humanoid") and m.Humanoid.Health > 0 then c = c + 1 end
    end
    infoCollect.Text = "Mobs ativos: " .. c
end)

-- ═══════════════════════════════════════════════════════════════
-- ABA CONFIG
-- ═══════════════════════════════════════════════════════════════
local configTab = criarAba("config", "⚙️ Config")

criarSecao(configTab, "Movimento")
criarSlider(configTab, "WalkSpeed", 16, 200, 16, 1, function(v) Config.WalkSpeed = v end)
criarSlider(configTab, "FlySpeed", 50, 500, 250, 10, function(v) Config.FlySpeed = v end)
criarSlider(configTab, "Bring Mob Range", 30, 300, 120, 10, function(v) Config.BringMobRange = v end)
criarSlider(configTab, "Gather Radius", 50, 500, 200, 25, function(v) Config.GatherRadius = v end)
criarSlider(configTab, "Attack Range", 5, 20, 8, 1, function(v) Config.AttackRange = v end)

criarSecao(configTab, "Combate")
criarSlider(configTab, "Attack Delay x0.05s", 1, 20, 3, 1, function(v) Config.AttackDelay = v * 0.05 end)
criarSlider(configTab, "Skill Delay x0.1s", 5, 50, 15, 5, function(v) Config.SkillDelay = v * 0.1 end)

criarSecao(configTab, "Navegação")
criarSlider(configTab, "Espera Spawn (s)", 1, 10, 3, 1, function(v) Config.EsperaSpawn = v end)
criarSlider(configTab, "Raio de Área", 500, 5000, 3000, 250, function(v) Config.RaioArea = v end)

criarSecao(configTab, "Sobrevivência")
criarSlider(configTab, "Ki pra Regen (%)", 10, 50, 30, 5, function(v) Config.KiMin = v / 100 end)
criarSlider(configTab, "Altura Segura (studs)", 40, 300, 100, 10, function(v) Config.SafeHeight = v end)

criarSecao(configTab, "Anti-Detecção")
criarToggle(configTab, "Modo Stealth", false, function(v) Config.Stealth = v end)

criarSecao(configTab, "Perigo")
criarBotao(configTab, "🔴 MATAR SCRIPT", function()
    Ativo = false
    for k, v in pairs(Config) do
        if type(v) == "boolean" then Config[k] = false end
    end
    gui:Destroy()
    print("[DBH] Script encerrado pelo usuário")
end)

-- ═══════════════════════════════════════════════════════════════
-- ABA CRÉDITOS
-- ═══════════════════════════════════════════════════════════════
local creditsTab = criarAba("credits", "ℹ️ Sobre")

criarSecao(creditsTab, "Criadores")
criarLabel(creditsTab,
    "🐉 DRAGON BLOX HUB\n\n" ..
    "Criadores:\n" ..
    "  • zyyx\n" ..
    "  • elliot\n\n" ..
    "Versão 5.0 Final - 2026",
    100)

criarSecao(creditsTab, "Informações do Servidor")
local infoServidor = criarLabel(creditsTab, "Carregando...", 120)

task.spawn(function()
    while Ativo and gui.Parent do
        local hora = os.date("%H:%M:%S")
        local data = os.date("%d/%m/%Y")
        local jobId = game.JobId ~= "" and game.JobId:sub(1, 8) .. "..." or "Servidor Privado"
        local numPlayers = #Players:GetPlayers()
        local ping = math.floor(plr:GetNetworkPing() * 1000)
        
        infoServidor.Text =
            "Hora: " .. hora ..
            "\nData: " .. data ..
            "\nServidor: " .. jobId ..
            "\nJogadores: " .. numPlayers ..
            "\nPing: " .. ping .. " ms" ..
            "\nFPS: " .. math.floor(workspace:GetRealPhysicsFPS())
        
        task.wait(2)
    end
end)

criarSecao(creditsTab, "Explicação das Funções")

local function addInfo(titulo, descricao)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -8, 0, 70)
    lbl.BackgroundColor3 = COR.Botao
    lbl.BackgroundTransparency = 0.5
    lbl.Text = "▸ " .. titulo .. "\n\n" .. descricao
    lbl.TextColor3 = COR.Texto
    lbl.TextSize = 11
    lbl.Font = Enum.Font.Gotham
    lbl.TextWrapped = true
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextYAlignment = Enum.TextYAlignment.Top
    lbl.Parent = creditsTab
    local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 6) c.Parent = lbl
    local p = Instance.new("UIPadding") p.PaddingLeft = UDim.new(0, 10) p.PaddingTop = UDim.new(0, 8) p.PaddingRight = UDim.new(0, 10) p.Parent = lbl
end

addInfo("Auto Farm", "Ataca automaticamente os mobs comuns. Ignora bosses se Auto Boss estiver ligado.")
addInfo("Auto Boss", "Ataca automaticamente apenas os bosses (detectados por nome).")
addInfo("Gather Mode", "Junta todos os mobs num raio ao redor de você antes de atacar.")
addInfo("Stick to Mob", "Se cola no mob alvo e ajusta a posição continuamente enquanto ataca.")
addInfo("Bring Mob", "Puxa os mobs no raio configurado para a sua frente.")
addInfo("Fast Attack", "Ataca várias vezes por segundo com IDs de combo reais.")
addInfo("Auto Skills", "Usa skills equipadas (Kamehameha, Spirit Bomb) automaticamente.")
addInfo("Auto Transform", "Ativa a transformação SSJAngel automaticamente.")
addInfo("Auto Tour", "Percorre automaticamente as áreas de spawn da ilha atual.")
addInfo("Auto Regen", "Sobe para altura segura quando o Ki cai e volta quando recuperar.")
addInfo("Auto Rebirth", "Rebirtha quando acumular X vezes o requisito configurado.")
addInfo("Auto Coletar", "Pega esferas e itens que caem no mapa automaticamente.")
addInfo("Auto Quest", "Aceita automaticamente a quest selecionada no dropdown.")
addInfo("Stealth", "Modo discreto: aumenta delays para dificultar detecção.")

print("[DBH] 7/8 Abas OK")

-- Ativa primeira aba
abas.farm.ativar()

-- ═══════════════════════════════════════════════════════════════
-- HOME BAR / DRAG / RESIZE
-- ═══════════════════════════════════════════════════════════════
homeBar.MouseButton1Click:Connect(function()
    janela.Visible = not janela.Visible
end)

-- Drag da janela
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

-- Resize
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

-- ═══════════════════════════════════════════════════════════════
-- LOOPS
-- ═══════════════════════════════════════════════════════════════

-- Auto Farm + Gather + Stick
task.spawn(function()
    while Ativo and task.wait(0.3) do
        if (Config.AutoFarm or Config.AutoBoss) and not emRegen and not Config.FastAttack then
            local alvo = getAlvo()
            if alvo then
                if Config.GatherMode then
                    gatherMobs()
                    task.wait(0.1)
                end
                if Config.StickToMob and not stickAtivo then
                    stickarNoMob(alvo)
                end
                atacar(alvo)
                if Config.StickToMob and stickAlvo and (not stickAlvo.Parent or stickAlvo.Humanoid.Health <= 0) then
                    pararStick()
                end
            else
                pararStick()
            end
        else
            pararStick()
        end
    end
end)

-- Fast Attack
task.spawn(function()
    while Ativo and task.wait(Config.AttackDelay) do
        if Config.FastAttack and not emRegen then
            local alvo = getAlvo()
            if alvo then
                if Config.GatherMode then gatherMobs() end
                if Config.StickToMob and not stickAtivo then stickarNoMob(alvo) end
                atacar(alvo)
            else
                pararStick()
            end
        end
    end
end)

-- Bring Mob
task.spawn(function()
    while Ativo and task.wait(0.3) do
        if Config.BringMob and not emRegen and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
            local myHrp = plr.Character.HumanoidRootPart
            for _, mob in ipairs(mobs) do
                if mob and mob.Parent and mob:FindFirstChild("HumanoidRootPart") and mob.Humanoid.Health > 0 then
                    local puxar = true
                    if Config.AutoFarm and not Config.AutoBoss then puxar = not isBoss(mob) end
                    if puxar then
                        local d = (mob.HumanoidRootPart.Position - myHrp.Position).Magnitude
                        if d <= Config.BringMobRange and d > 5 then
                            mob.HumanoidRootPart.CFrame = myHrp.CFrame * CFrame.new(0, 0, -6)
                        end
                    end
                end
            end
        end
    end
end)

-- Auto Regen
task.spawn(function()
    while Ativo and task.wait(1) do
        if Config.AutoRegen and (Config.AutoFarm or Config.AutoBoss or Config.FastAttack) then
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

-- Auto Skills
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

-- Auto Transform
task.spawn(function()
    while Ativo and task.wait(5) do
        if Config.AutoTransform and SelectMode then
            safe(function() SelectMode:FireServer(Config.TransformMode) end)
        end
    end
end)

-- Auto Quest
task.spawn(function()
    while Ativo and task.wait(3) do
        if Config.AutoQuest and Config.SelectedQuest and DialogAnswer then
            local q = Config.SelectedQuest
            local myChar = plr.Character
            if myChar and myChar:FindFirstChild("HumanoidRootPart") and q.pos then
                local d = (q.pos - myChar.HumanoidRootPart.Position).Magnitude
                if d > 30 then
                    voarPara(q.pos)
                else
                    safe(function() DialogAnswer:InvokeServer(q.group, 1, q.nome) end)
                    task.wait(0.5)
                    safe(function() DialogAnswer:InvokeServer(q.group, 2, q.nome) end)
                    task.wait(5)
                end
            end
        end
    end
end)

-- WalkSpeed
task.spawn(function()
    while Ativo and task.wait(0.5) do
        if plr.Character and plr.Character:FindFirstChild("Humanoid") then
            plr.Character.Humanoid.WalkSpeed = Config.WalkSpeed
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- AUTO COLLECT (conecta após UI pronta)
-- ═══════════════════════════════════════════════════════════════
task.spawn(function()
    task.wait(2)

    if OnEventEffect then
        OnEventEffect.OnClientEvent:Connect(function(evento, pos)
            if not Config.AutoCollect then return end
            if evento == "ShootingStar" and typeof(pos) == "Vector3" then
                print("[DBH] 🌠 ShootingStar detectada! Voando...")
                voarPara(pos)
            end
        end)
        print("[DBH] Hook OnEventEffect OK")
    end

    if ItemSpawned then
        ItemSpawned.OnClientEvent:Connect(function(data)
            if not Config.AutoCollect then return end
            if data and data.Pos then
                task.wait(0.8)
                voarPara(data.Pos)
                task.wait(1.5)
                if ClaimItem then
                    safe(function() ClaimItem:InvokeServer(data.Name, data.ItemName) end)
                    print("[DBH] 💎 Coletado: " .. tostring(data.ItemName))
                end
            end
        end)
        print("[DBH] Hook ItemSpawned OK")
    end
end)

print("[DBH] 8/8 Loops OK")
print("[DBH] ═══════════════════════════════════════════════")
print("[DBH] ✅ SCRIPT CARREGADO COM SUCESSO!")
print("[DBH] Toque na Home Bar no rodapé para abrir o menu.")
print("[DBH] ═══════════════════════════════════════════════")