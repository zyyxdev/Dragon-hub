local VERSION = "10.0"

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
    maxDepth = 16,
    rawMax = 8000,
    rateLimit = 0.02,
    snapshotEvery = 5,
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
    arch = {},
    services = {},
    network = 0,
    drops = {},
    snap = {},
    lastCall = {},
    place = PLACE,
    started = os.date("%Y-%m-%d %H:%M:%S"),
    switched = 0,
}

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
        local ok, p = pcall(function() return v:GetFullName() end)
        return "I(" .. (ok and p or v.Name) .. ")"
    elseif t == "Vector3" then
        return ("V3(%d,%d,%d)"):format(v.X, v.Y, v.Z)
    elseif t == "CFrame" then
        local p = v.Position
        return ("CF(%d,%d,%d)"):format(p.X, p.Y, p.Z)
    elseif t == "Color3" then
        return ("C3(%d,%d,%d)"):format(v.R * 255, v.G * 255, v.B * 255)
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
    pcall(print, ("[D10] %s %s %s"):format(method, path, sh))
end

local function isRemote(inst)
    return inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent")
        or inst:IsA("RemoteFunction")
end

local CONTAINER = {
    Folder = true, Model = true, ScreenGui = true, SurfaceGui = true,
    BillboardGui = true, PlayerGui = true, Player = true, Backpack = true,
    Configuration = true, ReplicatedStorage = true, Workspace = true,
    ReplicatedFirst = true, StarterGui = true, StarterPlayer = true,
    StarterPlayerScripts = true, StarterCharacterScripts = true,
    DataModel = true, Actor = true, WorldRoot = true,
}

local function walk(root, depth)
    if depth > CFG.maxDepth or not root then return end
    local ok, kids = pcall(function() return root:GetChildren() end)
    if not ok then return end
    for _, ch in ipairs(kids) do
        if isRemote(ch) then
            local okp, path = pcall(function() return ch:GetFullName() end)
            if okp then
                S.arch[#S.arch + 1] = ("[%s] %s"):format(ch.ClassName, path)
            end
        elseif CONTAINER[ch.ClassName] then
            walk(ch, depth + 1)
        end
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
                        entry[tipo][r.Name] = r:GetFullName()
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

local function scanArch()
    S.arch = {}
    walk(RS, 0)
    walk(WS, 0)
    walk(RF, 0)
    pcall(function() walk(plr, 0) end)
end

local function connectRemote(inst)
    if S.events[inst] then return end
    if not isRemote(inst) then return end
    S.events[inst] = true
    local path = inst:GetFullName()
    if inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent") then
        pcall(function()
            inst.OnClientEvent:Connect(function(...)
                if not S.active then return end
                local n = select("#", ...)
                local args = {}
                for i = 1, n do args[i] = select(i, ...) end
                registrar(path, "OnClient", args, n)
            end)
        end)
    else
        pcall(function()
            inst.OnClientInvoke = function(...)
                local n = select("#", ...)
                local args = {}
                for i = 1, n do args[i] = select(i, ...) end
                if S.active then registrar(path, "OnClientInvoke", args, n) end
                return nil
            end
        end)
    end
end

local function hookRemotes()
    for _, d in ipairs(RS:GetDescendants()) do connectRemote(d) end
    for _, d in ipairs(WS:GetDescendants()) do connectRemote(d) end
    pcall(function() RS.DescendantAdded:Connect(connectRemote) end)
    pcall(function() WS.DescendantAdded:Connect(connectRemote) end)
end

local function hookNamecall()
    if not ENV.hookmetamethod or not ENV.getrawmetatable then return false end
    local ok = pcall(function()
        local old
        old = hookmetamethod(game, "__namecall", function(self, ...)
            local metodo = getnamecallmethod()
            if S.active and not checkcaller()
                and (metodo == "FireServer" or metodo == "Fire"
                    or metodo == "InvokeServer" or metodo == "Invoke") then
                local n = select("#", ...)
                local args = {}
                for i = 1, n do args[i] = select(i, ...) end
                local okp, path = pcall(function() return self:GetFullName() end)
                path = okp and path or tostring(self)
                local agora = os.clock()
                local last = S.lastCall[path]
                if not last or agora - last >= CFG.rateLimit then
                    S.lastCall[path] = agora
                    pcall(registrar, path, metodo, args, n)
                end
            end
            return old(self, ...)
        end)
    end)
    return ok
end

local function snapshot()
    local char = plr.Character
    if not char then return end
    local out = {}
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        out[#out + 1] = ("hp=%.0f/%.0f"):format(hum.Health, hum.MaxHealth)
    end
    local status = char:FindFirstChild("Status")
    if status then
        for _, v in ipairs(status:GetChildren()) do
            if v:IsA("ValueBase") then
                if typeof(v.Value) == "number" then
                    out[#out + 1] = ("%s=%.2f"):format(v.Name, v.Value)
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
        if #S.snap > 400 then table.remove(S.snap, 1) end
    end
end

local FILTRO_DROP = { "drop", "orb", "star", "dragonball", "sphere", "chest", "bau", "baú", "boss" }
local function watchWorkspace()
    pcall(function()
        WS.ChildAdded:Connect(function(it)
            local low = it.Name:lower()
            for _, f in ipairs(FILTRO_DROP) do
                if low:find(f, 1, true) then
                    S.drops[#S.drops + 1] = ("%s | %s | %s"):format(
                        it.Name, it.ClassName, it:GetFullName())
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
    L[#L + 1] = ("[NETWORK] servicos=%d remotes_mapeados=%d"):format(S.network, #S.arch)
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
    end    if ENV.setclipboard then pcall(setclipboard, txt) end
    if not quiet then
        pcall(print, ("[D10] salvo %s (%d unicos / %d chamadas)"):format(FILE, S.uniq, S.total))
    end
    return FILE
end

scanNetwork()
scanArch()
hookRemotes()
local hooked = hookNamecall()
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

local root = Instance.new("Frame")
root.Size = UDim2.new(0, 272, 0, 120)
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
title.Size = UDim2.new(1, -16, 1, 0)
title.Position = UDim2.new(0, 8, 0, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.Code
title.TextSize = 11
title.TextColor3 = Color3.fromRGB(255, 160, 60)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = ("ZYYX DUMPER v%s"):format(VERSION)
title.Parent = bar

local info = Instance.new("TextLabel")
info.Size = UDim2.new(1, -16, 0, 52)
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
    b.Position = UDim2.new(0, x, 0, 86)
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

local btnRec
btnRec = mk(8, 82, "PAUSAR", Color3.fromRGB(150, 60, 40), function()
    S.active = not S.active
    btnRec.Text = S.active and "PAUSAR" or "GRAVAR"
    btnRec.BackgroundColor3 = S.active and Color3.fromRGB(150, 60, 40)
        or Color3.fromRGB(40, 140, 80)
end)
mk(96, 78, "SALVAR", Color3.fromRGB(200, 120, 20), function() save(false) end)
mk(180, 84, "RESCAN", Color3.fromRGB(40, 90, 190), function()
    scanNetwork()
    scanArch()
end)

local drag, dStart, sStart = false, nil, nil
bar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
        drag = true
        dStart = i.Position
        sStart = root.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if drag and (i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dStart
        root.Position = UDim2.new(sStart.X.Scale, sStart.X.Offset + d.X,
            sStart.Y.Scale, sStart.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
        drag = false
    end
end)

task.spawn(function()
    local t = 0
    while gui.Parent do
        info.Text = ("%s  place:%s\nservicos:%d  sig:%d  calls:%d\nhook:%s  file:%s"):format(
            S.active and "GRAVANDO" or "PAUSADO", S.place,
            S.network, S.uniq, S.total,
            hooked and "on" or "off",
            canFile and FILE or "clipboard")
        task.wait(0.4)
        t = t + 0.4
        if S.active and t >= CFG.snapshotEvery then
            t = 0
            pcall(snapshot)
        end
        if tostring(game.PlaceId) ~= S.place then
            S.place = tostring(game.PlaceId)
            S.switched = S.switched + 1
            pcall(scanNetwork)
            pcall(scanArch)
            pcall(function() writefile(FILE, buildReport() .. "\n\n[TELEPORTE] place=" .. S.place) end)
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

UIS.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == Enum.KeyCode.RightShift then
        S.active = not S.active
        btnRec.Text = S.active and "PAUSAR" or "GRAVAR"
        btnRec.BackgroundColor3 = S.active and Color3.fromRGB(150, 60, 40)
            or Color3.fromRGB(40, 140, 80)
    elseif inp.KeyCode == Enum.KeyCode.F9 then
        save(false)
    elseif inp.KeyCode == Enum.KeyCode.F10 then
        scanNetwork()
        scanArch()
    end
end)

getgenv = getgenv or function() return _G end
getgenv().__ZYYX_DUMP10 = {
    state = S,
    save = save,
    scan = function() scanNetwork(); scanArch() end,
    report = buildReport,
    map = buildMap,
    file = FILE,
    mapFile = MAPF,
    stop = function()
        S.active = false
        save(true)
        pcall(function() gui:Destroy() end)
        getgenv().__ZYYX_DUMP10 = nil
    end,
}

print(("[D10] v%s pronto | servicos=%d remotes=%d hook=%s"):format(
    VERSION, S.network, #S.arch, hooked and "on" or "off"))
print("[D10] RightShift grava/pausa | F9 salva | F10 rescan | getgenv().__ZYYX_DUMP10.stop()")
