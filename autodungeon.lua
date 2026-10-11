-- [AUTODUNGEON v0.2] standalone — cola no Delta
_G.AUTODUNGEON_ATIVO = true

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local VIM = game:GetService("VirtualInputManager")
local plr = Players.LocalPlayer

local CFG = {
    DungeonId = 2,
    Difficulty = 1,
    FlySpeed = 300,
    RaioAtaque = 14,
    DistanciaParar = 8,
    AutoTransform = true,
    TransformMode = "SSJAngel",
    AutoLock = true,
}

local function log(msg) print("[AD] " .. msg) end

-- ============================================================
-- KNIT
-- ============================================================
local function getKnitServices()
    local p = RS:FindFirstChild("Packages")
    if not p then return nil end
    local idx = p:FindFirstChild("_Index")
    if not idx then return nil end
    local cands = {}
    for _, f in ipairs(idx:GetChildren()) do
        if f.Name:find("sleitnick_knit") then table.insert(cands, f) end
    end
    table.sort(cands, function(a, b) return a.Name > b.Name end)
    for _, f in ipairs(cands) do
        local k = f:FindFirstChild("knit")
        if k then
            local s = k:FindFirstChild("Services")
            if s then return s end
        end
    end
    return nil
end

local Services = getKnitServices()
local function getRemote(svc, nome, isRF)
    if not Services then return nil end
    local S = Services:FindFirstChild(svc)
    if not S then return nil end
    local sub = S:FindFirstChild(isRF and "RF" or "RE")
    if not sub then return nil end
    return sub:FindFirstChild(nome)
end

local CreateLobby       = getRemote("DungeonLobbyService", "CreateLobby", true)
local StartDungeon      = getRemote("DungeonLobbyService", "StartDungeon", true)
local ExecuteSkill      = getRemote("SkillManagerV2", "ExecuteSkill", false)
local ExecuteSkill_Sp   = getRemote("SkillManagerV2", "ExecuteSkill_Special", false)
local LockedOnRemote    = getRemote("SkillManager", "LockedOnChanged", false)
local ToolbarRemote     = getRemote("ToolService", "UpdatePlayerToolbarSelection", false)
local SelectMode        = getRemote("ModeTransformService", "SelectMode", false)

if not CreateLobby then warn("[AD] Knit não encontrado") return end

-- ============================================================
-- UTIL
-- ============================================================
local function getHRP()
    local c = plr.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function safe(fn)
    local ok, err = pcall(fn)
    if not ok then warn("[AD] " .. tostring(err)) end
    return ok
end

-- ============================================================
-- VOO
-- ============================================================
local _bp, _bg

local function voarPara(destino, semGravidade)
    local hrp = getHRP()
    if not hrp then return end

    if not _bp or _bp.Parent ~= hrp then
        if _bp then _bp:Destroy() end
        _bp = Instance.new("BodyPosition")
        _bp.P = 10000
        _bp.Parent = hrp
    end
    if not _bg or _bg.Parent ~= hrp then
        if _bg then _bg:Destroy() end
        _bg = Instance.new("BodyGyro")
        _bg.P = 10000
        _bg.D = 500
        _bg.MaxTorque = Vector3.new(44550, 44550, 44550)
        _bg.Parent = hrp
    end

    _bp.MaxForce = semGravidade
        and Vector3.new(50000, 50000, 50000)
        or Vector3.new(50000, 0, 50000)
    _bp.Position = destino
    _bg.CFrame = CFrame.lookAt(hrp.Position, destino)
end

local function pararVoo()
    if _bp then _bp:Destroy(); _bp = nil end
    if _bg then _bg:Destroy(); _bg = nil end
end

-- ============================================================
-- PROMPT
-- ============================================================
local function acharPromptMaisProximo()
    local hrp = getHRP()
    if not hrp then return nil end
    local myPos = hrp.Position
    local melhor, melhorD = nil, math.huge
    for _, d in ipairs(WS:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Enabled ~= false then
            local parent = d.Parent
            local pos
            if parent:IsA("BasePart") then pos = parent.Position
            elseif parent.PrimaryPart then pos = parent.PrimaryPart.Position
            elseif parent:FindFirstChildWhichIsA("BasePart") then
                pos = parent:FindFirstChildWhichIsA("BasePart").Position
            end
            if pos then
                local dist = (pos - myPos).Magnitude
                if dist < melhorD then
                    melhor = { prompt = d, pos = pos, nome = parent:GetFullName(), hold = d.HoldDuration or 0 }
                    melhorD = dist
                end
            end
        end
    end
    return melhor, melhorD
end

local function acionarPrompt(info)
    if not info then return false end
    if fireproximityprompt then
        local ok = pcall(function() fireproximityprompt(info.prompt) end)
        if ok then log("fireproximityprompt OK"); return true end
    end
    if info.hold > 0 then task.wait(info.hold + 0.15) end
    safe(function() VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game) end)
    task.wait(0.15)
    safe(function() VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
    log("VIM E enviado")
    return true
end

-- ============================================================
-- FINDER DE MOBS (agora varre o Workspace inteiro)
-- ============================================================
local _conhecidos = setmetatable({}, {__mode = "k"})

local function ehMob(model)
    if not model:IsA("Model") then return false end
    if not model:FindFirstChild("Humanoid") then return false end
    if not model:FindFirstChild("HumanoidRootPart") then return false end
    return true
end

local function categoriaMob(mob)
    -- Sobe a árvore pra descobrir de qual pasta veio
    local p = mob.Parent
    while p and p ~= WS do
        local nome = p.Name
        if nome == "Mobs" or nome == "Boss Mobs" or nome == "Event Mobs" then
            return nome
        end
        p = p.Parent
    end
    return nil
end

local function listarMobs()
    local out = {}
    -- Varre Workspace inteiro
    for _, d in ipairs(WS:GetDescendants()) do
        if ehMob(d) then
            local cat = categoriaMob(d)
            if cat then
                local hum = d:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    out[#out+1] = d
                end
            end
        end
    end
    return out
end

local function mobMaisProximo()
    local hrp = getHRP()
    if not hrp then return nil end
    local myPos = hrp.Position
    local melhor, melhorD = nil, math.huge
    for _, m in ipairs(listarMobs()) do
        local mh = m:FindFirstChild("HumanoidRootPart")
        if mh then
            local d = (mh.Position - myPos).Magnitude
            if d < melhorD then melhor, melhorD = m, d end
        end
    end
    return melhor, melhorD
end

-- Debug helper: lista o que existe
local function debugMobs()
    log("--- DEBUG MOBS ---")
    local total = 0
    for _, d in ipairs(WS:GetDescendants()) do
        if d:IsA("Model") and d:FindFirstChild("Humanoid") then
            total = total + 1
            local cat = categoriaMob(d) or "?"
            local hum = d:FindFirstChildOfClass("Humanoid")
            local hp = hum and hum.Health or "?"
            log(string.format("  [%s] %s | HP=%s | %s", cat, d.Name, tostring(hp), d:GetFullName()))
        end
    end
    log("Total: " .. total)
end

-- ============================================================
-- TRANSFORMAÇÃO
-- ============================================================
local _transformado = false
local _ultimaChecagem = 0

local function checarTransformacao()
    if not CFG.AutoTransform or not SelectMode then return end
    if tick() - _ultimaChecagem < 5 then return end
    _ultimaChecagem = tick()

    local c = plr.Character
    if not c then return end
    local status = c:FindFirstChild("Status")
    if not status then return end

    -- Procura marcador de modo ativo
    local modo = nil
    for _, nome in ipairs({"CurrentMode", "FormName", "Mode", "Transform"}) do
        local v = status:FindFirstChild(nome)
        if v and v:IsA("StringValue") and v.Value ~= "" then
            modo = v.Value
            break
        end
    end

    if modo and modo ~= "" then
        if not _transformado then
            log("Transformação detectada: " .. modo)
            _transformado = true
        end
        return
    end

    -- Não tá transformado — manda SelectMode
    log("Ativando " .. CFG.TransformMode)
    safe(function() SelectMode:FireServer(CFG.TransformMode) end)
    _transformado = true
end

-- ============================================================
-- COMBATE
-- ============================================================
local _ultimaSkill = nil
local _slotAtual = 2

local function equiparSlot(slot)
    if slot == _slotAtual then return end
    if ToolbarRemote then
        safe(function() ToolbarRemote:FireServer(slot) end)
        _slotAtual = slot
        task.wait(0.3)
    end
end

local function lockOn(mob)
    if not CFG.AutoLock then return end
    if LockedOnRemote then
        safe(function() LockedOnRemote:FireServer(mob) end)
    end
end

local function unlock()
    if LockedOnRemote then
        safe(function() LockedOnRemote:FireServer(nil) end)
    end
end

local function usarSkill(nome, params, slot, pause)
    if not ExecuteSkill then return end
    if slot and slot ~= _slotAtual then equiparSlot(slot) end

    if _ultimaSkill ~= nome and ExecuteSkill_Sp then
        safe(function() ExecuteSkill_Sp:FireServer(plr.Name, nome) end)
        _ultimaSkill = nome
        task.wait(0.12)
    end

    safe(function() ExecuteSkill:FireServer(nome, params, 1, true) end)
    task.wait(pause or 0.6)
    safe(function() ExecuteSkill:FireServer(nome, params, 1, false) end)
end

local function getAnim(nomeAnim)
    local assets = RS:FindFirstChild("Assets")
    if not assets then return nil end
    local skillsV2 = assets:FindFirstChild("SkillsV2")
    if not skillsV2 then return nil end
    local weapons = skillsV2:FindFirstChild("Weapons")
    local sets = skillsV2:FindFirstChild("UniqueSets")
    -- Tenta achar por nome
    for _, root in ipairs({weapons, sets}) do
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("Animation") and d.Name == nomeAnim then return d end
            end
        end
    end
    return nil
end

-- Scythe slash (Weapons_3_2)
local function scytheSlash(mob)
    local hrp = getHRP()
    local mh = mob and mob:FindFirstChild("HumanoidRootPart")
    if not hrp or not mh then return end
    local params = {
        targetPos = mh.Position,
        HumCFrame = hrp.CFrame,
        ResumeOnTimePassed = 0.633,
        PauseTimeFrame = 0.616,
        animationSpeed = 1,
    }
    local anim = getAnim("Dimensional Slash")
    if anim then params.animationInstance = anim end
    usarSkill("Weapons_3_2", params, 2, 0.65)
end

-- Scythe sweep (Weapons_3_3)
local function scytheSweep()
    local hrp = getHRP()
    if not hrp then return end
    usarSkill("Weapons_3_3", { CFrame = hrp.CFrame }, 2, 0.5)
end

-- Galick Gun (UniqueSets_1_1)
local function galickGun(mob)
    local hrp = getHRP()
    local mh = mob and mob:FindFirstChild("HumanoidRootPart")
    if not hrp or not mh then return end
    local params = {
        targetPos = mh.Position,
        HumCFrame = hrp.CFrame,
        PauseTimeFrame = 0.35,
        ResumeOnTimePassed = 1,
        animationSpeed = 1,
    }
    local anim = getAnim("Galick Gun")
    if anim then params.animationInstance = anim end
    usarSkill("UniqueSets_1_1", params, 1, 0.4)
end

-- Melee (UniqueSets_1_2)
local function meleeSet(mob)
    local hrp = getHRP()
    if not hrp then return end
    usarSkill("UniqueSets_1_2", { HumCFrame = hrp.CFrame, Target = mob }, 1, 0.6)
end

-- Big Bang (UniqueSets_1_3)
local function bigBang(mob)
    local hrp = getHRP()
    local mh = mob and mob:FindFirstChild("HumanoidRootPart")
    if not hrp or not mh then return end
    local params = {
        targetPos = mh.Position,
        HumCFrame = hrp.CFrame,
        PauseTimeFrame = 0.75,
        ResumeOnTimePassed = 0.1,
        animationSpeed = 1,
    }
    local anim = getAnim("Big Bang Attack")
    if anim then params.animationInstance = anim end
    usarSkill("UniqueSets_1_3", params, 1, 0.8)
end

-- M1 spam
local function M1(mob)
    local SkillRemote = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("SkillRemote")
    local hrp = getHRP()
    if not SkillRemote or not hrp or not mob then return end
    local mh = mob:FindFirstChild("HumanoidRootPart")
    if not mh then return end
    local cam = workspace.CurrentCamera
    local camCF = cam and cam.CFrame or CFrame.new()
    safe(function()
        SkillRemote:FireServer({
            Began = true, CFrame = hrp.CFrame, Aim = mh.Position,
            Camera = camCF, Type = 1, SkillId = "1",
        })
    end)
    task.wait(0.05)
    safe(function()
        SkillRemote:FireServer({
            Began = false, CFrame = hrp.CFrame, Aim = mh.Position,
            Camera = camCF, Type = 1, SkillId = "1",
        })
    end)
end

-- ============================================================
-- ROTAÇÃO DE SKILLS (padrão do target)
-- ============================================================
-- Alterna entre scythe/punhos por ciclo, com M1 entre skills
local _rotIdx = 1
local ROTACAO = {
    { tipo = "scythe_slash", slot = 2, pause = 0.65 },
    { tipo = "scythe_sweep", slot = 2, pause = 0.5 },
    { tipo = "galick",       slot = 1, pause = 0.4 },
    { tipo = "melee",        slot = 1, pause = 0.6 },
    { tipo = "big_bang",     slot = 1, pause = 0.8 },
    { tipo = "m1",           slot = nil, pause = 0.1 },
}

local function executarRotacao(mob)
    local passo = ROTACAO[_rotIdx]
    _rotIdx = _rotIdx + 1
    if _rotIdx > #ROTACAO then _rotIdx = 1 end

    if passo.tipo == "scythe_slash" then scytheSlash(mob)
    elseif passo.tipo == "scythe_sweep" then scytheSweep()
    elseif passo.tipo == "galick" then galickGun(mob)
    elseif passo.tipo == "melee" then meleeSet(mob)
    elseif passo.tipo == "big_bang" then bigBang(mob)
    elseif passo.tipo == "m1" then M1(mob)
    end
end

-- ============================================================
-- COMBATE NO MOB
-- ============================================================
local function combaterMob(mob)
    if not mob or not mob.Parent then return end
    local hrp = getHRP()
    local mh = mob:FindFirstChild("HumanoidRootPart")
    if not hrp or not mh then return end

    -- Posiciona em cima do mob (+6Y)
    local destino = mh.Position + Vector3.new(0, 6, 0)
    voarPara(destino, true)
    lockOn(mob)

    local inicio = tick()
    while mob.Parent and _G.AUTODUNGEON_ATIVO do
        local hum = mob:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then break end
        if tick() - inicio > 25 then break end

        -- Atualiza posição
        local mh2 = mob:FindFirstChild("HumanoidRootPart")
        if mh2 and hrp then
            local d = (mh2.Position - hrp.Position).Magnitude
            if d > CFG.RaioAtaque then
                voarPara(mh2.Position + Vector3.new(0, 6, 0), true)
            end
        end

        -- Executa passo da rotação
        executarRotacao(mob)
        task.wait(0.1)
    end

    pararVoo()
    unlock()
end

-- ============================================================
-- LOOP DUNGEON
-- ============================================================
local function combaterDungeon()
    log("Combate iniciado")
    debugMobs()  -- roda uma vez pra ver o que tem

    local _semMobs = 0
    while _G.AUTODUNGEON_ATIVO do
        checarTransformacao()

        local mob, dist = mobMaisProximo()
        if mob then
            _semMobs = 0
            log(string.format("Mob: %s (%.0f studs)", mob.Name, dist or 0))
            combaterMob(mob)
        else
            _semMobs = _semMobs + 1
            if _semMobs >= 8 then
                log("Dungeon concluída (sem mobs)")
                break
            end
        end
        task.wait(0.5)
    end
    pararVoo()
end

-- ============================================================
-- ENTRY
-- ============================================================
local function irAoPad()
    local info, dist = acharPromptMaisProximo()
    if not info then return false end
    log(string.format("Pad: %s (%.0f studs)", info.nome, dist))

    local destino = info.pos + Vector3.new(0, 5, 0)
    local inicio = tick()
    while tick() - inicio < 20 and _G.AUTODUNGEON_ATIVO do
        local hrp = getHRP()
        if not hrp then break end
        if (destino - hrp.Position).Magnitude < 4 then break end
        voarPara(destino, false)
        task.wait(0.1)
    end
    pararVoo()

    local hrp = getHRP()
    if hrp then
        hrp.CFrame = CFrame.new(info.pos + Vector3.new(0, 3, 0))
        task.wait(0.35)
    end
    return true
end

local function iniciarDungeon()
    log("Entrando na dungeon")
    if not irAoPad() then return false end

    local info = acharPromptMaisProximo()
    if info then acionarPrompt(info) end
    task.wait(0.6)

    local args = { DungeonIdSelected = CFG.DungeonId, DungeonStats = { Difficulty = CFG.Difficulty } }

    safe(function()
        local ret = CreateLobby:InvokeServer(args)
        log("CreateLobby: " .. tostring(ret))
    end)
    task.wait(0.4)
    safe(function()
        local ret = StartDungeon:InvokeServer(args)
        log("StartDungeon: " .. tostring(ret))
    end)
    return true
end

-- ============================================================
-- DETECÇÃO
-- ============================================================
local function estaEmDungeon()
    for _, d in ipairs(WS:GetChildren()) do
        if d.Name:find("Dungeon") then return true end
    end
    return false
end

-- ============================================================
-- MAIN
-- ============================================================
local function main()
    log("AutoDungeon v0.2 | PlaceId: " .. game.PlaceId)
    task.wait(2)

    if estaEmDungeon() then
        log("Dungeon detectada")
        combaterDungeon()
    else
        log("Main place — entry")
        if iniciarDungeon() then
            local inicio = tick()
            while _G.AUTODUNGEON_ATIVO and tick() - inicio < 15 do
                task.wait(1)
                if estaEmDungeon() then
                    combaterDungeon()
                    return
                end
            end
            log("Teleporte não rolou")
        end
    end
end

main()
