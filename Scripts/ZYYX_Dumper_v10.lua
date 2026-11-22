local VERSION = "10.3"

if getgenv and getgenv().__ZYYX_DUMP10 then
    pcall(function() getgenv().__ZYYX_DUMP10.stop() end)
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local RF = game:GetService("ReplicatedFirst")
local UIS = game:GetService("UserInputService")
local plr = Players.LocalPlayer

local CFG = {
    rawMax = 8000,
    rateLimit = 0.02,
    evtRate = 0.25,
    slice = 120,
    wsDepth = 8,
    rsDepth = 12,
    maxNodes = 9000,
    snapshotEvery = 6,
}

local TS = os.date("%Y%m%d_%H%M%S")
local PLACE = tostring(game.PlaceId)
local FILE = ("ZYYX_v10_%s_%s.txt"):format(PLACE, TS)
local MAPF = ("ZYYX_v10_map_%s.lua"):format(PLACE)

local S = {
    active = true,
    total = 0,
    uniq = 0,
    sig = {},
    raw = {},
    appended = 0,
    events = {},
    evtLast = {},
    arch = {},
    services = {},
    network = 0,
    drops = {},
    snap = {},
    lastCall = {},
    onInv = {},
    place = PLACE,
    started = os.date("%Y-%m-%d %H:%M:%S"),
}

local SCAN = { active = false, nodes = 0, remotes = 0, token = 0 }
local CONNS = {}
local GUI_CONNS = {}
local HOOK_ORIG = {}
local HOOK = { active = false, budget = 0, janela = 0, maxPorSeg = 40, n = 0 }
local pathCache = setmetatable({}, { __mode = "k" })
local wiped = false

local function probe(f)
    local ok, v = pcall(f)
    return ok and v ~= nil and v ~= false
end

local ENV = {
    executor = (function()
        if type(identifyexecutor) ~= "function" then return "?" end
        local ok, n = pcall(identifyexecutor)
        return ok and tostring(n) or "?"
    end)(),
    writefile = probe(function() return typeof(writefile) == "function" end),
    appendfile = probe(function() return typeof(appendfile) == "function" end),
    isfile = probe(function() return typeof(isfile) == "function" end),
    readfile = probe(function() return typeof(readfile) == "function" end),
    hookmetamethod = probe(function() return typeof(hookmetamethod) == "function" end),
    getrawmetatable = probe(function() return typeof(getrawmetatable) == "function" end),
    getnamecallmethod = probe(function() return typeof(getnamecallmethod) == "function" end),
    checkcaller = probe(function() return typeof(checkcaller) == "function" end),
    hookfunction = probe(function() return typeof(hookfunction) == "function" end),
    setclipboard = probe(function() return typeof(setclipboard) == "function" end),
    gethui = probe(function() return typeof(gethui) == "function" end),
    getconnections = probe(function() return typeof(getconnections) == "function" end),
    getgc = probe(function() return typeof(getgc) == "function" end),
    getrenv = probe(function() return typeof(getrenv) == "function" end),
    getnilinstances = probe(function() return typeof(getnilinstances) == "function" end),
    getscripts = probe(function() return typeof(getscripts) == "function" end),
    decompile = probe(function() return typeof(decompile) == "function" end),
    http_request = probe(function() return typeof(http_request) == "function" end),
    firesignal = probe(function() return typeof(firesignal) == "function" end),
}

local function ser(v, d)
    d = d or 0
    if d > 3 then return "..." end
    local t = typeof(v)
    if t == "Instance" then
        return "I(" .. (v.Name or "?") .. ")"
    elseif t == "Vector3" then
        return ("V3(%d,%d,%d)"):format(v.X, v.Y, v.Z)
    elseif t == "CFrame" then
        local p = v.Position
        return ("CF(%d,%d,%d)"):format(p.X, p.Y, p.Z)
    elseif t == "table" then
        local out, i = {}, 0
        for k, x in pairs(v) do
            i = i + 1
            if i > 14 then out[#out + 1] = "..." break end
            out[#out + 1] = tostring(k) .. "=" .. ser(x, d + 1)
        end
        return "{" .. table.concat(out, ",") .. "}"
    elseif t == "string" then
        return '"' .. v:gsub('"', "'"):sub(1, 70) .. '"'
    elseif t == "boolean" or t == "number" then
        return tostring(v)
    elseif t == "nil" then
        return "nil"
    else
        return t .. "(" .. tostring(v):sub(1, 40) .. ")"
    end
end

local function shape(args, n)
    local out = {}
    for i = 1, n do
        local v = args[i]
        local t = typeof(v)
        if t == "table" then
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            out[i] = "t{" .. table.concat(keys, ",") .. "}"
        elseif t == "Instance" then
            out[i] = "I"
        else
            out[i] = t
        end
    end
    return table.concat(out, "|")
end

local canFile = ENV.writefile and ENV.appendfile

local function header()
    return table.concat({
        ("=== ZYYX DUMPER v%s ==="):format(VERSION),
        "place=" .. S.place,
        "job=" .. tostring(game.JobId),
        "player=" .. plr.Name,
        "start=" .. S.started,
        "network=" .. tostring(S.network),
        "=========================",
    }, "\n") .. "\n"
end

if canFile then pcall(writefile, FILE, header()) end

local function pushRaw(line)
    S.raw[#S.raw + 1] = line
    if #S.raw > CFG.rawMax then table.remove(S.raw, 1) end
end

local function registrar(path, method, args, n)
    n = n or (args and #args or 0)
    local sh = args and shape(args, n) or "-"
    local key = path .. "|" .. method .. "|" .. sh
    local rec = S.sig[key]
    S.total = S.total + 1
    if rec then
        rec.n = rec.n + 1
        rec.last = os.clock()
        if rec.n % 25 == 0 then
            pushRaw(("%06d %s→ %s  x%d"):format(S.total, method, path, rec.n))
        end
        return
    end
    local sample = "-"
    if args then
        local ok, out = pcall(ser, args)
        sample = ok and out or "?"
    end
    S.sig[key] = { path = path, method = method, shape = sh, n = 1,
        sample = sample, first = os.clock(), last = os.clock() }
    S.uniq = S.uniq + 1
    pushRaw(("%06d %s→ %s %s"):format(S.total, method, path, sample))
end

local function isRemote(inst)
    return inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent")
        or inst:IsA("RemoteFunction")
end

local CONTAINER = {
    Folder = true,
    PlayerGui = true,
    Player = true,
    Backpack = true,
    Configuration = true,
    Model = true,
    ScreenGui = true,
}

local MUDO = { "Postie", "GameAnalytics", "ZAP_", "Skypack", "Ping" }

local function deveConectar(path)
    for _, m in ipairs(MUDO) do
        if path:find(m, 1, true) then return false end
    end
    return true
end

local function connectRemote(inst, path)
    if wiped or S.events[inst] then return end
    S.events[inst] = true
    if not deveConectar(path) then return end
    if inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent") then
        pcall(function()
            CONNS[#CONNS + 1] = inst.OnClientEvent:Connect(function(...)
                if not S.active then return end
                local agora = os.clock()
                local last = S.evtLast[path]
                if last and agora - last < CFG.evtRate then return end
                S.evtLast[path] = agora
                local n = select("#", ...)
                local args = {}
                for i = 1, n do args[i] = select(i, ...) end
                registrar(path, "OnClient", args, n)
            end)
        end)
    elseif inst:IsA("RemoteFunction") then
        pcall(function()
            local prev = inst.OnClientInvoke
            S.onInv[inst] = prev
            inst.OnClientInvoke = function(...)
                local n = select("#", ...)
                local args = {}
                for i = 1, n do args[i] = select(i, ...) end
                if S.active then
                    local agora = os.clock()
                    local last = S.evtLast[path]
                    if not last or agora - last >= CFG.evtRate then
                        S.evtLast[path] = agora
                        pcall(registrar, path, "OnClientInvoke", args, n)
                    end
                end
                if type(prev) == "function" then return prev(...) end
                return nil
            end
        end)
    end
end

local function scanNetwork()
    S.services = {}
    S.network = 0
    local net = RS:FindFirstChild("Network")
    if not net then return 0 end
    for _, svc in ipairs(net:GetChildren()) do
        local entry = { RE = {}, RF = {} }
        local count = 0
        for _, tipo in ipairs({ "RE", "RF" }) do
            local g = svc:FindFirstChild(tipo)
            if g then
                for _, r in ipairs(g:GetChildren()) do
                    if isRemote(r) then
                        entry[tipo][r.Name] = "ReplicatedStorage.Network."
                            .. svc.Name .. "." .. tipo .. "." .. r.Name
                        count = count + 1
                    end
                end
            end
        end
        if count > 0 then
            S.services[svc.Name] = entry
            S.network = S.network + 1
        end
    end
    return S.network
end

local function scanAsync(onDone)
    if SCAN.active or wiped then return false end
    SCAN.active = true
    SCAN.nodes = 0
    SCAN.remotes = 0
    SCAN.token = SCAN.token + 1
    local meuToken = SCAN.token
    S.arch = {}

    local queue = {
        { RS, 0, "ReplicatedStorage", CFG.rsDepth },
        { RF, 0, "ReplicatedFirst", 4 },
        { plr, 0, plr.Name, 4 },
        { WS, 0, "Workspace", CFG.wsDepth },
    }
    local head = 1

    task.spawn(function()
        while head <= #queue and SCAN.token == meuToken do
            local item = queue[head]
            head = head + 1
            local inst, depth, path, maxd = item[1], item[2], item[3], item[4]

            if depth <= maxd and SCAN.nodes < CFG.maxNodes then
                local ok, kids = pcall(inst.GetChildren, inst)
                if ok then
                    for _, ch in ipairs(kids) do
                        SCAN.nodes = SCAN.nodes + 1
                        local cls = ch.ClassName
                        local cpath = path .. "." .. ch.Name
                        if isRemote(ch) then
                            SCAN.remotes = SCAN.remotes + 1
                            S.arch[#S.arch + 1] = ("[%s] %s"):format(cls, cpath)
                            connectRemote(ch, cpath)
                        elseif CONTAINER[cls] then
                            queue[#queue + 1] = { ch, depth + 1, cpath, maxd }
                        end
                    end
                end
            end

            if head % CFG.slice == 0 then task.wait() end
        end
        if SCAN.token == meuToken then
            SCAN.active = false
            if onDone then pcall(onDone) end
        end
    end)
    return true
end

local isOurs
if ENV.checkcaller and type(checkcaller) == "function" then
    isOurs = function() return checkcaller() end
else
    isOurs = function() return false end
end

local function caminhoDe(inst)
    local p = pathCache[inst]
    if p then return p end
    local ok, full = pcall(function() return inst:GetFullName() end)
    p = ok and full or tostring(inst)
    pathCache[inst] = p
    return p
end

local desligarHook

local function gravarChamada(self, nome, ...)
    if not HOOK.active or not S.active or isOurs() then return end
    local agora = os.clock()
    if agora - HOOK.janela >= 1 then
        HOOK.janela = agora
        HOOK.budget = 0
    end
    if HOOK.budget >= HOOK.maxPorSeg then return end
    local path = caminhoDe(self)
    if not deveConectar(path) then return end
    local last = S.lastCall[path]
    if last and agora - last < CFG.rateLimit then return end
    S.lastCall[path] = agora
    HOOK.budget = HOOK.budget + 1
    local n = select("#", ...)
    local lim = n > 8 and 8 or n
    local args = {}
    for i = 1, lim do args[i] = select(i, ...) end
    registrar(path, nome, args, lim)
end

local function instalarMetodo(inst, nome)
    if not inst then return false end
    local metodo
    pcall(function() metodo = inst[nome] end)
    if type(metodo) ~= "function" then return false end
    local ok = pcall(function()
        local registro = #HOOK_ORIG + 1
        local orig
        orig = hookfunction(metodo, function(self, ...)
            if HOOK.active and S.active then
                local okr = pcall(gravarChamada, self, nome, ...)
                if not okr then
                    pcall(function() hookfunction(HOOK_ORIG[registro].metodo, HOOK_ORIG[registro].orig) end)
                    HOOK_ORIG[registro] = nil
                    HOOK.active = false
                end
            end
            return orig(self, ...)
        end)
        HOOK_ORIG[registro] = { metodo = metodo, orig = orig }
    end)
    return ok
end

desligarHook = function()
    for i = #HOOK_ORIG, 1, -1 do
        local h = HOOK_ORIG[i]
        if h then pcall(function() hookfunction(h.metodo, h.orig) end) end
        HOOK_ORIG[i] = nil
    end
    HOOK.active = false
end

local function hookFireServer()
    if not ENV.hookfunction or type(hookfunction) ~= "function" then return false end
    local alvos = {}
    pcall(function()
        local net = RS:FindFirstChild("Network")
        local base = net or RS
        for _, d in ipairs(base:GetDescendants()) do
            local cls = d.ClassName
            if cls == "RemoteEvent" or cls == "UnreliableRemoteEvent"
                or cls == "RemoteFunction" then
                alvos[cls] = d
                if alvos.RemoteEvent and alvos.UnreliableRemoteEvent
                    and alvos.RemoteFunction then break end
            end
        end
    end)
    local n = 0
    if alvos.RemoteEvent and instalarMetodo(alvos.RemoteEvent, "FireServer") then n = n + 1 end
    if alvos.UnreliableRemoteEvent
        and instalarMetodo(alvos.UnreliableRemoteEvent, "FireServer") then n = n + 1 end
    if alvos.RemoteFunction and instalarMetodo(alvos.RemoteFunction, "InvokeServer") then n = n + 1 end
    HOOK.active = n > 0
    return n > 0
end

local function snapshot()
    local char = plr.Character
    if not char then return end
    local out = {}
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then out[#out + 1] = ("hp=%.0f/%.0f"):format(hum.Health, hum.MaxHealth) end
    local status = char:FindFirstChild("Status")
    if status then
        for _, v in ipairs(status:GetChildren()) do
            if v:IsA("ValueBase") then
                if typeof(v.Value) == "number" then
                    out[#out + 1] = ("%s=%.1f"):format(v.Name, v.Value)
                else
                    out[#out + 1] = v.Name .. "=" .. tostring(v.Value)
                end
            end
        end
    end
    local wm = WS:FindFirstChild("World Mobs")
    if wm then
        local mobs = wm:FindFirstChild("Mobs")
        local bosses = wm:FindFirstChild("Boss Mobs")
        out[#out + 1] = ("mobs=%d bosses=%d"):format(
            mobs and #mobs:GetChildren() or 0,
            bosses and #bosses:GetChildren() or 0)
    end
    if #out > 0 then
        S.snap[#S.snap + 1] = table.concat(out, " ")
        if #S.snap > 300 then table.remove(S.snap, 1) end
    end
end

local FILTRO_DROP = { "drop", "orb", "star", "dragonball", "sphere", "chest", "bau", "baú", "boss" }

local function watchWorkspace()
    pcall(function()
        CONNS[#CONNS + 1] = WS.ChildAdded:Connect(function(it)
            if wiped then return end
            local low = string.lower(it.Name)
            for _, f in ipairs(FILTRO_DROP) do
                if string.find(low, f, 1, true) then
                    S.drops[#S.drops + 1] = ("%s | %s"):format(it.Name, it.ClassName)
                    if #S.drops > 400 then table.remove(S.drops, 1) end
                    break
                end
            end
        end)
    end)
end

local function buildMap()
    local L = {}
    L[#L + 1] = "-- ZYYX Dumper v" .. VERSION .. " // " .. os.date("%Y-%m-%d %H:%M:%S")
    L[#L + 1] = "return {"
    L[#L + 1] = ("  place = %s,"):format(S.place)
    L[#L + 1] = "  services = {"
    for svc, entry in pairs(S.services) do
        L[#L + 1] = ("    [%q] = { RE = {"):format(svc)
        for k, path in pairs(entry.RE) do L[#L + 1] = ("      [%q] = %q,"):format(k, path) end
        L[#L + 1] = "    }, RF = {"
        for k, path in pairs(entry.RF) do L[#L + 1] = ("      [%q] = %q,"):format(k, path) end
        L[#L + 1] = "    } },"
    end
    L[#L + 1] = "  },"
    L[#L + 1] = "}"
    return table.concat(L, "\n")
end

local function buildReport()
    local L = {}
    L[#L + 1] = header()
    L[#L + 1] = "[AMBIENTE]"
    for k, v in pairs(ENV) do L[#L + 1] = ("  %-16s %s"):format(k, tostring(v)) end

    L[#L + 1] = ""
    L[#L + 1] = ("[NETWORK] servicos=%d remotes=%d"):format(S.network, #S.arch)
    for svc, entry in pairs(S.services) do
        local re, rf = 0, 0
        for _ in pairs(entry.RE) do re = re + 1 end
        for _ in pairs(entry.RF) do rf = rf + 1 end
        L[#L + 1] = ("  %-32s RE=%-3d RF=%-3d"):format(svc, re, rf)
    end

    L[#L + 1] = ""
    L[#L + 1] = "[SIG] caminho | metodo | assinatura | chamadas | amostra"
    local keys = {}
    for k in pairs(S.sig) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local r = S.sig[k]
        L[#L + 1] = ("  %s | %s | %s | %d | %s"):format(r.path, r.method, r.shape, r.n, r.sample)
    end

    if #S.drops > 0 then
        L[#L + 1] = ""
        L[#L + 1] = "[WS DROPS]"
        for _, d in ipairs(S.drops) do L[#L + 1] = "  " .. d end
    end

    if #S.snap > 0 then
        L[#L + 1] = ""
        L[#L + 1] = "[SNAP ultimo]"
        L[#L + 1] = "  " .. S.snap[#S.snap]
    end

    L[#L + 1] = ""
    L[#L + 1] = "[ARQUITETURAL]"
    for _, a in ipairs(S.arch) do L[#L + 1] = "  " .. a end

    L[#L + 1] = ""
    L[#L + 1] = "[CALL]"
    for _, l in ipairs(S.raw) do L[#L + 1] = "  " .. l end
    return table.concat(L, "\n")
end

local function save(quiet)
    local txt = buildReport()
    if canFile then
        pcall(writefile, FILE, txt)
        pcall(writefile, MAPF, buildMap())
        S.appended = #S.raw
    end
    if ENV.setclipboard then pcall(setclipboard, txt) end
    if not quiet then
        pcall(print, ("[D10] salvo %s (%d sig / %d chamadas)"):format(FILE, S.uniq, S.total))
    end
    return FILE
end

scanNetwork()
local hooked = hookFireServer()
watchWorkspace()

local guiParent = (ENV.gethui and gethui()) or plr:WaitForChild("PlayerGui")
local prev = guiParent:FindFirstChild("ZYYX_DUMP10")
if prev then prev:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "ZYYX_DUMP10"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 99
gui.Parent = guiParent

local function wipe(apagarArquivos)
    if wiped then return end
    wiped = true
    S.active = false
    SCAN.active = false
    SCAN.token = SCAN.token + 1
    pcall(save, true)

    for i = #CONNS, 1, -1 do
        pcall(function() CONNS[i]:Disconnect() end)
        CONNS[i] = nil
    end
    for i = #GUI_CONNS, 1, -1 do
        pcall(function() GUI_CONNS[i]:Disconnect() end)
        GUI_CONNS[i] = nil
    end

    pcall(desligarHook)

    for k in pairs(S.sig) do S.sig[k] = nil end
    for k in pairs(S.raw) do S.raw[k] = nil end
    for k in pairs(S.events) do S.events[k] = nil end
    for k in pairs(S.evtLast) do S.evtLast[k] = nil end
    for k in pairs(S.arch) do S.arch[k] = nil end
    for k in pairs(S.services) do S.services[k] = nil end
    for k in pairs(S.drops) do S.drops[k] = nil end
    for k in pairs(S.snap) do S.snap[k] = nil end
    for k in pairs(S.lastCall) do S.lastCall[k] = nil end
    S.total, S.uniq, S.appended, S.network = 0, 0, 0, 0

    if apagarArquivos and canFile then
        pcall(function()
            if typeof(delfile) == "function" then
                if type(isfile) ~= "function" or isfile(FILE) then delfile(FILE) end
                if type(isfile) ~= "function" or isfile(MAPF) then delfile(MAPF) end
            end
        end)
    end

    pcall(function() gui:Destroy() end)
    pcall(function() getgenv().__ZYYX_DUMP10 = nil end)
end

local root = Instance.new("Frame")
root.Size = UDim2.new(0, 272, 0, 150)
root.Position = UDim2.new(0, 14, 0, 14)
root.BackgroundColor3 = Color3.fromRGB(9, 9, 11)
root.BackgroundTransparency = 0.08
root.BorderSizePixel = 0
root.Active = true
root.Parent = gui
Instance.new("UICorner", root).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", root)
stroke.Color = Color3.fromRGB(255, 140, 30)
stroke.Thickness = 1
stroke.Transparency = 0.4

local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, 0, 0, 22)
bar.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
bar.BorderSizePixel = 0
bar.Parent = root
Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -46, 1, 0)
title.Position = UDim2.new(0, 8, 0, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.Code
title.TextSize = 11
title.TextColor3 = Color3.fromRGB(255, 160, 60)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = ("ZYYX DUMPER v%s"):format(VERSION)
title.Parent = bar

local btnX = Instance.new("TextButton")
btnX.Name = "ZYYX_CLOSE"
btnX.Size = UDim2.new(0, 18, 0, 18)
btnX.Position = UDim2.new(1, -22, 0, 2)
btnX.BackgroundColor3 = Color3.fromRGB(190, 45, 45)
btnX.BackgroundTransparency = 0.1
btnX.Text = "X"
btnX.TextColor3 = Color3.new(1, 1, 1)
btnX.Font = Enum.Font.GothamBold
btnX.TextSize = 11
btnX.TextXAlignment = Enum.TextXAlignment.Center
btnX.BorderSizePixel = 0
btnX.AutoButtonColor = false
btnX.Parent = bar
Instance.new("UICorner", btnX).CornerRadius = UDim.new(0, 4)
btnX.MouseEnter:Connect(function()
    btnX.BackgroundColor3 = Color3.fromRGB(240, 60, 60)
end)
btnX.MouseLeave:Connect(function()
    btnX.BackgroundColor3 = Color3.fromRGB(190, 45, 45)
end)
btnX.MouseButton1Click:Connect(function()
    btnX.Text = "..."
    wipe(false)
end)

local info = Instance.new("TextLabel")
info.Size = UDim2.new(1, -16, 0, 58)
info.Position = UDim2.new(0, 8, 0, 26)
info.BackgroundTransparency = 1
info.Font = Enum.Font.Code
info.TextSize = 11
info.TextColor3 = Color3.fromRGB(130, 240, 150)
info.TextXAlignment = Enum.TextXAlignment.Left
info.TextYAlignment = Enum.TextYAlignment.Top
info.Text = "..."
info.Parent = root

local function mk(x, w, txt, cor, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, w, 0, 24)
    b.Position = UDim2.new(0, x, 0, 92)
    b.BackgroundColor3 = cor
    b.Text = txt
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.BorderSizePixel = 0
    b.Parent = root
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(cb)
    return b
end

local btnRec = mk(8, 82, "PAUSAR", Color3.fromRGB(150, 60, 40), function()
    S.active = not S.active
    btnRec.Text = S.active and "PAUSAR" or "GRAVAR"
    btnRec.BackgroundColor3 = S.active and Color3.fromRGB(150, 60, 40)
        or Color3.fromRGB(40, 140, 80)
end)
local btnScan = mk(96, 78, "SCAN", Color3.fromRGB(40, 90, 190), function()
    if SCAN.active then return end
    scanNetwork()
    scanAsync()
end)
mk(180, 84, "SALVAR", Color3.fromRGB(200, 120, 20), function() save(false) end)

local function mk2(x, w, txt, cor, cb)
    local b = mk(x, w, txt, cor, cb)
    b.Position = UDim2.new(0, x, 0, 122)
    return b
end

local btnHook = mk2(8, 256, "HOOK: ON  (entrada + saida)", Color3.fromRGB(90, 45, 150), function()
    if #HOOK_ORIG == 0 then return end
    HOOK.active = not HOOK.active
    btnHook.Text = HOOK.active and "HOOK: ON  (entrada + saida)"
        or "HOOK: OFF  (so entrada)"
    btnHook.BackgroundColor3 = HOOK.active and Color3.fromRGB(90, 45, 150)
        or Color3.fromRGB(55, 55, 65)
end)
if #HOOK_ORIG == 0 then
    btnHook.Text = "HOOK: OFF  (executor sem hookfunction)"
    btnHook.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
end

local drag, dStart, sStart = false, nil, nil
bar.InputBegan:Connect(function(i)
    if i.Target == btnX then return end
    if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
        drag = true
        dStart = i.Position
        sStart = root.Position
    end
end)
GUI_CONNS[#GUI_CONNS + 1] = UIS.InputChanged:Connect(function(i)
    if drag and (i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dStart
        root.Position = UDim2.new(sStart.X.Scale, sStart.X.Offset + d.X,
            sStart.Y.Scale, sStart.Y.Offset + d.Y)
    end
end)
GUI_CONNS[#GUI_CONNS + 1] = UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
        drag = false
    end
end)

task.spawn(function()
    local t = 0
    while gui.Parent do
        local scanTxt = SCAN.active
            and ("varrendo %d nos / %d remotes"):format(SCAN.nodes, SCAN.remotes)
            or ("scan ok: %d remotes"):format(#S.arch)
        local hookTxt = #HOOK_ORIG == 0 and "hook:n/a"
            or (HOOK.active and "hook:on" or "hook:off")
        info.Text = ("%s %s  place:%s\n%s\nservicos:%d  sig:%d  calls:%d"):format(
            S.active and "GRAVANDO" or "PAUSADO", hookTxt, S.place,
            scanTxt, S.network, S.uniq, S.total)
        btnScan.Text = SCAN.active and "..." or "SCAN"
        task.wait(0.4)
        t = t + 0.4
        if S.active and t >= CFG.snapshotEvery then
            t = 0
            pcall(snapshot)
        end
        local pid = tostring(game.PlaceId)
        if pid ~= S.place then
            S.place = pid
            pcall(scanNetwork)
            pcall(scanAsync)
        end
    end
end)

task.spawn(function()
    while gui.Parent do
        task.wait(20)
        if canFile and S.active and S.appended < #S.raw then
            local chunk = table.concat(S.raw, "\n", S.appended + 1, #S.raw)
            S.appended = #S.raw
            pcall(appendfile, FILE, "\n" .. chunk .. "\n")
        end
    end
end)

GUI_CONNS[#GUI_CONNS + 1] = UIS.InputBegan:Connect(function(inp, gp)
    if wiped or gp then return end
    if inp.KeyCode == Enum.KeyCode.RightShift then
        S.active = not S.active
        btnRec.Text = S.active and "PAUSAR" or "GRAVAR"
        btnRec.BackgroundColor3 = S.active and Color3.fromRGB(150, 60, 40)
            or Color3.fromRGB(40, 140, 80)
    elseif inp.KeyCode == Enum.KeyCode.F9 then
        save(false)
    elseif inp.KeyCode == Enum.KeyCode.F10 then
        scanNetwork()
        scanAsync()
    end
end)

getgenv = getgenv or function() return _G end
getgenv().__ZYYX_DUMP10 = {
    state = S,
    scan = SCAN,
    save = save,
    report = buildReport,
    map = buildMap,
    file = FILE,
    mapFile = MAPF,
    wipe = wipe,
    stop = function() wipe(false) end,
}

print(("[D10] v%s pronto | servicos=%d hook=%s"):format(
    VERSION, S.network, (#HOOK_ORIG > 0 and HOOK.active) and "on" or "off"))

task.spawn(function()
    task.wait(1)
    if not wiped and not SCAN.active and #S.arch == 0 then scanAsync() end
end)
