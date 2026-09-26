package.path = "grimmory.koplugin/?.lua;" .. package.path

local function make_executor(initial_wifi_on)
    local wifi_on = initial_wifi_on
    local turn_on_count = 0
    local turn_off_count = 0
    local standby_count = 0

    local network = {
        isWifiOn = function() return wifi_on end,
        isConnected = function() return wifi_on end,
        requestToTurnOnWifi = function()
            wifi_on = true
            turn_on_count = turn_on_count + 1
        end,
        turnOffWifi = function()
            wifi_on = false
            turn_off_count = turn_off_count + 1
        end,
    }
    local ui_manager = {
        scheduleIn = function(_, _, callback, iteration)
            callback(iteration)
        end,
        preventStandby = function() standby_count = standby_count + 1 end,
        allowStandby = function() standby_count = standby_count - 1 end,
    }

    local mocks = {
        ["ffi/util"] = {
            runInSubProcess = function() return 42, 1 end,
            getNonBlockingReadSize = function() return 0 end,
            isSubProcessDone = function() return true end,
        },
        ["ffi"] = {},
        ["json"] = {},
        ["device"] = { hasWifiToggle = function() return true end },
        ["ui/network/manager"] = network,
        ["ui/uimanager"] = ui_manager,
        ["grimmory/logger"] = {
            new = function()
                return {
                    dbg = function() end,
                    err = function() end,
                    warn = function() end,
                }
            end,
        },
    }
    local original = {}
    for name, mock in pairs(mocks) do
        original[name] = package.loaded[name]
        package.loaded[name] = mock
    end
    local executor_class = assert(loadfile("grimmory.koplugin/grimmory/executor.lua"))()
    for name in pairs(mocks) do
        package.loaded[name] = original[name]
    end

    local function state()
        return wifi_on, turn_on_count, turn_off_count, standby_count
    end

    return executor_class:new(), state
end

describe("GrimmoryExecutor Wi-Fi", function()
    it("keeps Wi-Fi on until the subprocess run returns", function()
        local executor, state = make_executor(false)

        executor:background(function(run)
            assert.is_true(select(1, state()))
            run(function() end, function() end)
            assert.is_true(select(1, state()))
        end, true)

        local wifi_on, turned_on, turned_off, standby = state()
        assert.is_false(wifi_on)
        assert.are.equal(1, turned_on)
        assert.are.equal(1, turned_off)
        assert.are.equal(0, standby)
    end)

    it("connects before invoking the sync callback and restores Wi-Fi afterward", function()
        local executor, state = make_executor(false)
        local callback_ran = false

        executor:background(function()
            callback_ran = true
            assert.is_true(select(1, state()))
        end, true)

        assert.is_true(callback_ran)
        local wifi_on, turned_on, turned_off, standby = state()
        assert.is_false(wifi_on)
        assert.are.equal(1, turned_on)
        assert.are.equal(1, turned_off)
        assert.are.equal(0, standby)
    end)

    it("leaves Wi-Fi on when it was already on", function()
        local executor, state = make_executor(true)

        executor:background(function()
            assert.is_true(select(1, state()))
        end, true)

        local wifi_on, turned_on, turned_off, standby = state()
        assert.is_true(wifi_on)
        assert.are.equal(0, turned_on)
        assert.are.equal(0, turned_off)
        assert.are.equal(0, standby)
    end)

    it("does not turn on Wi-Fi when the setting is disabled", function()
        local executor, state = make_executor(false)

        executor:background(function()
            assert.is_false(select(1, state()))
        end, false)

        local wifi_on, turned_on, turned_off, standby = state()
        assert.is_false(wifi_on)
        assert.are.equal(0, turned_on)
        assert.are.equal(0, turned_off)
        assert.are.equal(0, standby)
    end)

    it("restores Wi-Fi even if the sync callback fails", function()
        local executor, state = make_executor(false)

        executor:background(function()
            error("sync failure")
        end, true)

        local wifi_on, turned_on, turned_off, standby = state()
        assert.is_false(wifi_on)
        assert.are.equal(1, turned_on)
        assert.are.equal(1, turned_off)
        assert.are.equal(0, standby)
    end)
end)
