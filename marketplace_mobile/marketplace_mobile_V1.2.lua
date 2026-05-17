local effil = require('effil')
local imgui = require('mimgui')
local encoding = require('encoding')
local fa = require('fAwesome6_solid')
local sampev = require('lib.samp.events')
local ffi = require("ffi")
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local inicfg = require 'inicfg'
local directIni = 'marketplace.ini'
local LOG_FILE = 'marketplace_mobile.log'
local ini = inicfg.load(inicfg.load({
    main = {
        notify_enabled_profit = true,
        notify_min_profit = 0,
        notify_enabled_lowprice = true,
        notify_min_lowprice = 0,
        vip_key = "",
        ui_last_section = 1,
        ui_window_x = -1,
        ui_window_y = -1,
        ui_window_w = -1,
        ui_window_h = -1,
        ui_accent_r = 0.95,
        ui_accent_g = 0.60,
        ui_accent_b = 0.12,
        ui_accent_dim_r = 0.55,
        ui_accent_dim_g = 0.35,
        ui_accent_dim_b = 0.10,
        ui_window_alpha = 0.98,
        ui_child_alpha = 0.60,
        ui_font_scale = 1.30,
        ui_theme_mode = 0,
    },
}, directIni))
inicfg.save(ini, directIni)

local FONT_SCALE = tonumber(ini.main.ui_font_scale) or 1.3
if FONT_SCALE < 0.9 then FONT_SCALE = 0.9 end
if FONT_SCALE > 1.8 then FONT_SCALE = 1.8 end

local UI_MIN_WIDTH = 980
local UI_MIN_HEIGHT = 640

-- ===== AUTOUPDATE CONFIG =====
local CURRENT_VERSION = "1.2"
local GITHUB_RELEASES_API = "https://api.github.com/repos/Moderator42/marketplace_mobile/releases"
-- ===== END AUTOUPDATE CONFIG =====

local USE_LAVKA_CACHE_PROXY = true
local LAVKA_CACHE_PROXY_URL = 'https://teto.moder42.tech/lavka/registry'
local LAVKA_DIRECT_MARKET_URL = 'https://api.arz.market/api/getSelectedMarketplace/'

local function getMarketplaceUrl(serverId)
    if USE_LAVKA_CACHE_PROXY then
        return LAVKA_CACHE_PROXY_URL
    end
    return LAVKA_DIRECT_MARKET_URL .. tostring(serverId or -1)
end

req = require "requests"

local notifyNewArbitrage = imgui.new.bool(ini.main.notify_enabled_profit)
local minProfitThreshold = imgui.new.int(ini.main.notify_min_profit)
local minDiscountThreshold = imgui.new.int(ini.main.notify_min_lowprice)
local notifyNewCheapItems = imgui.new.bool(ini.main.notify_enabled_lowprice)
local vipKeyInput = imgui.new.char[128](ini.main.vip_key or "")
local uiAccentColor = imgui.new.float[3](ini.main.ui_accent_r, ini.main.ui_accent_g, ini.main.ui_accent_b)
local uiAccentDimColor = imgui.new.float[3](ini.main.ui_accent_dim_r, ini.main.ui_accent_dim_g, ini.main.ui_accent_dim_b)
local uiWindowAlpha = imgui.new.float(ini.main.ui_window_alpha)
local uiChildAlpha = imgui.new.float(ini.main.ui_child_alpha)
local uiFontScaleValue = imgui.new.float(FONT_SCALE)
local uiThemeMode = imgui.new.int(tonumber(ini.main.ui_theme_mode) or 0) -- 0 dark, 1 light

local renderWindow = imgui.new.bool(false)
local vipAuthorized = false
local vipAuthError = ""
local vipFeatureEnabled = false

local VIP_KEYS = {
    ["DEMO-ARZ-2026"] = true,
}

local header_content_types = {
    ['xform'] = 'application/x-www-form-urlencoded',
    ['json'] = 'application/json',
}

local function faSafe(name, fallback)
    if fa and type(fa[name]) == 'string' then
        return fa[name]
    end
    return fallback or ''
end

local function logWrite(level, message)
    local ts = os.date('%Y-%m-%d %H:%M:%S')
    local text = string.format('[%s] [%s] %s', ts, level, tostring(message or ''))
    local f = io.open(LOG_FILE, 'a')
    if f then
        f:write(text .. '\n')
        f:close()
    end
end

local function logInfo(message)
    logWrite('INFO', message)
end

local function logError(message)
    logWrite('ERROR', message)
end

local function logErrorPrint(...)
    local parts = {}
    for i = 1, select('#', ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    local msg = table.concat(parts, ' | ')
    logError(msg)
    print(...)
end

local function encodeUrl(data) local function valueToUrlEncode(str) str = str:gsub('([^%w])', function(char) return string.format('%%%02X', string.byte(char)) end) return str end local t = {} for k, v in pairs(data) do if type(v) == 'table' then local n = {} for _, j in ipairs(v) do table.insert(n, valueToUrlEncode(u8(tostring(j)))) end if #n ~= 0 then table.insert(t, string.format('%s=%s', k, table.concat(n, '%2C'))) end else v = valueToUrlEncode(u8(tostring(v))) table.insert(t, string.format('%s=%s', k, v)) end end return u8(table.concat(t, '&')) end

local function deepCopyPlain(value)
    if type(value) ~= 'table' then
        return value
    end

    local copy = {}
    for key, item in pairs(value) do
        copy[deepCopyPlain(key)] = deepCopyPlain(item)
    end
    return copy
end

local function requestJson(method, url, body)
    local plainBody = deepCopyPlain(body)
    if type(plainBody) ~= 'table' then
        plainBody = { headers = {} }
    end
    local plainHeaders = (type(plainBody.headers) == 'table') and deepCopyPlain(plainBody.headers) or {}
    plainBody.headers = plainHeaders

    local safeMethod = tostring(method or 'GET')
    local safeUrl = tostring(url or '')

    local ok, resp = pcall(req.request, safeMethod, safeUrl, plainBody)
    if not ok then
        return nil, nil, resp
    end
    if not resp then
        return nil, nil, "empty response"
    end
    local text = resp.text or resp.content or resp.body or resp.data
    if text ~= nil and type(text) ~= 'string' then
        text = tostring(text)
    end
    if type(text) == 'string' and text:sub(1, 3) == "\239\187\191" then
        text = text:sub(4)
    end
    return resp.status_code, text, resp.err
end

local function createRequest(_method, _url, _body)
    local requests = require('requests')
    local function copyPlain(value)
        if type(value) ~= 'table' then
            return value
        end
        local copy = {}
        for key, item in pairs(value) do
            copy[copyPlain(key)] = copyPlain(item)
        end
        return copy
    end

    local plainBody = copyPlain(_body)
    if type(plainBody) ~= 'table' then
        plainBody = { headers = {} }
    end
    local plainHeaders = (type(plainBody.headers) == 'table') and copyPlain(plainBody.headers) or {}
    plainBody.headers = plainHeaders

    local safeMethod = tostring(_method or 'GET')
    local safeUrl = tostring(_url or '')

    local success, response = pcall(requests.request, safeMethod, safeUrl, plainBody)
    if success then
        response.json, response.xml = nil, nil
        return true, response
    else
        return false, response
    end
end

local function createEffilThread(method, url, body, callback)
    local thread = effil.thread(createRequest)(method, url, body)
    lua_thread.create(function()
        while true do
            wait(10)
            local status, err = thread:status()
            if not status or err then
                return callback(nil, nil, err)
            end
            if status == 'completed' or status == 'canceled' then
                local success, response = thread:get()
                if not success then
                    return callback(nil, nil, response)
                end
                return callback(response.status_code, response.text, nil)
            end
        end
    end)
end

local async_http_request = { request = {} }
async_http_request.__index = async_http_request

---@diagnostic disable-next-line:deprecated
local lower, sub, char, upper = string.lower, string.sub, string.char, string.upper
local concat = table.concat
table.push = table.insert;
function table.forEach(self, callback) for k, v in pairs(self) do callback(v, k); end end
function table.includes(self, value, searchStartIndex) local foundIndex; table.forEach(self, function(v, index) if (v == value and index >= (searchStartIndex or 1)) then foundIndex = index; end end); return foundIndex ~= nil, foundIndex; end
function table.filter(self, callback) table.forEach(self, function(value, index) if (not callback(value, index)) then self[index] = nil; end end); end
function table.keys(self) local keys = {}; table.forEach(self, function(_, k) table.insert(keys, k); end); return keys; end
function table.values(self) local values = {}; table.forEach(self, function(v, _) table.insert(values, v); end); return values; end
local lu_rus, ul_rus = {}, {}; local E, e = char(168), char(184); ul_rus[E] = e; lu_rus[e] = E
for i = 192, 223 do local A, a = char(i), char(i + 32) ul_rus[A] = a lu_rus[a] = A end
function string.nlower(s) s = lower(s) local len, res = #s, {} for i = 1, len do local ch = sub(s, i, i) res[i] = ul_rus[ch] or ch end return concat(res) end
function string.nupper(s) s = upper(s) local len, res = #s, {} for i = 1, len do local ch = sub(s, i, i) res[i] = lu_rus[ch] or ch end return concat(res) end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    --imgui.GetIO().Fonts:Clear()
    local glyph_ranges = imgui.GetIO().Fonts:GetGlyphRangesCyrillic()
    --imgui.GetIO().Fonts:AddFontFromFileTTF(getFolderPath(0x14)..'\\trebucbd.ttf', 20.0, nil, glyph_ranges)
    --imgui.InvalidateFontsTexture()
    Theme()
    fa.Init(64)
end)

local search = imgui.new.char[256]("")
local thresholdPercent = imgui.new.int(50)
local avgChartQuery = imgui.new.char[128]("")
local avgChartDays = imgui.new.int(7)
local avgChartValues = ffi.new("float[30]")
local avgChartMode = imgui.new.int(0) -- 0 = sell, 1 = buy
local avgChartSelectedName = ""
local avgChartLastQuery = ""

local servers = {
    {name = 'Phoenix', number = '1'},
    {name = 'Tucson', number = '2'},
    {name = 'Scottdale', number = '3'},
    {name = 'Chandler', number = '4'},
    {name = 'Brainburg', number = '5'},
    {name = 'SaintRose', number = '6'},
    {name = 'Mesa', number = '7'},
    {name = 'Red Rock', number = '8'},
    {name = 'Yuma', number = '9'},
    {name = 'Surprise', number = '10'},
    {name = 'Prescott', number = '11'},
    {name = 'Glendale', number = '12'},
    {name = 'Kingman', number = '13'},
    {name = 'Winslow', number = '14'},
    {name = 'Payson', number = '15'},
    {name = 'Gilbert', number = '16'},
    {name = 'Show Low', number = '17'},
    {name = 'CasaGrande', number = '18'},
    {name = 'Page', number = '19'},
    {name = 'Sun City', number = '20'},
    {name = 'Queen Creek', number = '21'},
    {name = 'Sedona', number = '22'},
    {name = 'Holiday', number = '23'},
    {name = 'Wednesday', number = '24'},
    {name = 'Yava', number = '25'},
    {name = 'Faraway', number = '26'},
    {name = 'Bumble Bee', number = '27'},
    {name = 'Christmas', number = '28'},
    {name = 'Mirage', number = '29'},
    {name = 'Love', number = '30'},
    {name = 'Drake', number = '31'},
    {name = 'Space', number = '32'},
    {name = 'Mobile III', number = '103'},
    {name = 'Mobile II', number = '102'},
    {name = 'Mobile I', number = '101'},
    {name = 'Vice City', number = '200'},
}

local serversId = {
    [u8'Все сервера'] = -1,
    ['Vice City'] = 0,
    ['Phoenix'] = 1,
    ['Tucson'] = 2,
    ['Scottdale'] = 3,
    ['Chandler'] = 4,
    ['Brainburg'] = 5,
    ['SaintRose'] = 6,
    ['Mesa'] = 7,
    ['Red Rock'] = 8,
    ['Yuma'] = 9,
    ['Surprise'] = 10,
    ['Prescott'] = 11,
    ['Glendale'] = 12,
    ['Kingman'] = 13,
    ['Winslow'] = 14,
    ['Payson'] = 15,
    ['Gilbert'] = 16,
    ['Show Low'] = 17,
    ['CasaGrande'] = 18,
    ['Page'] = 19,
    ['Sun City'] = 20,
    ['Queen Creek'] = 21,
    ['Sedona'] = 22,
    ['Holiday'] = 23,
    ['Wednesday'] = 24,
    ['Yava'] = 25,
    ['Faraway'] = 26,
    ['Bumble Bee'] = 27,
    ['Christmas'] = 28,
    ['Mirage'] = 29,
    ['Love'] = 30,
    ['Drake'] = 31,
    ['Space'] = 32,
}

local serversName = {
    u8'Все сервера',
    'Vice City',
    'Phoenix',
    'Tucson',
    'Scottdale',
    'Chandler',
    'Brainburg',
    'SaintRose',
    'Mesa',
    'Red Rock',
    'Yuma',
    'Surprise',
    'Prescott',
    'Glendale',
    'Kingman',
    'Winslow',
    'Payson',
    'Gilbert',
    'Show Low',
    'CasaGrande',
    'Page',
    'Sun City',
    'Queen Creek',
    'Sedona',
    'Holiday',
    'Wednesday',
    'Yava',
    'Faraway',
    'Bumble Bee',
    'Christmas',
    'Mirage',
    'Love',
    'Drake',
    'Space',
}

local function getARZServerNumber()
	local server = "0"
    if isSampAvailable() then
        for _, s in ipairs(servers) do
            if sampGetCurrentServerName():gsub('%-', ' '):find(s.name) then
                server = s.number
                break
            end
        end
    end
	return server
end

local server_selected = imgui.new.int(0)
local serverList = imgui.new['const char*'][#serversName](serversName)
local window = 1
local activeSidebarSection = tonumber(ini.main.ui_last_section) or 1
local pendingApplySavedWindowRect = false
local lastUiStateSave = 0
local lastAutoRefreshAt = 0
local lastRefreshFinishedAt = 0
local backgroundRefreshRunning = false
local CLOSED_REFRESH_INTERVAL_SECONDS = 30 * 60

local function saveUiState(force)
    local now = os.clock()
    if not force and (now - lastUiStateSave) < 0.8 then
        return
    end

    ini.main.ui_last_section = activeSidebarSection
    inicfg.save(ini, directIni)
    lastUiStateSave = now
end

local function applyUiThemeFromSettings()
    local style = imgui.GetStyle()
    local wr = math.max(0, math.min(1, uiAccentColor[0]))
    local wg = math.max(0, math.min(1, uiAccentColor[1]))
    local wb = math.max(0, math.min(1, uiAccentColor[2]))
    local dr = math.max(0, math.min(1, uiAccentDimColor[0]))
    local dg = math.max(0, math.min(1, uiAccentDimColor[1]))
    local db = math.max(0, math.min(1, uiAccentDimColor[2]))
    local wa = math.max(0.70, math.min(1.00, uiWindowAlpha[0]))
    local ca = math.max(0.20, math.min(1.00, uiChildAlpha[0]))

    if uiThemeMode[0] == 1 then
        style.Colors[imgui.Col.Text] = imgui.ImVec4(0.10, 0.12, 0.16, 1.00)
        style.Colors[imgui.Col.TextDisabled] = imgui.ImVec4(0.34, 0.38, 0.44, 1.00)
        style.Colors[imgui.Col.WindowBg] = imgui.ImVec4(0.93, 0.95, 0.98, wa)
        style.Colors[imgui.Col.ChildBg] = imgui.ImVec4(0.87, 0.90, 0.95, ca)
        style.Colors[imgui.Col.FrameBg] = imgui.ImVec4(0.82, 0.86, 0.93, 0.95)
        style.Colors[imgui.Col.FrameBgHovered] = imgui.ImVec4(0.76, 0.82, 0.91, 1.00)
        style.Colors[imgui.Col.FrameBgActive] = imgui.ImVec4(0.72, 0.79, 0.89, 1.00)
    else
        style.Colors[imgui.Col.Text] = imgui.ImVec4(0.95, 0.97, 1.00, 1.00)
        style.Colors[imgui.Col.TextDisabled] = imgui.ImVec4(0.56, 0.63, 0.74, 1.00)
        style.Colors[imgui.Col.WindowBg] = imgui.ImVec4(0.08, 0.10, 0.15, wa)
        style.Colors[imgui.Col.ChildBg] = imgui.ImVec4(0.12, 0.15, 0.22, ca)
        style.Colors[imgui.Col.FrameBg] = imgui.ImVec4(0.15, 0.19, 0.28, 0.85)
        style.Colors[imgui.Col.FrameBgHovered] = imgui.ImVec4(0.20, 0.26, 0.38, 0.95)
        style.Colors[imgui.Col.FrameBgActive] = imgui.ImVec4(0.24, 0.30, 0.44, 1.00)
    end

    style.Colors[imgui.Col.Button] = imgui.ImVec4(dr, dg, db, 0.95)
    style.Colors[imgui.Col.ButtonHovered] = imgui.ImVec4(wr, wg, wb, 1.00)
    style.Colors[imgui.Col.ButtonActive] = imgui.ImVec4(wr, wg, wb, 1.00)
    style.Colors[imgui.Col.Separator] = imgui.ImVec4(dr, dg, db, 0.80)
    style.Colors[imgui.Col.SeparatorHovered] = imgui.ImVec4(wr, wg, wb, 0.95)
    style.Colors[imgui.Col.SeparatorActive] = imgui.ImVec4(wr, wg, wb, 1.00)
    style.Colors[imgui.Col.ScrollbarGrab] = imgui.ImVec4(dr, dg, db, 0.70)
    style.Colors[imgui.Col.ScrollbarGrabHovered] = imgui.ImVec4(wr, wg, wb, 0.85)
    style.Colors[imgui.Col.ScrollbarGrabActive] = imgui.ImVec4(wr, wg, wb, 1.00)

    FONT_SCALE = math.max(0.9, math.min(1.8, uiFontScaleValue[0]))
end

local function saveAppearanceSettings()
    ini.main.ui_accent_r = uiAccentColor[0]
    ini.main.ui_accent_g = uiAccentColor[1]
    ini.main.ui_accent_b = uiAccentColor[2]
    ini.main.ui_accent_dim_r = uiAccentDimColor[0]
    ini.main.ui_accent_dim_g = uiAccentDimColor[1]
    ini.main.ui_accent_dim_b = uiAccentDimColor[2]
    ini.main.ui_window_alpha = uiWindowAlpha[0]
    ini.main.ui_child_alpha = uiChildAlpha[0]
    ini.main.ui_font_scale = FONT_SCALE
    ini.main.ui_theme_mode = uiThemeMode[0]
    inicfg.save(ini, directIni)
end

local function applyAppearancePreset(mode)
    uiThemeMode[0] = mode
    if mode == 1 then
        uiAccentColor[0], uiAccentColor[1], uiAccentColor[2] = 0.24, 0.46, 0.78
        uiAccentDimColor[0], uiAccentDimColor[1], uiAccentDimColor[2] = 0.52, 0.66, 0.84
        uiWindowAlpha[0] = 0.98
        uiChildAlpha[0] = 0.78
        uiFontScaleValue[0] = 1.25
    else
        uiAccentColor[0], uiAccentColor[1], uiAccentColor[2] = 0.95, 0.60, 0.12
        uiAccentDimColor[0], uiAccentDimColor[1], uiAccentDimColor[2] = 0.55, 0.35, 0.10
        uiWindowAlpha[0] = 0.98
        uiChildAlpha[0] = 0.60
        uiFontScaleValue[0] = 1.30
    end
end

local function applyColorPreset(name)
    if name == 'turquoise' then
        uiAccentColor[0], uiAccentColor[1], uiAccentColor[2] = 0.12, 0.78, 0.72
        uiAccentDimColor[0], uiAccentDimColor[1], uiAccentDimColor[2] = 0.10, 0.48, 0.44
        if uiThemeMode[0] == 1 then
            uiWindowAlpha[0] = 0.97
            uiChildAlpha[0] = 0.76
        else
            uiWindowAlpha[0] = 0.98
            uiChildAlpha[0] = 0.62
        end
    elseif name == 'ruby' then
        uiAccentColor[0], uiAccentColor[1], uiAccentColor[2] = 0.86, 0.24, 0.30
        uiAccentDimColor[0], uiAccentDimColor[1], uiAccentDimColor[2] = 0.50, 0.14, 0.18
        if uiThemeMode[0] == 1 then
            uiWindowAlpha[0] = 0.97
            uiChildAlpha[0] = 0.76
        else
            uiWindowAlpha[0] = 0.98
            uiChildAlpha[0] = 0.62
        end
    end
end

local lavka_data = {}
local items_data = {}
local market_data = {}
local market_data_version = 0
local filtered_market_cache = {}
local filtered_market_cache_version = -1
local cheapItems = {}
local arbitrageResults = {}
local lastArbitrageResults = {}
local lastCheapItems = {}

local search_results = {
    sell = {},
    buy = {}
}

local avg_prices = {
    user_server = { sell = {}, buy = {} },
    vc = { sell = {}, buy = {} },
}

local sort_type = 1
local sort_types = {
    "Без сортировки",
    "По возрастанию",
    "По убыванию"
}

local WINDOW_STATES = {
    MARKET_LIST = 1,
    USER_LAVKA = 2,
    SEARCH_RESULTS = 3
}


local function getFilteredMarketData(serverId)
    if filtered_market_cache_version ~= market_data_version then
        filtered_market_cache = {}
        filtered_market_cache_version = market_data_version
    end

    if filtered_market_cache[serverId] then
        return filtered_market_cache[serverId]
    end

    local filtered_list = {}
    for k, v in pairs(market_data) do
        if (v.serverId == serverId) or serverId == -1 then
            table.insert(filtered_list, v)
        end
    end
    filtered_market_cache[serverId] = filtered_list
    return filtered_list
end

local function getCurrentServerId()
    return serversId[serversName[server_selected[0] + 1]]
end

local function normalizeVipKey(key)
    if not key then return "" end
    return key:gsub("^%s+", ""):gsub("%s+$", ""):upper()
end

local function isVipKeyValid(key)
    return VIP_KEYS[normalizeVipKey(key)] == true
end

local function tryAuthorizeVipKey(rawKey)
    local normalized = normalizeVipKey(rawKey)
    if normalized == "" then
        return false, u8("Введите действительный VIP-ключ")
    end
    if not isVipKeyValid(normalized) then
        return false, u8("Неверный VIP-ключ")
    end

    ini.main.vip_key = normalized
    inicfg.save(ini, directIni)
    return true, ""
end

local function normalizeServerName(name)
    return (name or ""):gsub("%-", " "):gsub("%s+", " "):nlower()
end

local function detectCurrentServerComboIndex()
    if not isSampAvailable() then
        return 0
    end

    local current = normalizeServerName(sampGetCurrentServerName())
    for i, name in ipairs(serversName) do
        if i > 1 then
            local normalizedName = normalizeServerName(name)
            if current:find(normalizedName, 1, true) then
                return i - 1
            end
        end
    end

    return 0
end

local function syncServerSelectionWithCurrent()
    server_selected[0] = detectCurrentServerComboIndex()
end

local function getSelectedServernameSlug()
    local currentServerId = getCurrentServerId()
    if currentServerId == nil or currentServerId <= 0 then
        return nil
    end
    return serversName[server_selected[0] + 1]:gsub("%s", ""):lower()
end

local function refreshAllDataInBackground()
    if backgroundRefreshRunning then
        logInfo('Refresh skipped: already running')
        return
    end
    lastAutoRefreshAt = os.time()
    backgroundRefreshRunning = true
    local serverSlug = getSelectedServernameSlug()
    local marketServerId = -1
    logInfo('Refresh started; server=' .. tostring(serverSlug or 'vc/all') .. '; market_server_id=' .. tostring(marketServerId))

    local newMarketData = nil
    local newItemsData = nil
    local newUserAvgSellPrices = nil
    local newUserAvgBuyPrices = nil
    local newVcAvgSellPrices = nil
    local newVcAvgBuyPrices = nil

    local function finishRefresh()
        if newMarketData then
            market_data = newMarketData
            market_data_version = market_data_version + 1
        end
        if newItemsData then
            items_data = newItemsData
        end
        if newUserAvgSellPrices then
            avg_prices.user_server.sell = newUserAvgSellPrices
        end
        if newUserAvgBuyPrices then
            avg_prices.user_server.buy = newUserAvgBuyPrices
        end
        if newVcAvgSellPrices then
            avg_prices.vc.sell = newVcAvgSellPrices
        end
        if newVcAvgBuyPrices then
            avg_prices.vc.buy = newVcAvgBuyPrices
        end
        logInfo(string.format('Refresh finished; market=%s items=%s avg_user_sell=%s avg_user_buy=%s avg_vc_sell=%s avg_vc_buy=%s',
            tostring(newMarketData ~= nil),
            tostring(newItemsData ~= nil),
            tostring(newUserAvgSellPrices ~= nil),
            tostring(newUserAvgBuyPrices ~= nil),
            tostring(newVcAvgSellPrices ~= nil),
            tostring(newVcAvgBuyPrices ~= nil)
        ))
        lastRefreshFinishedAt = os.time()
        backgroundRefreshRunning = false
    end

    local function loadVcBuyPrices()
        async_http_request:create('json', 'GET', "https://raw.githubusercontent.com/FREYM1337/forumnick/main/avg_price/info_users_buy_vc.json")
        :setCallback(function (status_code, res, err)
            if status_code == 200 and type(res) == "string" then
                local okVc, parsedVc = pcall(decodeJson, res)
                if okVc and type(parsedVc) == "table" then
                    newVcAvgBuyPrices = parsedVc
                else
                    logErrorPrint("refresh avg vc buy decode error", err)
                end
            else
                logErrorPrint("refresh avg vc buy http error", status_code, err)
            end
            finishRefresh()
        end)
        :send()
    end

    local function loadVcSellPrices()
        async_http_request:create('json', 'GET', "https://raw.githubusercontent.com/FREYM1337/forumnick/main/avg_price/info_users_sell_vc.json")
        :setCallback(function (status_code, res, err)
            if status_code == 200 and type(res) == "string" then
                local okVc, parsedVc = pcall(decodeJson, res)
                if okVc and type(parsedVc) == "table" then
                    newVcAvgSellPrices = parsedVc
                else
                    logErrorPrint("refresh avg vc sell decode error", err)
                end
            else
                logErrorPrint("refresh avg vc sell http error", status_code, err)
            end
            loadVcBuyPrices()
        end)
        :send()
    end

    local function loadUserBuyPrices()
        if not serverSlug then
            loadVcSellPrices()
            return
        end

        async_http_request:create('json', 'GET', "https://raw.githubusercontent.com/FREYM1337/forumnick/main/avg_price/info_users_buy_"..serverSlug..".json")
        :setCallback(function (status_code, res, err)
            if status_code == 200 and type(res) == "string" then
                local okUser, parsedUser = pcall(decodeJson, res)
                if okUser and type(parsedUser) == "table" then
                    newUserAvgBuyPrices = parsedUser
                else
                    logErrorPrint("refresh avg user buy decode error", err)
                end
            else
                logErrorPrint("refresh avg user buy http error", status_code, err)
            end
            loadVcSellPrices()
        end)
        :send()
    end

    local function loadUserSellPrices()
        if not serverSlug then
            loadVcSellPrices()
            return
        end

        async_http_request:create('json', 'GET', "https://raw.githubusercontent.com/FREYM1337/forumnick/main/avg_price/info_users_sell_"..serverSlug..".json")
        :setCallback(function (status_code, res, err)
            if status_code == 200 and type(res) == "string" then
                local okUser, parsedUser = pcall(decodeJson, res)
                if okUser and type(parsedUser) == "table" then
                    newUserAvgSellPrices = parsedUser
                else
                    logErrorPrint("refresh avg user sell decode error", err)
                end
            else
                logErrorPrint("refresh avg user sell http error", status_code, err)
            end
            loadUserBuyPrices()
        end)
        :send()
    end

    local function loadItems()
        async_http_request:create('json', 'GET', "https://server-api.arizona.games/client/json/table/get?project=arizona&server=0&key=inventory_items")
        :setCallback(function (status_code, res, err)
            if status_code == 200 and type(res) == "string" then
                local okItems, itemsArz = pcall(decodeJson, res)
                if okItems and type(itemsArz) == "table" then
                    newItemsData = {}
                    for _, item in pairs(itemsArz) do
                        if item and item.id ~= nil and item.name ~= nil then
                            newItemsData[item.id] = u8:decode(item.name)
                        end
                    end
                else
                    logErrorPrint("refresh items decode error", err)
                end
            else
                logErrorPrint("refresh items http error", status_code, err)
            end
            loadUserSellPrices()
        end)
        :send()
    end

    async_http_request:create('json', 'GET', getMarketplaceUrl(marketServerId))
    :setCallback(function (status_code, res, err)
        if status_code == 200 and type(res) == "string" then
            local okMarket, parsedMarket = pcall(decodeJson, res)
            if okMarket and type(parsedMarket) == "table" then
                if parsedMarket.ok == true and type(parsedMarket.data) == "table" then
                    newMarketData = parsedMarket.data
                elseif parsedMarket.ok == false then
                    logErrorPrint("refresh market proxy error", parsedMarket.error or err)
                elseif next(parsedMarket) ~= nil then
                    newMarketData = parsedMarket
                else
                    logErrorPrint("refresh market empty/decode error", err)
                end
            else
                logErrorPrint("refresh market empty/decode error", err)
            end
        else
            logErrorPrint("refresh market http error", status_code, err)
        end
        loadItems()
    end)
    :send()
end

local function parseItemId(itemId)
    if type(itemId) == "string" then
        local item, ench = itemId:match("^(%d+)%((.+)%)$")
        if item then
            return tonumber(item), ench or ""
        end

        local numeric = tonumber(itemId)
        if numeric then
            return numeric, ""
        end
    end
    return itemId, ""
end

local function LavkaButton(text, lavkaId)
    lavkaId = lavkaId or 1
    local dl = imgui.GetWindowDrawList()
    local p = imgui.GetCursorScreenPos()
    local size = imgui.CalcTextSize(text)

    if imgui.InvisibleButton(text, imgui.ImVec2(size.x, size.y)) then
        sampSendChat("/findilavka " .. lavkaId)
    end

    local hovered = imgui.IsItemHovered()
    dl:AddText(p, hovered and 0xFFaaaaaa or -1, text)
end

local function findArbitrageOpportunities(marketData)
    local opportunities = {}

    local buyOffers = {}
    local sellOffers = {}

    for _, lavka in pairs(marketData) do
        for i, itemId in ipairs(lavka.items_sell) do
            local actualItemId, enchant = parseItemId(itemId)
            if not sellOffers[actualItemId] then
                sellOffers[actualItemId] = {}
            end

            table.insert(sellOffers[actualItemId], {
                lavka = lavka,
                price = lavka.price_sell[i],
                count = lavka.count_sell[i],
                itemId = itemId,
                enchant = enchant,
                type = "sell"
            })
        end

        for i, itemId in ipairs(lavka.items_buy) do
            local actualItemId, enchant = parseItemId(itemId)
            if not buyOffers[actualItemId] then
                buyOffers[actualItemId] = {}
            end

            table.insert(buyOffers[actualItemId], {
                lavka = lavka,
                price = lavka.price_buy[i],
                count = lavka.count_buy[i],
                itemId = itemId,
                enchant = enchant,
                type = "buy"
            })
        end
    end

    for itemId, buyList in pairs(buyOffers) do
        local sellList = sellOffers[itemId]

        if sellList then
            for _, buyOffer in ipairs(buyList) do
                for _, sellOffer in ipairs(sellList) do
                    if buyOffer.lavka.LavkaUid ~= sellOffer.lavka.LavkaUid and
                       buyOffer.lavka.serverId == sellOffer.lavka.serverId then

                        local profit = (buyOffer.price * 0.92) - sellOffer.price

                        if profit > 0 then
                            local itemName = getItemNameById(itemId)

                            table.insert(opportunities, {
                                itemId = itemId,
                                itemName = itemName,
                                buyLavka = buyOffer.lavka,
                                sellLavka = sellOffer.lavka,
                                buyPrice = buyOffer.price,
                                sellPrice = sellOffer.price,
                                profit = profit,
                                buyCount = buyOffer.count,
                                sellCount = sellOffer.count,
                                enchant = buyOffer.enchant
                            })
                        end
                    end
                end
            end
        end
    end

    table.sort(opportunities, function(a, b)
        return a.profit > b.profit
    end)

    return opportunities
end

local function checkNewArbitrageOpportunities(notify)
    if not notifyNewArbitrage[0] then return end

    local newOpportunities = {}

    for _, currentOpp in ipairs(arbitrageResults) do
        local isNew = true

        for _, lastOpp in ipairs(lastArbitrageResults) do
            if currentOpp.itemId == lastOpp.itemId and
               currentOpp.buyLavka.LavkaUid == lastOpp.buyLavka.LavkaUid and
               currentOpp.sellLavka.LavkaUid == lastOpp.sellLavka.LavkaUid and
               currentOpp.buyPrice == lastOpp.buyPrice and
               currentOpp.sellPrice == lastOpp.sellPrice then
                isNew = false
                break
            end
        end

        if isNew and currentOpp.profit >= minProfitThreshold[0] then
            table.insert(newOpportunities, currentOpp)
        end
    end

    if notify then
        if #newOpportunities > 0 then
            for _, opp in ipairs(newOpportunities) do
                local message = string.format("ПРОФИТ: {ffffff}%s. Покупка: лавка %d. Продажа: лавка %d. Профит: %s$",
                    opp.itemName .. (opp.enchant ~= "" and " (" .. opp.enchant .. ")" or ""),
                    opp.buyLavka.LavkaUid,
                    opp.sellLavka.LavkaUid,
                    comma_value(math.floor(opp.profit)))

                sampAddChatMessage(message, 0xaaaaaa)
            end
            sampAddChatMessage("Новые возможности: {ffffff}" .. #newOpportunities .. "", 0xaaaaaa)
        end
    end

    lastArbitrageResults = {}
    for _, opp in ipairs(arbitrageResults) do
        table.insert(lastArbitrageResults, {
            itemId = opp.itemId,
            buyLavka = {LavkaUid = opp.buyLavka.LavkaUid},
            sellLavka = {LavkaUid = opp.sellLavka.LavkaUid},
            buyPrice = opp.buyPrice,
            sellPrice = opp.sellPrice,
            profit = opp.profit
        })
    end

    return newOpportunities
end

local function findCheapItems(server, marketData, thresholdPercent)
    local cheapItems = {}

    local averagePrices = (avg_prices[server] and avg_prices[server].sell) or {}

    for _, lavka in pairs(marketData) do
        if (server == "user_server" and lavka.serverId == getCurrentServerId()) or
           (server == "vc" and lavka.serverId == 0) then

            for i, itemId in ipairs(lavka.items_sell) do
                local actualItemId, enchant = parseItemId(itemId)
                local itemName = getItemNameById(actualItemId)

                if itemName and averagePrices[itemName] and averagePrices[itemName].list then
                    local itemData = averagePrices[itemName]
                    local marketPrice = lavka.price_sell[i]

                    local totalSum = 0
                    local totalCount = 0
                    local dayData = itemData.list[1]
                    if dayData[2] > 0 then
                        totalSum = totalSum + dayData[3]
                        totalCount = totalCount + dayData[2]
                    end

                    if totalCount > 0 then
                        local averagePrice = totalSum / totalCount
                        local discountPercent = ((averagePrice - marketPrice) / averagePrice) * 100

                        if discountPercent >= thresholdPercent then
                            table.insert(cheapItems, {
                                itemId = actualItemId,
                                itemName = itemName,
                                lavka = lavka,
                                price = marketPrice,
                                averagePrice = averagePrice,
                                discountPercent = discountPercent,
                                count = lavka.count_sell[i],
                                enchant = enchant,
                            })
                        end
                    end
                end
            end
        end
    end

    table.sort(cheapItems, function(a, b)
        return a.discountPercent > b.discountPercent
    end)

    return cheapItems
end

local function drawCheapItems(cheapItems)
    if #cheapItems == 0 then
        imgui.Text(u8("Дешевые товары не найдены"))
        return
    end

    imgui.Text(u8("Найдено дешевых товаров: " .. #cheapItems))
    imgui.Separator()

    for i, item in ipairs(cheapItems) do
        LavkaButton(u8(string.format("%s -%d процентов", item.itemName .. (item.enchant ~= "" and " (" .. item.enchant .. ")" or ""), item.discountPercent)), item.lavka.LavkaUid)

        imgui.Text(u8("Цена: " .. comma_value(item.price) .. " " .. (item.lavka.serverId == 0 and "VC$" or "SA$")))
        imgui.SameLine()
        imgui.Text(u8("Средняя: " .. comma_value(math.floor(item.averagePrice)) .. " " .. (item.lavka.serverId == 0 and "VC$" or "SA$")))

        imgui.Text(u8("Лавка " .. item.lavka.LavkaUid .. " (" .. item.lavka.username .. ") - " .. item.count .. " шт."))

        if i < #cheapItems then
            imgui.Separator()
        end
    end
end

local function checkNewCheapItems(notify)
    if not notifyNewCheapItems[0] then return end

    local newCheapItems = {}

    for _, currentItem in ipairs(cheapItems) do
        local isNew = true

        for _, lastItem in ipairs(lastCheapItems) do
            if currentItem.itemId == lastItem.itemId and
               currentItem.lavka.LavkaUid == lastItem.lavka.LavkaUid and
               currentItem.price == lastItem.price and
               currentItem.discountPercent == lastItem.discountPercent then
                isNew = false
                break
            end
        end

        if isNew and
           currentItem.discountPercent >= minDiscountThreshold[0] then
            table.insert(newCheapItems, currentItem)
        end
    end

    if notify then
        if #newCheapItems > 0 then
            for _, item in ipairs(newCheapItems) do
                local message = string.format("LOWPRICE: {ffffff}%s. Цена: %s %s. Разница: %d процентов. Лавка %d (%s) - %d шт.",
                    item.itemName .. (item.enchant ~= "" and " (" .. item.enchant .. ")" or ""),
                    comma_value(item.price), item.lavka.serverId == 0 and "VC$" or "SA$",
                    math.floor(item.discountPercent),
                    item.lavka.LavkaUid, item.lavka.username, item.count)

                sampAddChatMessage(message, 0xaaaaaa)
            end

            sampAddChatMessage("Всего: {ffffff}" .. #newCheapItems .. "шт", 0xaaaaaa)
        end
    end

    lastCheapItems = {}
    for _, item in ipairs(cheapItems) do
        table.insert(lastCheapItems, {
            itemId = item.itemId,
            lavka = {LavkaUid = item.lavka.LavkaUid, username = item.lavka.username},
            price = item.price,
            discountPercent = item.discountPercent,
            count = item.count,
            enchant = item.enchant
        })
    end

    return newCheapItems
end

local function updateCheapItemsSearch(notify)
    local currentServerId = getCurrentServerId()
    local filtered_list = getFilteredMarketData(currentServerId)
    cheapItems = findCheapItems(currentServerId == 0 and "vc" or "user_server", filtered_list, thresholdPercent[0])

    checkNewCheapItems(notify)
end

local function drawCheapItemsTab()
    imgui.InputInt(u8("Разница"), thresholdPercent, 1, 10)
    imgui.Text(u8("Товары дешевле средней цены на " .. thresholdPercent[0] .. " процентов"))

    imgui.Text(u8("Настройки уведомлений:"))
    imgui.Checkbox(u8("Уведомлять о новых дешевых товарах"), notifyNewCheapItems)
    imgui.InputInt(u8("Мин. разница для уведомления (процентов)"), minDiscountThreshold, 1, 10)
    if imgui.Button(u8("Обновить"), imgui.ImVec2(-1, 80 * FONT_SCALE)) then
        updateCheapItemsSearch(true)
    end

    drawCheapItems(cheapItems)

    imgui.Separator()
    imgui.Text(u8("График средней цены (7/30 дней)"))

    imgui.PushItemWidth(420 * FONT_SCALE)
    imgui.InputTextWithHint("##avgChartQuery", u8("Название предмета"), avgChartQuery, ffi.sizeof(avgChartQuery))
    imgui.PopItemWidth()

    if imgui.Button(u8("7 дней"), imgui.ImVec2(150 * FONT_SCALE, 0)) then
        avgChartDays[0] = 7
    end
    imgui.SameLine()
    if imgui.Button(u8("30 дней"), imgui.ImVec2(150 * FONT_SCALE, 0)) then
        avgChartDays[0] = 30
    end

    local sourceKey = getCurrentServerId() == 0 and "vc" or "user_server"
    local averagePrices = (avg_prices[sourceKey] and avg_prices[sourceKey].sell) or {}
    local query = u8:decode(ffi.string(avgChartQuery)):nlower()

    if #query == 0 then
        imgui.Text(u8("Введите название предмета для графика"))
        return
    end

    local function avgEntryLabel(key, data)
        if type(key) == "string" then
            return key
        end
        if type(data) == "table" then
            if type(data.name) == "string" then
                return data.name
            end
            if type(data.item_name) == "string" then
                return data.item_name
            end
        end
        return nil
    end

    local foundName, foundData = nil, nil
    for key, data in pairs(averagePrices) do
        local label = avgEntryLabel(key, data)
        if label and type(data) == "table" and label:nlower() == query then
            foundName, foundData = label, data
            break
        end
    end

    if not foundData then
        for key, data in pairs(averagePrices) do
            local label = avgEntryLabel(key, data)
            if label and type(data) == "table" and label:nlower():find(query, 1, true) then
                foundName, foundData = label, data
                break
            end
        end
    end

    if not foundData or type(foundData.list) ~= "table" then
        imgui.Text(u8("Предмет не найден в базе средних цен"))
        return
    end

    local values = {}
    local maxDays = math.min(avgChartDays[0], #foundData.list, 30)
    for i = 1, maxDays do
        local dayData = foundData.list[i]
        local count = dayData and tonumber(dayData[2]) or 0
        local sum = dayData and tonumber(dayData[3]) or 0
        if count and count > 0 and sum then
            table.insert(values, sum / count)
        end
    end

    if #values == 0 then
        imgui.Text(u8("Недостаточно данных для построения графика"))
        return
    end

    local orderedValues = {}
    for i = #values, 1, -1 do
        table.insert(orderedValues, values[i])
    end

    local minVal, maxVal = orderedValues[1], orderedValues[1]
    for i, v in ipairs(orderedValues) do
        avgChartValues[i - 1] = v
        if v < minVal then minVal = v end
        if v > maxVal then maxVal = v end
    end

    imgui.Text(u8(string.format("%s | Период: %d дней", foundName, avgChartDays[0])))

    local chartW = imgui.GetContentRegionAvail().x
    local chartH = 220 * FONT_SCALE
    if chartW < 260 then chartW = 260 end
    local chartPos = imgui.GetCursorScreenPos()
    imgui.InvisibleButton("##avgPriceCanvas", imgui.ImVec2(chartW, chartH))

    local dl = imgui.GetWindowDrawList()
    local p1 = chartPos
    local p2 = imgui.ImVec2(chartPos.x + chartW, chartPos.y + chartH)
    dl:AddRectFilled(p1, p2, 0x1A1B2433, 10)
    dl:AddRect(p1, p2, 0x665F6B85, 10)

    local drawMin, drawMax = minVal, maxVal
    if drawMax <= drawMin then
        drawMin = drawMin - 1
        drawMax = drawMax + 1
    end

    local function mapX(i, n)
        if n <= 1 then return p1.x + chartW * 0.5 end
        return p1.x + ((i - 1) / (n - 1)) * chartW
    end

    local function mapY(v)
        local t = (v - drawMin) / (drawMax - drawMin)
        return p2.y - t * chartH
    end

    local n = #orderedValues
    for i = 1, n - 1 do
        local x1, y1 = mapX(i, n), mapY(orderedValues[i])
        local x2, y2 = mapX(i + 1, n), mapY(orderedValues[i + 1])
        dl:AddLine(imgui.ImVec2(x1, y1), imgui.ImVec2(x2, y2), 0xFF53D1FF, 3)
    end

    if n == 1 then
        dl:AddCircleFilled(imgui.ImVec2(mapX(1, 1), mapY(orderedValues[1])), 4, 0xFF53D1FF, 12)
    else
        dl:AddCircleFilled(imgui.ImVec2(mapX(1, n), mapY(orderedValues[1])), 4, 0xFF53D1FF, 12)
        dl:AddCircleFilled(imgui.ImVec2(mapX(n, n), mapY(orderedValues[n])), 4, 0xFF53D1FF, 12)
    end

    imgui.Text(u8(string.format("Мин: %s | Макс: %s | Последняя: %s",
        comma_value(math.floor(minVal)),
        comma_value(math.floor(maxVal)),
        comma_value(math.floor(orderedValues[#orderedValues])))))
end

local function drawCourseTab()
    imgui.Text(u8("Курс предметов"))
    imgui.Separator()

    imgui.PushItemWidth(460 * FONT_SCALE)
    imgui.InputTextWithHint("##avgChartQuery", u8("Название предмета"), avgChartQuery, ffi.sizeof(avgChartQuery))
    imgui.PopItemWidth()

    if imgui.Button(u8("7 дней"), imgui.ImVec2(150 * FONT_SCALE, 0)) then
        avgChartDays[0] = 7
    end
    imgui.SameLine()
    if imgui.Button(u8("30 дней"), imgui.ImVec2(150 * FONT_SCALE, 0)) then
        avgChartDays[0] = 30
    end

    if imgui.Button(u8("Продажа"), imgui.ImVec2(170 * FONT_SCALE, 0)) then
        avgChartMode[0] = 0
    end
    imgui.SameLine()
    if imgui.Button(u8("Скупка"), imgui.ImVec2(170 * FONT_SCALE, 0)) then
        avgChartMode[0] = 1
    end

    local sourceKey = getCurrentServerId() == 0 and "vc" or "user_server"
    local modeKey = avgChartMode[0] == 1 and "buy" or "sell"
    local averagePrices = (avg_prices[sourceKey] and avg_prices[sourceKey][modeKey]) or {}
    local query = u8:decode(ffi.string(avgChartQuery)):nlower()

    if query ~= avgChartLastQuery then
        avgChartLastQuery = query
        avgChartSelectedName = ""
    end

    if #query == 0 then
        imgui.Text(u8("Введите название предмета для графика"))
        return
    end

    local function avgEntryLabel(key, data)
        if type(key) == "string" then return key end
        if type(data) == "table" then
            if type(data.name) == "string" then return data.name end
            if type(data.item_name) == "string" then return data.item_name end
        end
        return nil
    end

    local matches = {}
    for key, data in pairs(averagePrices) do
        local label = avgEntryLabel(key, data)
        if label and type(data) == "table" then
            local labelLower = label:nlower()
            if labelLower == query or labelLower:find(query, 1, true) then
                matches[#matches + 1] = { name = label, data = data }
            end
        end
    end

    table.sort(matches, function(a, b)
        return a.name:nlower() < b.name:nlower()
    end)

    if #matches > 1 then
        imgui.Text(u8("Найдено несколько вариантов, выберите нужный:"))
        local shown = math.min(#matches, 14)
        imgui.BeginChild("##avgMatches", imgui.ImVec2(0, (24 * shown + 12) * FONT_SCALE), true)
        for i = 1, shown do
            local isSelected = avgChartSelectedName == matches[i].name
            if imgui.Selectable(u8(matches[i].name), isSelected) then
                avgChartSelectedName = matches[i].name
            end
        end
        imgui.EndChild()
    elseif #matches == 1 and avgChartSelectedName == "" then
        avgChartSelectedName = matches[1].name
    end

    local foundName, foundData = nil, nil
    if avgChartSelectedName ~= "" then
        for i = 1, #matches do
            if matches[i].name == avgChartSelectedName then
                foundName, foundData = matches[i].name, matches[i].data
                break
            end
        end
    end

    if not foundData and #matches > 0 then
        foundName, foundData = matches[1].name, matches[1].data
    end

    if not foundData or type(foundData.list) ~= "table" then
        imgui.Text(u8("Предмет не найден в базе средних цен"))
        return
    end

    local values = {}
    local maxDays = math.min(avgChartDays[0], #foundData.list, 30)
    for i = 1, maxDays do
        local dayData = foundData.list[i]
        local count = dayData and tonumber(dayData[2]) or 0
        local sum = dayData and tonumber(dayData[3]) or 0
        if count and count > 0 and sum then
            table.insert(values, sum / count)
        end
    end

    if #values == 0 then
        imgui.Text(u8("Недостаточно данных для построения графика"))
        return
    end

    local orderedValues = {}
    for i = #values, 1, -1 do table.insert(orderedValues, values[i]) end

    local minVal, maxVal = orderedValues[1], orderedValues[1]
    for i, v in ipairs(orderedValues) do
        avgChartValues[i - 1] = v
        if v < minVal then minVal = v end
        if v > maxVal then maxVal = v end
    end

    imgui.Text(u8(string.format("%s | Период: %d дней", foundName, avgChartDays[0])))
    imgui.SameLine()
    imgui.TextColored(imgui.ImVec4(0.75, 0.80, 0.95, 1.0), u8(modeKey == "buy" and "Скупка" or "Продажа"))
    local chartW = imgui.GetContentRegionAvail().x
    local chartH = 220 * FONT_SCALE
    if chartW < 260 then chartW = 260 end
    local chartPos = imgui.GetCursorScreenPos()
    imgui.InvisibleButton("##avgPriceCanvas", imgui.ImVec2(chartW, chartH))

    local dl = imgui.GetWindowDrawList()
    local p1 = chartPos
    local p2 = imgui.ImVec2(chartPos.x + chartW, chartPos.y + chartH)
    dl:AddRectFilled(p1, p2, 0x1A1B2433, 10)
    dl:AddRect(p1, p2, 0x665F6B85, 10)

    local drawMin, drawMax = minVal, maxVal
    if drawMax <= drawMin then drawMin = drawMin - 1 drawMax = drawMax + 1 end
    local function mapX(i, n)
        if n <= 1 then return p1.x + chartW * 0.5 end
        return p1.x + ((i - 1) / (n - 1)) * chartW
    end
    local function mapY(v)
        local t = (v - drawMin) / (drawMax - drawMin)
        return p2.y - t * chartH
    end

    local n = #orderedValues
    for i = 1, n - 1 do
        local x1, y1 = mapX(i, n), mapY(orderedValues[i])
        local x2, y2 = mapX(i + 1, n), mapY(orderedValues[i + 1])
        dl:AddLine(imgui.ImVec2(x1, y1), imgui.ImVec2(x2, y2), 0xFF53D1FF, 3)
    end

    if n == 1 then
        dl:AddCircleFilled(imgui.ImVec2(mapX(1, 1), mapY(orderedValues[1])), 4, 0xFF53D1FF, 12)
    else
        dl:AddCircleFilled(imgui.ImVec2(mapX(1, n), mapY(orderedValues[1])), 4, 0xFF53D1FF, 12)
        dl:AddCircleFilled(imgui.ImVec2(mapX(n, n), mapY(orderedValues[n])), 4, 0xFF53D1FF, 12)
    end

    imgui.Text(u8(string.format("Мин: %s | Макс: %s | Последняя: %s",
        comma_value(math.floor(minVal)),
        comma_value(math.floor(maxVal)),
        comma_value(math.floor(orderedValues[#orderedValues])))))
end

local function drawSettingsTab()
    imgui.Text(u8("Настройки интерфейса"))
    imgui.Separator()

    imgui.Text(u8("Цвет акцента"))
    imgui.ColorEdit3("##accentColor", uiAccentColor)
    imgui.Text(u8("Цвет вторичного акцента"))
    imgui.ColorEdit3("##accentDimColor", uiAccentDimColor)

    imgui.SliderFloat(u8("Прозрачность окна"), uiWindowAlpha, 0.70, 1.00, "%.2f")
    imgui.SliderFloat(u8("Прозрачность блоков"), uiChildAlpha, 0.20, 1.00, "%.2f")
    imgui.SliderFloat(u8("Масштаб интерфейса"), uiFontScaleValue, 0.90, 1.80, "%.2f")

    imgui.NewLine()
    imgui.Text(u8("Пресеты"))
    if imgui.Button(u8("Темная тема"), imgui.ImVec2(200 * FONT_SCALE, 0)) then
        applyAppearancePreset(0)
        saveAppearanceSettings()
    end
    imgui.SameLine()
    if imgui.Button(u8("Светлая тема"), imgui.ImVec2(200 * FONT_SCALE, 0)) then
        applyAppearancePreset(1)
        saveAppearanceSettings()
    end

    if imgui.Button(u8("Сбросить оформление"), imgui.ImVec2(260 * FONT_SCALE, 0)) then
        applyAppearancePreset(0)
        saveAppearanceSettings()
    end

    imgui.NewLine()
    imgui.Text(u8("Цветовые пресеты"))
    if imgui.Button(u8("Бирюзовый"), imgui.ImVec2(200 * FONT_SCALE, 0)) then
        applyColorPreset('turquoise')
        saveAppearanceSettings()
    end
    imgui.SameLine()
    if imgui.Button(u8("Рубиновый"), imgui.ImVec2(200 * FONT_SCALE, 0)) then
        applyColorPreset('ruby')
        saveAppearanceSettings()
    end

    imgui.NewLine()
    if imgui.Button(u8("Сохранить настройки"), imgui.ImVec2(260 * FONT_SCALE, 0)) then
        saveAppearanceSettings()
    end
end

local function drawArbitrageOpportunities(opportunities)
    if #opportunities == 0 then
        imgui.Text(u8("Не найдено"))
        return
    end

    imgui.Text(u8("Найдено: " .. #opportunities))
    imgui.Separator()

    for i, opp in ipairs(opportunities) do
        imgui.Text(u8(opp.itemName .. (opp.enchant ~= "" and " (" .. opp.enchant .. ")" or "")))

        LavkaButton(u8(string.format("ПОКУПКА: Лавка %d (%s) - %s %s (%d шт.)",
            opp.buyLavka.LavkaUid,
            opp.buyLavka.username,
            comma_value(opp.buyPrice),
            opp.buyLavka.serverId == 0 and "VC$" or "SA$",
            opp.buyCount)), opp.buyLavka.LavkaUid)

        LavkaButton(u8(string.format("ПРОДАЖА: Лавка %d (%s) - %s %s (%d шт.)",
            opp.sellLavka.LavkaUid,
            opp.sellLavka.username,
            comma_value(opp.sellPrice),
            opp.sellLavka.serverId == 0 and "VC$" or "SA$",
            opp.sellCount)), opp.sellLavka.LavkaUid)

        imgui.Text(u8("ПРОФИТ:"))
        imgui.SameLine()
        imgui.Text(u8(string.format("%s %s (с -8 процентов от цены продажи)", comma_value(opp.profit), opp.buyLavka.serverId == 0 and "VC$" or "SA$")))

        if i < #opportunities then
            imgui.Separator()
        end
    end
end

local function updateArbitrageOpportunities(notify)
    local currentServerId = getCurrentServerId()
    local filtered_list = getFilteredMarketData(currentServerId)
    local opportunities = findArbitrageOpportunities(filtered_list)
    arbitrageResults = opportunities

    checkNewArbitrageOpportunities(notify)
end

local function drawProfitTab()
    imgui.Text(u8("Покупка дороже продажи"))

    imgui.Text(u8("Настройки уведомлений:"))
    imgui.PushItemWidth(300 * FONT_SCALE)
    if imgui.InputInt(u8("Мин. профит для уведомления"), minProfitThreshold, 100, 1000) then
        ini.main.notify_min_profit = minProfitThreshold[0]
        inicfg.save(ini, directIni)
    end
    if imgui.Checkbox(u8("Уведомлять о новых предложениях"), notifyNewArbitrage) then
        ini.main.notify_enabled_profit = notifyNewArbitrage[0]
        inicfg.save(ini, directIni)
    end

    if imgui.Button(u8("Обновить"), imgui.ImVec2(-1, 80 * FONT_SCALE)) then
        updateArbitrageOpportunities(true)
    end

    imgui.NewLine()

    if arbitrageResults then
        drawArbitrageOpportunities(arbitrageResults)
    end
end

local function createItemData(lavka, itemId, price, count, index, isSell)
    local actual_item_id, enchant = parseItemId(itemId)

    return {
        item_id = actual_item_id,
        item_name = string.format("%d. %s%s", lavka.LavkaUid, getItemNameById(actual_item_id), enchant ~= "" and ("(%s)"):format(enchant) or ""),
        lavka_uid = lavka.LavkaUid,
        server_id = lavka.serverId,
        price = price,
        count = count,
        index = index,
        is_sell = isSell
    }
end

local function SearchHeader(itemCount)
    imgui.NewLine()
    imgui.NewLine()
    imgui.Text(fa["STORE"])
    imgui.SameLine()

    local cY = imgui.GetCursorPosY()
    imgui.SetCursorPosY(cY - 40)
    imgui.Indent(80 * FONT_SCALE)

    imgui.Text(u8("Всего найдено предметов в лавках: " .. itemCount))
end

local function SortButton()
    imgui.SameLine()
    imgui.SetCursorPosX(imgui.GetWindowWidth() / 3 * 2)
    if imgui.Button(u8("Сортировка: " .. sort_types[sort_type])) then
        sort_type = (sort_type % #sort_types) + 1
        return true
    end
    return false
end

local function drawLavkaCard(data)
    imgui.BeginChild("##lavka" .. data.username .. data.LavkaUid .. data.serverId, imgui.ImVec2(imgui.GetWindowWidth()/2 - 20, 310 * FONT_SCALE), true)

    imgui.NewLine()
    imgui.NewLine()
    imgui.Text(fa["STORE"])
    imgui.SameLine()

    local cY = imgui.GetCursorPosY()
    imgui.SetCursorPosY(cY - 40)
    imgui.Indent(80 * FONT_SCALE)

    imgui.Text(u8("Лавка игрока: " .. data.username))
    imgui.Text(u8("Продажа: " .. #data.items_sell))
    imgui.Text(u8("Скупка: " .. #data.items_buy))
    imgui.Text(u8("Сервер: " .. data.serverId))
    imgui.Text(u8("Лавка: " .. data.LavkaUid))

    if imgui.Button(u8("Открыть лавку"), imgui.ImVec2(-1, 80 * FONT_SCALE)) then
        window = WINDOW_STATES.USER_LAVKA
        lavka_data = data
    end

    imgui.EndChild()
end

local function drawLavkaItems(data, prefix, items, counts, prices)
    imgui.BeginChild("##lavka" .. prefix,
        imgui.ImVec2(imgui.GetWindowWidth() / 2 - imgui.GetStyle().ItemSpacing.x / 2 - imgui.GetStyle().WindowPadding.x, -1),
        true)

    for k, itemId in pairs(items) do
        local actual_item_id, enchant = parseItemId(itemId)

        LavkaButton(
            string.format("%d. %s%s", k, u8(getItemNameById(actual_item_id)), enchant),
            data.LavkaUid
        )

        imgui.Text(u8(string.format("%s шт. | %s %s",
            counts[k], comma_value(prices[k]),
            data.serverId == 0 and "VC$" or "SA$")))

        if k ~= #items then
            imgui.Separator()
        end
    end

    imgui.EndChild()
end

local function drawUserLavka(data)
    imgui.NewLine()
    imgui.Text(fa["STORE"])
    imgui.SameLine()

    local cY = imgui.GetCursorPosY()
    imgui.SetCursorPosY(cY - 40)
    imgui.Indent(80 * FONT_SCALE)

    imgui.Text(u8("Владелец лавки: " .. data.username))
    imgui.Text(u8("ID лавки: " .. data.LavkaUid))
    imgui.Text(u8("Всего предметов в лавке: " .. #data.items_buy + #data.items_sell))
    imgui.Text(u8("Предметов на скупке: " .. #data.items_buy))
    imgui.SameLine()
    imgui.SetCursorPosX(imgui.GetWindowWidth() / 2)
    imgui.Text(u8("Предметов на продаже: " .. #data.items_sell))
    imgui.SetCursorPosX(imgui.GetStyle().WindowPadding.x)

    drawLavkaItems(data, "buy", data.items_buy, data.count_buy, data.price_buy)
    imgui.SameLine()
    drawLavkaItems(data, "sell", data.items_sell, data.count_sell, data.price_sell)
end

local function drawSearchResultsColumn(items, id)
    imgui.BeginChild("##" .. id,
        imgui.ImVec2(imgui.GetWindowWidth() / 2 - imgui.GetStyle().ItemSpacing.x / 2 - imgui.GetStyle().WindowPadding.x, -1),
        true, nil)

    for k, item in pairs(items) do
        LavkaButton(u8(item.item_name), item.lavka_uid)

        imgui.Text(u8(string.format("%s шт. | %s %s Сервер: %s",
            item.count, comma_value(item.price),
            item.server_id == 0 and "VC$" or "SA$",
            serversName[item.server_id + 2])))

        if k ~= #items then
            imgui.Separator()
        end
    end

    imgui.EndChild()
end


local function searchItems(filtered_list)
    local search_text = u8:decode(ffi.string(search)):nlower()
    
    search_results = { sell = {}, buy = {} }

    for _, lavka in pairs(filtered_list) do
        -- Поиск в ПРОДАЖЕ
        for i, itemId in ipairs(lavka.items_sell) do
            local actual_item_id, enchant = parseItemId(itemId)
            local item_name = getItemNameById(actual_item_id):nlower()
            
            if item_name:find(search_text, 1, true) then
                local item_data = createItemData(lavka, itemId, lavka.price_sell[i], lavka.count_sell[i], i, true)
                table.insert(search_results.sell, item_data)
            end
        end

        -- Поиск в СКУПКЕ
        for i, itemId in ipairs(lavka.items_buy) do
            local actual_item_id, enchant = parseItemId(itemId)
            local item_name = getItemNameById(actual_item_id):nlower()
            
            if item_name:find(search_text, 1, true) then
                local item_data = createItemData(lavka, itemId, lavka.price_buy[i], lavka.count_buy[i], i, false)
                table.insert(search_results.buy, item_data)
            end
        end
    end

    if sort_type == 2 then
        table.sort(search_results.sell, function(a, b) return a.price < b.price end)
        table.sort(search_results.buy, function(a, b) return a.price < b.price end)
    elseif sort_type == 3 then
        table.sort(search_results.sell, function(a, b) return a.price > b.price end)
        table.sort(search_results.buy, function(a, b) return a.price > b.price end)
    end
end

local function drawSearchResults(data, all)
    SearchHeader(#data.buy + #data.sell)

    if SortButton() then
        searchItems(all)
    end

    imgui.NewLine()
    imgui.Text(u8("Предметов на скупке: " .. #data.buy))
    imgui.SameLine()
    imgui.SetCursorPosX(imgui.GetWindowWidth() / 2)
    imgui.Text(u8("Предметов на продаже: " .. #data.sell))

    imgui.SetCursorPosX(imgui.GetStyle().WindowPadding.x)
    drawSearchResultsColumn(data.buy, "lavkabuy")
    imgui.SameLine()
    drawSearchResultsColumn(data.sell, "lavkasell")
end

local function drawMarketGrid(filtered_list)
    local listClipper = imgui.ImGuiListClipper()
    listClipper:Begin(math.ceil(#filtered_list / 2), 230)

    while listClipper:Step() do
        for row = listClipper.DisplayStart, listClipper.DisplayEnd - 1 do
            local index1 = row * 2 + 1
            local index2 = row * 2 + 2
            local window_width = imgui.GetWindowWidth()
            local item_width = (window_width - 10 - imgui.GetStyle().ItemSpacing.x) / 2

            imgui.BeginGroup()
            if filtered_list[index1] then
                drawLavkaCard(filtered_list[index1])
            end
            imgui.EndGroup()

            local item1_width = imgui.GetItemRectSize().x
            if item1_width < item_width then
                imgui.SameLine(0, item_width - item1_width)
            else
                imgui.SameLine()
            end

            imgui.BeginGroup()
            if filtered_list[index2] then
                drawLavkaCard(filtered_list[index2])
            end
            imgui.EndGroup()
        end
    end
end

local function handleSearchInput(filtered_list)
    if #u8:decode(ffi.string(search)) > 0 then
        window = WINDOW_STATES.SEARCH_RESULTS
        searchItems(filtered_list)
    else
        window = WINDOW_STATES.MARKET_LIST
    end
end

local function drawMarketTab(filtered_list)
    if window == WINDOW_STATES.MARKET_LIST then
        drawMarketGrid(filtered_list)
    elseif window == WINDOW_STATES.USER_LAVKA then
        if imgui.Button(u8("Назад")) then
            window = WINDOW_STATES.MARKET_LIST
        end
        imgui.NewLine()
        drawUserLavka(lavka_data)

    elseif window == WINDOW_STATES.SEARCH_RESULTS then
        drawSearchResults(search_results, filtered_list)
    end
end

local newFrame = imgui.OnFrame(
    function() return renderWindow[0] end,
    function(self)
        local resX, resY = getScreenResolution()
        applyUiThemeFromSettings()
        imgui.SetNextWindowSizeConstraints(
            imgui.ImVec2(UI_MIN_WIDTH, UI_MIN_HEIGHT),
            imgui.ImVec2(math.max(UI_MIN_WIDTH, resX - 20), math.max(UI_MIN_HEIGHT, resY - 20))
        )
        if pendingApplySavedWindowRect and (ini.main.ui_window_w or -1) > 0 and (ini.main.ui_window_h or -1) > 0 then
            imgui.SetNextWindowPos(imgui.ImVec2(ini.main.ui_window_x, ini.main.ui_window_y), imgui.Cond.Always)
            imgui.SetNextWindowSize(imgui.ImVec2(ini.main.ui_window_w, ini.main.ui_window_h), imgui.Cond.Always)
            pendingApplySavedWindowRect = false
        else
            imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
            imgui.SetNextWindowSize(imgui.ImVec2(resY * 4 / 3, resY), imgui.Cond.FirstUseEver)
        end
        if imgui.Begin(u8('###marketplace_window'), renderWindow, imgui.WindowFlags.NoCollapse) then
            local wPos = imgui.GetWindowPos()
            local wSize = imgui.GetWindowSize()
            ini.main.ui_window_x = wPos.x
            ini.main.ui_window_y = wPos.y
            ini.main.ui_window_w = wSize.x
            ini.main.ui_window_h = wSize.y
            saveUiState(false)

            if vipFeatureEnabled and not vipAuthorized then
                imgui.Text(u8("Требуется VIP-ключ"))
                imgui.PushItemWidth(420 * FONT_SCALE)
                imgui.InputTextWithHint("##vipKey", u8("Введите ключ"), vipKeyInput, ffi.sizeof(vipKeyInput))
                imgui.PopItemWidth()
                if imgui.Button(u8("Активировать"), imgui.ImVec2(200 * FONT_SCALE, 0)) then
                    local ok, err = tryAuthorizeVipKey(u8:decode(ffi.string(vipKeyInput)))
                    vipAuthorized = ok
                    vipAuthError = err or ""
                end
                if #vipAuthError > 0 then
                    imgui.TextColored(imgui.ImVec4(1.00, 0.35, 0.35, 1.00), vipAuthError)
                end
                imgui.End()
                return
            end

            imgui.SetWindowFontScale(FONT_SCALE)
            local currentServerId = getCurrentServerId()
            local filtered_list = getFilteredMarketData(currentServerId)

            local accent = imgui.ImVec4(uiAccentColor[0], uiAccentColor[1], uiAccentColor[2], 1.00)
            local accentDim = imgui.ImVec4(uiAccentDimColor[0], uiAccentDimColor[1], uiAccentDimColor[2], 1.00)
            imgui.SetCursorPosY(imgui.GetCursorPosY() + 20 * FONT_SCALE)
            imgui.TextColored(accent, faSafe('STORE', 'M') .. u8(' MARKETPLACE'))
            if imgui.GetWindowWidth() > (930 * FONT_SCALE) then
                imgui.SameLine()
                imgui.TextColored(accentDim, u8('  Arizona RP mobile'))
            else
                imgui.TextColored(accentDim, u8('Arizona RP mobile'))
            end
            imgui.Separator()

            local sidebarWidth = 190 * FONT_SCALE
            if imgui.GetWindowWidth() < (1100 * FONT_SCALE) then
                sidebarWidth = 150 * FONT_SCALE
            end
            imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.10, 0.08, 0.06, 0.95))
            imgui.BeginChild("##sidebar", imgui.ImVec2(sidebarWidth, -1), true)
            imgui.TextColored(accent, u8("Навигация"))
            imgui.Separator()

            local menuItems = {
                { id = 1, label = u8("Маркет") },
                { id = 2, label = u8("Курс") },
                { id = 3, label = u8("Настройки") },
            }
            imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(14 * FONT_SCALE, 10 * FONT_SCALE))
            for _, it in ipairs(menuItems) do
                local isActive = activeSidebarSection == it.id
                if isActive then
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.95, 0.60, 0.12, 1.00))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.85, 0.52, 0.10, 1.00))
                    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.95, 0.60, 0.12, 1.00))
                    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.10, 0.08, 0.06, 1.00))
                else
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.19, 0.15, 0.11, 0.95))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.34, 0.24, 0.12, 0.95))
                    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.52, 0.34, 0.12, 0.95))
                    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.92, 0.88, 0.80, 1.00))
                end

                if imgui.Button(it.label .. "##menu" .. it.id, imgui.ImVec2(-1, 40 * FONT_SCALE)) then
                    activeSidebarSection = it.id
                    saveUiState(false)
                end
                imgui.PopStyleColor(4)
            end
            imgui.PopStyleVar()
            imgui.EndChild()
            imgui.PopStyleColor()

            imgui.SameLine()

            imgui.BeginChild("##content", imgui.ImVec2(0, -1), false)
            local contentWidth = imgui.GetContentRegionAvail().x
            imgui.Text(u8("Лавок: " .. #filtered_list))
            if contentWidth > (900 * FONT_SCALE) then
                imgui.SameLine()
            else
                imgui.NewLine()
            end

            local comboWidth = contentWidth > (900 * FONT_SCALE) and (300 * FONT_SCALE) or math.max(220 * FONT_SCALE, contentWidth)
            imgui.PushItemWidth(comboWidth)
            if imgui.Combo("##serverselect", server_selected, serverList, #serversName) then
                refreshAllDataInBackground()
            end
            imgui.PopItemWidth()

            if activeSidebarSection == 1 then
                if contentWidth > (900 * FONT_SCALE) then
                    imgui.SameLine()
                else
                    imgui.NewLine()
                end
                local searchWidth = contentWidth > (900 * FONT_SCALE) and (380 * FONT_SCALE) or math.max(240 * FONT_SCALE, contentWidth)
                imgui.PushItemWidth(searchWidth)
                if imgui.InputTextWithHint("##search", u8("Поиск товара"), search, ffi.sizeof(search)) then
                    handleSearchInput(filtered_list)
                end
                imgui.PopItemWidth()
                drawMarketTab(filtered_list)
            elseif activeSidebarSection == 2 then
                drawCourseTab()
            else
                drawSettingsTab()
            end

            imgui.EndChild()
            imgui.End()
        end
    end
)

-- ===== AUTO-UPDATE SYSTEM =====
local function parseVersion(vStr)
    -- РџСЂРµРІСЂР°С‰Р°РµС‚ "1.0" -> {1, 0}, "2.10" -> {2, 10}
    local parts = {}
    for n in tostring(vStr or ""):gmatch("(%d+)") do
        table.insert(parts, tonumber(n))
    end
    return parts
end

local function isNewerVersion(remoteStr, currentStr)
    local r = parseVersion(remoteStr)
    local c = parseVersion(currentStr)
    local maxLen = math.max(#r, #c)
    for i = 1, maxLen do
        local rv = r[i] or 0
        local cv = c[i] or 0
        if rv > cv then return true end
        if rv < cv then return false end
    end
    return false
end

-- getWorkingDirectory() вЂ” РїСЂР°РІРёР»СЊРЅС‹Р№ СЃРїРѕСЃРѕР± РїРѕР»СѓС‡РёС‚СЊ РїР°РїРєСѓ СЃРєСЂРёРїС‚РѕРІ РІ ArzMod.
-- thisScript().dirPath РЅР° Android РІРѕР·РІСЂР°С‰Р°РµС‚ РїСѓС‚СЊ Рє СЃР°РјРѕРјСѓ С„Р°Р№Р»Сѓ, Р° РЅРµ Рє РїР°РїРєРµ.
local function getScriptDir()
    local dir = getWorkingDirectory():gsub('\\', '/')
    if dir:sub(-1) ~= '/' then dir = dir .. '/' end
    return dir
end

-- Р—Р°РїСѓСЃРєР°РµС‚СЃСЏ РІ effil-РїРѕС‚РѕРєРµ (РѕС‚РґРµР»СЊРЅС‹Р№ Lua state, Р±РµР· upvalues).
-- РСЃРїРѕР»СЊР·СѓРµС‚ socket.http + ltn12 вЂ” РєР°Рє Arizona_Helper РЅР° РјРѕР±РёР»РєРµ.
-- socket.http СЃР»РµРґСѓРµС‚ СЂРµРґРёСЂРµРєС‚Р°Рј (301/302) Р°РІС‚РѕРјР°С‚РёС‡РµСЃРєРё, РІ РѕС‚Р»РёС‡РёРµ РѕС‚ lua-requests.
-- РџРёС€РµС‚ С„Р°Р№Р» РЅР°РїСЂСЏРјСѓСЋ С‡РµСЂРµР· ltn12.sink.file вЂ” Р±РµР· Р±СѓС„РµСЂРёР·Р°С†РёРё РІ РїР°РјСЏС‚Рё.
local function downloadToFileViaSocket(url, destPath)
    local http  = require('socket.http')
    local ltn12 = require('ltn12')

    local f, ferr = io.open(destPath, 'wb')
    if not f then
        return false, 'io.open failed: ' .. tostring(ferr)
    end

    local ok, code, _, _ = http.request{
        method  = 'GET',
        url     = url,
        sink    = ltn12.sink.file(f),
        headers = { ['user-agent'] = 'marketplace_mobile-autoupdate/lua' }
    }
    -- ltn12.sink.file Р·Р°РєСЂС‹РІР°РµС‚ f СЃР°Рј РїРѕСЃР»Рµ Р·Р°РїРёСЃРё

    if not ok then
        os.remove(destPath)
        return false, 'socket.http error: ' .. tostring(code)
    end
    if tonumber(code) ~= 200 then
        os.remove(destPath)
        return false, 'HTTP ' .. tostring(code)
    end

    return true, nil
end

local function performUpdate(newVersion, assetName, downloadUrl)
    logInfo("Autoupdate: start download " .. tostring(assetName) .. " | " .. tostring(downloadUrl))
    sampAddChatMessage(u8("[MarketHelper] Downloading update v" .. tostring(newVersion) .. "..."), 0xFFAA00)

    local scriptDir = getScriptDir()
    local newPath   = scriptDir .. assetName
    local oldPath   = thisScript().path

    logInfo("Autoupdate: new file path: " .. tostring(newPath))
    logInfo("Autoupdate: old file path: " .. tostring(oldPath))

    local thread = effil.thread(downloadToFileViaSocket)(downloadUrl, newPath)

    lua_thread.create(function()
        while true do
            wait(300)
            local status, threadErr = thread:status()
            if not status or threadErr then
                logErrorPrint("Autoupdate: effil thread failed", tostring(threadErr))
                sampAddChatMessage(u8("[MarketHelper] Download thread error!"), 0xFF4444)
                return
            end

            if status == 'completed' or status == 'canceled' then
                local ok, dlErr = thread:get()
                if not ok then
                    logErrorPrint("Autoupdate: download failed", tostring(dlErr))
                    sampAddChatMessage(u8("[MarketHelper] Download error: " .. tostring(dlErr or "unknown")), 0xFF4444)
                    return
                end

                logInfo("Autoupdate: file saved: " .. tostring(newPath))

                if oldPath ~= newPath then
                    local removed = os.remove(oldPath)
                    logInfo("Autoupdate: old file " .. (removed and "removed" or "not removed") .. ": " .. tostring(oldPath))
                end

                sampAddChatMessage(u8("[MarketHelper] Update v" .. tostring(newVersion) .. " installed! Use /reloadscripts"), 0x44FF44)
                logInfo("Autoupdate: v" .. tostring(newVersion) .. " installed")
                return
            end
        end
    end)
end

local function checkForUpdates()
    logInfo("Autoupdate: checking updates (current v" .. tostring(CURRENT_VERSION) .. ")")

    async_http_request:create('json', 'GET', GITHUB_RELEASES_API)
    :setHeaders({
        ['User-Agent'] = 'marketplace_mobile-autoupdate/lua',
        ['Accept'] = 'application/vnd.github+json'
    })
    :setCallback(function(status_code, res, err)
        if status_code ~= 200 or type(res) ~= 'string' then
            logErrorPrint("Autoupdate: GitHub API error", status_code, err)
            return
        end

        local ok, releases = pcall(decodeJson, res)
        if not ok or type(releases) ~= 'table' or #releases == 0 then
            logErrorPrint("Autoupdate: failed to parse releases JSON")
            return
        end

        local latest = releases[1]
        local remoteVer = tostring(latest.name or "")
        if remoteVer == "" then
            logErrorPrint("Autoupdate: empty release name")
            return
        end

        logInfo("Autoupdate: GitHub v" .. remoteVer .. ", local v" .. tostring(CURRENT_VERSION))

        if not isNewerVersion(remoteVer, CURRENT_VERSION) then
            logInfo("Autoupdate: no update required")
            return
        end

        local assets = latest.assets or {}
        local dlUrl, assetName
        for _, asset in ipairs(assets) do
            if type(asset.name) == 'string' and asset.name:lower():match("%.lua$") then
                dlUrl = asset.browser_download_url
                assetName = asset.name
                break
            end
        end

        if not dlUrl then
            logErrorPrint("Autoupdate: .lua asset not found in release v" .. remoteVer)
            return
        end

        logInfo("Autoupdate: update found v" .. tostring(CURRENT_VERSION) .. " -> v" .. remoteVer .. " (" .. tostring(assetName) .. ")")
        sampAddChatMessage(u8("[MarketHelper] Update available: v" .. tostring(CURRENT_VERSION) .. " -> v" .. remoteVer), 0xFFCC00)

        performUpdate(remoteVer, assetName, dlUrl)
    end)
    :send()
end
-- ===== END AUTO-UPDATE SYSTEM =====

function main()
    while not isSampAvailable() do wait(0) end
    logInfo('Script main started')

    vipAuthorized = (not vipFeatureEnabled) or isVipKeyValid(ini.main.vip_key or "")
    syncServerSelectionWithCurrent()

    -- РџСЂРѕРІРµСЂРєР° РѕР±РЅРѕРІР»РµРЅРёР№ С‡РµСЂРµР· 3 СЃРµРє РїРѕСЃР»Рµ СЃС‚Р°СЂС‚Р° (С‡С‚РѕР±С‹ SAMP СѓСЃРїРµР» РёРЅРёС†РёР°Р»РёР·РёСЂРѕРІР°С‚СЊСЃСЏ)
    lua_thread.create(function()
        wait(3000)
        checkForUpdates()
    end)

    sampRegisterChatCommand('market', function()
        local opening = not renderWindow[0]
        renderWindow[0] = opening
        if opening then
            logInfo('/market open requested')
            syncServerSelectionWithCurrent()
            pendingApplySavedWindowRect = true
            refreshAllDataInBackground()
            lastAutoRefreshAt = os.time()
        else
            logInfo('/market close requested')
            saveUiState(true)
        end
    end)
    refreshAllDataInBackground()
    lastAutoRefreshAt = os.time()
    while true do
        wait(1000)
        local now = os.time()
        if (not renderWindow[0]) and now - lastAutoRefreshAt >= CLOSED_REFRESH_INTERVAL_SECONDS then
            lastAutoRefreshAt = now
            refreshAllDataInBackground()
        end
    end
end

addEventHandler("onWindowMessage", function (msg, wp, lp)
    if wp == 0x1B and renderWindow[0] then
        if msg == 0x100 then
            consumeWindowMessage(true, false)
        end
        if msg == 0x101 then
            renderWindow[0] = false
            saveUiState(true)
        end
    end
end)

function updateMarketData(server, notify)
    server = server or "-1"
    async_http_request:create('json', 'GET', getMarketplaceUrl(server))
    :setCallback(function (status_code, res, err)
        if status_code == 200 then
            local ok, parsed = pcall(decodeJson, res)
            if ok and type(parsed) == "table" then
                if parsed.ok == true and type(parsed.data) == "table" then
                    market_data = parsed.data
                    market_data_version = market_data_version + 1
                elseif parsed.ok == false then
                    logErrorPrint("updateMarketData proxy error", parsed.error or err)
                    return
                elseif next(parsed) ~= nil then
                    market_data = parsed
                    market_data_version = market_data_version + 1
                else
                    logErrorPrint("updateMarketData empty data", status_code, err)
                    return
                end
            else
                logErrorPrint("updateMarketData decode error", status_code, err)
                return
            end
        else
            logErrorPrint(status_code, res, err)
        end
    end)
    :send()
end

--[[
function DeepPrint (t)
  local request_headers_all = ""
  for k, v in pairs(t) do
    if type(v) == "table" then
      request_headers_all = request_headers_all .. "[" .. k .. " " .. DeepPrint(v) .. "] "
    else
      local rowtext = ""
      if type(k) == "string" then
        rowtext = string.format("[%s %s] ", k, v)
      else
        rowtext = string.format("[%s] ", v)
      end    
      request_headers_all = request_headers_all .. rowtext
    end
  end
  return request_headers_all
end
]]

function updateItemsData()
    --async_http_request:create('json', 'GET', "https://raw.githubusercontent.com/FREYM1337/forumnick/main/items_data.json")
    --async_http_request:create('json', 'GET', "https://items.shinoa.tech/items.php")
    async_http_request:create('json', 'GET', "https://server-api.arizona.games/client/json/table/get?project=arizona&server=0&key=inventory_items")
    :setCallback(function (status_code, res, err)
        if status_code == 200 then
            items_data = {}
            local ok, items_arz = pcall(decodeJson, res)
            if not ok or type(items_arz) ~= "table" then
                logErrorPrint("updateItemsData decode error", status_code, err)
                return
            end
            for i,v in pairs(items_arz) do
            	--print(type(v.id), v.id, DeepPrint(v))
            	--print(v.id, v.item_name)
            	items_data[v.id] = u8:decode(v.name)
            end
            --print(DeepPrint(items_arz))
            --print(DeepPrint(items_data))
        else
            logErrorPrint(status_code, res, err)
        end
    end)
    :send()
end

function updateAvgPrices(servername)
    avg_prices.vc = {}
    if servername then
        avg_prices.user_server = {}
        async_http_request:create('json', 'GET', "https://raw.githubusercontent.com/FREYM1337/forumnick/main/avg_price/info_users_sell_"..servername..".json")
        :setCallback(function (status_code, res, err)
            if status_code == 200 then
                local ok, parsed = pcall(decodeJson, res)
                if ok and type(parsed) == "table" then
                    avg_prices.user_server.sell = parsed
                else
                    logErrorPrint("updateAvgPrices user_server decode error", status_code, err)
                end
            else
                logErrorPrint(status_code, res, err)
            end
        end)
        :send()
    end
    async_http_request:create('json', 'GET', "https://raw.githubusercontent.com/FREYM1337/forumnick/main/avg_price/info_users_sell_vc.json")
    :setCallback(function (status_code, res, err)
        if status_code == 200 then
            local ok, parsed = pcall(decodeJson, res)
            if ok and type(parsed) == "table" then
                avg_prices.vc.sell = parsed
            else
                logErrorPrint("updateAvgPrices vc decode error", status_code, err)
            end
        else
            logErrorPrint(status_code, res, err)
        end
    end)
    :send()
end

function findItemsByName(name)
    local result = {}
    local search_lower = name:nlower()

    for itemId, item in pairs(items_data) do
        if item:nlower():find(search_lower) then
            table.insert(result, tonumber(itemId))
        end
    end

    return result
end

function getItemNameById(itemId)
    local numId = tonumber(itemId)
    if numId and items_data[numId] then
        return items_data[numId]
    end

    if type(itemId) == "string" and itemId ~= "" then
        local ok, decoded = pcall(function() return u8:decode(itemId) end)
        if ok and type(decoded) == "string" and decoded ~= "" then
            return decoded
        end
        return itemId
    end

    return ":item" .. tostring(itemId) .. ":"
end

function sampev.onConnectionRequestAccepted(ip, port, playerId, challenge)
    syncServerSelectionWithCurrent()
    
    lua_thread.create(function()
        wait(1000)
        sampAddChatMessage(u8("[MarketHelper] Type /market to open marketplace"), 0xFFCC00)
    end)
end

--- @param type 'xform'|'json'
--- @param method 'GET'|'POST'
--- @param url string
function async_http_request:create(type, method, url)
    self.request = {
        method = method,
        type = type,
        url = url,
        body = {
        headers = {}
        },
        callback = function() end
    }
    self:setHeaders({ ['content-type'] = header_content_types[type] })
    return self
end

--- @param headers table
function async_http_request:setHeaders(headers)
    for k, v in pairs(headers) do
        self.request.body.headers[k] = v
    end
    return self
end

--- @param params table
function async_http_request:setParams(params)
    self.request.url = self.request.url .. '?' .. encodeUrl(params)
    return self
end

--- @param data table
function async_http_request:setData(data)
    if self.request.type == 'xform' then
        self.request.body.data = encodeUrl(data)
    elseif self.request.type == 'json' then
        self.request.body.data = u8(encodeJson(data))
    end
    return self
end

--- @param callback fun(status_code: string|nil, res: any|nil, err: string|nil)
function async_http_request:setCallback(callback)
    self.request.callback = callback
    return self
end

function async_http_request:send()
    local method = self.request.method
    local url = tostring(self.request.url or '')
    local body = deepCopyPlain(self.request.body)
    if type(body) ~= 'table' then
        body = { headers = {} }
    end
    if type(body.headers) ~= 'table' then
        body.headers = {}
    end
    local callback = self.request.callback

    logInfo('HTTP request: ' .. tostring(method) .. ' ' .. tostring(url))
    local ok, err = pcall(createEffilThread, method, url, body, function(status_code, res, reqErr)
        local okCb, cbErr = pcall(callback, status_code, res, reqErr)
        if not okCb then
            logErrorPrint('callback failed', cbErr)
        end
    end)

    if not ok then
        logErrorPrint('createEffilThread failed, fallback to lua_thread', err)
        lua_thread.create(function()
            local okReq, status_code, res, reqErr = pcall(requestJson, method, url, body)
            if not okReq then
                logErrorPrint('requestJson failed', status_code)
                local okCb, cbErr = pcall(callback, nil, nil, tostring(status_code))
                if not okCb then
                    logErrorPrint('callback failed after requestJson error', cbErr)
                end
                return
            end

            local okCb, cbErr = pcall(callback, status_code, res, reqErr)
            if not okCb then
                logErrorPrint('callback failed', cbErr)
            end
        end)
    end
end

function Theme()
    imgui.SwitchContext()
    local style = imgui.GetStyle()

    style.WindowPadding = imgui.ImVec2(16, 16)
    style.WindowRounding = 14.0
    style.ChildRounding = 10.0
    style.FramePadding = imgui.ImVec2(16 * FONT_SCALE, 14 * FONT_SCALE)
    style.FrameRounding = 12.0
    style.ItemSpacing = imgui.ImVec2(10, 10)
    style.ItemInnerSpacing = imgui.ImVec2(10, 6)
    style.IndentSpacing = 25.0
    style.ScrollbarSize = 18.0
    style.ScrollbarRounding = 12.0
    style.GrabMinSize = 10.0
    style.GrabRounding = 8.0
    style.PopupRounding = 8
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
    style.ButtonTextAlign = imgui.ImVec2(0.5, 0.5)

    style.Colors[imgui.Col.Text]                   = imgui.ImVec4(0.95, 0.97, 1.00, 1.00)
    style.Colors[imgui.Col.TextDisabled]           = imgui.ImVec4(0.56, 0.63, 0.74, 1.00)
    style.Colors[imgui.Col.WindowBg]               = imgui.ImVec4(0.08, 0.10, 0.15, 0.98)
    style.Colors[imgui.Col.ChildBg]                = imgui.ImVec4(0.12, 0.15, 0.22, 0.60)
    style.Colors[imgui.Col.PopupBg]                = imgui.ImVec4(0.10, 0.13, 0.19, 0.96)
    style.Colors[imgui.Col.Border]                 = imgui.ImVec4(0.25, 0.34, 0.48, 0.85)
    style.Colors[imgui.Col.BorderShadow]           = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
    style.Colors[imgui.Col.FrameBg]                = imgui.ImVec4(0.15, 0.19, 0.28, 0.85)
    style.Colors[imgui.Col.FrameBgHovered]         = imgui.ImVec4(0.20, 0.26, 0.38, 0.95)
    style.Colors[imgui.Col.FrameBgActive]          = imgui.ImVec4(0.24, 0.30, 0.44, 1.00)
    style.Colors[imgui.Col.TitleBg]                = imgui.ImVec4(0.11, 0.15, 0.24, 1.00)
    style.Colors[imgui.Col.TitleBgCollapsed]       = imgui.ImVec4(0.09, 0.12, 0.18, 1.00)
    style.Colors[imgui.Col.TitleBgActive]          = imgui.ImVec4(0.13, 0.18, 0.29, 1.00)
    style.Colors[imgui.Col.MenuBarBg]              = imgui.ImVec4(0.10, 0.13, 0.20, 1.00)
    style.Colors[imgui.Col.ScrollbarBg]            = imgui.ImVec4(0.08, 0.11, 0.17, 0.70)
    style.Colors[imgui.Col.ScrollbarGrab]          = imgui.ImVec4(0.30, 0.49, 0.76, 0.70)
    style.Colors[imgui.Col.ScrollbarGrabHovered]   = imgui.ImVec4(0.39, 0.60, 0.86, 0.85)
    style.Colors[imgui.Col.ScrollbarGrabActive]    = imgui.ImVec4(0.45, 0.67, 0.93, 1.00)
    style.Colors[imgui.Col.CheckMark]              = imgui.ImVec4(0.36, 0.84, 0.79, 1.00)
    style.Colors[imgui.Col.SliderGrab]             = imgui.ImVec4(0.32, 0.73, 0.93, 0.95)
    style.Colors[imgui.Col.SliderGrabActive]       = imgui.ImVec4(0.36, 0.84, 0.97, 1.00)
    style.Colors[imgui.Col.Button]                 = imgui.ImVec4(0.18, 0.36, 0.60, 0.95)
    style.Colors[imgui.Col.ButtonHovered]          = imgui.ImVec4(0.24, 0.49, 0.77, 1.00)
    style.Colors[imgui.Col.ButtonActive]           = imgui.ImVec4(0.28, 0.60, 0.90, 1.00)
    style.Colors[imgui.Col.Header]                 = imgui.ImVec4(0.17, 0.28, 0.46, 0.85)
    style.Colors[imgui.Col.HeaderHovered]          = imgui.ImVec4(0.22, 0.40, 0.63, 0.95)
    style.Colors[imgui.Col.HeaderActive]           = imgui.ImVec4(0.27, 0.50, 0.75, 1.00)
    style.Colors[imgui.Col.Separator]              = imgui.ImVec4(0.23, 0.35, 0.52, 0.80)
    style.Colors[imgui.Col.SeparatorHovered]       = imgui.ImVec4(0.33, 0.51, 0.75, 0.95)
    style.Colors[imgui.Col.SeparatorActive]        = imgui.ImVec4(0.39, 0.60, 0.85, 1.00)
    style.Colors[imgui.Col.ResizeGrip]             = imgui.ImVec4(0.34, 0.58, 0.84, 0.65)
    style.Colors[imgui.Col.ResizeGripHovered]      = imgui.ImVec4(0.42, 0.69, 0.93, 0.85)
    style.Colors[imgui.Col.ResizeGripActive]       = imgui.ImVec4(0.48, 0.78, 1.00, 1.00)
    style.Colors[imgui.Col.PlotLines]              = imgui.ImVec4(0.32, 0.82, 1.00, 1.00)
    style.Colors[imgui.Col.PlotLinesHovered]       = imgui.ImVec4(0.60, 0.92, 1.00, 1.00)
    style.Colors[imgui.Col.PlotHistogram]          = imgui.ImVec4(0.34, 0.84, 0.73, 1.00)
    style.Colors[imgui.Col.PlotHistogramHovered]   = imgui.ImVec4(0.57, 0.95, 0.85, 1.00)
    style.Colors[imgui.Col.TextSelectedBg]         = imgui.ImVec4(0.30, 0.52, 0.82, 0.45)
    style.Colors[imgui.Col.ModalWindowDimBg]       = imgui.ImVec4(0.05, 0.06, 0.09, 0.72)
    style.Colors[imgui.Col.Tab]                    = imgui.ImVec4(0.14, 0.22, 0.34, 0.92)
    style.Colors[imgui.Col.TabHovered]             = imgui.ImVec4(0.24, 0.42, 0.64, 1.00)
    style.Colors[imgui.Col.TabActive]              = imgui.ImVec4(0.28, 0.52, 0.78, 1.00)
end

function tableToString(tbl, indent)
    local function formatTableKey(k)
        local defaultType = type(k);
        if (defaultType ~= 'string') then
            k = tostring(k);
        end
        local useSquareBrackets = k:find('^(%d+)') or k:find('(%p)') or k:find('\\') or k:find('%-');
        return useSquareBrackets == nil and k or ('[%s]'):format(defaultType == 'string' and "'" .. k .. "'" or k);
    end
    local str = { '{' };
    local indent = indent or 0;
    for k, v in pairs(tbl) do
        table.insert(str, ('%s%s = %s,'):format(string.rep("    ", indent + 1), formatTableKey(k), type(v) == "table" and tableToString(v, indent + 1) or (type(v) == 'string' and "'" .. v .. "'" or tostring(v))));
    end
    table.insert(str, string.rep('    ', indent) .. '}');
    return table.concat(str, '\n');
end

function comma_value(n)
	local left,num,right = string.match(n,'^([^%d]*%d)(%d*)(.-)$')
    return left..(num:reverse():gsub('(%d%d%d)','%1.'):reverse())..right
end

EXPORTS = {
   canToggle = function() return false end,
   getToggle = function() return false end,
   toggle = function() renderWindow[0] = not renderWindow[0] end
}