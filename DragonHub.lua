-- [CORE]
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VIM = game:GetService("VirtualInputManager")
local plr = Players.LocalPlayer
local Ativo = true

-- [REMOTES]
local function getKnit()
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

local function getR(svc, name, isRF)
    local s = getKnit() if not s then return nil end
    local S = s:FindFirstChild(svc) if not S then return nil end
    local sub = S:FindFirstChild(isRF and "RF" or "RE") if not sub then return nil end
    return sub:FindFirstChild(name)
end

local RE_ExecuteSkill        = getR("SkillManagerV2", "ExecuteSkill", false)
local RE_ExecuteSkillSpecial = getR("SkillManagerV2", "ExecuteSkill_Special", false)
local RE_LockedOn            = getR("SkillManager", "LockedOnChanged", false)
local RE_Prompt              = getR("PromptService", "Prompt", false)
local RF_Rebirth             = getR("PlayerLevelService", "RequestRebirth", true)
local RE_SuperFlight         = getR("FlightService", "SuperFlight", false)
local SkillRemote            = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("SkillRemote")

-- [CONFIG]
local Config = {
    AutoFarm = false,
    AutoM1 = true,
    AutoBoss = false,
    AutoSkill = false,
    AutoLock = true,
    ESPMobs = false,
    ESPDrops = true,
    AutoCollect = false,
    AutoRebirth = false,
    RebirthMult = 3,
    Noclip = false,
    FlySpeed = 120,
    WalkSpeed = 16,
    OverrideSpeed = false,
    M1_Range = 12,
    M1_Delay = 0.35,
    Skill_Delay = 1.5,
    MobAlvo = nil,
}

local KiCfg = { Limite = 0.30, Alvo = 0.95, TempoMax = 5, Recarregando = false }

-- [HELPERS]
local function getChar()
    local c = plr.Character
    if not c then return nil end
    local h = c:FindFirstChild("HumanoidRootPart")
    return c, h, c:FindFirstChildOfClass("Humanoid")
end

local function listarMobs()
    local seen = {}
    local wm = WS:FindFirstChild("World Mobs")
    if not wm then return {"(todos)"} end
    for _, p in ipairs(wm:GetChildren()) do
        if p:IsA("Folder") or p:IsA("Model") then
            for _, m in ipairs(p:GetChildren()) do
                if m:IsA("Model") and m:FindFirstChild("Humanoid") then
                    local b = m.Name:gsub("%-?%d+$", "")
                    seen[b] = true
                end
            end
        end
    end
    local lista = {"(todos)"}
    for k in pairs(seen) do table.insert(lista, k) end
    table.sort(lista, function(a, b)
        if a == "(todos)" then return true end
        if b == "(todos)" then return false end
        return a < b
    end)
    return lista
end

local function getMob()
    local _, hrp = getChar()
    if not hrp then return nil end
    local myPos = hrp.Position
    local melhor, minD = nil, math.huge

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
                    if valido and Config.MobAlvo and base ~= Config.MobAlvo then valido = false end
                    if valido then
                        local d = (mob.HumanoidRootPart.Position - myPos).Magnitude
                        if d < minD then
                            minD = d
                            melhor = {
                                model = mob,
                                baseName = base,
                                pos = mob.HumanoidRootPart.Position,
                                dist = d,
                                isBoss = isBoss,
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
        checar(wm:FindFirstChild("Event Mobs"), true)
    end
    return melhor
end

-- [MOVIMENTO]
local function pararVoo()
    local _, hrp = getChar()
    if not hrp then return end
    local bv = hrp:FindFirstChild("__bv")
    local bg = hrp:FindFirstChild("__bg")
    if bv then bv:Destroy() end
    if bg then bg:Destroy() end
end

local function voarPara(pos, speed)
    local _, hrp = getChar()
    if not hrp then return end
    speed = speed or Config.FlySpeed

    local bv = hrp:FindFirstChild("__bv") or Instance.new("BodyVelocity")
    bv.Name = "__bv"
    bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    bv.Parent = hrp

    local bg = hrp:FindFirstChild("__bg") or Instance.new("BodyGyro")
    bg.Name = "__bg"
    bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    bg.P = 10000
    bg.Parent = hrp

    local dir = pos - hrp.Position
    if dir.Magnitude > 5 then
        local spd = math.min(speed, dir.Magnitude * 3)
        bv.Velocity = dir.Unit * spd
        bg.CFrame = CFrame.new(hrp.Position, pos)
    else
        bv.Velocity = Vector3.zero
    end
end

-- [LOCK]
local lockConexao, lockAlvo
local function pararLock()
    if lockConexao then lockConexao:Disconnect(); lockConexao = nil end
    lockAlvo = nil
end

local function lockOn(mobModel)
    if RE_LockedOn then pcall(function() RE_LockedOn:FireServer(mobModel) end) end
    pararLock()
    if not mobModel or not mobModel:FindFirstChild("HumanoidRootPart") then return end
    lockAlvo = mobModel
    lockConexao = RunService.RenderStepped:Connect(function()
        if not lockAlvo or not lockAlvo.Parent then pararLock() return end
        local mh = lockAlvo:FindFirstChild("HumanoidRootPart")
        local hum = lockAlvo:FindFirstChildOfClass("Humanoid")
        if not mh or not hum or hum.Health <= 0 then pararLock() return end
        local cam = workspace.CurrentCamera
        if cam then cam.CFrame = CFrame.lookAt(cam.CFrame.Position, mh.Position) end
    end)
end

-- [M1 — SkillId="1"]
local function m1(alvo)
    if not SkillRemote then return end
    local _, hrp = getChar()
    if not hrp then return end
    local cam = workspace.CurrentCamera
    local aim = alvo and alvo.pos or (hrp.Position + hrp.CFrame.LookVector * 10)
    local camCF = cam and cam.CFrame or hrp.CFrame

    pcall(function()
        SkillRemote:FireServer({
            Began = true, CFrame = hrp.CFrame, Aim = aim,
            Camera = camCF, Type = 1, SkillId = "1",
        })
    end)
    task.wait(0.05)
    pcall(function()
        SkillRemote:FireServer({
            Began = false, CFrame = hrp.CFrame, Aim = aim,
            Camera = camCF, Type = 1, SkillId = "1",
        })
    end)
end

-- [SKILL]
local SkillList = {"UniqueSets_2_1", "UniqueSets_2_2", "UniqueSets_2_3", "Weapons_3_2", "Weapons_3_3"}
local skillIdx = 0
local ultimaSpecial = nil

local function proximaSkill()
    skillIdx = skillIdx + 1
    if skillIdx > #SkillList then skillIdx = 1 end
    return SkillList[skillIdx]
end

local function usarSkill(skillId, alvo)
    local c, hrp = getChar()
    if not c or not hrp or not RE_ExecuteSkill then return end

    if skillId ~= ultimaSpecial and RE_ExecuteSkillSpecial then
        pcall(function() RE_ExecuteSkillSpecial:FireServer(c, skillId) end)
        ultimaSpecial = skillId
        task.wait(0.08)
    end

    local params = {}
    if skillId:find("UniqueSets") then
        local ok, f = pcall(function()
            return RS.Assets.SkillsV2.UniqueSets["Seijin Instinct"].Animations
        end)
        if ok and f then
            local anim = skillId:find("_2_1") and "Kamehameha"
                or skillId:find("_2_3") and "SpiritBomb" or nil
            if anim then
                params = {
                    HoldAnimation = f:FindFirstChild("Hold_" .. anim),
                    ReleaseAnimation = f:FindFirstChild("Release_" .. anim),
                    HumCFrame = hrp.CFrame,
                    ResumeOnTimePassed = (anim == "Kamehameha") and 3 or 0.1,
                    targetPos = alvo and alvo.pos or (hrp.Position + hrp.CFrame.LookVector * 10),
                }
            else
                params = { HumCFrame = hrp.CFrame, Target = alvo and alvo.model or nil }
            end
        end
    elseif skillId == "Weapons_3_2" then
        params = {
            targetPos = alvo and alvo.pos or (hrp.Position + hrp.CFrame.LookVector * 10),
            PauseTimeFrame = 0.616, animationSpeed = 1,
            ResumeOnTimePassed = 0.633, HumCFrame = hrp.CFrame,
        }
    elseif skillId == "Weapons_3_3" then
        params = { CFrame = hrp.CFrame }
    end

    pcall(function() RE_ExecuteSkill:FireServer(skillId, params, 1, true) end)
    task.wait(0.3)
    pcall(function() RE_ExecuteSkill:FireServer(skillId, params, 1, false) end)
end

-- [KI]
local function getKi()
    local c = plr.Character
    if not c then return 0, 0 end
    local st = c:FindFirstChild("Status")
    if not st then return 0, 0 end
    local cur = st:FindFirstChild("CurrentEnergy")
    local max = st:FindFirstChild("MaxEnergy")
    if not cur or not max then return 0, 0 end
    return cur.Value, max.Value
end

local function recarregarKi()
    if KiCfg.Recarregando then return end
    KiCfg.Recarregando = true
    local c, hrp = getChar()
    if not c or not hrp then KiCfg.Recarregando = false return end

    local mob = getMob()
    if mob and mob.dist < 40 then
        voarPara(hrp.Position + (hrp.Position - mob.pos).Unit * 40, 100)
        task.wait(0.5)
    end

    local inicio = os.clock()
    VIM:SendKeyEvent(true, Enum.KeyCode.C, false, game)
    while KiCfg.Recarregando and Ativo do
        local cur, max = getKi()
        local pct = max > 0 and (cur / max) or 0
        if pct >= KiCfg.Alvo then break end
        if (os.clock() - inicio) >= KiCfg.TempoMax then break end
        task.wait(0.15)
    end
    VIM:SendKeyEvent(false, Enum.KeyCode.C, false, game)
    KiCfg.Recarregando = false
    task.wait(0.3)
end

-- [REBIRTH]
local function fazerRebirth()
    if RE_Prompt then
        pcall(function()
            RE_Prompt:FireServer({
                UniqueTag = "HudRebirth", Title = "Rebirth",
                LeftButton = "Details", MiddleButton = "Confirm",
                Prompt = "HudRebirth", RightButton = "Cancel",
                Description = "Confirm Rebirth?",
            }, "Confirm")
        end)
    end
    task.wait(0.4)
    if RF_Rebirth then
        pcall(function() RF_Rebirth:InvokeServer(true) end)
    end
end

local function checarRebirth()
    local st = plr:FindFirstChild("Stats")
    if not st then return false, nil end
    local reb = st:FindFirstChild("Rebirth")
    local str = st:FindFirstChild("Strength")
    local ki = st:FindFirstChild("Ki")
    if not reb or not str or not ki then return false, nil end
    local total = str.Value + ki.Value
    local minimo = (reb.Value * 3000000) + 2000000
    local alvo = minimo * Config.RebirthMult
    return total >= alvo, { reb = reb.Value, total = total, alvo = alvo }
end

-- [AUTOCOLLECT]
local coletando = false

local function tentarColetar()
    if coletando then return end
    local c, hrp = getChar()
    if not c or not hrp then return end
    local ps = WS:FindFirstChild("PartStorage")
    if not ps then return end

    for _, item in ipairs(ps:GetChildren()) do
        if item.Name:find("ItemDrop_") then
            local drop = item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")
            if drop then
                coletando = true
                voarPara(drop.Position, 200)
                task.wait(1)
                c.HumanoidRootPart.CFrame = CFrame.new(drop.Position)
                task.wait(0.5)
                coletando = false
                return
            end
        end
    end
end

-- [ESP]
local espGui = Instance.new("ScreenGui")
espGui.Name = "DBH_ESP"
espGui.ResetOnSpawn = false
espGui.Parent = CoreGui

local dropESP = {}
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
                        bb.Size = UDim2.new(0, 140, 0, 30)
                        bb.StudsOffset = Vector3.new(0, 4, 0)
                        bb.AlwaysOnTop = true
                        bb.Adornee = base
                        bb.Parent = espGui
                        local l = Instance.new("TextLabel", bb)
                        l.Size = UDim2.new(1, 0, 1, 0)
                        l.BackgroundTransparency = 1
                        l.Text = "💎 " .. item.Name
                        l.TextColor3 = Color3.fromRGB(255, 200, 60)
                        l.TextStrokeTransparency = 0.5
                        l.Font = Enum.Font.GothamBold
                        l.TextSize = 12
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

local espCache = {}
local function criarESP(mob)
    local hrp = mob:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0, 140, 0, 30)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Adornee = hrp
    bb.Parent = espGui
    local n = Instance.new("TextLabel", bb)
    n.Size = UDim2.new(1, 0, 1, 0)
    n.BackgroundTransparency = 1
    n.TextColor3 = (mob.Parent and mob.Parent.Name == "Boss Mobs") and Color3.fromRGB(255, 80, 80)
        or (mob.Parent and mob.Parent.Name == "Event Mobs") and Color3.fromRGB(200, 80, 255)
        or Color3.fromRGB(255, 200, 80)
    n.TextStrokeTransparency = 0.5
    n.TextSize = 12
    n.Font = Enum.Font.GothamBold
    n.Text = mob.Name
    espCache[mob] = bb
end

local function removerESP(mob)
    if espCache[mob] then espCache[mob]:Destroy(); espCache[mob] = nil end
end

-- [UI]
local UI = {}
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

local function I(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end
local function corner(o, r)
    return I("UICorner", { CornerRadius = r or UDim.new(0, 7) }, o)
end

local gui, mainFrame, floatBtn
function UI.newWindow()
    gui = I("ScreenGui", { Name = "DragonBloxHub", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, CoreGui)
    local m = I("Frame", {
        Size = UDim2.new(0, 400, 0, 320),
        Position = UDim2.new(0.5, -200, 0.5, -160),
        BackgroundColor3 = T.bg,
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        Active = true,
    }, gui)
    corner(m, UDim.new(0, 10))
    I("UIStroke", { Color = T.border, Thickness = 1 }, m)

    local header = I("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.panel, BorderSizePixel = 0 }, m)
    corner(header, UDim.new(0, 10))
    I("TextLabel", {
        Size = UDim2.new(1, -70, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Text = "🐉 Dragon Blox",
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

    local side = I("Frame", { Size = UDim2.new(0, 100, 1, -30), Position = UDim2.new(0, 0, 0, 30), BackgroundColor3 = T.panel, BorderSizePixel = 0 }, m)
    I("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, side)
    I("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, side)

    local content = I("Frame", { Size = UDim2.new(1, -100, 1, -30), Position = UDim2.new(0, 100, 0, 30), BackgroundColor3 = T.bg, BorderSizePixel = 0 }, m)

    local drag, ds, ss = false, nil, nil
    header.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            drag = true; ds = i.Position; ss = m.Position
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - ds
            m.Position = UDim2.new(ss.X.Scale, ss.X.Offset + d.X, ss.Y.Scale, ss.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = false end
    end)

    floatBtn = I("TextButton", {
        Size = UDim2.new(0, 46, 0, 46),
        Position = UDim2.new(0, 20, 0.4, 0),
        BackgroundColor3 = T.bg,
        Text = "🐉",
        TextColor3 = T.accent,
        Font = Enum.Font.GothamBold,
        TextSize = 20,
        AutoButtonColor = false,
        Visible = false,
        Active = true,
        Draggable = true,
        BorderSizePixel = 0,
    }, gui)
    corner(floatBtn, UDim.new(1, 0))
    I("UIStroke", { Color = T.accent, Thickness = 1 }, floatBtn)

    btnMin.MouseButton1Click:Connect(function() m.Visible = false; floatBtn.Visible = true end)
    floatBtn.MouseButton1Click:Connect(function() m.Visible = true; floatBtn.Visible = false end)
    btnKill.MouseButton1Click:Connect(function()
        Ativo = false
        if gui then gui:Destroy() end
        if espGui then espGui:Destroy() end
    end)

    return { frame = m, sidebar = side, content = content, tabs = {} }
end

function UI.newTab(win, icon, name)
    local b = I("TextButton", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = T.panel,
        TextColor3 = T.dim,
        Font = Enum.Font.Gotham,
        TextSize = 10,
        Text = " " .. icon .. "  " .. name,
        TextXAlignment = Enum.TextXAlignment.Left,
        BorderSizePixel = 0,
        AutoButtonColor = false,
    }, win.sidebar)
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
    }, win.content)
    local l = I("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, f)
    I("UIPadding", { PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2) }, f)
    l:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        f.CanvasSize = UDim2.new(0, 0, 0, l.AbsoluteContentSize.Y + 18)
    end)

    b.MouseButton1Click:Connect(function()
        for _, t in pairs(win.tabs) do
            t.btn.BackgroundColor3 = T.panel
            t.btn.TextColor3 = T.dim
            t.frame.Visible = false
        end
        b.BackgroundColor3 = T.elev
        b.TextColor3 = T.accent
        f.Visible = true
    end)

    local tab = { btn = b, frame = f }
    win.tabs[name] = tab
    return tab
end

function UI.section(tab, txt)
    return I("TextLabel", {
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        Text = txt,
        TextColor3 = T.accent,
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, tab.frame)
end

function UI.toggle(tab, opts)
    local st = opts.default or false
    local f = I("TextButton", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = T.elev,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
    }, tab.frame)
    corner(f, UDim.new(0, 7))
    I("TextLabel", {
        Size = UDim2.new(1, -60, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Text = opts.name,
        TextColor3 = T.text,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, f)
    local sw = I("Frame", {
        Size = UDim2.new(0, 36, 0, 20),
        Position = UDim2.new(1, -46, 0.5, -10),
        BackgroundColor3 = st and T.success or T.off,
        BorderSizePixel = 0,
    }, f)
    corner(sw, UDim.new(1, 0))
    local kn = I("Frame", {
        Size = UDim2.new(0, 16, 0, 16),
        Position = st and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, sw)
    corner(kn, UDim.new(1, 0))
    local function set(v)
        st = v
        sw.BackgroundColor3 = v and T.success or T.off
        kn.Position = v and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    end
    f.MouseButton1Click:Connect(function()
        set(not st)
        if opts.callback then opts.callback(st) end
    end)
    return { set = set }
end

function UI.slider(tab, opts)
    local min, max = opts.min or 0, opts.max or 100
    local val = opts.default or min
    local suf = opts.suffix or ""

    local f = I("Frame", {
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = T.elev,
        BorderSizePixel = 0,
    }, tab.frame)
    corner(f, UDim.new(0, 7))
    I("TextLabel", {
        Size = UDim2.new(1, -80, 0, 20),
        Position = UDim2.new(0, 10, 0, 4),
        BackgroundTransparency = 1,
        Text = opts.name,
        TextColor3 = T.text,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, f)
    local vl = I("TextLabel", {
        Size = UDim2.new(0, 70, 0, 20),
        Position = UDim2.new(1, -80, 0, 4),
        BackgroundTransparency = 1,
        Text = tostring(val) .. suf,
        TextColor3 = T.accent,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, f)
    local tr = I("Frame", {
        Size = UDim2.new(1, -20, 0, 5),
        Position = UDim2.new(0, 10, 0, 30),
        BackgroundColor3 = T.border,
        BorderSizePixel = 0,
    }, f)
    corner(tr, UDim.new(1, 0))
    local fi = I("Frame", {
        Size = UDim2.new((val - min) / (max - min), 0, 1, 0),
        BackgroundColor3 = T.accent,
        BorderSizePixel = 0,
    }, tr)
    corner(fi, UDim.new(1, 0))
    local drag = false
    local function upd(x)
        local rel = math.clamp((x - tr.AbsolutePosition.X) / tr.AbsoluteSize.X, 0, 1)
        local v = math.floor(min + (max - min) * rel + 0.5)
        fi.Size = UDim2.new(rel, 0, 1, 0)
        vl.Text = tostring(v) .. suf
        val = v
        if opts.callback then opts.callback(v) end
    end
    tr.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            drag = true; upd(i.Position.X)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            upd(i.Position.X)
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            drag = false
        end
    end)
end

function UI.button(tab, opts)
    local b = I("TextButton", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = T.elev,
        Text = opts.name,
        TextColor3 = T.text,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        BorderSizePixel = 0,
        AutoButtonColor = true,
    }, tab.frame)
    corner(b, UDim.new(0, 7))
    b.MouseButton1Click:Connect(function()
        if opts.callback then opts.callback() end
    end)
end

function UI.label(tab, opts)
    local l = I("TextLabel", {
        Size = UDim2.new(1, 0, 0, opts.height or 50),
        BackgroundColor3 = T.elev,
        TextColor3 = T.text,
        Font = Enum.Font.Code,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        Text = opts.text or "",
    }, tab.frame)
    corner(l, UDim.new(0, 7))
    I("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6) }, l)
    return l
end

function UI.dropdown(tab, opts)
    local cur = opts.default or "(todos)"
    local b = I("TextButton", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = T.elev,
        Text = "  " .. opts.name .. ": " .. cur,
        TextColor3 = T.text,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        BorderSizePixel = 0,
        AutoButtonColor = false,
    }, tab.frame)
    corner(b, UDim.new(0, 7))
    local function upd() b.Text = "  " .. opts.name .. ": " .. cur end
    b.MouseButton1Click:Connect(function()
        local pop = I("Frame", {
            Size = UDim2.new(0, 220, 0, 260),
            Position = UDim2.new(0.5, -110, 0.5, -130),
            BackgroundColor3 = T.panel,
            BorderSizePixel = 0,
            ZIndex = 100,
            Active = true,
        }, gui)
        corner(pop, UDim.new(0, 10))
        I("UIStroke", { Color = T.accent, Thickness = 1 }, pop)
        I("TextLabel", {
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundTransparency = 1,
            Text = opts.name,
            TextColor3 = T.accent,
            Font = Enum.Font.GothamBold,
            TextSize = 12,
        }, pop)
        local sc = I("ScrollingFrame", {
            Size = UDim2.new(1, -14, 1, -44),
            Position = UDim2.new(0, 7, 0, 26),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = T.border,
            CanvasSize = UDim2.new(0, 0, 0, 0),
        }, pop)
        local ll = I("UIListLayout", { Padding = UDim.new(0, 3) }, sc)
        local lista = opts.options
        if type(lista) == "function" then lista = lista() end
        for _, opt in ipairs(lista) do
            local ob = I("TextButton", {
                Size = UDim2.new(1, 0, 0, 28),
                BackgroundColor3 = T.elev,
                Text = tostring(opt),
                TextColor3 = T.text,
                Font = Enum.Font.Gotham,
                TextSize = 11,
                BorderSizePixel = 0,
                AutoButtonColor = true,
            }, sc)
            corner(ob, UDim.new(0, 6))
            ob.MouseButton1Click:Connect(function()
                cur = opt
                upd()
                pop:Destroy()
                if opts.callback then opts.callback(opt) end
            end)
        end
        sc.CanvasSize = UDim2.new(0, 0, 0, ll.AbsoluteContentSize.Y + 10)
        local bx = I("TextButton", {
            Size = UDim2.new(0, 36, 0, 20),
            Position = UDim2.new(1, -42, 0, 3),
            BackgroundColor3 = T.danger,
            Text = "×",
            TextColor3 = Color3.new(1, 1, 1),
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            BorderSizePixel = 0,
        }, pop)
        corner(bx, UDim.new(0, 5))
        bx.MouseButton1Click:Connect(function() pop:Destroy() end)
    end)
    return { set = function(v) cur = v; upd() end }
end

-- [BUILD UI]
local win = UI.newWindow()
mainFrame = win.frame

local farmTab = UI.newTab(win, "⚔", "Farm")
local collectTab = UI.newTab(win, "💎", "Collect")
local rebirthTab = UI.newTab(win, "🔄", "Rebirth")
local configTab = UI.newTab(win, "⚙", "Config")
local sobreTab = UI.newTab(win, "ℹ", "Sobre")

farmTab.btn.BackgroundColor3 = T.elev
farmTab.btn.TextColor3 = T.accent
farmTab.frame.Visible = true

-- FARM
UI.section(farmTab, "⚔ COMBATE")
UI.toggle(farmTab, { name = "Auto Farm", default = false, callback = function(v) Config.AutoFarm = v end })
UI.toggle(farmTab, { name = "Auto M1", default = true, callback = function(v) Config.AutoM1 = v end })
UI.toggle(farmTab, { name = "Auto Boss", default = false, callback = function(v) Config.AutoBoss = v end })
UI.toggle(farmTab, { name = "Auto Skill", default = false, callback = function(v) Config.AutoSkill = v end })
UI.toggle(farmTab, { name = "Auto Lock-On", default = true, callback = function(v) Config.AutoLock = v end })
UI.toggle(farmTab, { name = "ESP Mobs", default = false, callback = function(v) Config.ESPMobs = v end })

UI.section(farmTab, "🎯 MOB ALVO")
UI.dropdown(farmTab, {
    name = "Filtrar",
    options = function() return listarMobs() end,
    default = "(todos)",
    callback = function(o) Config.MobAlvo = (o == "(todos)") and nil or o end,
})

UI.section(farmTab, "📏 RANGES")
UI.slider(farmTab, { name = "M1 Range", min = 8, max = 40, default = 12, suffix = " st", callback = function(v) Config.M1_Range = v end })
UI.slider(farmTab, { name = "M1 Delay", min = 10, max = 80, default = 35, suffix = " ms", callback = function(v) Config.M1_Delay = v / 100 end })
UI.slider(farmTab, { name = "Skill Delay", min = 10, max = 50, default = 15, suffix = " x0.1s", callback = function(v) Config.Skill_Delay = v / 10 end })

-- COLLECT
UI.section(collectTab, "💎 AUTO COLLECT")
UI.toggle(collectTab, { name = "Ativar", default = false, callback = function(v) Config.AutoCollect = v end })
UI.toggle(collectTab, { name = "ESP Drops", default = true, callback = function(v) Config.ESPDrops = v end })
UI.label(collectTab, { text = "Detecta ItemDrop_* em PartStorage\ne voa até esferas automaticamente.", height = 44 })

-- REBIRTH
UI.section(rebirthTab, "🔄 AUTO REBIRTH")
UI.toggle(rebirthTab, { name = "Ativar", default = false, callback = function(v) Config.AutoRebirth = v end })
UI.slider(rebirthTab, { name = "Multiplicador", min = 1, max = 10, default = 3, callback = function(v) Config.RebirthMult = v end })
UI.button(rebirthTab, { name = "🔄 Forçar Rebirth", callback = function() fazerRebirth() end })
local infoReb = UI.label(rebirthTab, { text = "Aguardando...", height = 50 })

-- CONFIG
UI.section(configTab, "✈ MOVIMENTO")
UI.slider(configTab, { name = "Voo", min = 50, max = 500, default = 120, suffix = " st/s", callback = function(v) Config.FlySpeed = v end })
UI.toggle(configTab, { name = "Forçar WalkSpeed", default = false, callback = function(v) Config.OverrideSpeed = v end })
UI.slider(configTab, { name = "WalkSpeed", min = 16, max = 200, default = 16, callback = function(v) Config.WalkSpeed = v end })

UI.section(configTab, "💠 KI")
UI.slider(configTab, { name = "Ki mínimo %", min = 10, max = 80, default = 30, suffix = "%", callback = function(v) KiCfg.Limite = v / 100 end })
UI.slider(configTab, { name = "Ki alvo %", min = 50, max = 100, default = 95, suffix = "%", callback = function(v) KiCfg.Alvo = v / 100 end })
UI.slider(configTab, { name = "Tempo máx.", min = 2, max = 15, default = 5, suffix = " s", callback = function(v) KiCfg.TempoMax = v end })

UI.section(configTab, "🛠 UTILITÁRIOS")
UI.toggle(configTab, { name = "Noclip", default = false, callback = function(v) Config.Noclip = v end })

UI.section(configTab, "🌌 VOO NATIVO")
UI.button(configTab, { name = "SuperFlight (5s)", callback = function()
    if RE_SuperFlight then
        pcall(function() RE_SuperFlight:FireServer(true) end)
        task.wait(5)
        pcall(function() RE_SuperFlight:FireServer(false) end)
    end
end })

UI.section(configTab, "🛑 SISTEMA")
UI.button(configTab, { name = "Encerrar Hub", callback = function()
    Ativo = false
    if gui then gui:Destroy() end
    if espGui then espGui:Destroy() end
end })

-- SOBRE
UI.section(sobreTab, "📊 SEUS STATUS")
local infoP = UI.label(sobreTab, { text = "Carregando...", height = 80 })
UI.section(sobreTab, "🖥 SERVIDOR")
local infoS = UI.label(sobreTab, { text = "Carregando...", height = 50 })

-- [LOOPS]
-- combate
task.spawn(function()
    local ultimoM1 = 0
    local ultimoSkill = 0
    local alvoTravado = nil

    while Ativo do
        task.wait(0.1)

        if not Config.AutoFarm and not Config.AutoBoss and not Config.AutoSkill then
            alvoTravado = nil
            pararVoo()
            task.wait(0.4)
            continue
        end

        local cur, max = getKi()
        local pct = max > 0 and (cur / max) or 1
        if pct < KiCfg.Limite and Config.AutoSkill then
            lockOn(nil)
            pararVoo()
            recarregarKi()
            ultimoSkill = os.clock()
            continue
        end

        local mob = getMob()
        if not mob then
            pararVoo()
            task.wait(0.3)
            continue
        end

        local _, hrp = getChar()
        if not hrp then continue end

        if Config.AutoLock and alvoTravado ~= mob.baseName then
            lockOn(mob.model)
            alvoTravado = mob.baseName
        end

        if mob.dist > Config.M1_Range then
            voarPara(mob.pos)
            task.wait(0.05)
            continue
        end

        pararVoo()
        hrp.CFrame = CFrame.new(hrp.Position, mob.pos)

        if Config.AutoM1 and (Config.AutoFarm or Config.AutoBoss)
        and (os.clock() - ultimoM1) >= Config.M1_Delay then
            m1(mob)
            ultimoM1 = os.clock()
        end

        if Config.AutoSkill and (os.clock() - ultimoSkill) >= Config.Skill_Delay then
            local s = proximaSkill()
            usarSkill(s, mob)
            ultimoSkill = os.clock()
        end
    end
end)

-- noclip
task.spawn(function()
    while Ativo do
        task.wait(0.2)
        if Config.Noclip then
            local c = plr.Character
            if c then
                for _, p in ipairs(c:GetDescendants()) do
                    if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
                end
            end
        end
    end
end)

-- walkspeed
task.spawn(function()
    while Ativo do
        task.wait(0.5)
        if Config.OverrideSpeed then
            local c = plr.Character
            if c then
                local h = c:FindFirstChildOfClass("Humanoid")
                if h then h.WalkSpeed = Config.WalkSpeed end
            end
        end
    end
end)

-- rebirth
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

-- esp mobs
task.spawn(function()
    while Ativo do
        task.wait(0.4)
        if not Config.ESPMobs then
            for m in pairs(espCache) do removerESP(m) end
            continue
        end
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
    end
end)

-- esp drops + autocollect
task.spawn(function()
    while Ativo do
        task.wait(0.5)
        if Config.ESPDrops then atualizarDropESP() end
        if Config.AutoCollect then tentarColetar() end
    end
end)

-- stats
task.spawn(function()
    while Ativo do
        task.wait(2)
        local st = plr:FindFirstChild("Stats")
        if st then
            local function g(n)
                local v = st:FindFirstChild(n)
                return v and tostring(v.Value) or "0"
            end
            infoP.Text = string.format(
                "Level: %s\nRebirth: %s\nStrength: %s\nKi: %s",
                g("Level"), g("Rebirth"), g("Strength"), g("Ki"))
        end
        local jobId = game.JobId ~= "" and game.JobId:sub(1, 8) .. "..." or "Privado"
        local ping = 0
        pcall(function() ping = math.floor(plr:GetNetworkPing() * 1000) end)
        infoS.Text = string.format("%s • %s\nServ: %s • %d players • %d ms",
            os.date("%d/%m/%Y"), os.date("%H:%M:%S"),
            jobId, #Players:GetPlayers(), ping)
        local _, info = checarRebirth()
        if info then
            infoReb.Text = "Rebirth: " .. info.reb .. "\nTotal: " .. info.total .. "\nAlvo: " .. info.alvo
        end
    end
end)

print("[DBH] ✅ v8 carregado!")
