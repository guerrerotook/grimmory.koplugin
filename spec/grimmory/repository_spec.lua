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

package.preload["lua-ljsqlite3/init"] = function()
    return {
        open = function() error("database access is not expected") end
    }
end

package.preload["datastorage"] = function()
    return {
        getSettingsDir = function() return "/tmp" end
    }
end

package.preload["util"] = function()
    return {
        directoryExists = function() return false end,
        findFiles = function() end,
    }
end

package.preload["grimmory/plugin_metadata"] = function()
    return {
        getPluginPath = function() return "/tmp" end
    }
end

local GrimmoryLocalRepository = require("grimmory/repository")

describe("GrimmoryLocalRepository", function()
    describe("getSessionCutoff", function()
        it("excludes events that may still belong to an in-flight session", function()
            local now = 1786960000

            local cutoff = GrimmoryLocalRepository.getSessionCutoff(now)

            assert.is_true(cutoff < now)
            assert.are.equal(180, now - cutoff)
        end)

        it("defaults to the current time", function()
            local cutoff = GrimmoryLocalRepository.getSessionCutoff()

            assert.is_true(cutoff <= os.time())
            assert.is_true(cutoff >= os.time() - 181)
        end)
    end)
end)
