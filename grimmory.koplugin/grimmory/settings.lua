local _ = require("gettext")

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local random = require("random")
local Device = require("device")

local GrimmoryLogger = require("grimmory/logger")

local logger = GrimmoryLogger:new()

-- Contains all of the stored settings and settings UI
-- elements to control Grimmory connections & sync.

---@class GrimmoryTargetShelf
---@field id number
---@field name string

---@class GrimmorySettingsData
---@field automatic_check_updates boolean
---@field base_uri string
---@field username string
---@field password string
---@field refresh_token string
---@field extra_headers { [string]: string }
---@field session_threshold_seconds number
---@field session_threshold_pages number
---@field sync_on_close_document boolean
---@field sync_on_suspend boolean
---@field sync_on_power_off boolean
---@field sync_enable_wifi boolean
---@field sync_periodically boolean
---@field sync_frequency number
---@field download_books boolean
---@field download_remove_books boolean
---@field sync_target_shelves GrimmoryTargetShelf[]
---@field sync_download_directory string
---@field sync_reading_sessions boolean
---@field sync_reading_progress boolean
---@field sync_annotations boolean
---@field sync_shelves_as_collections boolean
---@field sync_retain_empty_shelves boolean
---@field device_id string
---@field device_name string
---@field settings_version number

-- Bump when a setting is renamed or its meaning changes, and add the
-- matching step to `MIGRATIONS`.
local SETTINGS_VERSION = 1

---@type GrimmorySettingsData
local DEFAULTS = {
    automatic_check_updates = false,
    extra_headers = {},
    base_uri = "",
    username = "",
    password = "",
    refresh_token = "",
    session_threshold_seconds = 30,
    session_threshold_pages = 0,
    sync_on_close_document = false,
    sync_on_suspend = false,
    sync_on_power_off = false,
    sync_enable_wifi = false,
    sync_periodically = false,
    sync_frequency = 120,
    download_books = true,
    download_remove_books = false,
    sync_target_shelves = {},
    sync_download_directory = "grimmory/",
    sync_reading_sessions = true,
    sync_reading_progress = true,
    sync_annotations = true,
    sync_shelves_as_collections = true,
    sync_retain_empty_shelves = false,
    device_id = random.uuid(),
    device_name = Device.model,
    settings_version = SETTINGS_VERSION,
}

---@type (fun(data: GrimmorySettingsData): nil)[]
local MIGRATIONS = {
    -- 1: `sync_shelves` used to hold the "Download Books" switch, which
    --    read nothing like the "Sync Shelves" setting stored next to it
    --    in `sync_shelves_as_collections`.
    function(data)
        if data.sync_shelves ~= nil then
            if data.download_books == nil then
                data.download_books = data.sync_shelves
            end

            data.sync_shelves = nil
        end
    end,
}

---@class GrimmorySettings
---@field settings any Underlying lua settings interactions
---@field data GrimmorySettingsData In-memory setting values
local GrimmorySettings = {
    data = DEFAULTS,
}

local SETTING_KEY = "grimmory"

local function openSettingsHandle()
  local path = DataStorage:getSettingsDir() .. "/" .. SETTING_KEY .. ".lua"
  return LuaSettings:open(path)
end

function GrimmorySettings:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o:init()
    return o
end

function GrimmorySettings:init()
    self.settings = openSettingsHandle()
    local success, result = pcall(function()
        return self.settings:readSetting(SETTING_KEY, {}) or {}
    end)

    if success then
        self.data = result
        self:migrate()
    else
        logger:err("Error reading settings, using defaults", result)
        self.data = DEFAULTS
        self:write()
    end
end

-- Applies any migration that the stored settings have not seen yet, so
-- renamed keys keep their value instead of silently reverting.
function GrimmorySettings:migrate()
    local version = tonumber(self.data.settings_version) or 0

    if version >= SETTINGS_VERSION then
        return
    end

    for index = version + 1, SETTINGS_VERSION do
        local migration = MIGRATIONS[index]

        if migration ~= nil then
            local ok, message = pcall(migration, self.data)

            if not ok then
                logger:err("Failed to migrate settings to version", index, "-", message)
                return
            end

            logger:info("Migrated settings to version", index)
        end
    end

    self.data.settings_version = SETTINGS_VERSION
    self:write()
end

function GrimmorySettings:write()
    local success, error_msg = pcall(function()
        if not self.settings then
            logger:err("No settings object available for write")
            return false
        end

        logger:dbg("Saving settings data", self.data)
        self.settings:saveSetting(SETTING_KEY, self.data)
        self.settings:flush()
        logger:dbg("Settings saved and flushed successfully")
        return true
    end)

    if not success then
        logger:err("Error writing settings:", error_msg)
        return false
    end

    return true
end

function GrimmorySettings:getDeviceId()
    return self.data.device_id or DEFAULTS.device_id
end

function GrimmorySettings:setDeviceId(device_id)
    self.data.device_id = device_id
    self:write()
end

function GrimmorySettings:getDeviceName()
    return self.data.device_name or DEFAULTS.device_name
end

function GrimmorySettings:setDeviceName(device_name)
    self.data.device_name = device_name
    self:write()
end

function GrimmorySettings:getBaseUri()
    return self.data.base_uri or DEFAULTS.base_uri
end

function GrimmorySettings:setBaseUri(uri)
    uri = tostring(uri or ""):gsub("/*$", "")

    if uri ~= self:getBaseUri() then
        -- Tokens are only valid for the server that issued them.
        self:clearRefreshToken()
    end

    self.data.base_uri = uri
    self:write()
end

function GrimmorySettings:getExtraHeaders()
    return self.data.extra_headers or DEFAULTS.extra_headers
end

function GrimmorySettings:setExtraHeaders(headers)
    self.data.extra_headers = headers
    self:write()
end

function GrimmorySettings:getUsername()
    return self.data.username or DEFAULTS.username
end

function GrimmorySettings:setUsername(username)
    if username ~= self:getUsername() then
        -- Tokens belong to the user that signed in.
        self:clearRefreshToken()
    end

    self.data.username = username
    self:write()
end

function GrimmorySettings:getPassword()
    return self.data.password or DEFAULTS.password
end

-- The password is only needed to sign in once; afterwards the rotating
-- refresh token keeps the session alive, so the plaintext copy is
-- dropped rather than kept on disk.
function GrimmorySettings:clearPassword()
    if self:getPassword() == "" then
        return
    end

    self.data.password = ""
    self:write()
end

function GrimmorySettings:getRefreshToken()
    return self.data.refresh_token or DEFAULTS.refresh_token
end

---@param refresh_token string | nil
function GrimmorySettings:setRefreshToken(refresh_token)
    refresh_token = refresh_token or ""

    if refresh_token == self:getRefreshToken() then
        return
    end

    self.data.refresh_token = refresh_token
    self:write()
end

function GrimmorySettings:clearRefreshToken()
    self:setRefreshToken("")
end

function GrimmorySettings:getSessionThresholdSeconds()
    return self.data.session_threshold_seconds or DEFAULTS.session_threshold_seconds
end

---@param seconds integer
function GrimmorySettings:setSessionThresholdSeconds(seconds)
    self.data.session_threshold_seconds = seconds
    self:write()
end

function GrimmorySettings:getSessionThresholdPages()
    return self.data.session_threshold_pages or DEFAULTS.session_threshold_pages
end

---@param pages integer
function GrimmorySettings:setSessionThresholdPages(pages)
    self.data.session_threshold_pages = pages
    self:write()
end

function GrimmorySettings:getDownloadsBooks()
    if self.data.download_books == nil then
        return DEFAULTS.download_books
    end

    return self.data.download_books
end

function GrimmorySettings:toggleDownloadsBooks()
    self.data.download_books = not self:getDownloadsBooks()
    self:write()
end

function GrimmorySettings:getDownloadRemoveBooks()
    if self.data.download_remove_books == nil then
        return DEFAULTS.download_remove_books
    end

    return self.data.download_remove_books
end

function GrimmorySettings:toggleDownloadRemoveBooks()
    self.data.download_remove_books = not self:getDownloadRemoveBooks()
    self:write()
end

function GrimmorySettings:getDownloadDirectory()
    return self.data.sync_download_directory or DEFAULTS.sync_download_directory
end

---@param directory string
function GrimmorySettings:setDownloadDirectory(directory)
    self.data.sync_download_directory = directory
    self:write()
end

function GrimmorySettings:getDownloadTargetShelves()
    return self.data.sync_target_shelves or DEFAULTS.sync_target_shelves
end

---@param target_shelves GrimmoryTargetShelf[]
function GrimmorySettings:setDownloadTargetShelves(target_shelves)
    self.data.sync_target_shelves = target_shelves
    self:write()
end

function GrimmorySettings:getSyncReadingProgress()
    if self.data.sync_reading_progress == nil then
        return DEFAULTS.sync_reading_progress
    end

    return self.data.sync_reading_progress
end

function GrimmorySettings:toggleSyncReadingProgress()
    self.data.sync_reading_progress = not self:getSyncReadingProgress()
    self:write()
end

function GrimmorySettings:getSyncReadingSessions()
    if self.data.sync_reading_sessions == nil then
        return DEFAULTS.sync_reading_sessions
    end

    return self.data.sync_reading_sessions
end

function GrimmorySettings:toggleSyncReadingSessions()
    self.data.sync_reading_sessions = not self:getSyncReadingSessions()
    self:write()
end

function GrimmorySettings:getSyncAnnotations()
    if self.data.sync_annotations == nil then
        return DEFAULTS.sync_annotations
    end

    return self.data.sync_annotations
end

function GrimmorySettings:toggleSyncAnnotations()
    self.data.sync_annotations = not self:getSyncAnnotations()
    self:write()
end

function GrimmorySettings:getSyncShelves()
    if self.data.sync_shelves_as_collections == nil then
        return DEFAULTS.sync_shelves_as_collections
    end

    return self.data.sync_shelves_as_collections
end

function GrimmorySettings:toggleSyncShelves()
    self.data.sync_shelves_as_collections = not self:getSyncShelves()
    self:write()
end

function GrimmorySettings:getSyncRetainEmptyShelves()
    if self.data.sync_retain_empty_shelves == nil then
        return DEFAULTS.sync_retain_empty_shelves
    end

    return self.data.sync_retain_empty_shelves
end

function GrimmorySettings:toggleSyncRetainEmptyShelves()
    self.data.sync_retain_empty_shelves = not self:getSyncRetainEmptyShelves()
    self:write()
end

function GrimmorySettings:getSyncPeriodically()
    if self.data.sync_periodically == nil then
        return DEFAULTS.sync_periodically
    end

    return self.data.sync_periodically
end

function GrimmorySettings:toggleSyncPeriodically()
    self.data.sync_periodically = not self:getSyncPeriodically()
    self:write()
end

function GrimmorySettings:getSyncFrequency()
    return self.data.sync_frequency or DEFAULTS.sync_frequency
end

function GrimmorySettings:setSyncFrequency(seconds)
    self.data.sync_frequency = seconds
    self:write()
end

function GrimmorySettings:getSyncOnCloseDocument()
    if self.data.sync_on_close_document == nil then
        return DEFAULTS.sync_on_close_document
    end

    return self.data.sync_on_close_document
end

function GrimmorySettings:toggleSyncOnCloseDocument()
    self.data.sync_on_close_document = not self:getSyncOnCloseDocument()
    self:write()
end

function GrimmorySettings:getSyncOnSuspend()
    if self.data.sync_on_suspend == nil then
        return DEFAULTS.sync_on_suspend
    end

    return self.data.sync_on_suspend
end

function GrimmorySettings:toggleSyncOnSuspend()
    self.data.sync_on_suspend = not self:getSyncOnSuspend()
    self:write()
end

function GrimmorySettings:getSyncOnPowerOff()
    if self.data.sync_on_power_off == nil then
        return DEFAULTS.sync_on_power_off
    end

    return self.data.sync_on_power_off
end

function GrimmorySettings:toggleSyncOnPowerOff()
    self.data.sync_on_power_off = not self:getSyncOnPowerOff()
    self:write()
end

function GrimmorySettings:getSyncEnableWifi()
    if self.data.sync_enable_wifi == nil then
        return DEFAULTS.sync_enable_wifi
    end

    return self.data.sync_enable_wifi
end

function GrimmorySettings:toggleSyncEnableWifi()
    self.data.sync_enable_wifi = not self:getSyncEnableWifi()
    self:write()
end

return GrimmorySettings
