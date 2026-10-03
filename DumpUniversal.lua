print("[DUMPER v6.0] Iniciando...")

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local plr = Players.LocalPlayer

local targetParent = (gethui and gethui()) or CoreGui

-- ═══════════════════════════════════════════════
-- ESTADO
-- ═══════════════════════════════════════════════
local State = {
    sessao = "Sessao",
    capturando = false,
    hookAtivo = false,
    hookMetodo = "nenhum",
    trfBuf = {},
    arquitetural = {},
    unicos = {},
    nomesCache = {},
    contadorBruto = 0,
    filtros = {
        dungeon = true, skills = true, drops = true,
        bossEvent = true, swordOrb = true, toolbar = true,
        rebirth = true, ruido = false,
    },
    catAtiva = "captura",
    filtroLogCat = "todos",
}

local _hookFire = nil
local _hookInvoke = nil
local _nomecallOriginal = nil
local ultimoPath = {}
local RATE_LIMIT = 0.15
local MAX_UNICOS = 2000

-- ═══════════════════════════════════════════════
-- UTIL
-- ═══════════════════════════════════════════════
local function getNome(inst)
    if State.nomesCache[inst] then return State.nomesCache[inst] end
    local ok, n = pcall(function() return inst:GetFullName() end)
    n = ok and n or "?"
    State.nomesCache[inst] = n
    return n
end

local function log(cat, msg)
    print(string.format("[DUMPER/%s] %s", cat, msg))
end

-- ═══════════════════════════════════════════════
-- RUIDO
-- ═══════════════════════════════════════════════
local RUIDO = {
    "Ping","DataChanged","PlayAnimation","PlayEffect",
    "DamageLabel","DamageNotifier","Knockback","RagdollData",
    "UpdateLocal","Heartbeat","changeAnimationClient",
    "GameAnalytics","Postie",
}
local function ehRuido(path)
    if State.filtros.ruido then return false end
    for i = 1, #RUIDO do
        if path:find(RUIDO[i]) then return true end
    end
    return false
end

-- ═══════════════════════════════════════════════
-- CLASSIFICAR
-- ═══════════════════════════════════════════════
local function classificar(path)
    if path:find("Dungeon") or path:find("dungeon")
    or path:find("NextArea") or path:find("Wave") or path:find("Stage")
    or path:find("LobbyService") then return "DUNGEON" end
    if path:find("UpdatePlayerToolbar") or path:find("ToolService") then return "TOOLBAR" end
    if path:find("SkillRemote") then return "M1" end
    if path:find("ExecuteSkill") then return "SKILL" end
    if path:find("ClaimItem") or path:find("WishService")
    or path:find("ItemDropService") then return "DROP" end
    if path:find("Boss") or path:find("Zaja") or path:find("Destroyer") then return "BOSS" end
    if path:find("Weapon") or path:find("Orb") then return "SWORD_ORB" end
    if path:find("Rebirth") or path:find("Prompt") then return "REBIRTH" end
    if path:find("LockedOn") then return "LOCK" end
    if path:find("Event") then return "EVENT" end
    return "OTHER"
end

local CAT_INFO = {
    DUNGEON   = { icone = "🎮", cor = "00FFC6", nome = "Dungeon" },
    M1        = { icone = "🖱", cor = "5FE8FF", nome = "M1/Ataque" },
    SKILL     = { icone = "⚔️", cor = "C68AFF", nome = "Skills" },
    DROP      = { icone = "💰", cor = "5FDC78", nome = "Drops" },
    BOSS      = { icone = "👹", cor = "FF5C5C", nome = "Bosses" },
    SWORD_ORB = { icone = "🔮", cor = "FFE45C", nome = "Armas/Orbs" },
    TOOLBAR   = { icone = "🎒", cor = "FF9AC6", nome = "Toolbar" },
    REBIRTH   = { icone = "🔄", cor = "FF9642", nome = "Rebirth" },
    LOCK      = { icone = "🔒", cor = "8AFF8A", nome = "Lock-On" },
    EVENT     = { icone = "📢", cor = "9A9AA0", nome = "Eventos" },
    OTHER     = { icone = "❔", cor = "9A9AA0", nome = "Outros" },
}

-- ═══════════════════════════════════════════════
-- SERIALIZAR
-- ═══════════════════════════════════════════════
local function ser(v, d)
    d = d or 0
    if d > 2 then return "..." end
    local t = typeof(v)
    if t == "Instance" then return getNome(v) end
    if t == "Vector3" then
        return string.format("V3(%.0f,%.0f,%.0f)", v.X, v.Y, v.Z)
    end
    if t == "CFrame" then
        local p = v.Position
        return string.format("CF(%.0f,%.0f,%.0f)", p.X, p.Y, p.Z)
    end
    if t == "table" then
        local p, n = {}, 0
        for k, vv in pairs(v) do
            n = n + 1
            if n > 6 then p[#p+1] = "..." break end
            p[#p+1] = tostring(k).."="..ser(vv, d+1)
        end
        return "{"..table.concat(p,",").."}"
    end
    return "["..t.."] "..tostring(v)
end

-- ═══════════════════════════════════════════════
-- ADICIONAR TRAFEGO
-- ═══════════════════════════════════════════════
local function addTrafego(cat, path, args)
    State.contadorBruto = State.contadorBruto + 1
    if cat == "EVENT" and (args == "" or args == nil) then return end
    local chave = cat.."|"..path.."|"..args
    if State.unicos[chave] then
        State.unicos[chave].count = State.unicos[chave].count + 1
        State.unicos[chave].ultimo = os.date("%H:%M:%S")
        return
    end
    local entry = {
        cat = cat, path = path, args = args, count = 1,
        primeiro = os.date("%H:%M:%S"), ultimo = os.date("%H:%M:%S"),
    }
    State.unicos[chave] = entry
    table.insert(State.trfBuf, entry)
    print(string.format("[CAP/%s] %s | %s", cat, path, args))
    if #State.trfBuf > MAX_UNICOS then
        local rem = table.remove(State.trfBuf, 1)
        for k, v in pairs(State.unicos) do
            if v == rem then State.unicos[k] = nil break end
        end
    end
end

-- ═══════════════════════════════════════════════
-- PROCESSAR CHAMADA
-- ═══════════════════════════════════════════════
local function processarChamada(self, ...)
    if not State.capturando then return end
    local n = select("#", ...)
    local args = {...}
    local ok, path = pcall(function() return self:GetFullName() end)
    if not ok or not path then return end
    if ehRuido(path) then return end

    local agora = os.clock()
    if ultimoPath[path] and (agora - ultimoPath[path]) < RATE_LIMIT then return end
    ultimoPath[path] = agora

    local cat = classificar(path)
    local aceito = false
    local f = State.filtros
    if cat == "DUNGEON" and f.dungeon then aceito = true end
    if (cat == "M1" or cat == "SKILL" or cat == "LOCK") and f.skills then aceito = true end
    if cat == "DROP" and f.drops then aceito = true end
    if cat == "BOSS" and f.bossEvent then aceito = true end
    if cat == "SWORD_ORB" and f.swordOrb then aceito = true end
    if cat == "TOOLBAR" and f.toolbar then aceito = true end
    if cat == "REBIRTH" and f.rebirth then aceito = true end
    if cat == "EVENT" then aceito = true end
    if f.ruido then aceito = true end
    if not aceito then return end

    local parts = {}
    for i = 1, math.min(n, 6) do
        parts[#parts+1] = ser(args[i])
    end
    addTrafego(cat, path:gsub("ReplicatedStorage%.", "RS."), table.concat(parts, " | "))
end

-- ═══════════════════════════════════════════════
-- HOOK (método compartilhado — ÚNICO que funciona no Delta)
-- ═══════════════════════════════════════════════
local function instalarHook()
    if State.hookAtivo then return end

    if not hookfunction then
        State.hookMetodo = "SEM-HOOKFUNCTION"
        log("ERROR", "Executor sem hookfunction")
        return
    end

    local re = Instance.new("RemoteEvent")
    local rf = Instance.new("RemoteFunction")
    local okFire, okInv = false, false

    pcall(function()
        _hookFire = hookfunction(re.FireServer, function(self, ...)
            pcall(processarChamada, self, ...)
            return _hookFire(self, ...)
        end)
        okFire = true
    end)

    pcall(function()
        _hookInvoke = hookfunction(rf.InvokeServer, function(self, ...)
            pcall(processarChamada, self, ...)
            return _hookInvoke(self, ...)
        end)
        okInv = true
    end)

    if okFire or okInv then
        State.hookAtivo = true
        State.hookMetodo = "hookfunction"
        log("SUCCESS", "✅ Hook ativo (FireServer="..tostring(okFire).." InvokeServer="..tostring(okInv)..")")
    else
        State.hookMetodo = "FALHOU"
        log("ERROR", "❌ Hook falhou")
    end
end

local function removerHook()
    if _hookFire and hookfunction then
        pcall(function() hookfunction(Instance.new("RemoteEvent").FireServer, _hookFire) end)
        _hookFire = nil
    end
    if _hookInvoke and hookfunction then
        pcall(function() hookfunction(Instance.new("RemoteFunction").InvokeServer, _hookInvoke) end)
        _hookInvoke = nil
    end
    State.hookAtivo = false
end

-- ═══════════════════════════════════════════════
-- DIAGNÓSTICO
-- ═══════════════════════════════════════════════
local function diagnostico()
    log("INFO", "════════ DIAGNÓSTICO ════════")
    log("INFO", "Executor: "..tostring(identifyexecutor and identifyexecutor() or "?"))
    log("INFO", "hookfunction: "..tostring(hookfunction ~= nil))
    log("INFO", "hookmetamethod: "..tostring(hookmetamethod ~= nil))
    log("INFO", "Hook instalado: "..tostring(State.hookAtivo))
    log("INFO", "Método: "..State.hookMetodo)
    local rem = RS:FindFirstChild("Remotes")
    if rem then
        local lista = {}
        for _, c in ipairs(rem:GetChildren()) do
            if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then
                table.insert(lista, c.Name.." ("..c.ClassName..")")
            end
        end
        log("INFO", "Remotes em RS.Remotes ("..#lista.."): "..table.concat(lista, ", "))
    else
        log("WARN", "RS.Remotes não encontrado")
    end
end

-- ═══════════════════════════════════════════════
-- SCANNER WORKSPACE
-- ═══════════════════════════════════════════════
task.spawn(function()
    local conhecidos = {}
    while true do
        task.wait(3)
        if State.capturando then
            local wm = WS:FindFirstChild("World Mobs")
            local ps = WS:FindFirstChild("PartStorage")

            if wm and State.filtros.bossEvent then
                local ev = wm:FindFirstChild("Event Mobs")
                if ev then
                    for _, obj in ipairs(ev:GetChildren()) do
                        if not conhecidos[obj] and obj:IsA("Model") then
                            conhecidos[obj] = true
                            local hrp = obj:FindFirstChild("HumanoidRootPart")
                            if hrp then
                                addTrafego("BOSS", "WS.Event Mobs."..obj.Name,
                                    string.format("V3(%.0f,%.0f,%.0f)", hrp.Position.X, hrp.Position.Y, hrp.Position.Z))
                            end
                        end
                    end
                end
            end

            if ps and State.filtros.drops then
                for _, obj in ipairs(ps:GetChildren()) do
                    if not conhecidos[obj] and obj:IsA("Model") then
                        conhecidos[obj] = true
                        local base = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
                        if base then
                            addTrafego("DROP", "WS.PartStorage."..obj.Name,
                                string.format("V3(%.0f,%.0f,%.0f)", base.Position.X, base.Position.Y, base.Position.Z))
                        end
                    end
                end
            end

            if State.filtros.dungeon then
                for _, obj in ipairs(WS:GetChildren()) do
                    local nm = obj.Name:lower()
                    if (nm:find("dungeon") or nm:find("portal") or nm:find("gate"))
                    and not conhecidos[obj] then
                        conhecidos[obj] = true
                        local pos = obj:IsA("BasePart") and obj.Position
                            or (obj.PrimaryPart and obj.PrimaryPart.Position)
                        if pos then
                            addTrafego("DUNGEON", "WS."..obj.Name,
                                string.format("V3(%.0f,%.0f,%.0f)", pos.X, pos.Y, pos.Z))
                        end
                    end
                end
            end

            if #State.trfBuf > MAX_UNICOS * 0.8 then
                State.nomesCache = {}
            end
        end
    end
end)

-- ═══════════════════════════════════════════════
-- SCAN ARQ
-- ═══════════════════════════════════════════════
local function scanArquitetural()
    State.arquitetural = {}
    log("INFO", "Scan arquitetural iniciado...")
    task.spawn(function()
        local t0 = os.clock()
        local total = 0
        local function varrer(inst, path, depth)
            if depth > 8 or not inst then return end
            task.wait()
            local ok, ch = pcall(function() return inst:GetChildren() end)
            if not ok then return end
            for _, c in ipairs(ch) do
                local cls = c.ClassName
                if cls == "RemoteEvent" or cls == "RemoteFunction"
                or cls == "UnreliableRemoteEvent" then
                    table.insert(State.arquitetural, {
                        tipo = "REMOTE", cls = cls, path = path.."."..c.Name
                    })
                    total = total + 1
                elseif cls == "ModuleScript" then
                    table.insert(State.arquitetural, {
                        tipo = "MODULE", cls = cls, path = path.."."..c.Name
                    })
                    total = total + 1
                end
                if cls == "Folder" or cls == "Model" then
                    varrer(c, path.."."..c.Name, depth + 1)
                end
            end
        end
        pcall(function() varrer(RS, "RS", 0) end)
        log("SUCCESS", string.format("Scan: %.2fs — %d itens", os.clock() - t0, total))
    end)
end

-- ═══════════════════════════════════════════════
-- SALVAR (estrutura organizada)
-- ═══════════════════════════════════════════════
local function salvarArquivo()
    local L = {}
    local function add(s) table.insert(L, s or "") end

    add("╔══════════════════════════════════════════════════════╗")
    add("║        🐉 DUMPER v6.0 — RELATÓRIO DE SESSÃO          ║")
    add("╚══════════════════════════════════════════════════════╝")
    add("")
    add("┌─ 📋 METADATA ────────────────────────────────────────")
    add("│ Player:       "..plr.Name)
    add("│ PlaceId:      "..game.PlaceId)
    add("│ JobId:        "..(game.JobId ~= "" and game.JobId or "privado"))
    add("│ Data:         "..os.date("%Y-%m-%d %H:%M:%S"))
    add("│ Sessão:       "..State.sessao)
    add("│ Hook:         "..State.hookMetodo)
    add("│ Bruto:        "..State.contadorBruto.." chamadas")
    add("│ Únicos:       "..#State.trfBuf.." entradas")
    add("└──────────────────────────────────────────────────────")
    add("")

    -- Agrupa por categoria
    local porCat = {}
    for _, t in ipairs(State.trfBuf) do
        porCat[t.cat] = porCat[t.cat] or {}
        table.insert(porCat[t.cat], t)
    end

    add("╔══════════════════════════════════════════════════════╗")
    add("║              📡 TRÁFEGO CAPTURADO                    ║")
    add("╚══════════════════════════════════════════════════════╝")
    add("")

    local ordem = {"DUNGEON","M1","SKILL","DROP","BOSS","SWORD_ORB",
                   "TOOLBAR","REBIRTH","LOCK","EVENT","OTHER"}

    for _, cat in ipairs(ordem) do
        if porCat[cat] and #porCat[cat] > 0 then
            local info = CAT_INFO[cat] or CAT_INFO.OTHER
            add("")
            add("┏━━ "..info.icone.." "..string.upper(info.nome)..
                " ── "..#porCat[cat].." entradas "..
                string.rep("━", math.max(1, 40 - #info.nome)).."┓")
            for _, t in ipairs(porCat[cat]) do
                if t.count > 1 then
                    add("┃ ▸ "..t.path)
                    add("┃   ⏱ "..t.primeiro.." ~ "..t.ultimo.."  (×"..t.count.." chamadas)")
                    add("┃   ↳ "..t.args)
                else
                    add("┃ ▸ "..t.path)
                    add("┃   ⏱ "..t.primeiro)
                    add("┃   ↳ "..t.args)
                end
                add("┃")
            end
            add("┗"..string.rep("━", 54).."┛")
        end
    end

    if #State.arquitetural > 0 then
        add("")
        add("╔══════════════════════════════════════════════════════╗")
        add("║              🏗️  ESTRUTURA ARQUITETURAL              ║")
        add("╚══════════════════════════════════════════════════════╝")
        add("")

        local remotes, modules = {}, {}
        for _, item in ipairs(State.arquitetural) do
            if item.tipo == "REMOTE" then
                table.insert(remotes, item)
            else
                table.insert(modules, item)
            end
        end

        if #remotes > 0 then
            add("┏━━ 📡 REMOTES ── "..#remotes.." ━━━━━━━━━━━━━━━━━━━━━━━━━┓")
            for _, r in ipairs(remotes) do
                add("┃ ["..r.cls.."] "..r.path)
            end
            add("┗"..string.rep("━", 54).."┛")
            add("")
        end

        if #modules > 0 then
            add("┏━━ 📦 MODULES ── "..#modules.." ━━━━━━━━━━━━━━━━━━━━━━━━━┓")
            for _, m in ipairs(modules) do
                add("┃ "..m.path)
            end
            add("┗"..string.rep("━", 54).."┛")
        end
    end

    add("")
    add("╔══════════════════════════════════════════════════════╗")
    add("║  Fim do dump — "..os.date("%Y-%m-%d %H:%M:%S").."            ║")
    add("╚══════════════════════════════════════════════════════╝")

    local conteudo = table.concat(L, "\n")
    local nome = "Dump_"..State.sessao.."_"..os.time()..".txt"
    local ok = pcall(function() if writefile then writefile(nome, conteudo) end end)
    if ok then
        log("SUCCESS", "Salvo: "..nome.." ("..#conteudo.."b)")
        return
    end
    pcall(function() setclipboard(conteudo) end)
    log("SUCCESS", "Clipboard ("..#conteudo.."b)")
end

-- ═══════════════════════════════════════════════
-- UI
-- ═══════════════════════════════════════════════
local old = targetParent:FindFirstChild("DumperFinal")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "DumperFinal"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
if syn and syn.protect_gui then
    pcall(function() syn.protect_gui(gui) end)
end
gui.Parent = targetParent

local T = {
    bg         = Color3.fromRGB(0, 0, 0),
    panel      = Color3.fromRGB(10, 10, 12),
    elev       = Color3.fromRGB(20, 20, 24),
    elevHover  = Color3.fromRGB(30, 30, 36),
    border     = Color3.fromRGB(38, 38, 46),
    accent     = Color3.fromRGB(0, 255, 198),
    accent2    = Color3.fromRGB(0, 180, 140),
    text       = Color3.fromRGB(240, 240, 245),
    textDim    = Color3.fromRGB(140, 145, 155),
    textMuted  = Color3.fromRGB(90, 95, 105),
    success    = Color3.fromRGB(80, 220, 140),
    danger     = Color3.fromRGB(255, 90, 90),
    warn       = Color3.fromRGB(255, 180, 60),
    info       = Color3.fromRGB(90, 170, 255),
}

local function safeUI(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            print("[DUMPER/UI-ERRO] "..tostring(err))
        end
    end
end

-- ═══════ JANELA PRINCIPAL ═══════
local W = 540
local H = 620

local main = Instance.new("Frame")
main.Size = UDim2.new(0, W, 0, H)
main.Position = UDim2.new(0.5, -W/2, 0.5, -H/2)
main.BackgroundColor3 = T.bg
main.BackgroundTransparency = 0.08
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 14)
local mStroke = Instance.new("UIStroke", main)
mStroke.Color = T.border
mStroke.Thickness = 1
mStroke.Transparency = 0.4

-- ═══════ HEADER ═══════
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 42)
header.BackgroundTransparency = 1
header.Parent = main

local titulo = Instance.new("TextLabel")
titulo.Size = UDim2.new(1, -140, 1, 0)
titulo.Position = UDim2.new(0, 18, 0, 0)
titulo.BackgroundTransparency = 1
titulo.Text = "🐉  DUMPER"
titulo.TextColor3 = T.accent
titulo.Font = Enum.Font.GothamBold
titulo.TextSize = 14
titulo.TextXAlignment = Enum.TextXAlignment.Left
titulo.Parent = header

local statusDot = Instance.new("Frame")
statusDot.Size = UDim2.new(0, 8, 0, 8)
statusDot.Position = UDim2.new(1, -116, 0.5, -4)
statusDot.BackgroundColor3 = T.textMuted
statusDot.BorderSizePixel = 0
statusDot.Parent = header
Instance.new("UICorner", statusDot).CornerRadius = UDim.new(1, 0)

local statusTxt = Instance.new("TextLabel")
statusTxt.Size = UDim2.new(0, 70, 1, 0)
statusTxt.Position = UDim2.new(1, -104, 0, 0)
statusTxt.BackgroundTransparency = 1
statusTxt.Text = "parado"
statusTxt.TextColor3 = T.textDim
statusTxt.Font = Enum.Font.GothamMedium
statusTxt.TextSize = 10
statusTxt.TextXAlignment = Enum.TextXAlignment.Left
statusTxt.Parent = header

local btnMin = Instance.new("TextButton")
btnMin.Size = UDim2.new(0, 26, 0, 26)
btnMin.Position = UDim2.new(1, -68, 0.5, -13)
btnMin.BackgroundColor3 = T.elev
btnMin.Text = "—"
btnMin.TextColor3 = T.text
btnMin.Font = Enum.Font.GothamBold
btnMin.TextSize = 14
btnMin.BorderSizePixel = 0
btnMin.AutoButtonColor = false
btnMin.Parent = header
Instance.new("UICorner", btnMin).CornerRadius = UDim.new(0, 6)

local btnKill = Instance.new("TextButton")
btnKill.Size = UDim2.new(0, 26, 0, 26)
btnKill.Position = UDim2.new(1, -36, 0.5, -13)
btnKill.BackgroundColor3 = T.elev
btnKill.Text = "×"
btnKill.TextColor3 = T.danger
btnKill.Font = Enum.Font.GothamBold
btnKill.TextSize = 16
btnKill.BorderSizePixel = 0
btnKill.AutoButtonColor = false
btnKill.Parent = header
Instance.new("UICorner", btnKill).CornerRadius = UDim.new(0, 6)

-- ═══════ SIDEBAR ═══════
local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 118, 1, -78)
sidebar.Position = UDim2.new(0, 12, 0, 50)
sidebar.BackgroundColor3 = T.panel
sidebar.BackgroundTransparency = 0.35
sidebar.BorderSizePixel = 0
sidebar.Parent = main
Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0, 10)

local sbList = Instance.new("UIListLayout", sidebar)
sbList.Padding = UDim.new(0, 4)
sbList.SortOrder = Enum.SortOrder.LayoutOrder
local sbPad = Instance.new("UIPadding", sidebar)
sbPad.PaddingTop = UDim.new(0, 6)
sbPad.PaddingLeft = UDim.new(0, 6)
sbPad.PaddingRight = UDim.new(0, 6)

local sidebarItens = {}

local function criarItemSidebar(id, icone, nome, subtituloFn)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 52)
    btn.BackgroundColor3 = T.elev
    btn.BackgroundTransparency = 0.5
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.Parent = sidebar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

    local ic = Instance.new("TextLabel")
    ic.Size = UDim2.new(0, 26, 0, 26)
    ic.Position = UDim2.new(0, 8, 0, 6)
    ic.BackgroundTransparency = 1
    ic.Text = icone
    ic.TextSize = 16
    ic.TextColor3 = T.text
    ic.Font = Enum.Font.GothamBold
    ic.Parent = btn

    local nm = Instance.new("TextLabel")
    nm.Size = UDim2.new(1, -40, 0, 16)
    nm.Position = UDim2.new(0, 38, 0, 8)
    nm.BackgroundTransparency = 1
    nm.Text = nome
    nm.TextColor3 = T.text
    nm.TextSize = 11
    nm.Font = Enum.Font.GothamBold
    nm.TextXAlignment = Enum.TextXAlignment.Left
    nm.Parent = btn

    local sub = Instance.new("TextLabel")
    sub.Size = UDim2.new(1, -14, 0, 14)
    sub.Position = UDim2.new(0, 10, 0, 32)
    sub.BackgroundTransparency = 1
    sub.Text = "—"
    sub.TextColor3 = T.textMuted
    sub.TextSize = 9
    sub.Font = Enum.Font.GothamMedium
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.Parent = btn

    sidebarItens[id] = { btn = btn, sub = sub, subFn = subtituloFn }

    btn.MouseButton1Click:Connect(safeUI(function()
        State.catAtiva = id
        atualizarSidebar()
        atualizarConteudo()
    end))

    return btn
end

-- ═══════ CONTEÚDO ═══════
local content = Instance.new("Frame")
content.Size = UDim2.new(1, -142, 1, -78)
content.Position = UDim2.new(0, 130, 0, 50)
content.BackgroundColor3 = T.panel
content.BackgroundTransparency = 0.35
content.BorderSizePixel = 0
content.Parent = main
Instance.new("UICorner", content).CornerRadius = UDim.new(0, 10)

-- Painel CAPTURA
local painelCaptura = Instance.new("Frame")
painelCaptura.Size = UDim2.new(1, 0, 1, 0)
painelCaptura.BackgroundTransparency = 1
painelCaptura.Parent = content

local inputSessao = Instance.new("TextBox")
inputSessao.Size = UDim2.new(1, -24, 0, 36)
inputSessao.Position = UDim2.new(0, 12, 0, 12)
inputSessao.BackgroundColor3 = T.elev
inputSessao.Text = "Sessao"
inputSessao.PlaceholderText = "Nome da sessão..."
inputSessao.TextColor3 = T.text
inputSessao.PlaceholderColor3 = T.textMuted
inputSessao.Font = Enum.Font.GothamMedium
inputSessao.TextSize = 12
inputSessao.BorderSizePixel = 0
inputSessao.ClearTextOnFocus = false
inputSessao.Parent = painelCaptura
Instance.new("UICorner", inputSessao).CornerRadius = UDim.new(0, 8)
local ip = Instance.new("UIPadding", inputSessao)
ip.PaddingLeft = UDim.new(0, 12)

local btnCap = Instance.new("TextButton")
btnCap.Size = UDim2.new(1, -24, 0, 48)
btnCap.Position = UDim2.new(0, 12, 0, 58)
btnCap.BackgroundColor3 = T.accent
btnCap.Text = "▶  INICIAR CAPTURA"
btnCap.TextColor3 = T.bg
btnCap.Font = Enum.Font.GothamBold
btnCap.TextSize = 13
btnCap.BorderSizePixel = 0
btnCap.AutoButtonColor = false
btnCap.Parent = painelCaptura
Instance.new("UICorner", btnCap).CornerRadius = UDim.new(0, 8)

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, -24, 0, 30)
hint.Position = UDim2.new(0, 12, 0, 112)
hint.BackgroundTransparency = 1
hint.Text = "Após iniciar, faça ações no jogo — ataque, use skills, entre na dungeon."
hint.TextColor3 = T.textMuted
hint.TextSize = 10
hint.Font = Enum.Font.GothamMedium
hint.TextWrapped = true
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.Parent = painelCaptura

local feedTitulo = Instance.new("TextLabel")
feedTitulo.Size = UDim2.new(1, -24, 0, 20)
feedTitulo.Position = UDim2.new(0, 12, 0, 148)
feedTitulo.BackgroundTransparency = 1
feedTitulo.Text = "FLUXO RECENTE"
feedTitulo.TextColor3 = T.textDim
feedTitulo.TextSize = 9
feedTitulo.Font = Enum.Font.GothamBold
feedTitulo.TextXAlignment = Enum.TextXAlignment.Left
feedTitulo.Parent = painelCaptura

local feedScroll = Instance.new("ScrollingFrame")
feedScroll.Size = UDim2.new(1, -24, 1, -180)
feedScroll.Position = UDim2.new(0, 12, 0, 172)
feedScroll.BackgroundColor3 = T.bg
feedScroll.BackgroundTransparency = 0.5
feedScroll.BorderSizePixel = 0
feedScroll.ScrollBarThickness = 3
feedScroll.ScrollBarImageColor3 = T.border
feedScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
feedScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
feedScroll.Parent = painelCaptura
Instance.new("UICorner", feedScroll).CornerRadius = UDim.new(0, 8)
local fpad = Instance.new("UIPadding", feedScroll)
fpad.PaddingLeft = UDim.new(0, 10)
fpad.PaddingTop = UDim.new(0, 8)
fpad.PaddingRight = UDim.new(0, 10)
fpad.PaddingBottom = UDim.new(0, 8)

local feedText = Instance.new("TextLabel")
feedText.Size = UDim2.new(1, 0, 0, 0)
feedText.BackgroundTransparency = 1
feedText.TextColor3 = T.text
feedText.Font = Enum.Font.Code
feedText.TextSize = 10
feedText.TextXAlignment = Enum.TextXAlignment.Left
feedText.TextYAlignment = Enum.TextYAlignment.Top
feedText.TextWrapped = true
feedText.RichText = true
feedText.AutomaticSize = Enum.AutomaticSize.Y
feedText.Parent = feedScroll

-- Painel FILTROS
local painelFiltros = Instance.new("Frame")
painelFiltros.Size = UDim2.new(1, 0, 1, 0)
painelFiltros.BackgroundTransparency = 1
painelFiltros.Visible = false
painelFiltros.Parent = content

local filtrosScroll = Instance.new("ScrollingFrame")
filtrosScroll.Size = UDim2.new(1, -24, 1, -24)
filtrosScroll.Position = UDim2.new(0, 12, 0, 12)
filtrosScroll.BackgroundTransparency = 1
filtrosScroll.BorderSizePixel = 0
filtrosScroll.ScrollBarThickness = 3
filtrosScroll.ScrollBarImageColor3 = T.border
filtrosScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
filtrosScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
filtrosScroll.Parent = painelFiltros
local flList = Instance.new("UIListLayout", filtrosScroll)
flList.Padding = UDim.new(0, 4)

local function criarFiltro(icone, nome, descricao, key)
    local f = Instance.new("TextButton")
    f.Size = UDim2.new(1, 0, 0, 44)
    f.BackgroundColor3 = State.filtros[key] and T.elevHover or T.elev
    f.BackgroundTransparency = 0.3
    f.Text = ""
    f.AutoButtonColor = false
    f.BorderSizePixel = 0
    f.Parent = filtrosScroll
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)

    local ic = Instance.new("TextLabel")
    ic.Size = UDim2.new(0, 24, 0, 24)
    ic.Position = UDim2.new(0, 10, 0.5, -12)
    ic.BackgroundTransparency = 1
    ic.Text = icone
    ic.TextSize = 15
    ic.Parent = f

    local nm = Instance.new("TextLabel")
    nm.Size = UDim2.new(1, -100, 0, 16)
    nm.Position = UDim2.new(0, 40, 0, 6)
    nm.BackgroundTransparency = 1
    nm.Text = nome
    nm.TextColor3 = T.text
    nm.TextSize = 11
    nm.Font = Enum.Font.GothamBold
    nm.TextXAlignment = Enum.TextXAlignment.Left
    nm.Parent = f

    local ds = Instance.new("TextLabel")
    ds.Size = UDim2.new(1, -100, 0, 14)
    ds.Position = UDim2.new(0, 40, 0, 22)
    ds.BackgroundTransparency = 1
    ds.Text = descricao
    ds.TextColor3 = T.textMuted
    ds.TextSize = 9
    ds.Font = Enum.Font.GothamMedium
    ds.TextXAlignment = Enum.TextXAlignment.Left
    ds.Parent = f

    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 10, 0, 10)
    dot.Position = UDim2.new(1, -22, 0.5, -5)
    dot.BackgroundColor3 = State.filtros[key] and T.accent or T.textMuted
    dot.BorderSizePixel = 0
    dot.Parent = f
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    f.MouseButton1Click:Connect(safeUI(function()
        State.filtros[key] = not State.filtros[key]
        local ativo = State.filtros[key]
        f.BackgroundColor3 = ativo and T.elevHover or T.elev
        dot.BackgroundColor3 = ativo and T.accent or T.textMuted
        atualizarSidebar()
    end))
end

criarFiltro("🎮", "Dungeon", "Remotes de dungeon, waves, stages", "dungeon")
criarFiltro("⚔️", "Skills / M1", "ExecuteSkill, SkillRemote, Lock-On", "skills")
criarFiltro("💰", "Drops", "ClaimItem, Wish, ItemDrop", "drops")
criarFiltro("👹", "Bosses", "Event Mobs spawns", "bossEvent")
criarFiltro("🔮", "Armas / Orbs", "Weapon e Orb remotes", "swordOrb")
criarFiltro("🎒", "Toolbar", "Troca de slots", "toolbar")
criarFiltro("🔄", "Rebirth", "Prompt + RequestRebirth", "rebirth")
criarFiltro("🔊", "Ruído", "⚠ Loga TUDO (pode lagar)", "ruido")

-- Painel LOGS
local painelLogs = Instance.new("Frame")
painelLogs.Size = UDim2.new(1, 0, 1, 0)
painelLogs.BackgroundTransparency = 1
painelLogs.Visible = false
painelLogs.Parent = content

local logTabs = Instance.new("Frame")
logTabs.Size = UDim2.new(1, -24, 0, 28)
logTabs.Position = UDim2.new(0, 12, 0, 12)
logTabs.BackgroundTransparency = 1
logTabs.Parent = painelLogs
local ltLayout = Instance.new("UIListLayout", logTabs)
ltLayout.FillDirection = Enum.FillDirection.Horizontal
ltLayout.Padding = UDim.new(0, 4)

local filtroLogBtns = {}
local function criarTabLog(cat, label)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 58, 1, 0)
    b.BackgroundColor3 = T.elev
    b.BackgroundTransparency = 0.3
    b.Text = label
    b.TextColor3 = T.textDim
    b.Font = Enum.Font.GothamBold
    b.TextSize = 9
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Parent = logTabs
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    filtroLogBtns[cat] = b
    b.MouseButton1Click:Connect(safeUI(function()
        State.filtroLogCat = cat
        for c, bt in pairs(filtroLogBtns) do
            bt.BackgroundColor3 = (c == cat) and T.accent2 or T.elev
            bt.TextColor3 = (c == cat) and T.bg or T.textDim
        end
    end))
end

criarTabLog("todos", "todos")
criarTabLog("DUNGEON", "dung")
criarTabLog("SKILL", "skill")
criarTabLog("DROP", "drop")
criarTabLog("BOSS", "boss")
criarTabLog("M1", "m1")

local logsScroll = Instance.new("ScrollingFrame")
logsScroll.Size = UDim2.new(1, -24, 1, -54)
logsScroll.Position = UDim2.new(0, 12, 0, 46)
logsScroll.BackgroundColor3 = T.bg
logsScroll.BackgroundTransparency = 0.5
logsScroll.BorderSizePixel = 0
logsScroll.ScrollBarThickness = 3
logsScroll.ScrollBarImageColor3 = T.border
logsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
logsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
logsScroll.Parent = painelLogs
Instance.new("UICorner", logsScroll).CornerRadius = UDim.new(0, 8)
local lp = Instance.new("UIPadding", logsScroll)
lp.PaddingLeft = UDim.new(0, 10)
lp.PaddingTop = UDim.new(0, 8)
lp.PaddingRight = UDim.new(0, 10)
lp.PaddingBottom = UDim.new(0, 8)

local logsText = Instance.new("TextLabel")
logsText.Size = UDim2.new(1, 0, 0, 0)
logsText.BackgroundTransparency = 1
logsText.TextColor3 = T.text
logsText.Font = Enum.Font.Code
logsText.TextSize = 10
logsText.TextXAlignment = Enum.TextXAlignment.Left
logsText.TextYAlignment = Enum.TextYAlignment.Top
logsText.TextWrapped = true
logsText.RichText = true
logsText.AutomaticSize = Enum.AutomaticSize.Y
logsText.Parent = logsScroll

-- Painel ARQUIVO
local painelArquivo = Instance.new("Frame")
painelArquivo.Size = UDim2.new(1, 0, 1, 0)
painelArquivo.BackgroundTransparency = 1
painelArquivo.Visible = false
painelArquivo.Parent = content

local function mkBotaoAcao(y, icone, nome, desc, cor, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -24, 0, 54)
    b.Position = UDim2.new(0, 12, 0, y)
    b.BackgroundColor3 = T.elev
    b.BackgroundTransparency = 0.3
    b.Text = ""
    b.AutoButtonColor = false
    b.BorderSizePixel = 0
    b.Parent = painelArquivo
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)

    local ic = Instance.new("TextLabel")
    ic.Size = UDim2.new(0, 32, 0, 32)
    ic.Position = UDim2.new(0, 12, 0.5, -16)
    ic.BackgroundTransparency = 1
    ic.Text = icone
    ic.TextSize = 20
    ic.Parent = b

    local nm = Instance.new("TextLabel")
    nm.Size = UDim2.new(1, -70, 0, 18)
    nm.Position = UDim2.new(0, 54, 0, 8)
    nm.BackgroundTransparency = 1
    nm.Text = nome
    nm.TextColor3 = cor
    nm.TextSize = 12
    nm.Font = Enum.Font.GothamBold
    nm.TextXAlignment = Enum.TextXAlignment.Left
    nm.Parent = b

    local ds = Instance.new("TextLabel")
    ds.Size = UDim2.new(1, -70, 0, 16)
    ds.Position = UDim2.new(0, 54, 0, 28)
    ds.BackgroundTransparency = 1
    ds.Text = desc
    ds.TextColor3 = T.textMuted
    ds.TextSize = 9
    ds.Font = Enum.Font.GothamMedium
    ds.TextXAlignment = Enum.TextXAlignment.Left
    ds.Parent = b

    b.MouseButton1Click:Connect(safeUI(cb))
end

mkBotaoAcao(12, "📁", "Scan Arquitetural", "Mapeia todos os remotes e modules do jogo", T.info, function()
    scanArquitetural()
end)

mkBotaoAcao(74, "💾", "Salvar Dump", "Gera .txt com estrutura organizada", T.accent, function()
    State.sessao = inputSessao.Text ~= "" and inputSessao.Text or State.sessao
    salvarArquivo()
end)

mkBotaoAcao(136, "🗑", "Limpar Buffers", "Apaga tráfego e arquitetural capturado", T.warn, function()
    State.trfBuf = {}
    State.unicos = {}
    State.arquitetural = {}
    State.nomesCache = {}
    State.contadorBruto = 0
    log("INFO", "Buffers limpos")
end)

-- Painel DIAG
local painelDiag = Instance.new("Frame")
painelDiag.Size = UDim2.new(1, 0, 1, 0)
painelDiag.BackgroundTransparency = 1
painelDiag.Visible = false
painelDiag.Parent = content

local diagText = Instance.new("TextLabel")
diagText.Size = UDim2.new(1, -24, 1, -80)
diagText.Position = UDim2.new(0, 12, 0, 12)
diagText.BackgroundColor3 = T.bg
diagText.BackgroundTransparency = 0.5
diagText.Text = "Clique em 'Rodar diagnóstico' abaixo."
diagText.TextColor3 = T.text
diagText.Font = Enum.Font.Code
diagText.TextSize = 10
diagText.TextXAlignment = Enum.TextXAlignment.Left
diagText.TextYAlignment = Enum.TextYAlignment.Top
diagText.TextWrapped = true
diagText.Parent = painelDiag
Instance.new("UICorner", diagText).CornerRadius = UDim.new(0, 8)
local dp = Instance.new("UIPadding", diagText)
dp.PaddingLeft = UDim.new(0, 12)
dp.PaddingTop = UDim.new(0, 10)

local btnDiag = Instance.new("TextButton")
btnDiag.Size = UDim2.new(1, -24, 0, 36)
btnDiag.Position = UDim2.new(0, 12, 1, -48)
btnDiag.BackgroundColor3 = T.elev
btnDiag.Text = "🩺  Rodar diagnóstico"
btnDiag.TextColor3 = T.text
btnDiag.Font = Enum.Font.GothamBold
btnDiag.TextSize = 11
btnDiag.BorderSizePixel = 0
btnDiag.AutoButtonColor = false
btnDiag.Parent = painelDiag
Instance.new("UICorner", btnDiag).CornerRadius = UDim.new(0, 8)

local btnTeste = Instance.new("TextButton")
btnTeste.Size = UDim2.new(1, -24, 0, 32)
btnTeste.Position = UDim2.new(0, 12, 1, -88)
btnTeste.BackgroundColor3 = T.elev
btnTeste.Text = "🔬  Testar hook (dispara SkillRemote)"
btnTeste.TextColor3 = T.warn
btnTeste.Font = Enum.Font.GothamBold
btnTeste.TextSize = 10
btnTeste.BorderSizePixel = 0
btnTeste.AutoButtonColor = false
btnTeste.Parent = painelDiag
Instance.new("UICorner", btnTeste).CornerRadius = UDim.new(0, 8)

-- ═══════ RODAPÉ ═══════
local footer = Instance.new("Frame")
footer.Size = UDim2.new(1, -24, 0, 26)
footer.Position = UDim2.new(0, 12, 1, -34)
footer.BackgroundTransparency = 1
footer.Parent = main

local footTxt = Instance.new("TextLabel")
footTxt.Size = UDim2.new(1, 0, 1, 0)
footTxt.BackgroundTransparency = 1
footTxt.Text = "0 bruto  •  0 únicos  •  hook: —"
footTxt.TextColor3 = T.textMuted
footTxt.Font = Enum.Font.GothamMedium
footTxt.TextSize = 10
footTxt.TextXAlignment = Enum.TextXAlignment.Left
footTxt.Parent = footer

-- ═══════ CRIAR ITENS DO SIDEBAR ═══════
criarItemSidebar("captura", "📡", "Captura", function()
    if State.capturando then return "REC • "..State.contadorBruto end
    return State.contadorBruto > 0 and (State.contadorBruto.." bruto") or "parado"
end)

criarItemSidebar("filtros", "🎛", "Filtros", function()
    local ativos = 0
    for _, v in pairs(State.filtros) do if v then ativos = ativos + 1 end end
    return ativos.." ativos"
end)

criarItemSidebar("logs", "📊", "Logs", function()
    return #State.trfBuf.." únicos"
end)

criarItemSidebar("arquivo", "📁", "Arquivo", function()
    return #State.arquitetural > 0 and (#State.arquitetural.." mapeados") or "não escaneado"
end)

criarItemSidebar("diag", "🩺", "Diagnóstico", function()
    return State.hookAtivo and "hook ok" or "sem hook"
end)

-- ═══════ ATUALIZAR SIDEBAR ═══════
local function atualizarSidebar()
    for id, item in pairs(sidebarItens) do
        local ativo = (State.catAtiva == id)
        item.btn.BackgroundColor3 = ativo and T.elevHover or T.elev
        item.btn.BackgroundTransparency = ativo and 0.2 or 0.6
        local sub = item.subFn and item.subFn() or "—"
        item.sub.Text = sub
        item.sub.TextColor3 = ativo and T.accent or T.textMuted
    end
end

-- ═══════ ATUALIZAR CONTEÚDO ═══════
local function atualizarConteudo()
    painelCaptura.Visible = (State.catAtiva == "captura")
    painelFiltros.Visible = (State.catAtiva == "filtros")
    painelLogs.Visible = (State.catAtiva == "logs")
    painelArquivo.Visible = (State.catAtiva == "arquivo")
    painelDiag.Visible = (State.catAtiva == "diag")
end

-- ═══════ BTN CAPTURAR ═══════
local function atualizarBtnCap()
    if State.capturando then
        btnCap.BackgroundColor3 = T.danger
        btnCap.Text = "■  PARAR CAPTURA"
        statusDot.BackgroundColor3 = T.danger
        statusTxt.Text = "gravando"
        statusTxt.TextColor3 = T.danger
    else
        btnCap.BackgroundColor3 = T.accent
        btnCap.Text = "▶  INICIAR CAPTURA"
        statusDot.BackgroundColor3 = T.textMuted
        statusTxt.Text = "parado"
        statusTxt.TextColor3 = T.textDim
    end
    atualizarSidebar()
end

btnCap.MouseButton1Click:Connect(safeUI(function()
    State.sessao = inputSessao.Text ~= "" and inputSessao.Text or State.sessao
    State.capturando = not State.capturando
    if State.capturando then
        print("═══════════════════════════════════")
        print("[DUMPER] 🔴 CAPTURA INICIADA — faça ações no jogo")
        print("═══════════════════════════════════")
        instalarHook()
    else
        print("[DUMPER] ⚪ CAPTURA PARADA (bruto="..State.contadorBruto..")")
        removerHook()
    end
    atualizarBtnCap()
end))

btnMin.MouseButton1Click:Connect(safeUI(function()
    main.Visible = not main.Visible
end))

btnKill.MouseButton1Click:Connect(safeUI(function()
    State.capturando = false
    removerHook()
    gui:Destroy()
    print("[DUMPER v6.0] Encerrado")
end))

btnDiag.MouseButton1Click:Connect(safeUI(function()
    local info = {}
    table.insert(info, "Executor:  "..tostring(identifyexecutor and identifyexecutor() or "?"))
    table.insert(info, "hookfunction:     "..tostring(hookfunction ~= nil))
    table.insert(info, "hookmetamethod:   "..tostring(hookmetamethod ~= nil))
    table.insert(info, "Hook instalado:   "..tostring(State.hookAtivo))
    table.insert(info, "Método:           "..State.hookMetodo)
    table.insert(info, "PlaceId:          "..game.PlaceId)
    table.insert(info, "")
    table.insert(info, "── Remotes em RS.Remotes ──")
    local rem = RS:FindFirstChild("Remotes")
    if rem then
        for _, c in ipairs(rem:GetChildren()) do
            if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then
                table.insert(info, "  • "..c.Name.."  ("..c.ClassName..")")
            end
        end
    else
        table.insert(info, "  RS.Remotes não encontrado")
    end
    diagText.Text = table.concat(info, "\n")
    diagnostico()
end))

btnTeste.MouseButton1Click:Connect(safeUI(function()
    local rem = RS:FindFirstChild("Remotes")
    if not rem then return end
    local sr = rem:FindFirstChild("SkillRemote")
    if not sr then return end
    print("[DUMPER] 🔬 Disparando SkillRemote de teste...")
    pcall(function()
        sr:FireServer({
            Began = false, CFrame = CFrame.new(), Aim = Vector3.new(),
            Camera = CFrame.new(), Type = 1, SkillId = "TESTE",
        })
    end)
    task.wait(0.3)
    print("[DUMPER] Teste enviado. Se não apareceu [CAP/M1] acima, hook falhou.")
end))

-- ═══════ DRAG ═══════
local dragging, dStart, sStart = false, nil, nil
header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dStart = i.Position
        sStart = main.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dStart
        main.Position = UDim2.new(
            sStart.X.Scale, sStart.X.Offset + d.X,
            sStart.Y.Scale, sStart.Y.Offset + d.Y
        )
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- ═══════ LOOPS DE ATUALIZAÇÃO ═══════
task.spawn(function()
    while gui.Parent do
        task.wait(0.5)

        -- Feed
        local linhas = {}
        local ini = math.max(1, #State.trfBuf - 25)
        for i = ini, #State.trfBuf do
            local t = State.trfBuf[i]
            local info = CAT_INFO[t.cat] or CAT_INFO.OTHER
            local suf = t.count > 1 and (" ×"..t.count) or ""
            table.insert(linhas, string.format(
                "<font color='#666'>[%s]</font> <font color='#%s'>%s %s</font> <font color='#888'>%s%s</font>",
                t.primeiro, info.cor, info.icone, t.cat, t.path:sub(-40), suf))
        end
        feedText.Text = #linhas == 0
            and "<font color='#666'>Aguardando captura...</font>"
            or table.concat(linhas, "\n")

        -- Logs
        local linhasL = {}
        local filtro = State.filtroLogCat
        local ini2 = math.max(1, #State.trfBuf - 200)
        for i = ini2, #State.trfBuf do
            local t = State.trfBuf[i]
            if filtro == "todos" or t.cat == filtro then
                local info = CAT_INFO[t.cat] or CAT_INFO.OTHER
                local suf = t.count > 1 and (" [×"..t.count.."]") or ""
                table.insert(linhasL, string.format(
                    "<font color='#888'>%s</font> <font color='#%s'>%s %s</font><font color='#666'>%s</font>\n  <font color='#AAA'>%s</font>\n",
                    t.primeiro, info.cor, info.icone, t.cat, suf, t.path))
                table.insert(linhasL, string.format("  <font color='#777'>↳ %s</font>\n", t.args))
            end
        end
        logsText.Text = #linhasL == 0
            and "<font color='#666'>Sem entradas ainda.</font>"
            or table.concat(linhasL, "")

        -- Footer
        footTxt.Text = string.format(
            "%d bruto  •  %d únicos  •  hook: %s",
            State.contadorBruto, #State.trfBuf, State.hookMetodo)

        atualizarSidebar()
    end
end)

atualizarSidebar()
atualizarConteudo()

print("[DUMPER v6.0] ✅ Pronto")
print("[DUMPER] 1) Captura → INICIAR  2) ações no jogo  3) PARAR  4) Arquivo → SALVAR")