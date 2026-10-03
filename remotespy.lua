--[[
    Dragon Hub Remote Spy — v2.2
    Causa do 0ms encontrada: typeof(self) + GetFullName() + serializeArgs()
    rodavam em TODO namecall, inclusive em duplicatas. Corrigido com:
      • cache fraco de tipo (RemoteCache)
      • cache fraco de path/noise (PathCache)
      • throttle por-remote ANTES da serialização (LastSerialize)
      • remoção de task.spawn por chamada
      • sem typeof no hot path
]]

local CoreGui          = game:GetService("CoreGui")
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

if _G.AmoledSpyGui then pcall(function() _G.AmoledSpyGui:Destroy() end) end

local State = {
    Paused      = false,
    Filter      = "All",
    LogCount    = 0,
    MaxLogs     = 150,
    Seen        = {},
    TotalRaw    = 0,
    TotalUnique = 0,
    DumpOrder   = {},
}

-- Caches fracos: não seguram instâncias vivas
local RemoteCache   = setmetatable({}, {__mode = "k"})  -- [inst] = true|false
local PathCache     = setmetatable({}, {__mode = "k"})  -- [inst] = "path" | false
local LastSerialize = setmetatable({}, {__mode = "k"})  -- [inst] = os.clock()
local LastSignature = setmetatable({}, {__mode = "k"})  -- [inst] = string

local SERIALIZE_COOLDOWN = 0.03  -- ~33 processamentos/s por remote

local NOISE_PATTERNS = {
    "ClientReplication", "RakNet", "TeleportService",
    "PlayerScripts", "CoreGui",
}

local function pathIsNoise(path)
    for i = 1, #NOISE_PATTERNS do
        if string.find(path, NOISE_PATTERNS[i], 1, true) then return true end
    end
    return false
end

local function getCachedPath(inst)
    local p = PathCache[inst]
    if p ~= nil then return p end
    local ok, full = pcall(function() return inst:GetFullName() end)
    if not ok or pathIsNoise(full) then
        PathCache[inst] = false
        return false
    end
    PathCache[inst] = full
    return full
end

local function isRemoteCached(inst)
    local v = RemoteCache[inst]
    if v ~= nil then return v end
    local ok, res = pcall(function()
        return inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction")
    end)
    v = ok and res or false
    RemoteCache[inst] = v
    return v
end

-- ==========================================
-- Serializer
-- ==========================================
local MAX_TABLE_ENTRIES = 6
local MAX_STRING_LEN    = 120
local MAX_DEPTH         = 2
local MAX_ARGS          = 8

local function serializeValue(v, depth)
    depth = depth or 0
    if depth > MAX_DEPTH then return "..." end

    local t = typeof(v)

    if t == "string" then
        if #v > MAX_STRING_LEN then
            return string.format("%q", v:sub(1, MAX_STRING_LEN) .. "...<trunc>")
        end
        return string.format("%q", v)
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "Instance" then
        if depth > 0 then return "Instance" end
        local ok, name = pcall(function() return v:GetFullName() end)
        return ok and ("game." .. name) or "Instance"
    elseif t == "Vector3" then
        return string.format("Vector3.new(%g,%g,%g)", v.X, v.Y, v.Z)
    elseif t == "Vector2" then
        return string.format("Vector2.new(%g,%g)", v.X, v.Y)
    elseif t == "Color3" then
        return string.format("Color3.fromRGB(%d,%d,%d)",
            math.floor(v.R*255), math.floor(v.G*255), math.floor(v.B*255))
    elseif t == "EnumItem" then
        return string.format("Enum.%s.%s", tostring(v.EnumType), v.Name)
    elseif t == "CFrame" then
        return "CFrame.new(...)"
    elseif t == "table" then
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n += 1
            if n > MAX_TABLE_ENTRIES then
                parts[#parts+1] = "...<+" .. (n - MAX_TABLE_ENTRIES) .. ">"
                break
            end
            local key = typeof(k) == "string" and k
                       or ("["..serializeValue(k, depth+1).."]")
            parts[#parts+1] = string.format("%s=%s",
                key, serializeValue(val, depth+1))
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "nil"
end

local function serializeArgs(args)
    local out = {}
    local n = math.min(#args, MAX_ARGS)
    for i = 1, n do
        out[i] = serializeValue(args[i], 0)
    end
    if #args > MAX_ARGS then
        out[#out+1] = "...<+" .. (#args - MAX_ARGS) .. ">"
    end
    return table.concat(out, ", ")
end

local function buildAccessCode(fullPath)
    local service, rest = fullPath:match("^([^%.]+)%.?(.*)$")
    if not service then return fullPath end
    if rest == "" then
        return string.format('game:GetService("%s")', service)
    end
    return string.format('game:GetService("%s").%s', service, rest)
end

-- ==========================================
-- UI
-- ==========================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AmoledRemoteSpy"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true

if syn and syn.protect_gui then
    syn.protect_gui(ScreenGui); ScreenGui.Parent = CoreGui
elseif gethui then
    ScreenGui.Parent = gethui()
else
    ScreenGui.Parent = CoreGui
end
_G.AmoledSpyGui = ScreenGui

local NEON_GREEN = Color3.fromRGB(0, 255, 128)
local NEON_RED   = Color3.fromRGB(255, 80, 80)
local CYAN       = Color3.fromRGB(0, 220, 255)
local ORANGE     = Color3.fromRGB(255, 180, 0)

local Ball = Instance.new("TextButton")
Ball.Name = "FloatingBall"
Ball.Size = UDim2.new(0, 52, 0, 52)
Ball.Position = UDim2.new(0, 24, 0, 140)
Ball.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
Ball.BackgroundTransparency = 0.15
Ball.Text = "⚡"
Ball.TextColor3 = NEON_GREEN
Ball.TextSize = 22
Ball.Font = Enum.Font.GothamBold
Ball.AutoButtonColor = false
Ball.Active = true
Ball.Parent = ScreenGui

Instance.new("UICorner", Ball).CornerRadius = UDim.new(1, 0)
local BallStroke = Instance.new("UIStroke", Ball)
BallStroke.Color = NEON_GREEN
BallStroke.Thickness = 1.6
BallStroke.Transparency = 0.35

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 390, 0, 300)
MainFrame.Position = UDim2.new(0.5, -195, 0.5, -150)
MainFrame.BackgroundColor3 = Color3.fromRGB(6, 6, 9)
MainFrame.BackgroundTransparency = 0.15
MainFrame.Visible = false
MainFrame.Active = true
MainFrame.Parent = ScreenGui

Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 12)
local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Color = Color3.fromRGB(32, 32, 42)
MainStroke.Thickness = 1

local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 38)
TopBar.BackgroundTransparency = 1
TopBar.Parent = MainFrame

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -190, 1, 0)
TitleLabel.Position = UDim2.new(0, 14, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "SPY // DRAGON CORE"
TitleLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
TitleLabel.TextSize = 13
TitleLabel.Font = Enum.Font.Code
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TopBar

local HeaderBtns = Instance.new("Frame")
HeaderBtns.Size = UDim2.new(0, 170, 0, 26)
HeaderBtns.Position = UDim2.new(1, -178, 0, 6)
HeaderBtns.BackgroundTransparency = 1
HeaderBtns.Parent = TopBar

local function makeHeaderBtn(text, order, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 26, 0, 26)
    b.Position = UDim2.new(0, order * 32, 0, 0)
    b.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    b.Text = text
    b.TextColor3 = color or Color3.fromRGB(200, 200, 210)
    b.TextSize = 14
    b.Font = Enum.Font.GothamBold
    b.AutoButtonColor = false
    b.Parent = HeaderBtns
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

local PauseBtn    = makeHeaderBtn("⏸", 0, NEON_GREEN)
local ClearBtn    = makeHeaderBtn("🗑", 1, ORANGE)
local SaveBtn     = makeHeaderBtn("💾", 2, CYAN)
local MinimizeBtn = makeHeaderBtn("–",  3, Color3.fromRGB(200, 200, 210))
local CloseBtn    = makeHeaderBtn("✕",  4, NEON_RED)

local FilterRow = Instance.new("Frame")
FilterRow.Size = UDim2.new(1, -16, 0, 26)
FilterRow.Position = UDim2.new(0, 8, 0, 42)
FilterRow.BackgroundTransparency = 1
FilterRow.Parent = MainFrame

local filterButtons = {}
local function makeFilterBtn(label, xOffset, width)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, width, 1, 0)
    b.Position = UDim2.new(0, xOffset, 0, 0)
    b.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
    b.Text = label
    b.TextColor3 = Color3.fromRGB(180, 180, 190)
    b.TextSize = 11
    b.Font = Enum.Font.Code
    b.AutoButtonColor = false
    b.Parent = FilterRow
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    filterButtons[label] = b
    return b
end

makeFilterBtn("All",           0, 60)
makeFilterBtn("FireServer",   66, 90)
makeFilterBtn("InvokeServer", 162, 100)

local LogScroll = Instance.new("ScrollingFrame")
LogScroll.Size = UDim2.new(1, -16, 1, -78)
LogScroll.Position = UDim2.new(0, 8, 0, 72)
LogScroll.BackgroundTransparency = 1
LogScroll.BorderSizePixel = 0
LogScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
LogScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
LogScroll.ScrollBarThickness = 3
LogScroll.ScrollBarImageColor3 = NEON_GREEN
LogScroll.ScrollingDirection = Enum.ScrollingDirection.Y
LogScroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
LogScroll.Parent = MainFrame

local ListLayout = Instance.new("UIListLayout", LogScroll)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Padding = UDim.new(0, 6)

local ListPad = Instance.new("UIPadding", LogScroll)
ListPad.PaddingRight  = UDim.new(0, 4)
ListPad.PaddingBottom = UDim.new(0, 8)

-- ==========================================
-- Drag
-- ==========================================
local function makeDraggable(target, handle, onTap)
    local dragging, dragStart, startPos, moved = false, nil, nil, false

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
           or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging  = true
            moved     = false
            dragStart = input.Position
            startPos  = target.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.Touch
           and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local delta = input.Position - dragStart
        if math.abs(delta.X) > 6 or math.abs(delta.Y) > 6 then moved = true end
        if moved then
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.Touch
           and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        dragging = false
        if not moved and onTap then onTap() end
    end)
end

local windowOpen = false
local function setWindowOpen(v)
    windowOpen = v
    MainFrame.Visible = v
    local col = v and NEON_RED or NEON_GREEN
    Ball.TextColor3 = col
    BallStroke.Color = col
end

makeDraggable(Ball, Ball, function() setWindowOpen(not windowOpen) end)
makeDraggable(MainFrame, TopBar, nil)
MinimizeBtn.MouseButton1Click:Connect(function() setWindowOpen(false) end)

-- ==========================================
-- Render queue
-- ==========================================
local RenderQueue     = {}
local RENDER_INTERVAL = 1 / 30
local lastRender      = 0
local HEARTBEAT_CONN

local function passesFilter(method)
    return State.Filter == "All" or State.Filter == method
end

local function createLogEntry(method, path, snippet, signature)
    local entry = State.Seen[signature]

    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, 62)
    Frame.BackgroundColor3 = Color3.fromRGB(12, 12, 17)
    Frame.BackgroundTransparency = 0.35
    Frame.Visible = passesFilter(method)
    Frame.Parent = LogScroll
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 6)

    local TypeLabel = Instance.new("TextLabel")
    TypeLabel.Size = UDim2.new(0, 90, 0, 18)
    TypeLabel.Position = UDim2.new(0, 8, 0, 4)
    TypeLabel.BackgroundTransparency = 1
    TypeLabel.Text = "[" .. method .. "]"
    TypeLabel.TextColor3 = (method == "FireServer") and CYAN or ORANGE
    TypeLabel.TextSize = 11
    TypeLabel.Font = Enum.Font.Code
    TypeLabel.TextXAlignment = Enum.TextXAlignment.Left
    TypeLabel.Parent = Frame

    local Counter = Instance.new("TextLabel")
    Counter.Size = UDim2.new(0, 40, 0, 18)
    Counter.Position = UDim2.new(1, -46, 0, 4)
    Counter.BackgroundTransparency = 1
    Counter.Text = ""
    Counter.TextColor3 = NEON_GREEN
    Counter.TextSize = 11
    Counter.Font = Enum.Font.Code
    Counter.TextXAlignment = Enum.TextXAlignment.Right
    Counter.Parent = Frame

    local PathLabel = Instance.new("TextLabel")
    PathLabel.Size = UDim2.new(1, -110, 0, 18)
    PathLabel.Position = UDim2.new(0, 100, 0, 4)
    PathLabel.BackgroundTransparency = 1
    PathLabel.Text = path
    PathLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
    PathLabel.TextSize = 11
    PathLabel.Font = Enum.Font.Code
    PathLabel.TextXAlignment = Enum.TextXAlignment.Left
    PathLabel.TextTruncate = Enum.TextTruncate.AtEnd
    PathLabel.Parent = Frame

    local SnippetBox = Instance.new("TextBox")
    SnippetBox.Size = UDim2.new(1, -16, 0, 30)
    SnippetBox.Position = UDim2.new(0, 8, 0, 26)
    SnippetBox.BackgroundColor3 = Color3.fromRGB(4, 4, 6)
    SnippetBox.BackgroundTransparency = 0.5
    SnippetBox.Text = snippet
    SnippetBox.TextColor3 = NEON_GREEN
    SnippetBox.TextSize = 10
    SnippetBox.Font = Enum.Font.Code
    SnippetBox.TextXAlignment = Enum.TextXAlignment.Left
    SnippetBox.TextYAlignment = Enum.TextYAlignment.Top
    SnippetBox.ClearTextOnFocus = false
    SnippetBox.TextWrapped = false
    SnippetBox.Parent = Frame
    Instance.new("UICorner", SnippetBox).CornerRadius = UDim.new(0, 4)

    SnippetBox.MouseButton1Click:Connect(function()
        if setclipboard then
            setclipboard(snippet)
            SnippetBox.TextColor3 = Color3.fromRGB(255, 255, 255)
            task.delay(0.3, function()
                SnippetBox.TextColor3 = NEON_GREEN
            end)
        end
    end)

    if entry then
        entry.frame = Frame
        entry.counterLabel = Counter
        if entry.count > 1 then Counter.Text = "x" .. entry.count end
    end
end

HEARTBEAT_CONN = RunService.Heartbeat:Connect(function()
    if #RenderQueue == 0 then return end
    local now = os.clock()
    if now - lastRender < RENDER_INTERVAL then return end
    lastRender = now

    local budget = math.min(#RenderQueue, 12)
    for _ = 1, budget do
        local job = table.remove(RenderQueue, 1)
        pcall(createLogEntry, job.method, job.path, job.snippet, job.signature)
    end
end)

-- ==========================================
-- pushLog
-- ==========================================
local function pushLog(remote, method, args)
    local path = getCachedPath(remote)
    if not path then return end

    State.TotalRaw += 1

    local serialized = serializeArgs(args)
    local signature  = method .. "|" .. path .. "|" .. serialized

    local cached = State.Seen[signature]
    if cached then
        cached.count += 1
        cached.lastSeen = os.clock()
        if cached.counterLabel then
            cached.counterLabel.Text = "x" .. cached.count
        end
        LastSignature[remote] = signature
        return
    end

    if State.LogCount >= State.MaxLogs then
        local oldest = LogScroll:FindFirstChildWhichIsA("Frame")
        if oldest then oldest:Destroy() end
        State.LogCount -= 1
    end

    local snippet = buildAccessCode(path) .. ":" .. method .. "(" .. serialized .. ")"

    State.Seen[signature] = {
        frame = nil, counterLabel = nil,
        count = 1, lastSeen = os.clock(),
        method = method, path = path, snippet = snippet,
    }
    table.insert(State.DumpOrder, signature)
    State.LogCount    += 1
    State.TotalUnique += 1
    LastSignature[remote] = signature

    table.insert(RenderQueue, {
        method = method, path = path,
        snippet = snippet, signature = signature,
    })
end

-- ==========================================
-- Hook __namecall
-- ==========================================
local originalNamecall
originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    if State.Paused then
        return originalNamecall(self, ...)
    end

    local method = getnamecallmethod()
    if method ~= "FireServer" and method ~= "InvokeServer" then
        return originalNamecall(self, ...)
    end

    if isRemoteCached(self) then
        local now  = os.clock()
        local last = LastSerialize[self]

        if last and now - last < SERIALIZE_COOLDOWN then
            -- Throttled: só incrementa a última assinatura conhecida
            local sig = LastSignature[self]
            if sig then
                local entry = State.Seen[sig]
                if entry then
                    entry.count += 1
                    if entry.counterLabel then
                        entry.counterLabel.Text = "x" .. entry.count
                    end
                end
            end
        else
            LastSerialize[self] = now
            local args = table.pack(...)
            pcall(pushLog, self, method, args)
        end
    end

    return originalNamecall(self, ...)
end)

-- ==========================================
-- Botões
-- ==========================================
PauseBtn.MouseButton1Click:Connect(function()
    State.Paused = not State.Paused
    PauseBtn.Text = State.Paused and "▶" or "⏸"
    PauseBtn.TextColor3 = State.Paused and NEON_RED or NEON_GREEN
    BallStroke.Transparency = State.Paused and 0.8 or 0.35
end)

ClearBtn.MouseButton1Click:Connect(function()
    for _, child in ipairs(LogScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    State.Seen = {}
    State.DumpOrder = {}
    State.LogCount = 0
    State.TotalUnique = 0
    State.TotalRaw = 0
    RenderQueue = {}
end)

local function applyFilter()
    for _, child in ipairs(LogScroll:GetChildren()) do
        if child:IsA("Frame") then
            local tl = child:FindFirstChildWhichIsA("TextLabel")
            local m = tl and tl.Text:match("%[(.-)%]")
            child.Visible = (State.Filter == "All") or (m == State.Filter)
        end
    end
    for label, btn in pairs(filterButtons) do
        local on = (label == State.Filter)
        btn.BackgroundColor3 = on and Color3.fromRGB(28, 28, 36) or Color3.fromRGB(14, 14, 18)
        btn.TextColor3 = on and NEON_GREEN or Color3.fromRGB(180, 180, 190)
    end
end

for label, btn in pairs(filterButtons) do
    btn.MouseButton1Click:Connect(function()
        State.Filter = label
        applyFilter()
    end)
end
applyFilter()

-- ==========================================
-- Save .txt
-- ==========================================
SaveBtn.MouseButton1Click:Connect(function()
    if not writefile then
        SaveBtn.TextColor3 = NEON_RED
        task.delay(0.5, function() SaveBtn.TextColor3 = CYAN end)
        return
    end

    local lines = {}
    table.insert(lines, "==================================================")
    table.insert(lines, " DRAGON CORE // REMOTE SPY DUMP")
    table.insert(lines, " Gerado em: " .. os.date("%Y-%m-%d %H:%M:%S"))
    table.insert(lines, string.format(" Únicos: %d | Total interceptado: %d",
        State.TotalUnique, State.TotalRaw))
    table.insert(lines, "==================================================")
    table.insert(lines, "")

    local categories = { FireServer = {}, InvokeServer = {} }
    for _, sig in ipairs(State.DumpOrder) do
        local e = State.Seen[sig]
        if e then table.insert(categories[e.method], e) end
    end

    for _, method in ipairs({ "FireServer", "InvokeServer" }) do
        local list = categories[method]
        table.insert(lines, "--------------------------------------------------")
        table.insert(lines, " [" .. method .. "]  (" .. #list .. " únicos)")
        table.insert(lines, "--------------------------------------------------")
        table.insert(lines, "")
        for i, e in ipairs(list) do
            table.insert(lines, string.format("[%03d] %s   (chamado %dx)", i, e.path, e.count))
            table.insert(lines, "      Call:")
            table.insert(lines, "      " .. e.snippet)
            table.insert(lines, "")
        end
    end

    local filename = "RemoteSpy_Dump_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
    local ok = pcall(function() writefile(filename, table.concat(lines, "\n")) end)
    SaveBtn.TextColor3 = ok and NEON_GREEN or NEON_RED
    task.delay(0.7, function() SaveBtn.TextColor3 = CYAN end)
end)

-- ==========================================
-- Kill switch
-- ==========================================
local function killScript()
    State.Paused = true

    pcall(function()
        if originalNamecall then
            hookmetamethod(game, "__namecall", originalNamecall)
        end
    end)

    pcall(function()
        if HEARTBEAT_CONN then HEARTBEAT_CONN:Disconnect() end
    end)

    RenderQueue     = {}
    State.Seen      = {}
    State.DumpOrder = {}

    pcall(function()
        if ScreenGui then ScreenGui:Destroy() end
    end)

    _G.AmoledSpyGui = nil
end

CloseBtn.MouseButton1Click:Connect(killScript)