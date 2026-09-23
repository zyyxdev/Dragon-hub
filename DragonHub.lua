-- ════════════════════════════════════════════════════════════════
--                DRAGON BLOX HUB - v6.0 (CONSOLIDATED)
-- ════════════════════════════════════════════════════════════════

local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VIM = game:GetService("VirtualInputManager")
local plr = Players.LocalPlayer

local mainFrame = nil
local gui = nil

-- ═══════════════════════════════════════════════
-- REMOTES CONFIRMADOS
-- ═══════════════════════════════════════════════
local KnitPath = RS.Packages._Index["sleitnick_knit@1.4.7"].knit.Services

local SkillMgrV2      = KnitPath.SkillManagerV2.RE
local SkillMgr        = KnitPath.SkillManager.RE
local PromptSVC       = KnitPath.PromptService.RE
local PlayerLevelSVC  = KnitPath.PlayerLevelService.RF
local ToolSVC         = KnitPath.ToolService.RE
local FlightSVC       = KnitPath.FlightService.RE
local ModeTransform   = KnitPath.ModeTransformService.RE
local SkillRemote     = RS.Remotes.SkillRemote

local RE_ExecuteSkill        = SkillMgrV2.ExecuteSkill
local RE_ExecuteSkillSpecial = SkillMgrV2.ExecuteSkill_Special
local RE_LockedOnChanged     = SkillMgr.LockedOnChanged
local RE_Prompt              = PromptSVC.Prompt
local RF_RequestRebirth      = PlayerLevelSVC.RequestRebirth
local RE_Toolbar             = ToolSVC.UpdatePlayerToolbarSelection
local RE_SuperFlight         = FlightSVC.SuperFlight
local RE_SelectMode          = ModeTransform and ModeTransform.SelectMode

-- ═══════════════════════════════════════════════
-- CONFIG (flat)
-- ═══════════════════════════════════════════════
local Config = {
    -- Farm
    AutoFarm        = false,
    AutoBoss        = false,
    AutoSkill       = false,
    AutoLock        = true,
    ShowESP         = false,
    M1_Range        = 12,
    M1_Delay        = 0.35,
    Skill_Delay     = 1.2,
    Skill_Slot      = 1,
    MobAlvo         = nil,       -- filtro por nome (nil = todos)

    -- Tour
    AutoTour        = false,
    AreaSelecionada = nil,
    RaioArea        = 3000,
    EsperaSpawn     = 3,

    -- Combate avançado
    Godmode         = false,
    Stick           = false,
    HitboxGigante   = false,
    HitboxPlayer    = false,
    PlayerHitboxSize= 30,
    Noclip          = false,

    -- Rebirth
    AutoRebirth     = false,
    RebirthMultiplier = 3,

    -- Quests
    AutoQuest       = false,
    SelectedQuest   = nil,

    -- Collect
    AutoCollect     = false,

    -- Transform
    AutoTransform   = false,
    TransformMode   = "SSJAngel",

    -- Equip
    AutoEquip       = false,
    EquipSlot       = 1,

    -- Movement
    FlySpeed        = 100,
    WalkSpeed       = 16,
    OverrideSpeed   = false,

    -- Skills
    SkillTap        = true,

    -- Console Log
    ConsoleAtivo    = true,
    ConsoleIntervalo = 60,
}

local KiCfg = {
    LimiteRecarga   = 0.30,
    AlvoRecarga     = 0.95,
    TempoMaxRecarga = 5,
    Recarregando    = false,
}

local Ativo = true
local hitboxOriginal = nil
local ultimaSpecial = nil

-- Console System Globals
local ConsoleBuf = {}
local ConsoleUltimoSalvar = os.clock()
local ConsoleInicio = os.time()
local ConsoleLabelRef = nil

-- ═══════════════════════════════════════════════
-- CONSOLE LITE (SISTEMA DE LOG)
-- ═══════════════════════════════════════════════
local EVENTOS_IMPORTANTES = {
    "ItemSpawned", "ItemDrop", "ShootingStar", "onEventEffect",
    "Prompt", "Reward", "Drop", "Spawn", "Boss", "Zaja",
    "Quest", "Dialog", "UnlockMode", "Rebirth",
}

local function consoleAdd(tipo, msg)
    if not Config.ConsoleAtivo then return end
    local linha = string.format("[%s] [%s] %s", os.date("%H:%M:%S"), tipo, msg)
    table.insert(ConsoleBuf, linha)
    if #ConsoleBuf > 2000 then table.remove(ConsoleBuf, 1) end
    if ConsoleLabelRef then
        ConsoleLabelRef.Text = table.concat(ConsoleBuf, "\n")
    end
end

local function deveCapturar(nome)
    for _, kw in ipairs(EVENTOS_IMPORTANTES) do
        if nome:find(kw) then return true end
    end
    return false
end

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local m
    local okM = pcall(function() m = getnamecallmethod() end)
    if okM and (m == "FireServer" or m == "Fire" or m == "InvokeServer") then
        local ok, path = pcall(game.GetFullName, self)
        if ok and deveCapturar(path) then
            local args = {}
            for i = 1, math.min(select("#", ...), 5) do
                local v = select(i, ...)
                local t = typeof(v)
                if t == "Instance" then
                    local ok2, fn = pcall(game.GetFullName, v)
                    table.insert(args, ok2 and fn or tostring(v))
                elseif t == "Vector3" then
                    table.insert(args, string.format("V3(%.0f,%.0f,%.0f)", v.X, v.Y, v.Z))
                else
                    table.insert(args, tostring(v))
                end
            end
            consoleAdd("REMOTE", path:gsub("ReplicatedStorage%.", "") .. " | " .. table.concat(args, " | "))
        end
    end
    return oldNamecall(self, ...)
end)

-- Auto-Save Logs
task.spawn(function()
    while Ativo do
        task.wait(5)
        if Config.ConsoleAtivo and (os.clock() - ConsoleUltimoSalvar) >= Config.ConsoleIntervalo then
            if #ConsoleBuf > 0 then
                local nome = "DBH_Log_" .. ConsoleInicio .. ".txt"
                pcall(function() writefile(nome, table.concat(ConsoleBuf, "\n")) end)
                ConsoleUltimoSalvar = os.clock()
            end
        end
    end
end)

-- ═══════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════
local function safe(fn)
    local ok, err = pcall(fn)
    if not ok then warn("[DBH] " .. tostring(err)) end
    return ok
end

local function podeAtacar()
    local pg = plr:FindFirstChild("PlayerGui")
    if pg then
        local chat = pg:FindFirstChild("Chat")
        if chat and chat:FindFirstChild("ChatWindow") and chat.ChatWindow.Visible then
            return false
        end
    end
    local char = plr.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    return true
end

-- ═══════════════════════════════════════════════
-- NOCLIP
-- ═══════════════════════════════════════════════
task.spawn(function()
    while Ativo do
        task.wait(0.2)
        if Config.Noclip then
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
-- HITBOX DOS MOBS (gigante local)
-- ═══════════════════════════════════════════════
local function aplicarHitboxMobs()
    if not Config.HitboxGigante then return end
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
                    hrp.Size = orig.Value * 3
                    hrp.Transparency = math.max(hrp.Transparency, 0.95)
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════
-- ÍMÃ DE MOB (hitbox do player)
-- ═══════════════════════════════════════════════
local function aplicarHitboxPlayer()
    local char = plr.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    if Config.HitboxPlayer then
        if not hitboxOriginal then hitboxOriginal = hrp.Size end
        local s = Config.PlayerHitboxSize
        hrp.Size = Vector3.new(s, s, s)
        hrp.Transparency = 1
        hrp.Massless = true
        hrp.CanCollide = false
    elseif hitboxOriginal then
        hrp.Size = hitboxOriginal
        hrp.CanCollide = true
        hitboxOriginal = nil
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
                    local base = mob.Name:gsub("%-?%d+$", "")
                    
                    local valido = false
                    if Config.AutoFarm and not isBoss then valido = true end
                    if Config.AutoBoss and isBoss then valido = true end
                    if Config.AutoFarm and Config.AutoBoss then valido = true end

                    if valido and Config.MobAlvo and base ~= Config.MobAlvo then
                        valido = false
                    end

                    if valido then
                        local d = (mob.HumanoidRootPart.Position - myPos).Magnitude
                        if d < minD then
                            minD = d
                            maisProximo = {
                                model = mob,
                                fullName = mob.Name,
                                baseName = base,
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
    end

    local wm = WS:FindFirstChild("World Mobs")
    if wm then
        checar(wm:FindFirstChild("Mobs"), false)
        checar(wm:FindFirstChild("Boss Mobs"), true)
        
        for _, pasta in ipairs(wm:GetChildren()) do
            if pasta.Name:lower():find("boss") and pasta.Name ~= "Boss Mobs" then
                checar(pasta, true)
            end
        end
    end

    return maisProximo
end

local function listarMobsUnicos()
    local lista = {"(todos)"}
    local seen = {}
    local wm = WS:FindFirstChild("World Mobs")
    if not wm then return lista end
    
    for _, pasta in ipairs(wm:GetChildren()) do
        if pasta:IsA("Folder") or pasta:IsA("Model") then
            for _, mob in ipairs(pasta:GetChildren()) do
                if mob:IsA("Model") and mob:FindFirstChild("Humanoid") then
                    local base = mob.Name:gsub("%-?%d+$", "")
                    if not seen[base] then
                        seen[base] = true
                        table.insert(lista, base)
                    end
                end
            end
        end
    end
    table.sort(lista, function(a, b)
        if a == "(todos)" then return true end
        if b == "(todos)" then return false end
        return a < b
    end)
    return lista
end

-- ═══════════════════════════════════════════════
-- MOVIMENTAÇÃO
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
        local spd = math.min(speed, dir.Magnitude * 4)
        bv.Velocity = dir.Unit * spd
        bg.CFrame = CFrame.new(hrp.Position, pos)
    else
        bv.Velocity = Vector3.zero
    end
end

-- ═══════════════════════════════════════════════
-- STICK / GODMODE
-- ═══════════════════════════════════════════════
local stickAtivo = false
local stickAlvo = nil

local function stickarNoMob(mob)
    if stickAtivo then return end
    stickAtivo = true
    stickAlvo = mob
    task.spawn(function()
        while stickAtivo and Ativo and stickAlvo and stickAlvo.Parent do
            local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
            local mhrp = stickAlvo:FindFirstChild("HumanoidRootPart")
            if hrp and mhrp then
                local dist = (mhrp.Position - hrp.Position).Magnitude
                if dist > Config.M1_Range + 3 then
                    hrp.CFrame = CFrame.new(mhrp.Position - mhrp.CFrame.LookVector * -Config.M1_Range)
                end
            else
                break
            end
            task.wait(0.15)
        end
        stickAtivo = false
        stickAlvo = nil
    end)
end

local function pararStick()
    stickAtivo = false
    stickAlvo = nil
end

local function godmodePosicional(mob)
    if not Config.Godmode or not mob then return end
    local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
    local mhrp = mob:FindFirstChild("HumanoidRootPart")
    if not hrp or not mhrp then return end
    local targetPos = mhrp.Position + Vector3.new(0, 8, 0)
    hrp.CFrame = CFrame.new(targetPos, mhrp.Position)
end

-- ═══════════════════════════════════════════════
-- M1 (SkillId=2)
-- ═══════════════════════════════════════════════
local function m1(alvo)
    if not podeAtacar() then return end
    
    local char = plr.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local cam = workspace.CurrentCamera
    local aimPos = alvo and alvo.pos or (hrp.Position + hrp.CFrame.LookVector * 10)
    local camCF = cam and cam.CFrame or hrp.CFrame

    pcall(function()
        SkillRemote:FireServer({
            Began = true, CFrame = hrp.CFrame, Aim = aimPos,
            Camera = camCF, Type = 1, SkillId = "2",
        })
    end)
    task.wait(0.05)
    pcall(function()
        SkillRemote:FireServer({
            Began = false, CFrame = hrp.CFrame, Aim = aimPos,
            Camera = camCF, Type = 1, SkillId = "2",
        })
    end)
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
local skillIdx = 0

local function proximaSkill()
    skillIdx = skillIdx + 1
    if skillIdx > #SkillList then skillIdx = 1 end
    return SkillList[skillIdx]
end

local function usarSkill(skillId, slot, targetPos, mobModel)
    local char = plr.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    if skillId ~= ultimaSpecial then
        pcall(function() RE_ExecuteSkillSpecial:FireServer(char, skillId) end)
        ultimaSpecial = skillId
        task.wait(0.08)
    end

    local params = {}
    if skillId:find("UniqueSets") then
        local ok, folder = pcall(function()
            return RS.Assets.SkillsV2.UniqueSets["Seijin Instinct"].Animations
        end)
        if ok and folder then
            local anim = skillId:find("_2_1") and "Kamehameha" 
                or skillId:find("_2_3") and "SpiritBomb" 
                or nil
            if anim then
                params = {
                    HoldAnimation = folder["Hold_" .. anim],
                    ReleaseAnimation = folder["Release_" .. anim],
                    HumCFrame = hrp.CFrame,
                    ResumeOnTimePassed = (anim == "Kamehameha") and 3 or 0.1,
                    targetPos = targetPos or (hrp.Position + hrp.CFrame.LookVector * 10),
                }
            else
                params = { HumCFrame = hrp.CFrame, Target = mobModel }
            end
        end
    elseif skillId == "Weapons_3_2" then
        params = {
            targetPos = targetPos or (hrp.Position + hrp.CFrame.LookVector * 10),
            PauseTimeFrame = 0.6166666666666667,
            animationSpeed = 1,
            ResumeOnTimePassed = 0.6333333333333333,
            HumCFrame = hrp.CFrame,
        }
    elseif skillId == "Weapons_3_3" then
        params = { CFrame = hrp.CFrame }
    end

    pcall(function()
        RE_ExecuteSkill:FireServer(skillId, params, slot or 1, true)
    end)
    task.wait(0.3)
    pcall(function()
        RE_ExecuteSkill:FireServer(skillId, params, slot or 1, false)
    end)
end

-- ═══════════════════════════════════════════════
-- LOCK-ON
-- ═══════════════════════════════════════════════
local LockConexao = nil
local LockAlvo = nil

local function pararLock()
    if LockConexao then LockConexao:Disconnect(); LockConexao = nil end
    LockAlvo = nil
end

local function lockOn(mobModel)
    pcall(function() RE_LockedOnChanged:FireServer(mobModel) end)
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
-- KI CHARGE (tecla C)
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

    local inicio = os.clock()
    VIM:SendKeyEvent(true, Enum.KeyCode.C, false, game)

    while KiCfg.Recarregando and Ativo do
        local cur, max = getKiAtual()
        local pct = max > 0 and (cur / max) or 0
        if pct >= KiCfg.AlvoRecarga then break end
        if (os.clock() - inicio) >= KiCfg.TempoMaxRecarga then break end
        task.wait(0.15)
    end

    VIM:SendKeyEvent(false, Enum.KeyCode.C, false, game)
    KiCfg.Recarregando = false
    task.wait(0.3)
end

-- ═══════════════════════════════════════════════
-- ÁREAS / TOUR
-- ═══════════════════════════════════════════════
local areas = {}
local areaAtual = nil
local areaIdx = 0

local function descobrirAreas()
    areas = {}
    local wm = WS:FindFirstChild("World Mobs")
    if not wm then return end
    local char = plr.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local myPos = hrp.Position

    for _, categoria in ipairs(wm:GetChildren()) do
        if categoria:IsA("Folder") or categoria:IsA("Model") then
            for _, sub in ipairs(categoria:GetChildren()) do
                if sub:IsA("Folder") or sub:IsA("Model") then
                    local ancora = nil
                    for _, d in ipairs(sub:GetDescendants()) do
                        if d:IsA("BasePart") then ancora = d break end
                    end
                    if not ancora then
                        for _, d in ipairs(sub:GetDescendants()) do
                            if d:IsA("Model") and d:FindFirstChild("HumanoidRootPart") then
                                ancora = d.HumanoidRootPart
                                break
                            end
                        end
                    end
                    if ancora then
                        local dist = (ancora.Position - myPos).Magnitude
                        if dist < Config.RaioArea then
                            table.insert(areas, {
                                nome = sub.Name,
                                categoria = categoria.Name,
                                pos = ancora.Position,
                                distancia = dist,
                            })
                        end
                    end
                end
            end
        end
    end
    table.sort(areas, function(a, b) return a.distancia < b.distancia end)
    return areas
end

local function irParaArea(area)
    if not area then return end
    areaAtual = area
    voarPara(area.pos, Config.FlySpeed * 0.8)
end

local function mobsNaArea(area, raio)
    raio = raio or 150
    if not area then return 0 end
    local count = 0
    local wm = WS:FindFirstChild("World Mobs")
    if not wm then return 0 end
    for _, pasta in ipairs({wm:FindFirstChild("Mobs"), wm:FindFirstChild("Boss Mobs")}) do
        if pasta then
            for _, mob in ipairs(pasta:GetChildren()) do
                if mob:IsA("Model") and mob:FindFirstChild("HumanoidRootPart") then
                    local hum = mob:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        local d = (mob.HumanoidRootPart.Position - area.pos).Magnitude
                        if d <= raio then count = count + 1 end
                    end
                end
            end
        end
    end
    return count
end

-- ═══════════════════════════════════════════════
-- QUESTS
-- ═══════════════════════════════════════════════
local questsList = {}

local function atualizarQuests()
    questsList = {}
    local npcFolder = WS:FindFirstChild("NPC")
    local questsFolder = npcFolder and npcFolder:FindFirstChild("Quests")
    if not questsFolder then return end
    for _, npc in ipairs(questsFolder:GetChildren()) do
        local num = tonumber(npc.Name:match("QuestNPCMain(%d+)_")) or 0
        local nome = npc.Name:match("QuestNPCMain%d+_(.+)") or npc.Name
        local hrp = npc:FindFirstChild("HumanoidRootPart")
        table.insert(questsList, {
            nome = npc.Name,
            numero = num,
            display = num .. ". " .. nome,
            pos = hrp and hrp.Position or nil,
        })
    end
    table.sort(questsList, function(a, b) return a.numero < b.numero end)
end
atualizarQuests()

-- ═══════════════════════════════════════════════
-- REBIRTH
-- ═══════════════════════════════════════════════
local function calcularRequisito(reb) return (reb * 3000000) + 2000000 end

local function checarRebirth()
    local stats = plr:FindFirstChild("Stats")
    if not stats then return false, nil end
    local reb = stats:FindFirstChild("Rebirth")
    local str = stats:FindFirstChild("Strength")
    local ki  = stats:FindFirstChild("Ki")
    if not reb or not str or not ki then return false, nil end
    local r = reb.Value
    local total = str.Value + ki.Value
    local minimo = calcularRequisito(r)
    local alvo = minimo * Config.RebirthMultiplier
    return total >= alvo, { rebirth = r, total = total, minimo = minimo, alvo = alvo }
end

local function fazerRebirth()
    pcall(function()
        RE_Prompt:FireServer({
            UniqueTag = "HudRebirth", Title = "Rebirth",
            LeftButton = "Details", MiddleButton = "Confirm",
            Prompt = "HudRebirth", RightButton = "Cancel",
            Description = "Confirm Rebirth?",
        }, "Confirm")
    end)
    task.wait(0.3)
    pcall(function()
        RF_RequestRebirth:InvokeServer(true)
    end)
end

-- ═══════════════════════════════════════════════
-- COLLECT
-- ═══════════════════════════════════════════════
local OnEventEffect = KnitPath.PeriodicEventService and KnitPath.PeriodicEventService.RE.onEventEffect
local ItemSpawned  = KnitPath.ItemDropService and KnitPath.ItemDropService.RE.ItemSpawned
local ClaimItem    = KnitPath.ItemDropService and KnitPath.ItemDropService.RF.ClaimItem

task.spawn(function()
    task.wait(3)
    if OnEventEffect then
        OnEventEffect.OnClientEvent:Connect(function(evento, pos)
            if not Config.AutoCollect then return end
            if evento == "ShootingStar" and typeof(pos) == "Vector3" then
                consoleAdd("COLLECT", "Meteoro detectado em: " .. tostring(pos))
                voarPara(pos)
                task.wait(3)
            end
        end)
    end
    if ItemSpawned then
        ItemSpawned.OnClientEvent:Connect(function(data)
            if not Config.AutoCollect then return end
            if type(data) == "table" and data.Pos then
                consoleAdd("COLLECT", "Item Spawned: " .. tostring(data.Name))
                task.wait(1)
                voarPara(data.Pos)
                task.wait(2)
                if ClaimItem then
                    pcall(function() ClaimItem:InvokeServer(data.Name, data.ItemName) end)
                end
            end
        end)
    end
end)

-- ═══════════════════════════════════════════════
-- ESP COM TIMER DE BOSS
-- ═══════════════════════════════════════════════
local espGui = Instance.new("ScreenGui")
espGui.Name = "DBH_ESP"
espGui.ResetOnSpawn = false
espGui.Parent = CoreGui

local espCache = {}
local bossTimers = {}

local function criarESP(mob)
    local hrp = mob:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local bb = Instance.new("BillboardGui")
    bb.Name = "DBH_ESP"
    bb.Size = UDim2.new(0, 140, 0, 60)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Adornee = hrp
    bb.Parent = espGui

    local nome = Instance.new("TextLabel", bb)
    nome.Size = UDim2.new(1, 0, 0, 18)
    nome.BackgroundTransparency = 1
    nome.TextColor3 = mob.Parent and mob.Parent.Name == "Boss Mobs" 
        and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 200, 80)
    nome.TextStrokeTransparency = 0.5
    nome.TextSize = 12
    nome.Font = Enum.Font.GothamBold
    nome.Text = mob.Name

    local hpBar = Instance.new("Frame", bb)
    hpBar.Size = UDim2.new(1, -10, 0, 6)
    hpBar.Position = UDim2.new(0, 5, 0, 20)
    hpBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    hpBar.BorderSizePixel = 0

    local hpFill = Instance.new("Frame", hpBar)
    hpFill.Size = UDim2.new(1, 0, 1, 0)
    hpFill.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
    hpFill.BorderSizePixel = 0

    local timerLabel = Instance.new("TextLabel", bb)
    timerLabel.Size = UDim2.new(1, 0, 0, 16)
    timerLabel.Position = UDim2.new(0, 0, 0, 28)
    timerLabel.BackgroundTransparency = 1
    timerLabel.TextColor3 = Color3.fromRGB(255, 140, 30)
    timerLabel.TextSize = 10
    timerLabel.Font = Enum.Font.Code
    timerLabel.Text = ""
    timerLabel.Visible = false

    espCache[mob] = {bb = bb, hpFill = hpFill, timerLabel = timerLabel}
end

local function removerESP(mob)
    local c = espCache[mob]
    if c and c.bb then c.bb:Destroy() end
    espCache[mob] = nil
end

task.spawn(function()
    while Ativo do
        task.wait(0.3)
        if not Config.ShowESP then
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
                                c.hpFill.BackgroundColor3 = pct > 0.5 and Color3.fromRGB(80, 200, 120)
                                    or pct > 0.2 and Color3.fromRGB(255, 200, 80)
                                    or Color3.fromRGB(220, 60, 60)
                                if pasta.Name == "Boss Mobs" then
                                    local base = mob.Name:gsub("%-?%d+$", "")
                                    local t = bossTimers[base]
                                    if t and t.morreuEm then
                                        local restante = math.max(0, t.respawnEstimado - (os.clock() - t.morreuEm))
                                        if restante > 0 then
                                            c.timerLabel.Text = string.format("Respawn: %ds", math.floor(restante))
                                            c.timerLabel.Visible = true
                                        else
                                            c.timerLabel.Visible = false
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        for mob in pairs(espCache) do
            if not vivos[mob] then
                if mob.Parent and mob.Parent.Name == "Boss Mobs" then
                    local base = mob.Name:gsub("%-?%d+$", "")
                    bossTimers[base] = {morreuEm = os.clock(), respawnEstimado = 180}
                end
                removerESP(mob)
            end
        end
    end
end)

-- ═══════════════════════════════════════════════
-- UI LIBRARY (Rayfield AMOLED)
-- ═══════════════════════════════════════════════
local UI = {}
UI.Theme = {
    Bg = Color3.fromRGB(0, 0, 0),
    Panel = Color3.fromRGB(8, 8, 8),
    Elevated = Color3.fromRGB(14, 14, 14),
    Border = Color3.fromRGB(26, 26, 30),
    Accent = Color3.fromRGB(255, 140, 30),
    Text = Color3.fromRGB(235, 235, 240),
    TextDim = Color3.fromRGB(150, 150, 160),
    Success = Color3.fromRGB(80, 200, 120),
    Danger = Color3.fromRGB(220, 60, 60),
    Off = Color3.fromRGB(45, 45, 55),
}
local FONT, FONT_BOLD, FONT_MONO = Enum.Font.GothamMedium, Enum.Font.GothamBold, Enum.Font.Code

local function I(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end
local function corner(o, r) return I("UICorner", {CornerRadius = r or UDim.new(0, 7)}, o) end
local function pad(o, t, b, l, r)
    return I("UIPadding", {
        PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0),
        PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or 0),
    }, o)
end

function UI.newWindow()
    gui = I("ScreenGui", {Name = "DragonBloxHub_v6", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, CoreGui)
    local main = I("Frame", {
        Size = UDim2.new(0, 500, 0, 400),
        Position = UDim2.new(0.5, -250, 0.5, -200),
        BackgroundColor3 = UI.Theme.Bg, BackgroundTransparency = 0.05,
        BorderSizePixel = 0, Active = true,
    }, gui)
    corner(main, UDim.new(0, 10))
    I("UIStroke", {Color = UI.Theme.Border, Thickness = 1}, main)

    local header = I("Frame", {Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = UI.Theme.Panel, BorderSizePixel = 0}, main)
    corner(header, UDim.new(0, 10))
    I("TextLabel", {
        Size = UDim2.new(1, -110, 1, 0), Position = UDim2.new(0, 14, 0, 0),
        BackgroundTransparency = 1, Text = "🐉   Dragon Blox Hub v6",
        TextColor3 = UI.Theme.Text, Font = FONT_BOLD, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, header)

    local btnClose = I("TextButton", {
        Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(1, -30, 0.5, -11),
        BackgroundColor3 = UI.Theme.Danger, Text = "×", TextColor3 = Color3.new(1, 1, 1),
        Font = FONT_BOLD, TextSize = 14, AutoButtonColor = false, BorderSizePixel = 0,
    }, header)
    corner(btnClose, UDim.new(0, 5))

    local btnMin = I("TextButton", {
        Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(1, -56, 0.5, -11),
        BackgroundColor3 = UI.Theme.Elevated, Text = "—", TextColor3 = UI.Theme.Text,
        Font = FONT_BOLD, TextSize = 12, AutoButtonColor = false, BorderSizePixel = 0,
    }, header)
    corner(btnMin, UDim.new(0, 5))

    local sidebar = I("Frame", {
        Size = UDim2.new(0, 130, 1, -36), Position = UDim2.new(0, 0, 0, 36),
        BackgroundColor3 = UI.Theme.Panel, BorderSizePixel = 0,
    }, main)
    I("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder}, sidebar)
    pad(sidebar, 8, 8, 8, 8)

    local content = I("Frame", {
        Size = UDim2.new(1, -130, 1, -36), Position = UDim2.new(0, 130, 0, 36),
        BackgroundColor3 = UI.Theme.Bg, BorderSizePixel = 0,
    }, main)

    local dragging, dragStart, startPos = false, nil, nil
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = main.Position
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    local float = I("TextButton", {
        Size = UDim2.new(0, 46, 0, 46), Position = UDim2.new(0, 20, 0.4, 0),
        BackgroundColor3 = UI.Theme.Bg, Text = "🐉", TextColor3 = UI.Theme.Accent,
        Font = FONT_BOLD, TextSize = 20, AutoButtonColor = false, Visible = false,
        Active = true, Draggable = true, BorderSizePixel = 0,
    }, gui)
    corner(float, UDim.new(1, 0))
    I("UIStroke", {Color = UI.Theme.Accent, Thickness = 1}, float)

    btnMin.MouseButton1Click:Connect(function() main.Visible = false; float.Visible = true end)
    float.MouseButton1Click:Connect(function() main.Visible = true; float.Visible = false end)
    btnClose.MouseButton1Click:Connect(function() gui:Destroy() end)

    return {gui = gui, frame = main, sidebar = sidebar, content = content, tabs = {}}
end

function UI.newTab(win, icon, name)
    local btn = I("TextButton", {
        Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = UI.Theme.Panel,
        TextColor3 = UI.Theme.TextDim, Font = FONT, TextSize = 11,
        Text = "  " .. icon .. "   " .. name,
        TextXAlignment = Enum.TextXAlignment.Left,
        BorderSizePixel = 0, AutoButtonColor = false,
    }, win.sidebar)
    corner(btn, UDim.new(0, 7))

    local frame = I("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = UI.Theme.Border,
        CanvasSize = UDim2.new(0, 0, 0, 0), Visible = false,
    }, win.content)
    local layout = I("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, frame)
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

function UI.section(tab, title)
    return I("TextLabel", {
        Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1,
        Text = title, TextColor3 = UI.Theme.Accent, Font = FONT_BOLD, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, tab.frame)
end

function UI.toggle(tab, opts)
    local state = opts.default or false
    local frame = I("TextButton", {
        Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = UI.Theme.Elevated,
        BorderSizePixel = 0, Text = "", AutoButtonColor = false,
    }, tab.frame)
    corner(frame, UDim.new(0, 8))
    I("TextLabel", {
        Size = UDim2.new(1, -70, 1, 0), Position = UDim2.new(0, 14, 0, 0),
        BackgroundTransparency = 1, Text = opts.name, TextColor3 = UI.Theme.Text,
        Font = FONT, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)
    local sw = I("Frame", {
        Size = UDim2.new(0, 42, 0, 24), Position = UDim2.new(1, -56, 0.5, -12),
        BackgroundColor3 = state and UI.Theme.Success or UI.Theme.Off, BorderSizePixel = 0,
    }, frame)
    corner(sw, UDim.new(1, 0))
    local knob = I("Frame", {
        Size = UDim2.new(0, 20, 0, 20),
        Position = state and UDim2.new(1, -22, 0.5, -10) or UDim2.new(0, 2, 0.5, -10),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0,
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

function UI.slider(tab, opts)
    local min, max = opts.min or 0, opts.max or 100
    local value = opts.default or min
    local suffix = opts.suffix or ""

    local frame = I("Frame", {
        Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = UI.Theme.Elevated, BorderSizePixel = 0,
    }, tab.frame)
    corner(frame, UDim.new(0, 8))
    I("TextLabel", {
        Size = UDim2.new(1, -90, 0, 22), Position = UDim2.new(0, 14, 0, 6),
        BackgroundTransparency = 1, Text = opts.name, TextColor3 = UI.Theme.Text,
        Font = FONT, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)
    local valLabel = I("TextLabel", {
        Size = UDim2.new(0, 80, 0, 22), Position = UDim2.new(1, -92, 0, 6),
        BackgroundTransparency = 1, Text = tostring(value) .. suffix,
        TextColor3 = UI.Theme.Accent, Font = FONT_BOLD, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, frame)
    local track = I("Frame", {
        Size = UDim2.new(1, -28, 0, 6), Position = UDim2.new(0, 14, 0, 38),
        BackgroundColor3 = UI.Theme.Border, BorderSizePixel = 0,
    }, frame)
    corner(track, UDim.new(1, 0))
    local fill = I("Frame", {
        Size = UDim2.new((value - min) / (max - min), 0, 1, 0),
        BackgroundColor3 = UI.Theme.Accent, BorderSizePixel = 0,
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
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; update(input.Position.X)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            update(input.Position.X)
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
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

function UI.button(tab, opts)
    local btn = I("TextButton", {
        Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = UI.Theme.Elevated,
        Text = opts.name, TextColor3 = UI.Theme.Text, Font = FONT, TextSize = 12,
        BorderSizePixel = 0, AutoButtonColor = true,
    }, tab.frame)
    corner(btn, UDim.new(0, 8))
    btn.MouseButton1Click:Connect(function()
        if opts.callback then opts.callback() end
    end)
    return btn
end

function UI.label(tab, opts)
    local l = I("TextLabel", {
        Size = UDim2.new(1, 0, 0, opts.height or 60),
        BackgroundColor3 = UI.Theme.Elevated, TextColor3 = UI.Theme.Text,
        Font = FONT_MONO, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true, Text = opts.text or "",
    }, tab.frame)
    corner(l, UDim.new(0, 8))
    pad(l, 10, 10, 14, 14)
    return l
end

function UI.dropdown(tab, opts)
    local current = opts.default or "(todos)"
    local btn = I("TextButton", {
        Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = UI.Theme.Elevated,
        Text = "  " .. opts.name .. ": " .. current,
        TextColor3 = UI.Theme.Text, Font = FONT, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        BorderSizePixel = 0, AutoButtonColor = false,
    }, tab.frame)
    corner(btn, UDim.new(0, 8))

    local function atualizarTexto()
        btn.Text = "  " .. opts.name .. ": " .. current
    end

    btn.MouseButton1Click:Connect(function()
        local popup = I("Frame", {
            Size = UDim2.new(0, 260, 0, 300),
            Position = UDim2.new(0.5, -130, 0.5, -150),
            BackgroundColor3 = UI.Theme.Panel, BorderSizePixel = 0,
            ZIndex = 100, Active = true,
        }, gui)
        corner(popup, UDim.new(0, 10))
        I("UIStroke", {Color = UI.Theme.Accent, Thickness = 1}, popup)

        I("TextLabel", {
            Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1,
            Text = opts.name, TextColor3 = UI.Theme.Accent,
            Font = FONT_BOLD, TextSize = 13,
        }, popup)

        local scroll = I("ScrollingFrame", {
            Size = UDim2.new(1, -16, 1, -50), Position = UDim2.new(0, 8, 0, 32),
            BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 3, ScrollBarImageColor3 = UI.Theme.Border,
            CanvasSize = UDim2.new(0, 0, 0, 0),
        }, popup)
        local layout = I("UIListLayout", {Padding = UDim.new(0, 4)}, scroll)

        local listaAtual = opts.options
        if type(listaAtual) == "function" then listaAtual = listaAtual() end

        for _, opt in ipairs(listaAtual) do
            local ob = I("TextButton", {
                Size = UDim2.new(1, 0, 0, 34),
                BackgroundColor3 = UI.Theme.Elevated,
                Text = tostring(opt), TextColor3 = UI.Theme.Text,
                Font = FONT, TextSize = 12, BorderSizePixel = 0,
                AutoButtonColor = true,
            }, scroll)
            corner(ob, UDim.new(0, 6))
            ob.MouseButton1Click:Connect(function()
                current = opt
                atualizarTexto()
                popup:Destroy()
                if opts.callback then opts.callback(opt) end
            end)
        end
        scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)

        local btnFechar = I("TextButton", {
            Size = UDim2.new(0, 40, 0, 24), Position = UDim2.new(1, -46, 0, 3),
            BackgroundColor3 = UI.Theme.Danger, Text = "×", TextColor3 = Color3.new(1, 1, 1),
            Font = FONT_BOLD, TextSize = 14, BorderSizePixel = 0,
        }, popup)
        corner(btnFechar, UDim.new(0, 6))
        btnFechar.MouseButton1Click:Connect(function() popup:Destroy() end)
    end)
    return {set = function(v) current = v; atualizarTexto() end}
end

-- ═══════════════════════════════════════════════
-- KILL SWITCH
-- ═══════════════════════════════════════════════
local function matarTudo()
    Ativo = false
    Config.AutoFarm = false; Config.AutoBoss = false; Config.AutoSkill = false; Config.AutoTour = false
    Config.AutoRebirth = false; Config.AutoQuest = false; Config.AutoCollect = false
    Config.AutoTransform = false; Config.AutoEquip = false; Config.Noclip = false
    Config.ShowESP = false; Config.Godmode = false; Config.Stick = false
    Config.HitboxPlayer = false; Config.HitboxGigante = false

    local char = plr.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            for _, o in ipairs(hrp:GetChildren()) do
                if o:IsA("BodyMover") then o:Destroy() end
            end
        end
        if hitboxOriginal then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.Size = hitboxOriginal; hrp.CanCollide = true end
        end
    end
    if gui then gui:Destroy() end
    if espGui then espGui:Destroy() end
    print("[DBH] Script encerrado.")
end

-- ═══════════════════════════════════════════════
-- APLICAÇÃO DA UI
-- ═══════════════════════════════════════════════
local win = UI.newWindow()
mainFrame = win.frame

local farmTab      = UI.newTab(win, "⚔", "Farm")
local tourTab      = UI.newTab(win, "🗺", "Tour")
local rebirthTab   = UI.newTab(win, "🔄", "Rebirth")
local questTab     = UI.newTab(win, "📜", "Quest")
local collectTab   = UI.newTab(win, "💎", "Collect")
local transformTab = UI.newTab(win, "🌀", "Transform")
local consoleTab   = UI.newTab(win, "📜", "Console")
local miscTab      = UI.newTab(win, "🛠", "Misc")
local configTab    = UI.newTab(win, "⚙", "Config")
local statsTab     = UI.newTab(win, "📊", "Stats")
local sobreTab     = UI.newTab(win, "ℹ", "Sobre")

farmTab.btn.BackgroundColor3 = UI.Theme.Elevated
farmTab.btn.TextColor3 = UI.Theme.Accent
farmTab.frame.Visible = true

-- ═══ FARM ═══
UI.section(farmTab, "⚔   COMBATE")
UI.toggle(farmTab, {name = "Auto Farm (Mobs)", default = false, callback = function(v) Config.AutoFarm = v end})
UI.toggle(farmTab, {name = "Auto Farm (Bosses)", default = false, callback = function(v) Config.AutoBoss = v end})
UI.toggle(farmTab, {name = "Auto Skill", default = false, callback = function(v) Config.AutoSkill = v end})
UI.toggle(farmTab, {name = "Auto Lock-On", default = true, callback = function(v) Config.AutoLock = v end})
UI.toggle(farmTab, {name = "Mostrar ESP", default = false, callback = function(v) Config.ShowESP = v end})

UI.section(farmTab, "🎯   MOB ALVO")
local mobDropdown
mobDropdown = UI.dropdown(farmTab, {
    name = "Filtrar Mob",
    options = function() return listarMobsUnicos() end,
    default = "(todos)",
    callback = function(opt)
        if opt == "(todos)" then Config.MobAlvo = nil else Config.MobAlvo = opt end
    end
})
UI.button(farmTab, {name = "🔄 Atualizar Lista de Mobs", callback = function()
    mobDropdown.set("(todos)")
    Config.MobAlvo = nil
end})

UI.section(farmTab, "📏   RANGES & DELAYS")
UI.slider(farmTab, {name = "M1 Range", min = 5, max = 50, default = 12, suffix = " studs", callback = function(v) Config.M1_Range = v end})
UI.slider(farmTab, {name = "M1 Delay", min = 10, max = 100, default = 35, suffix = " ms", callback = function(v) Config.M1_Delay = v / 100 end})
UI.slider(farmTab, {name = "Skill Delay", min = 3, max = 50, default = 12, suffix = " x0.1s", callback = function(v) Config.Skill_Delay = v / 10 end})

UI.section(farmTab, "🎯   COMBATE AVANÇADO")
UI.toggle(farmTab, {name = "Stick to Mob", default = false, callback = function(v) Config.Stick = v end})
UI.toggle(farmTab, {name = "Godmode Posicional", default = false, callback = function(v) Config.Godmode = v end})
UI.toggle(farmTab, {name = "Hitbox Gigante (mob)", default = false, callback = function(v) Config.HitboxGigante = v end})

-- ═══ TOUR ═══
UI.section(tourTab, "🗺   AUTO TOUR")
UI.toggle(tourTab, {name = "Auto Tour (percorrer áreas)", default = false, callback = function(v) Config.AutoTour = v end})
UI.slider(tourTab, {name = "Raio de Descoberta", min = 500, max = 8000, default = 3000, suffix = " studs", callback = function(v) Config.RaioArea = v end})
UI.slider(tourTab, {name = "Espera por Área", min = 1, max = 15, default = 3, suffix = " s", callback = function(v) Config.EsperaSpawn = v end})

UI.section(tourTab, "📍   ÁREAS")
UI.button(tourTab, {name = "🔄 Re-escaneiar Áreas", callback = function() descobrirAreas() end})
local areaDropdown
areaDropdown = UI.dropdown(tourTab, {
    name = "Ir para Área",
    options = function()
        local lista = {"(nenhuma)"}
        for _, a in ipairs(areas) do
            table.insert(lista, a.categoria .. " ▸ " .. a.nome)
        end
        return lista
    end,
    default = "(nenhuma)",
    callback = function(opt)
        if opt == "(nenhuma)" then Config.AreaSelecionada = nil return end
        for _, a in ipairs(areas) do
            if (a.categoria .. " ▸ " .. a.nome) == opt then
                Config.AreaSelecionada = a
                irParaArea(a)
                break
            end
        end
    end
})

local infoArea = UI.label(tourTab, {text = "Área: --\nMobs: --", height = 50})

-- ═══ REBIRTH ═══
UI.section(rebirthTab, "🔄   AUTO REBIRTH")
UI.toggle(rebirthTab, {name = "Auto Rebirth", default = false, callback = function(v)
    Config.AutoRebirth = v
end})
UI.slider(rebirthTab, {name = "Acumular (x requisito)", min = 1, max = 10, default = 3, callback = function(v) Config.RebirthMultiplier = v end})
UI.button(rebirthTab, {name = "🔄 Forçar Rebirth", callback = function()
    fazerRebirth()
end})

local infoRebirth = UI.label(rebirthTab, {text = "Rebirth: --\nStats: --\nAlvo: --", height = 80})

-- ═══ QUEST ═══
UI.section(questTab, "📜   QUEST")
local questDropdown
questDropdown = UI.dropdown(questTab, {
    name = "Quest",
    options = function()
        local lista = {"(nenhuma)"}
        for _, q in ipairs(questsList) do table.insert(lista, q.display) end
        return lista
    end,
    default = "(nenhuma)",
    callback = function(opt)
        for _, q in ipairs(questsList) do
            if q.display == opt then Config.SelectedQuest = q break end
        end
    end
})
UI.button(questTab, {name = "🔄 Atualizar Quests", callback = function() atualizarQuests() end})
UI.button(questTab, {name = "✈️ Voar até o NPC", callback = function()
    if Config.SelectedQuest and Config.SelectedQuest.pos then voarPara(Config.SelectedQuest.pos) end
end})
UI.toggle(questTab, {name = "Auto Aceitar Quest", default = false, callback = function(v) Config.AutoQuest = v end})

-- ═══ COLLECT ═══
UI.section(collectTab, "💎   AUTO COLLECT")
UI.toggle(collectTab, {name = "Auto Coletar (esferas/meteoros/items)", default = false, callback = function(v) Config.AutoCollect = v end})

UI.section(collectTab, "ℹ   INFO")
local infoCollect = UI.label(collectTab, {text = "Escaneando Drops...", height = 60})

-- ═══ TRANSFORM ═══
UI.section(transformTab, "🌀   TRANSFORMAÇÃO")
UI.toggle(transformTab, {name = "Auto Transform", default = false, callback = function(v) Config.AutoTransform = v end})
UI.dropdown(transformTab, {
    name = "Modo",
    options = {
        "SSJ", "SSJ2", "SSJ3", "SSJB", "SSJB2", "SSJB3", "SSJG",
        "SSJAngel", "SSJAngel2", "SSJAngel3",
        "SSJDemon", "SSJDemon2", "SSJDemon3",
        "SSJDivinity", "SSJDivinity2", "SSJDivinity3",
        "SSJRage", "SSJRage2", "SSJRose", "SSJRose2", "SSJRose3",
        "LSSJ", "LSSJ2", "LSSJ3", "FSSJ", "UltraInstinct", "UltraEgo", "Beast",
    },
    default = "SSJAngel",
    callback = function(opt) Config.TransformMode = opt end
})

-- ═══ CONSOLE LOG ═══
UI.section(consoleTab, "📜   CONSOLE LOGS")
UI.toggle(consoleTab, {name = "Capturar Remotes", default = true, callback = function(v) Config.ConsoleAtivo = v end})
ConsoleLabelRef = UI.label(consoleTab, {text = "Iniciando captura de dados de rede...", height = 220})

-- ═══ MISC ═══
UI.section(miscTab, "🛠   UTILITÁRIOS")
UI.toggle(miscTab, {name = "Noclip", default = false, callback = function(v) Config.Noclip = v end})

UI.section(miscTab, "🎯   HITBOX DO PLAYER (Ímã)")
UI.toggle(miscTab, {name = "Ativar Hitbox Player", default = false, callback = function(v)
    Config.HitboxPlayer = v; aplicarHitboxPlayer()
end})
UI.slider(miscTab, {name = "Tamanho da Hitbox", min = 15, max = 60, default = 30, suffix = " studs", callback = function(v)
    Config.PlayerHitboxSize = v
    if Config.HitboxPlayer then aplicarHitboxPlayer() end
end})

UI.section(miscTab, "✈   MOVIMENTO")
UI.slider(miscTab, {name = "Velocidade de Voo", min = 50, max = 500, default = 100, suffix = " studs/s", callback = function(v) Config.FlySpeed = v end})
UI.toggle(miscTab, {name = "Forçar WalkSpeed", default = false, callback = function(v) Config.OverrideSpeed = v end})
UI.slider(miscTab, {name = "WalkSpeed", min = 16, max = 200, default = 16, callback = function(v) Config.WalkSpeed = v end})

UI.section(miscTab, "🌌   VOO NATIVO")
UI.button(miscTab, {name = "Ativar Voo Nativo (5s)", callback = function()
    pcall(function() RE_SuperFlight:FireServer(true) end)
    task.wait(5)
    pcall(function() RE_SuperFlight:FireServer(false) end)
end})

-- ═══ CONFIG ═══
UI.section(configTab, "⚡   SKILLS")
UI.toggle(configTab, {name = "Skills: Tap (não segurar)", default = true, callback = function(v) Config.SkillTap = v end})

UI.section(configTab, "💠   KI / ENERGIA")
UI.slider(configTab, {name = "Ki mín. p/ recarregar", min = 10, max = 80, default = 30, suffix = "%", callback = function(v) KiCfg.LimiteRecarga = v / 100 end})
UI.slider(configTab, {name = "Ki alvo pós-recarga", min = 50, max = 100, default = 95, suffix = "%", callback = function(v) KiCfg.AlvoRecarga = v / 100 end})
UI.slider(configTab, {name = "Tempo máx. recarga", min = 2, max = 15, default = 5, suffix = " s", callback = function(v) KiCfg.TempoMaxRecarga = v end})

UI.section(configTab, "🔧   FERRAMENTA")
UI.toggle(configTab, {name = "Auto Equip", default = false, callback = function(v) Config.AutoEquip = v end})
UI.slider(configTab, {name = "Slot da Ferramenta", min = 1, max = 9, default = 1, callback = function(v) Config.EquipSlot = v end})

UI.section(configTab, "🛑   SISTEMA")
UI.button(configTab, {name = "🛑 MATAR SCRIPT", callback = matarTudo})

-- ═══ STATS ═══
UI.section(statsTab, "📊   STATUS")
local statsLabel = UI.label(statsTab, {text = "Carregando...", height = 130})

-- ═══ SOBRE ═══
UI.section(sobreTab, "ℹ   INFO")
UI.label(sobreTab, {text = "🐉 DRAGON BLOX HUB v6\n\nCriadores: zyyx & elliot\n\nSistema de Auto-Farm otimizado via Knit Remotes + VirtualInputManager.\n\nAgradecimentos: comunidade Dragon Blox.", height = 130})

UI.section(sobreTab, "🖥   SERVIDOR")
local infoServidor = UI.label(sobreTab, {text = "Carregando...", height = 120})

-- ═══════════════════════════════════════════════
-- LOOPS FINAIS
-- ═══════════════════════════════════════════════

-- Combate principal
task.spawn(function()
    local ultimoM1 = 0
    local ultimoSkill = 0
    local ultimoHitboxCheck = 0
    local alvoTravado = nil

    while Ativo do
        task.wait(0.1)
        if os.clock() - ultimoHitboxCheck >= 1.0 then
            aplicarHitboxMobs()
            ultimoHitboxCheck = os.clock()
        end

        if not Config.AutoFarm and not Config.AutoBoss and not Config.AutoSkill then
            alvoTravado = nil
            pararVoo()
            pararStick()
            task.wait(0.5)
            continue
        end

        local cur, max = getKiAtual()
        local pct = max > 0 and (cur / max) or 1
        if pct < KiCfg.LimiteRecarga then
            lockOn(nil)
            pararVoo()
            recarregarKi()
            ultimoSkill = os.clock()
            continue
        end

        local mob = getMobMaisProximo()
        if not mob then
            pararVoo()
            pararStick()
            task.wait(0.5)
            continue
        end

        local char = plr.Character
        if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end

        if Config.AutoLock and alvoTravado ~= mob.baseName then
            lockOn(mob.model)
            alvoTravado = mob.baseName
        end

        if Config.Stick and not stickAtivo then
            stickarNoMob(mob.model)
        end

        if mob.dist > Config.M1_Range then
            voarPara(mob.pos)
            task.wait(0.1)
            continue
        end

        pararVoo()
        if not Config.Godmode then
            hrp.CFrame = CFrame.new(hrp.Position, mob.pos)
        else
            godmodePosicional(mob.model)
        end

        if (Config.AutoFarm or Config.AutoBoss) and (os.clock() - ultimoM1) >= Config.M1_Delay then
            m1(mob)
            ultimoM1 = os.clock()
        end

        if Config.AutoSkill and (os.clock() - ultimoSkill) >= Config.Skill_Delay then
            local s = proximaSkill()
            usarSkill(s, Config.Skill_Slot, mob.pos, mob.model)
            ultimoSkill = os.clock()
        end
    end
end)

-- Auto Tour
task.spawn(function()
    while Ativo do
        task.wait(2)
        if Config.AutoTour and (Config.AutoFarm or Config.AutoBoss or Config.AutoSkill) then
            if #areas == 0 then descobrirAreas() end
            if #areas > 0 then
                if Config.AreaSelecionada then
                    if areaAtual ~= Config.AreaSelecionada then irParaArea(Config.AreaSelecionada) end
                else
                    local n = mobsNaArea(areaAtual, 200)
                    if n == 0 then
                        areaIdx = areaIdx + 1
                        if areaIdx > #areas then areaIdx = 1; descobrirAreas() end
                        local prox = areas[areaIdx]
                        if prox then
                            irParaArea(prox)
                            task.wait(Config.EspaSpawn)
                        end
                    end
                end
                if areaAtual then
                    infoArea.Text = "Área: " .. areaAtual.nome .. "\nMobs: " .. mobsNaArea(areaAtual, 200)
                end
            end
        end
    end
end)

-- Auto Rebirth
task.spawn(function()
    while Ativo do
        task.wait(5)
        if Config.AutoRebirth then
            local pronto = checarRebirth()
            if pronto then
                fazerRebirth()
                task.wait(10)
            end
        end
    end
end)

-- Auto Transform
task.spawn(function()
    while Ativo do
        task.wait(5)
        if Config.AutoTransform and RE_SelectMode then
            pcall(function() RE_SelectMode:FireServer(Config.TransformMode) end)
        end
    end
end)

-- Auto Equip
task.spawn(function()
    while Ativo do
        task.wait(3)
        if Config.AutoEquip and RE_Toolbar then
            pcall(function() RE_Toolbar:FireServer(Config.EquipSlot) end)
        end
    end
end)

-- WalkSpeed
task.spawn(function()
    while Ativo do
        task.wait(0.5)
        if Config.OverrideSpeed then
            local char = plr.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum.WalkSpeed = Config.WalkSpeed end
            end
        end
    end
end)

-- Stats + Rebirth info
task.spawn(function()
    while Ativo do
        local char = plr.Character
        if char then
            local status = char:FindFirstChild("Status")
            if status then
                local cur = status:FindFirstChild("CurrentEnergy")
                local max = status:FindFirstChild("MaxEnergy")
                if cur and max then
                    local pct = max.Value > 0 and (cur.Value / max.Value) or 0
                    local stats = plr:FindFirstChild("Stats")
                    local reb = stats and stats:FindFirstChild("Rebirth")
                    local str = stats and stats:FindFirstChild("Strength")
                    local ki = stats and stats:FindFirstChild("Ki")
                    local endu = stats and stats:FindFirstChild("Endurance")
                    local agi = stats and stats:FindFirstChild("Agility")

                    statsLabel.Text = string.format(
                        "Ki: %d / %d (%.0f%%)\nRebirth: %d\nStrength: %d\nKi Stat: %d\nEndurance: %d\nAgility: %d\n\nWalkSpeed: %d\nFlySpeed: %d",
                        cur.Value, max.Value, pct * 100,
                        reb and reb.Value or 0, str and str.Value or 0,
                        ki and ki.Value or 0, endu and endu.Value or 0, agi and agi.Value or 0,
                        Config.WalkSpeed, Config.FlySpeed
                    )
                end
            end
        end

        local _, info = checarRebirth()
        if info then
            infoRebirth.Text = "Rebirth: " .. info.rebirth ..
                "\nSeus stats: " .. info.total ..
                "\nAlvo (" .. Config.RebirthMultiplier .. "x): " .. info.alvo
        end

        local jobId = game.JobId ~= "" and game.JobId:sub(1, 8) .. "..." or "Privado"
        infoServidor.Text = "Hora: " .. os.date("%H:%M:%S") ..
            "\nServidor: " .. jobId ..
            "\nJogadores: " .. #Players:GetPlayers() ..
            "\nPing: " .. math.floor(plr:GetNetworkPing() * 1000) .. " ms"
        task.wait(2)
    end
end)

print("[DBH] ✅ Dragon Blox Hub v6 carregado com Rayfield AMOLED UI intacta!")
