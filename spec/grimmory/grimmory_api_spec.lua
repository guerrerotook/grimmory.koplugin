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
local function make_sessions(count, matching_index)    local sessions = {}

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

-- Settings double that behaves like the real one: the refresh token is a
-- file, so it survives a process that never learned about a rotation.
local function make_settings(stored)
    stored = stored or {}

    return {
        refresh_token = stored.refresh_token or "",
        password = stored.password or "",
        base_uri = stored.base_uri or "https://grimmory.example",
        username = stored.username or "reader",
        extra_headers = {},

        getRefreshToken = function(self) return self.refresh_token end,
        setRefreshToken = function(self, token) self.refresh_token = token or "" end,
        clearRefreshToken = function(self) self.refresh_token = "" end,
        getPassword = function(self) return self.password end,
        clearPassword = function(self) self.password = "" end,
        getBaseUri = function(self) return self.base_uri end,
        getUsername = function(self) return self.username end,
        getExtraHeaders = function(self) return self.extra_headers end,
    }
end

---@param settings table
---@param responses table
local function make_auth_api(settings, responses)
    local api = GrimmoryAPI:new({ settings = settings })

    api.calls = {}

    api.rawRequest = function(self, method, uri, ...)
        table.insert(self.calls, uri)

        for pattern, response in pairs(responses) do
            if uri:match(pattern) then
                if type(response) == "function" then
                    return response(self, method, uri, ...)
                end

                return response[1], response[2], response[3]
            end
        end

        return true, 200, {}
    end

    return api
end

describe("GrimmoryAPI auth", function()
    it("keeps the stored token when the refresh fails for transport reasons", function()
        local settings = make_settings({ refresh_token = "stored-token" })

        local api = make_auth_api(settings, {
            ["/auth/refresh"] = { false, 0, "timeout" },
        })

        local ok = api:request("GET", "/api/v1/version")

        assert.is_false(ok)
        assert.are.equal("stored-token", settings.refresh_token)
        assert.is_false(api.requires_sign_in)
    end)

    it("keeps the stored token when the server is broken", function()
        local settings = make_settings({ refresh_token = "stored-token" })

        local api = make_auth_api(settings, {
            ["/auth/refresh"] = { false, 502, "bad gateway" },
        })

        api:request("GET", "/api/v1/version")

        assert.are.equal("stored-token", settings.refresh_token)
    end)

    it("signs out when the refresh token is actually rejected", function()
        local settings = make_settings({ refresh_token = "stored-token" })

        local api = make_auth_api(settings, {
            ["/auth/refresh"] = { false, 401, "unauthorized" },
            ["/auth/login"] = { false, 401, "unauthorized" },
        })

        api:request("GET", "/api/v1/version")

        assert.are.equal("", settings.refresh_token)
        assert.is_true(api.requires_sign_in)
    end)

    it("stores the rotated token on every refresh", function()
        local settings = make_settings({ refresh_token = "stored-token" })

        local api = make_auth_api(settings, {
            ["/auth/refresh"] = {
                true,
                200,
                { accessToken = "access", refreshToken = "rotated", expires = 7200 },
            },
        })

        api:request("GET", "/api/v1/version")

        assert.are.equal("rotated", settings.refresh_token)
    end)

    it("prefers the stored token over the one it cached before a fork", function()
        local settings = make_settings({ refresh_token = "stored-token" })

        local api = make_auth_api(settings, {
            ["/auth/refresh"] = function(_, _, _, data)
                if data.refreshToken ~= "rotated-elsewhere" then
                    return false, 401, "unauthorized"
                end

                return true, 200, { accessToken = "access", refreshToken = "newer", expires = 7200 }
            end,
        })

        -- Another process rotated the token after this one cached it.
        api.cached_refresh_token = "stale-token"
        settings.refresh_token = "rotated-elsewhere"

        local ok = api:request("GET", "/api/v1/version")

        assert.is_true(ok)
        assert.are.equal("newer", settings.refresh_token)
    end)

    it("reports that a sign in is needed when no credentials are left", function()
        local api = make_auth_api(make_settings(), {})

        assert.is_true(api:requiresSignIn())
    end)

    it("does not ask for a sign in while a token is stored", function()
        local api = make_auth_api(make_settings({ refresh_token = "stored-token" }), {})

        assert.is_false(api:requiresSignIn())
    end)

    it("does not ask for a sign in while a password is stored", function()
        local api = make_auth_api(make_settings({ password = "hunter2" }), {})

        assert.is_false(api:requiresSignIn())
    end)

    it("tests the stored session when no password is typed", function()
        local settings = make_settings({ refresh_token = "stored-token" })

        local api = make_auth_api(settings, {
            ["/auth/refresh"] = {
                true,
                200,
                { accessToken = "access", refreshToken = "rotated", expires = 7200 },
            },
            ["/api/v1/version"] = { true, 200, { current = "1.2.3" } },
        })

        local ok, version = api:testConnection("https://grimmory.example", "reader", "")

        assert.is_true(ok)
        assert.are.equal("1.2.3", version)
    end)

    it("asks for a password before testing a different server", function()
        local api = make_auth_api(make_settings({ refresh_token = "stored-token" }), {})

        local ok = api:testConnection("https://other.example", "reader", "")

        assert.is_false(ok)
        assert.are.equal(0, #api.calls)
    end)
end)
