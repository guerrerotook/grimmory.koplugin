local assert = require 'luassert'
local spy = require 'luassert.spy'

package.path = "grimmory.koplugin/?.lua;" .. package.path

local fake_logger = {
    err = spy.new(function() end),
    warn = spy.new(function() end),
    info = spy.new(function() end),
    dbg = spy.new(function() end),
}

package.preload["grimmory/logger"] = function()
    return {
        new = function()
            return fake_logger
        end
    }
end

package.preload["gettext"] = function()
    return function(text) return text end
end

package.preload["datastorage"] = function()
    return {
        getSettingsDir = function() return "/tmp" end
    }
end

local stored_settings = {}
local stored_session = {}

-- The refresh token is kept in its own file, so the stub has to keep the
-- two apart the way LuaSettings does.
local function store_for(path)
    if tostring(path):match("grimmory_session") then
        return stored_session
    end

    return stored_settings
end

package.preload["luasettings"] = function()
    return {
        open = function(_, path)
            local store = store_for(path)

            return {
                readSetting = function(_, key, default)
                    if store[key] == nil then
                        return default
                    end

                    return store[key]
                end,
                saveSetting = function(_, key, value)
                    store[key] = value
                end,
                delSetting = function(_, key)
                    store[key] = nil
                end,
                flush = function() end,
            }
        end
    }
end

package.preload["random"] = function()
    return {
        uuid = function() return "uuid" end
    }
end

package.preload["device"] = function()
    return {
        model = "Test Device"
    }
end

local GrimmorySettings = require("grimmory/settings")

---@return GrimmorySettings
local function make_settings(data)
    stored_settings = { grimmory = data }
    stored_session = {}

    return GrimmorySettings:new()
end

describe("GrimmorySettings", function()
    describe("migrate", function()
        it("moves the legacy download switch to its own key", function()
            local settings = make_settings({ sync_shelves = false })

            assert.is_false(settings:getDownloadsBooks())
            assert.is_nil(settings.data.sync_shelves)
            assert.is_false(settings.data.download_books)
        end)

        it("keeps the shelf collection setting untouched", function()
            local settings = make_settings({
                sync_shelves = false,
                sync_shelves_as_collections = true,
            })

            assert.is_false(settings:getDownloadsBooks())
            assert.is_true(settings:getSyncShelves())
        end)

        it("does not run again once the settings are migrated", function()
            local settings = make_settings({ sync_shelves = false })

            settings:toggleDownloadsBooks()
            assert.is_true(settings:getDownloadsBooks())

            local reloaded = GrimmorySettings:new()

            assert.is_true(reloaded:getDownloadsBooks())
        end)

        it("defaults to downloading books when nothing was stored", function()
            local settings = make_settings({})

            assert.is_true(settings:getDownloadsBooks())
        end)
    end)

    describe("credentials", function()
        it("clears the password once it is no longer needed", function()
            local settings = make_settings({ password = "hunter2" })

            assert.are.equal("hunter2", settings:getPassword())

            settings:clearPassword()

            assert.are.equal("", settings:getPassword())
        end)

        it("stores and clears the refresh token", function()
            local settings = make_settings({})

            settings:setRefreshToken("token")
            assert.are.equal("token", settings:getRefreshToken())

            settings:clearRefreshToken()
            assert.are.equal("", settings:getRefreshToken())
        end)

        it("drops the refresh token when the server changes", function()
            local settings = make_settings({ base_uri = "https://one.example" })

            settings:setRefreshToken("token")
            settings:setBaseUri("https://two.example")

            assert.are.equal("", settings:getRefreshToken())
        end)

        it("keeps the refresh token when the server is unchanged", function()
            local settings = make_settings({ base_uri = "https://one.example" })

            settings:setRefreshToken("token")
            settings:setBaseUri("https://one.example")

            assert.are.equal("token", settings:getRefreshToken())
        end)

        it("drops the refresh token when the user changes", function()
            local settings = make_settings({ username = "reader" })

            settings:setRefreshToken("token")
            settings:setUsername("someone-else")

            assert.are.equal("", settings:getRefreshToken())
        end)
    end)
end)
