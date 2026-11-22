--[[
  DB_Resolver — resolução de remotes runtime p/ Dragon Blox
  Sem versão fixa do Knit. Sem caminho fixo. Ordem de resolução:
    1) mapa gerado pelo ZYYX Dumper v9 (ZYYX_v9_map_<place>.lua)
    2) require no módulo knit descoberto em Packages._Index
    3) varredura de filhos do módulo (builds que não permitem require)
    4) busca por nome em toda a árvore de ReplicatedStorage (último recurso)

  Uso:
    local DB = loadstring(...)()          -- ou cole como módulo local
    local ExecuteSkill = DB.rem("SkillManagerV2.RE.ExecuteSkill")
    local SkillRemote  = DB.raw("SkillRemote")
    print(DB.report())
]]

local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local Players = game:GetService("Players")

local DB = {}
DB.services = {}
DB.rawMap = {}
DB.source = "none"

local function versionScore(name)
    local a, b, c = name:match("@(%d+)%.?(%d*)%.?(%d*)$")
    return (tonumber(a) or 0) * 1e6 + (tonumber(b) or 0) * 1e3 + (tonumber(c) or 0)
end

local function safeFullName(inst)
    local ok, p = pcall(function() return inst:GetFullName() end)
    return ok and p or (inst and inst.Name) or nil
end

local function indexPath(path)
    -- "ReplicatedStorage.Packages._Index.x.knit.Services.A.B" -> instância
    local node = game
    for part in path:gmatch("[^%.]+") do
        local nextNode
        for _, child in ipairs(node:GetChildren()) do
            if child.Name == part then nextNode = child break end
        end
        if not nextNode then return nil end
        node = nextNode
    end
    return node
end

-- ── 1. mapa do dumper
local function loadMap()
    if typeof(readfile) ~= "function" or typeof(isfile) ~= "function" then return false end
    local name = ("ZYYX_v9_map_%s.lua"):format(tostring(game.PlaceId))
    if not isfile(name) then return false end
    local ok, chunk = pcall(readfile, name)
    if not ok or not chunk then return false end
    local loader = loadstring or load
    local fn = loader(chunk)
    if not fn then return false end
    local ok2, data = pcall(fn)
    if not ok2 or type(data) ~= "table" then return false end

    for svcName, entry in pairs(data.services or {}) do
        DB.services[svcName] = { RE = {}, RF = {} }
        for k, path in pairs(entry.RE or {}) do
            DB.services[svcName].RE[k] = indexPath(path)
        end
        for k, path in pairs(entry.RF or {}) do
            DB.services[svcName].RF[k] = indexPath(path)
        end
    end
    for k, path in pairs(data.remotes or {}) do
        DB.rawMap[k] = indexPath(path)
    end
    DB.source = "map"
    return DB.services["SkillManagerV2"] ~= nil
end

-- ── 2. Knit runtime
local function findKnit()
    local pk = RS:FindFirstChild("Packages")
    local idx = pk and pk:FindFirstChild("_Index")
    local best, score
    if idx then
        for _, pkg in ipairs(idx:GetChildren()) do
            if pkg.Name:find("knit", 1, true) then
                local mod = pkg:FindFirstChild("knit") or pkg:FindFirstChild("Knit")
                if mod then
                    local sc = versionScore(pkg.Name)
                    if not score or sc > score then best, score = pkg, sc end
                end
            end
        end
    end
    if not best then return nil end
    return best, best:FindFirstChild("knit") or best:FindFirstChild("Knit")
end

local function buildFromServices(lib)
    for svcName, svc in pairs(lib.Services) do
        local entry = { RE = {}, RF = {} }
        for _, tipo in ipairs({ "RE", "RF" }) do
            local grupo = svc[tipo]
            if type(grupo) == "table" then
                for k, v in pairs(grupo) do entry[tipo][tostring(k)] = v end
            end
        end
        DB.services[svcName] = entry
    end
end

-- pós-update: remotes em RS.Network.<Service>.RE/RF
local function loadNetwork()
    local net = RS:FindFirstChild("Network")
    if not net then return false end
    local n = 0
    for _, svc in ipairs(net:GetChildren()) do
        local e = { RE = {}, RF = {} }
        for _, tipo in ipairs({ "RE", "RF" }) do
            local g = svc:FindFirstChild(tipo)
            if g then
                for _, r in ipairs(g:GetChildren()) do
                    if r:IsA("RemoteEvent") or r:IsA("RemoteFunction")
                        or r:IsA("UnreliableRemoteEvent") then
                        e[tipo][r.Name] = r
                        DB.rawMap[r.Name] = DB.rawMap[r.Name] or r
                    end
                end
            end
        end
        DB.services[svc.Name] = e
        n = n + 1
    end
    DB.source = "network"
    return n > 0
end

local function loadKnit()
    local pkg, mod = findKnit()
    if not pkg then return false end

    local ok, lib = pcall(require, mod)
    if ok and type(lib) == "table" and lib.Services then
        buildFromServices(lib)
        DB.source = "knit-require"
        return true
    end

    -- builds que não deixam require: Services como pastas de filhos
    local svcFolder = pkg:FindFirstChild("Services") or (mod and mod:FindFirstChild("Services"))
    if svcFolder then
        local ok2, lib2 = pcall(require, svcFolder)
        if ok2 and type(lib2) == "table" then
            buildFromServices({ Services = lib2 })
            DB.source = "knit-folder"
            return true
        end
        -- varredura: pasta Service -> subpastas RE/RF
        local svcs = {}
        for _, s in ipairs(svcFolder:GetChildren()) do
            local e = { RE = {}, RF = {} }
            for _, tipo in ipairs({ "RE", "RF" }) do
                local g = s:FindFirstChild(tipo)
                if g then
                    for _, r in ipairs(g:GetChildren()) do e[tipo][r.Name] = r end
                end
            end
            svcs[s.Name] = e
        end
        DB.services = svcs
        DB.source = "knit-tree"
        return true
    end
    return false
end

-- ── 4. fallback por nome
local function findAnywhere(name)
    for _, d in ipairs(RS:GetDescendants()) do
        if d.Name == name and (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")
            or d:IsA("UnreliableRemoteEvent")) then
            return d
        end
    end
    return nil
end

-- ── API
function DB.rem(path)
    -- "Service.RE.Nome" | "Service.RF.Nome"
    local svc, tipo, nome = path:match("^([%w_]+)%.([%w_]+)%.([%w_]+)$")
    if not svc then return nil end
    local s = DB.services[svc]
    local inst = s and s[tipo] and s[tipo][nome]
    if typeof(inst) == "Instance" then return inst end
    return findAnywhere(nome)
end

function DB.svc(name)
    return DB.services[name]
end

function DB.raw(name)
    return DB.rawMap[name] or findAnywhere(name)
end

function DB.mapRaw()
    local pk = RS:FindFirstChild("Packages")
    local idx = pk and pk:FindFirstChild("_Index")
    if idx then
        for _, pkg in ipairs(idx:GetChildren()) do
            if pkg.Name:find("knit", 1, true) then
                local ok, lib = pcall(require, pkg:FindFirstChild("knit") or pkg:FindFirstChild("Knit"))
                if ok and type(lib) == "table" and lib.Services then
                    for svcName, svc in pairs(lib.Services) do
                        for _, tipo in ipairs({ "RE", "RF" }) do
                            if type(svc[tipo]) == "table" then
                                for k, v in pairs(svc[tipo]) do
                                    if typeof(v) == "Instance" then
                                        DB.rawMap[tostring(k)] = v
                                    end
                                end
                            end
                        end
                    end
                end
                break
            end
        end
    end
end

function DB.report()
    local svcCount, remoteCount = 0, 0
    for _ in pairs(DB.services) do svcCount = svcCount + 1 end
    for _ in pairs(DB.rawMap) do remoteCount = remoteCount + 1 end
    return ("DB.Resolver source=%s services=%d raw=%d"):format(DB.source, svcCount, remoteCount)
end

-- ── boot
if not loadMap() then
    loadKnit()
end
DB.mapRaw()

return DB
