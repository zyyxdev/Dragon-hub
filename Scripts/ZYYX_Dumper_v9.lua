--[[
  ══════════════════════════════════════════════════════════════════════
   ZYYX DUMPER v9.0 — Dragon Blox (pós-update, agnóstico de versão)
  ══════════════════════════════════════════════════════════════════════
   Diferença pro v8:
     - NÃO assume sleitnick_knit@1.4.7. Descobre qualquer versão em _Index.
     - Registra TODOS os remotes de RS / WS / ReplicatedFirst / PlayerGui.
     - Mapa de remotes gerado em .lua (pronto pro hub consumir).
     - Sonda de ambiente (o que o executor ainda permite).
     - Append incremental: se o processo morrer, o dump não se perde.
     - Dedupe por assinatura de argumentos (path|metodo|shape).
   Teclas:
     RightShift = liga/desliga captura
     F9         = salvar agora (arquivo + mapa + clipboard)
     F10        = re-scan arquitetural
  ══════════════════════════════════════════════════════════════════════
]]

local VERSION = "9.0"

if getgenv and getgenv().__ZYYX_DUMP9 then
    pcall(function() getgenv().__ZYYX_DUMP9.stop() end)
end

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local WS      = game:GetService("Workspace")
local RF      = game:GetService("ReplicatedFirst")
local UIS     = game:GetService("UserInputService")
local plr     = Players.LocalPlayer

local cfg = {
    maxDepth  = 14,
    maxLog    = 20000,
    rateLimit = 0.02,
    session   = "Sessao",
}

local TS    = os.date("%Y%m%d_%H%M%S")
local PLACE = tostring(game.PlaceId)
local FILE  = ("ZYYX_v9_%s_%s.txt"):format(PLACE, TS)
local MAPF  = ("ZYYX_v9_map_%s.lua"):format(PLACE)

local S = {
    active   = true,
    total    = 0,
    uniq     = 0,
    seen     = {},
    lines    = {},
    events   = {},
    arch     = {},
    knit     = nil,
    services = {},
    remoteMap = {},
    hooked   = false,
    inHook   = false,
    lastCall = {},
}

-- ───────────────────────────── env probe
local function cap(name, f)
    local ok, v = pcall(f)
    return ok and v ~= nil and v ~= false
end

local ENV = {
    executor      = (function()
        if type(identifyexecutor) ~= "function" then return "?" end
        local ok, name = pcall(identifyexecutor)
        return ok and tostring(name) or "?"
    end)(),
    writefile     = cap("writefile", function() return typeof(writefile) == "function" end),
    appendfile    = cap("appendfile", function() return typeof(appendfile) == "function" end),
    isfile        = cap("isfile", function() return typeof(isfile) == "function" end),
    readfile      = cap("readfile", function() return typeof(readfile) == "function" end),
    hookmetamethod= cap("hookmetamethod", function() return typeof(hookmetamethod) == "function" end),
    getrawmetatable=cap("getrawmetatable", function() return typeof(getrawmetatable) == "function" end),
    getnamecallmethod = cap("getnamecallmethod", function() return typeof(getnamecallmethod) == "function" end),
    checkcaller   = cap("checkcaller", function() return typeof(checkcaller) == "function" end),
    hookfunction  = cap("hookfunction", function() return typeof(hookfunction) == "function" end),
    setclipboard  = cap("setclipboard", function() return typeof(setclipboard) == "function" end),
    gethui        = cap("gethui", function() return typeof(gethui) == "function" end),
    getconnections= cap("getconnections", function() return typeof(getconnections) == "function" end),
    firesignal    = cap("firesignal", function() return typeof(firesignal) == "function" end),
    getgc         = cap("getgc", function() return typeof(getgc) == "function" end),
    getrenv       = cap("getrenv", function() return typeof(getrenv) == "function" end),
    getnilinstances=cap("getnilinstances", function() return typeof(getnilinstances) == "function" end),
    getscripts    = cap("getscripts", function() return typeof(getscripts) == "function" end),
    decompile     = cap("decompile", function() return typeof(decompile) == "function" end),
    http_request  = cap("http_request", function() return typeof(http_request) == "function" end),
}

-- ───────────────────────────── serializador
local function ser(v, d)
    d = d or 0
    if d > 4 then return "..." end
    local t = typeof(v)
    if t == "Instance" then
        local ok, p = pcall(function() return v:GetFullName() end)
        return "I(" .. (ok and p or v.Name) .. ")"
    elseif t == "Vector3" then
        return ("V3(%d,%d,%d)"):format(v.X, v.Y, v.Z)
    elseif t == "Vector2" then
        return ("V2(%d,%d)"):format(v.X, v.Y)
    elseif t == "CFrame" then
        local p = v.Position
        return ("CF(%d,%d,%d)"):format(p.X, p.Y, p.Z)
    elseif t == "Color3" then
        return ("C3(%d,%d,%d)"):format(v.R * 255, v.G * 255, v.B * 255)
    elseif t == "table" then
        local parts, i = {}, 0
        for k, x in pairs(v) do
            i = i + 1
            if i > 16 then parts[#parts + 1] = "..." break end
            parts[#parts + 1] = tostring(k) .. "=" .. ser(x, d + 1)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "string" then
        return '"' .. v:gsub('"', "'"):sub(1, 90) .. '"'
    elseif t == "boolean" or t == "number" then
        return tostring(v)
    elseif t == "nil" then
        return "nil"
    else
        return t .. "(" .. tostring(v):sub(1, 60) .. ")"
    end
end

-- assinatura de tipo dos args: serve pra agrupar chamadas equivalentes
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
        else
            out[i] = t
        end
    end
    return table.concat(out, "|")
end

-- ───────────────────────────── persistência
local canFile = ENV.writefile and ENV.appendfile

local function header()
    return table.concat({
        ("=== ZYYX DUMPER v%s ==="):format(VERSION),
        "place=" .. PLACE,
        "job=" .. tostring(game.JobId),
        "player=" .. plr.Name,
        "start=" .. os.date("%Y-%m-%d %H:%M:%S"),
        "kinit=" .. tostring(S.knit and S.knit.index or "?"),
        "=========================",
    }, "\n") .. "\n"
end

if canFile then
    pcall(writefile, FILE, header())
end

local function log(cat, alvo, metodo, corpo, extra)
    if not S.active and cat ~= "SYS" then return end
    S.total = S.total + 1
    local linha = ("%06d %-5s %s→ %s %s%s"):format(
        S.total, cat, alvo, metodo, corpo or "", extra and (" " .. extra) or "")
    S.lines[#S.lines + 1] = linha
    if #S.lines > cfg.maxLog then table.remove(S.lines, 1) end
    if cat ~= "EVT" then pcall(print, "[D9] " .. linha) end
end

local function registrar(cat, alvo, metodo, args, n)
    n = n or (args and #args or 0)
    local corpo = args and ser(args) or "-"
    local sh = args and shape(args, n) or "-"
    local key = cat .. "|" .. alvo .. "|" .. metodo .. "|" .. sh
    local rec = S.seen[key]
    if rec then
        rec.n = rec.n + 1
        if rec.n ~= 2 and rec.n % 20 ~= 0 then return end
        corpo = corpo .. ("  [x%d]"):format(rec.n)
    else
        S.seen[key] = { n = 1 }
        S.uniq = S.uniq + 1
    end
    log(cat, alvo, metodo, corpo, "{" .. sh .. "}")
end

-- ───────────────────────────── Knit discovery (sem versão fixa)
local function versionScore(name)
    local ver = name:match("@([%d%.]+)$") or "0"
    local a, b, c = ver:match("^(%d+)%.?(%d*)%.?(%d*)")
    return (tonumber(a) or 0) * 1e6 + (tonumber(b) or 0) * 1e3 + (tonumber(c) or 0)
end

local function findKnit()
    local pk = RS:FindFirstChild("Packages")
    local idx = pk and pk:FindFirstChild("_Index")
    local best, bestScore, bestName

    if idx then
        for _, pkg in ipairs(idx:GetChildren()) do
            if pkg.Name:find("knit", 1, true) then
                local knit = pkg:FindFirstChild("knit") or pkg:FindFirstChild("Knit")
                if knit then
                    local sc = versionScore(pkg.Name)
                    if not bestScore or sc > bestScore then
                        best, bestScore, bestName = pkg, sc, pkg.Name
                    end
                end
            end
        end
    end

    -- fallback: varredura rasa de RS atrás de ModuleScript nomeado knit
    if not best then
        for _, d in ipairs(RS:GetDescendants()) do
            if d.Name == "knit" and d:IsA("ModuleScript") and d.Parent then
                best = d.Parent
                bestName = d.Parent.Name
                break
            end
        end
    end

    if not best then return nil end
    return { pkg = best, index = bestName, mod = best:FindFirstChild("knit") or best:FindFirstChild("Knit") }
end

local function isRemote(inst)
    return inst:IsA("RemoteEvent")
        or inst:IsA("UnreliableRemoteEvent")
        or inst:IsA("RemoteFunction")
end

local function collectFromFolder(servicesFolder)
    local count = 0
    for _, svcFolder in ipairs(servicesFolder:GetChildren()) do
        local entry = S.services[svcFolder.Name] or { RE = {}, RF = {} }
        for _, tipo in ipairs({ "RE", "RF" }) do
            local grupo = svcFolder:FindFirstChild(tipo)
            if grupo then
                for _, r in ipairs(grupo:GetChildren()) do
                    if isRemote(r) then
                        local okp, path = pcall(function() return r:GetFullName() end)
                        entry[tipo][r.Name] = okp and path or r.Name
                        log("KNIT", svcFolder.Name .. "." .. tipo, "existe", r.Name, okp and path or r.Name)
                    end
                end
            end
        end
        S.services[svcFolder.Name] = entry
        count = count + 1
    end
    return count
end

local function loadKnit()
    local k = findKnit()
    if not k then
        log("SYS", "knit", "nao_encontrado", "-", "scan por Packages._Index e RS")
        return nil
    end
    S.knit = k

    local mod = k.mod
    local lib
    if mod then
        local ok, res = pcall(require, mod)
        if ok and type(res) == "table" then lib = res end
    end

    -- caminho real observado: remotes ficam como filhos de knit.Services.<Svc>.RE/RF
    local servicesFolder = mod and mod:FindFirstChild("Services")
    if servicesFolder then
        local n = collectFromFolder(servicesFolder)
        log("SYS", "knit", "tree", ("index=%s services=%d"):format(k.index, n))
        return lib
    end

    if not lib or not lib.Services then
        log("SYS", "knit", "sem_services", k.index, "require falhou e sem pasta Services")
        return nil
    end

    local count = 0
    for svcName, svc in pairs(lib.Services) do
        count = count + 1
        local entry = { RE = {}, RF = {} }
        for _, tipo in ipairs({ "RE", "RF" }) do
            local grupo = svc[tipo]
            if type(grupo) == "table" then
                for rk, rv in pairs(grupo) do
                    if typeof(rv) == "Instance" then
                        local ok, p = pcall(function() return rv:GetFullName() end)
                        entry[tipo][tostring(rk)] = ok and p or rv.Name
                        log("KNIT", svcName .. "." .. tipo, "existe", tostring(rk), ok and p or rv.Name)
                    end
                end
            end
        end
        S.services[svcName] = entry
    end
    log("SYS", "knit", "lib", ("index=%s services=%d"):format(k.index, count))
    return lib
end

local KnitLib = loadKnit()

-- ───────────────────────────── varredura de remotes
local CONTAINER = {
    Folder = true, Model = true, ScreenGui = true, SurfaceGui = true,
    BillboardGui = true, PlayerGui = true, Player = true, Backpack = true,
    Configuration = true, ReplicatedStorage = true, Workspace = true,
    ReplicatedFirst = true, StarterGui = true, StarterPlayer = true,
    StarterPlayerScripts = true, StarterCharacterScripts = true, DataModel = true,
}

local function walkRemotes(root, depth)
    if depth > cfg.maxDepth or not root then return end
    local ok, kids = pcall(function() return root:GetChildren() end)
    if not ok then return end
    for _, ch in ipairs(kids) do
        if isRemote(ch) then
            local okp, path = pcall(function() return ch:GetFullName() end)
            if okp then
                S.arch[#S.arch + 1] = ("[%s] %s"):format(ch.ClassName, path)
                S.remoteMap[ch.Name] = S.remoteMap[ch.Name] or path
            end
        elseif CONTAINER[ch.ClassName] then
            walkRemotes(ch, depth + 1)
        end
    end
end

local function scanArch()
    S.arch = {}
    S.remoteMap = {}
    walkRemotes(RS, 0)
    walkRemotes(WS, 0)
    walkRemotes(RF, 0)
    pcall(function() walkRemotes(plr, 0) end)
    log("SYS", "scan", "ok", ("remotes=%d"):format(#S.arch))
end

-- ───────────────────────────── server->client
local function connectRemote(inst)
    if S.events[inst] then return end
    if not isRemote(inst) then return end
    S.events[inst] = true
    local nome = inst:GetFullName()
    if inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent") then
        pcall(function()
            inst.OnClientEvent:Connect(function(...)
                if not S.active then return end
                registrar("EVT", nome, "OnClient", { ... }, select("#", ...))
            end)
        end)
    elseif inst:IsA("RemoteFunction") then
        pcall(function()
            inst.OnClientInvoke = function(...)
                if S.active then
                    registrar("EVT", nome, "OnClientInvoke", { ... }, select("#", ...))
                end
                return nil
            end
        end)
    end
end

local function hookAll()
    for _, d in ipairs(RS:GetDescendants()) do connectRemote(d) end
    for _, d in ipairs(WS:GetDescendants()) do connectRemote(d) end
    pcall(function()
        RS.DescendantAdded:Connect(function(d) connectRemote(d) end)
    end)
    pcall(function()
        WS.DescendantAdded:Connect(function(d) connectRemote(d) end)
    end)
end
hookAll()

-- ───────────────────────────── __namecall
local function hookNamecall()
    if S.hooked then return end
    if not ENV.hookmetamethod or not ENV.getrawmetatable then
        log("SYS", "hook", "indisponivel", "-", "sem hookmetamethod/getrawmetatable")
        return
    end
    local mt = getrawmetatable(game)
    local old
    local ok, err = pcall(function()
        old = hookmetamethod(game, "__namecall", function(self, ...)
            local metodo = getnamecallmethod()
            if not S.inHook and S.active and not checkcaller()
                and (metodo == "FireServer" or metodo == "Fire"
                    or metodo == "InvokeServer" or metodo == "Invoke") then
                local n = select("#", ...)
                local args = {}
                for i = 1, n do args[i] = select(i, ...) end
                local agora = os.clock()
                local okp, alvo = pcall(function() return self:GetFullName() end)
                alvo = okp and alvo or tostring(self)
                if not (S.lastCall[alvo] and agora - S.lastCall[alvo] < cfg.rateLimit) then
                    S.lastCall[alvo] = agora
                    S.inHook = true
                    pcall(function()
                        registrar("CALL", alvo, metodo, args, n)
                    end)
                    S.inHook = false
                end
            end
            return old(self, ...)
        end)
    end)
    if not ok then
        log("SYS", "hook", "falhou", tostring(err))
        return
    end
    S.hooked = true
    log("SYS", "hook", "ok", "__namecall")
end
hookNamecall()

-- ───────────────────────────── snapshot de status do player
local function snapshotPlayer()
    local char = plr.Character
    if not char then return end
    local status = char:FindFirstChild("Status")
    log("SYS", "char", "children", (function()
        local t = {}
        for _, c in ipairs(char:GetChildren()) do t[#t + 1] = c.Name .. ":" .. c.ClassName end
        return table.concat(t, ",")
    end)())
    if status then
        local t = {}
        for _, v in ipairs(status:GetChildren()) do
            if v:IsA("ValueBase") then t[#t + 1] = v.Name .. "=" .. tostring(v.Value) end
        end
        log("SYS", "status", "valores", table.concat(t, " "))
    end
end
task.spawn(function()
    task.wait(2)
    snapshotPlayer()
end)

-- ───────────────────────────── mapa consumível
local function buildMapText()
    local L = {}
    L[#L + 1] = "-- gerado por ZYYX Dumper v" .. VERSION .. " — " .. os.date("%Y-%m-%d %H:%M:%S")
    L[#L + 1] = "return {"
    L[#L + 1] = ("  place = %s,"):format(PLACE)
    L[#L + 1] = ("  knitIndex = %q,"):format(tostring(S.knit and S.knit.index or ""))
    L[#L + 1] = "  services = {"
    for svcName, entry in pairs(S.services) do
        L[#L + 1] = ("    [%q] = { RE = {"):format(svcName)
        for k, path in pairs(entry.RE) do
            L[#L + 1] = ("      [%q] = %q,"):format(k, path)
        end
        L[#L + 1] = "    }, RF = {"
        for k, path in pairs(entry.RF) do
            L[#L + 1] = ("      [%q] = %q,"):format(k, path)
        end
        L[#L + 1] = "    } },"
    end
    L[#L + 1] = "  },"
    L[#L + 1] = "  remotes = {"
    for name, path in pairs(S.remoteMap) do
        L[#L + 1] = ("    [%q] = %q,"):format(name, path)
    end
    L[#L + 1] = "  },"
    L[#L + 1] = "}"
    return table.concat(L, "\n")
end

local function save(quiet)
    local L = {}
    L[#L + 1] = header()
    L[#L + 1] = "── AMBIENTE ──"
    for k, v in pairs(ENV) do
        L[#L + 1] = ("  %-16s %s"):format(k, tostring(v))
    end
    L[#L + 1] = ""
    L[#L + 1] = "── ARQUITETURAL (remotes) ──"
    for _, a in ipairs(S.arch) do L[#L + 1] = "  " .. a end
    L[#L + 1] = ""
    L[#L + 1] = "── TRAFEGO ──"
    for _, l in ipairs(S.lines) do L[#L + 1] = l end

    local txt = table.concat(L, "\n")
    local map = buildMapText()

    if canFile then
        pcall(writefile, FILE, txt)
        pcall(writefile, MAPF, map)
    end
    if ENV.setclipboard then
        pcall(setclipboard, txt)
    end
    if not quiet then
        log("SYS", "save", "ok", ("linhas=%d unicos=%d"):format(#S.lines, S.uniq))
        pcall(print, "[D9] salvo: " .. FILE .. " | mapa: " .. MAPF)
    end
    return FILE
end

-- ───────────────────────────── UI mínima
local guiParent = (ENV.gethui and gethui()) or plr:WaitForChild("PlayerGui")
local old = guiParent:FindFirstChild("ZYYX_DUMP9")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "ZYYX_DUMP9"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = guiParent

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 250, 0, 98)
frame.Position = UDim2.new(0, 14, 0, 14)
frame.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
frame.BackgroundTransparency = 0.1
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(255, 140, 30)
stroke.Thickness = 1

local lbl = Instance.new("TextLabel")
lbl.Size = UDim2.new(1, -14, 0, 54)
lbl.Position = UDim2.new(0, 7, 0, 6)
lbl.BackgroundTransparency = 1
lbl.Font = Enum.Font.Code
lbl.TextSize = 12
lbl.TextColor3 = Color3.fromRGB(120, 255, 140)
lbl.TextXAlignment = Enum.TextXAlignment.Left
lbl.TextYAlignment = Enum.TextYAlignment.Top
lbl.Parent = frame

local function mkBtn(x, txt, cor, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 76, 0, 26)
    b.Position = UDim2.new(0, x, 0, 66)
    b.BackgroundColor3 = cor
    b.Text = txt
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.BorderSizePixel = 0
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(cb)
end

mkBtn(6, "CAPTURAR", Color3.fromRGB(40, 150, 90), function()
    S.active = not S.active
    log("SYS", "captura", S.active and "ON" or "OFF", "-")
end)
mkBtn(86, "SALVAR", Color3.fromRGB(210, 120, 20), function() save(false) end)
mkBtn(166, "RESCAN", Color3.fromRGB(50, 100, 190), function() scanArch() end)

-- drag
local drag, dStart, sStart = false, nil, nil
frame.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
        drag = true; dStart = i.Position; sStart = frame.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if drag and (i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dStart
        frame.Position = UDim2.new(sStart.X.Scale, sStart.X.Offset + d.X,
            sStart.Y.Scale, sStart.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then drag = false end
end)

task.spawn(function()
    while gui.Parent do
        lbl.Text = ("ZYYX D9 %s\nremotes:%d unicos:%d chamadas:%d\nknit:%s"):format(
            S.active and "[REC]" or "[PAUSA]", #S.arch, S.uniq, S.total,
            tostring(S.knit and S.knit.index or "?"))
        task.wait(0.5)
    end
end)

-- ───────────────────────────── flush incremental (crash-safe)
task.spawn(function()
    while gui.Parent do
        task.wait(15)
        if canFile and #S.lines > 0 then
            local chunk = table.concat(S.lines, "\n", math.max(1, #S.lines - 400))
            pcall(appendfile, FILE, chunk .. "\n")
        end
    end
end)

UIS.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == Enum.KeyCode.RightShift then
        S.active = not S.active
        log("SYS", "captura", S.active and "ON" or "OFF", "-")
    elseif inp.KeyCode == Enum.KeyCode.F9 then
        save(false)
    elseif inp.KeyCode == Enum.KeyCode.F10 then
        scanArch()
    end
end)

-- ───────────────────────────── API global
getgenv = getgenv or function() return _G end
getgenv().__ZYYX_DUMP9 = {
    state = S,
    save = save,
    scan = scanArch,
    map = buildMapText,
    file = FILE,
    mapFile = MAPF,
    stop = function()
        S.active = false
        save(true)
        pcall(function() gui:Destroy() end)
        getgenv().__ZYYX_DUMP9 = nil
    end,
}

scanArch()
log("SYS", "start", "ok", ("place=%s player=%s arch=%d"):format(PLACE, plr.Name, #S.arch))
print("[D9] rodando. RightShift pausa | F9 salva | F10 rescan | getgenv().__ZYYX_DUMP9.stop()")
