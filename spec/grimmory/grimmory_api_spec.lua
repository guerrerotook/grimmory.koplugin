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

package.preload["socket.http"] = function()
    return { request = function() end }
end

package.preload["ssl.https"] = function()
    return { request = function() end }
end

package.preload["json"] = function()
    return {
        encode = function() return "" end,
        decode = function() return {} end,
    }
end

package.preload["ltn12"] = function()
    return {
        source = { string = function() end },
        sink = { table = function() end },
    }
end

package.preload["luasettings"] = function()
    return { open = function() return {} end }
end

package.preload["datastorage"] = function()
    return { getSettingsDir = function() return "/tmp" end }
end

package.preload["pluginloader"] = function()
    return {
        _discover = function() return {} end
    }
end

package.preload["util"] = function()
    return {
        directoryExists = function() return false end,
    }
end

local GrimmoryAPI = require("grimmory/grimmory_api")

local START_TIME = 1700000000
local DURATION_SECONDS = 300

---@param pages table[]
local function make_api(pages)
    local api = GrimmoryAPI:new({
        settings = {
            getRefreshToken = function() return "" end,
        },
    })

    api.requests = {}

    api.request = function(self, method, path)
        table.insert(self.requests, { method = method, path = path })

        local page = tonumber(path:match("page=(%d+)"))
        local body = pages[page + 1]

        if body == nil then
            return false, 500, nil
        end

        return true, 200, body
    end

    return api
end

---@param count number
---@param matching_index number | nil
local function make_sessions(count, matching_index)
    local sessions = {}

    for index = 1, count do
        local matches = index == matching_index

        table.insert(sessions, {
            startTime = matches and "2023-11-14T22:13:20Z" or "2020-01-01T00:00:00Z",
            durationSeconds = matches and DURATION_SECONDS or 60,
        })
    end

    return sessions
end

describe("GrimmoryAPI", function()
    describe("hasRecordedSession", function()
        it("finds a session on the first page", function()
            local api = make_api({
                { content = make_sessions(3, 2) },
            })

            local ok, found = api:hasRecordedSession(1, START_TIME, DURATION_SECONDS)

            assert.is_true(ok)
            assert.is_true(found)
            assert.are.equal(1, #api.requests)
        end)

        it("reports a missing session once the pages run out", function()
            local api = make_api({
                { content = make_sessions(3) },
            })

            local ok, found = api:hasRecordedSession(1, START_TIME, DURATION_SECONDS)

            assert.is_true(ok)
            assert.is_false(found)
            assert.are.equal(1, #api.requests)
        end)

        it("keeps paging until the session is found", function()
            local api = make_api({
                { content = make_sessions(100) },
                { content = make_sessions(100) },
                { content = make_sessions(100, 42) },
            })

            local ok, found = api:hasRecordedSession(7, START_TIME, DURATION_SECONDS)

            assert.is_true(ok)
            assert.is_true(found)
            assert.are.equal(3, #api.requests)
            assert.are.equal(
                "/api/v1/reading-sessions/book/7?page=0&size=100",
                api.requests[1].path
            )
            assert.are.equal(
                "/api/v1/reading-sessions/book/7?page=2&size=100",
                api.requests[3].path
            )
        end)

        it("stops paging on a short page", function()
            local api = make_api({
                { content = make_sessions(100) },
                { content = make_sessions(4) },
            })

            local ok, found = api:hasRecordedSession(1, START_TIME, DURATION_SECONDS)

            assert.is_true(ok)
            assert.is_false(found)
            assert.are.equal(2, #api.requests)
        end)

        it("stops paging on the last reported page", function()
            local api = make_api({
                { content = make_sessions(100), page = { totalPages = 2 } },
                { content = make_sessions(100), page = { totalPages = 2 } },
                { content = make_sessions(100, 1) },
            })

            local ok, found = api:hasRecordedSession(1, START_TIME, DURATION_SECONDS)

            assert.is_true(ok)
            assert.is_false(found)
            assert.are.equal(2, #api.requests)
        end)

        it("reports a failure when a page cannot be read", function()
            local api = make_api({})

            local ok, found = api:hasRecordedSession(1, START_TIME, DURATION_SECONDS)

            assert.is_false(ok)
            assert.is_false(found)
        end)

        it("gives up rather than paging forever", function()
            local pages = setmetatable({}, {
                __index = function()
                    return { content = make_sessions(100) }
                end
            })

            local api = make_api(pages)

            local ok, found = api:hasRecordedSession(1, START_TIME, DURATION_SECONDS)

            assert.is_false(ok)
            assert.is_false(found)
            assert.are.equal(100, #api.requests)
        end)
    end)
end)
