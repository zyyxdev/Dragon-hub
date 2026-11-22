--[[
  ════════════════════════════════════════════════════════════════
   ZYYX DUMPER v8.0  —  Dragon Blox (foco: drops / itens / prompts)
  ════════════════════════════════════════════════════════════════
  O que captura:
    1. __namecall  -> todo FireServer / InvokeServer do cliente
    2. Server->Client -> conecta em TODOS os RemoteEvents e loga
    3. Prompts (PromptService.Prompt) e equipar item (Toolbar)
    4. Backpack.ChildAdded -> item que entrou na mochila
    5. Workspace.ChildAdded -> spawn de drop/boss (filtro por nome)
  Saída:
    - arquivo ZYYX_dump_v8_<place>_<ts>.txt (writefile)
    - clipboard
    - console
  Teclas:
    RightShift = pausa/retoma captura
    F9         = flush + salvar agora
  ════════════════════════════════════════════════════════════════
]]

-- impede duplicar
if getgenv and getgenv().__ZYYX_DUMP8 then
    pcall(function() getgenv().__ZYYX_DUMP8.stop() end)
end

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local WS      = game:GetService("Workspace")
local UIS     = game:GetService("UserInputService")
local plr     = Players.LocalPlayer

local TS = tostring(tonumber(tick()) or os.time())
local PLACE = tostring(game.PlaceId)
local FILE = "ZYYX_dump_v8_" .. PLACE .. "_" .. TS:gsub("%.", "") .. ".txt"

local S = {
    ativo = true,
    total = 0,
    unicos = 0,
    vistos = {},
    linhas = {},
    eventos = {},   -- remote events conectados
    hookado = false,
    inHook = false,
}

local function enc(s) return tostring(s) end

local function ser(v, d)
    d = d or 0
    if d > 4 then return "..." end
    local t = typeof(v)
    if t == "Instance" then
        local ok, p = pcall(function() return v:GetFullName() end)
        return "I(" .. (ok and p or v.Name) .. ")"
    elseif t == "Vector3" then
        return string.format("V3(%d,%d,%d)", v.X, v.Y, v.Z)
    elseif t == "CFrame" then
        local p = v.Position
        return string.format("CF(%d,%d,%d)", p.X, p.Y, p.Z)
    elseif t == "table" then
        local parts = {}
        local i = 0
        for k, x in pairs(v) do
            i = i + 1
            if i > 14 then parts[#parts + 1] = "..." break end
            parts[#parts + 1] = enc(k) .. "=" .. ser(x, d + 1)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "string" then
        return '"' .. v:gsub('"', "'"):sub(1, 120) .. '"'
    elseif t == "boolean" or t == "number" then
        return tostring(v)
    elseif t == "nil" then
        return "nil"
    else
        return t .. "(" .. enc(v) .. ")"
    end
end

local function registrar(cat, alvo, metodo, args, extra)
    if not S.ativo then return end
    local corpo = ""
    local ok = pcall(function() corpo = ser(args) end)
    if not ok then corpo = "?" end
    local chave = cat .. "|" .. alvo .. "|" .. metodo .. "|" .. corpo
    local c = S.vistos[chave]
    if c then
        c.n = c.n + 1
        if c.n ~= 2 and c.n % 25 ~= 0 then return end
        corpo = corpo .. "  [x" .. c.n .. "]"
    else
        S.vistos[chave] = { n = 1 }
        S.unicos = S.unicos + 1
    end
    S.total = S.total + 1
    local linha = string.format("%06d %s %s→ %s %s%s",
        S.total, cat, alvo, metodo, corpo, extra and (" " .. extra) or "")
    S.linhas[#S.linhas + 1] = linha
    if #S.linhas > 6000 then table.remove(S.linhas, 1) end
    if not c then
        pcall(print, "[DUMP8] " .. linha)
    end
end

-- ───────────────────────────── arquivo
local podeFile = (typeof(writefile) == "function") and (typeof(appendfile) == "function")
local cabecalho = table.concat({
    "=== ZYYX DUMPER v8.0 ===",
    "placeholder=" .. tostring(game.PlaceId),
    "player=" .. plr.Name,
    "inicio=" .. os.date("%Y-%m-%d %H:%M:%S"),
    "file=" .. FILE,
    "=========================",
}, "\n") .. "\n"

if podeFile then
    pcall(function()
        if typeof(isfile) == "function" and isfile(FILE) then
            writefile(FILE, cabecalho)
        else
            writefile(FILE, cabecalho)
        end
    end)
end

local function salvar()
    local txt = table.concat(S.linhas, "\n")
    if podeFile then
        pcall(writefile, FILE, cabecalho .. txt .. "\n")
    end
    if typeof(setclipboard) == "function" then
        pcall(setclipboard, txt)
    end
    pcall(print, "[DUMP8] salvo: " .. FILE .. " (" .. #S.linhas .. " linhas)")
end

-- ───────────────────────────── 1. eventos servidor->cliente
local function conectarEvento(inst)
    if S.eventos[inst] then return end
    if not inst:IsA("RemoteEvent") and not inst:IsA("UnreliableRemoteEvent") then return end
    S.eventos[inst] = true
    local nome = inst:GetFullName()
    pcall(function()
        inst.OnClientEvent:Connect(function(...)
            if not S.ativo then return end
            registrar("EVT", nome, "OnClient", { ... })
        end)
    end)
end

for _, d in ipairs(RS:GetDescendants()) do
    conectarEvento(d)
end
pcall(function()
    RS.DescendantAdded:Connect(function(d) conectarEvento(d) end)
end)

-- ───────────────────────────── 2. hook __namecall
local function instalarHook()
    if S.hookado then return end
    local getmt = getrawmetatable
    local hook = hookmetamethod
    if type(getmt) ~= "function" or type(hook) ~= "function" then
        registrar("SYS", "hook", "erro", "sem getrawmetatable/hookmetamethod")
        return
    end
    local mt = getmt(game)
    local old
    old = hook(game, "__namecall", function(self, ...)
        local metodo = getnamecallmethod()
        if not S.inHook and S.ativo and (metodo == "FireServer" or metodo == "InvokeServer")
            and not checkcaller() then
            S.inHook = true
            local args = table.pack(...)
            pcall(function()
                local alvo = tostring(self)
                if typeof(self) == "Instance" then
                    local ok, p = pcall(function() return self:GetFullName() end)
                    if ok then alvo = p end
                end
                registrar("CALL", alvo, metodo .. "→", args)
            end)
            S.inHook = false
        end
        return old(self, ...)
    end)
    S.hookado = true
    registrar("SYS", "hook", "ok", "__namecall instalado")
end
instalarHook()

-- ───────────────────────────── 3. prompts / toolbar (observa chamadas conhecidas)
local function observa(nomeServico, sub)
    local ok, svc = pcall(function()
        local Knit = RS.Packages._Index["sleitnick_knit@1.4.7"].knit
        return Knit.Services[nomeServico]
    end)
    if not ok or not svc then return end
    for _, tipo in ipairs({ "RE", "RF" }) do
        local grupo = svc[tipo]
        if grupo then
            for k in pairs(grupo) do
                registrar("SVC", nomeServico .. "." .. tipo .. "." .. tostring(k), "existe", "-")
            end
        end
    end
end
for _, s in ipairs({ "PromptService", "ToolService", "SkillManagerV2", "SkillManager",
                     "PlayerLevelService", "InventoryService", "DropService", "ItemService" }) do
    observa(s, nil)
end

-- ───────────────────────────── 4. backpack
pcall(function()
    local bp = plr:WaitForChild("Backpack", 10)
    if bp then
        bp.ChildAdded:Connect(function(it)
            registrar("BAG", it:GetFullName(), "entrou", { it.Name, it.ClassName })
        end)
    end
end)

-- ───────────────────────────── 5. workspace drops/boss
local filtro = { "drop", "item", "orb", "sword", "boss", "chest", "baú", "bau", "crate" }
pcall(function()
    WS.ChildAdded:Connect(function(it)
        local n = string.lower(it.Name)
        for _, f in ipairs(filtro) do
            if string.find(n, f, 1, true) then
                registrar("WS", it:GetFullName(), "spawn", { it.Name, it.ClassName })
                break
            end
        end
    end)
end)

-- ───────────────────────────── UI
local gui = Instance.new("ScreenGui")
gui.Name = "ZYYX_DUMP8"
gui.ResetOnSpawn = false
local parent = (typeof(gethui) == "function" and gethui()) or plr:WaitForChild("PlayerGui")
gui.Parent = parent

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 230, 0, 46)
frame.Position = UDim2.new(0, 12, 0, 12)
frame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
frame.BackgroundTransparency = 0.15
frame.BorderSizePixel = 0
frame.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

local lbl = Instance.new("TextLabel")
lbl.Size = UDim2.new(1, -10, 1, -10)
lbl.Position = UDim2.new(0, 5, 0, 5)
lbl.BackgroundTransparency = 1
lbl.Font = Enum.Font.Code
lbl.TextSize = 13
lbl.TextColor3 = Color3.fromRGB(120, 255, 140)
lbl.TextXAlignment = Enum.TextXAlignment.Left
lbl.TextYAlignment = Enum.TextYAlignment.Top
lbl.Parent = frame

task.spawn(function()
    while gui.Parent do
        lbl.Text = string.format("ZYYX DUMP8 %s\nlinhas:%d unicos:%d\n%s",
            S.ativo and "[ON]" or "[PAUSADO]", #S.linhas, S.unicos,
            podeFile and FILE or "sem writefile")
        task.wait(0.5)
    end
end)

-- ───────────────────────────── teclas
UIS.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == Enum.KeyCode.RightShift then
        S.ativo = not S.ativo
        registrar("SYS", "captura", S.ativo and "ON" or "OFF", "-")
    elseif inp.KeyCode == Enum.KeyCode.F9 then
        salvar()
    end
end)

-- ───────────────────────────── API global
getgenv = getgenv or function() return _G end
getgenv().__ZYYX_DUMP8 = {
    state = S,
    salvar = salvar,
    file = FILE,
    stop = function()
        S.ativo = false
        salvar()
        pcall(function() gui:Destroy() end)
        getgenv().__ZYYX_DUMP8 = nil
    end,
}

registrar("SYS", "start", "ok", { place = PLACE, player = plr.Name, file = FILE })
print("[DUMP8] rodando. RightShift pausa | F9 salva | getgenv().__ZYYX_DUMP8.stop() encerra")
