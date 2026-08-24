local assert = require 'luassert'

package.path = "grimmory.koplugin/?.lua;" .. package.path

local GrimmoryDateTime = require("grimmory/datetime")

describe("GrimmoryDateTime", function()
    describe("fromUTC", function()
        it("round trips a UTC timestamp regardless of the device timezone", function()
            local timestamp = 1710000000

            assert.are.equal(
                timestamp,
                GrimmoryDateTime.fromUTC(os.date("!*t", timestamp))
            )
        end)

        it("reads the fields as UTC and not as local time", function()
            local timestamp = GrimmoryDateTime.fromUTC({
                year = 2024,
                month = 3,
                day = 9,
                hour = 16,
                min = 0,
                sec = 0,
            })

            assert.are.equal("2024-03-09T16:00:00Z", os.date("!%Y-%m-%dT%H:%M:%SZ", timestamp))
        end)

        it("accepts fields captured as strings", function()
            assert.are.equal(
                GrimmoryDateTime.fromUTC({
                    year = 2024,
                    month = 3,
                    day = 9,
                    hour = 16,
                    min = 0,
                    sec = 0,
                }),
                GrimmoryDateTime.fromUTC({
                    year = "2024",
                    month = "03",
                    day = "09",
                    hour = "16",
                    min = "00",
                    sec = "00",
                })
            )
        end)

        it("returns nil for incomplete fields", function()
            assert.is_nil(GrimmoryDateTime.fromUTC({ year = 2024, month = 3 }))
            assert.is_nil(GrimmoryDateTime.fromUTC({}))
        end)

        it("stays exact around daylight saving changes", function()
            -- Absolute instants, so these hold in any device timezone.
            local instants = {
                1710046800, -- an hour before the US spring forward
                1710050400,
                1710054000, -- the US spring forward
                1730610000, -- an hour before the US fall back
                1730613600, -- the US fall back
                1711846800, -- the EU spring forward
                1729984800, -- the EU fall back
            }

            for _, instant in ipairs(instants) do
                assert.are.equal(
                    instant,
                    GrimmoryDateTime.fromUTC(os.date("!*t", instant)),
                    "failed for " .. os.date("!%Y-%m-%dT%H:%M:%SZ", instant)
                )
            end
        end)
    end)

    describe("fromLocal", function()
        it("round trips a local timestamp", function()
            local timestamp = 1710000000

            assert.are.equal(
                timestamp,
                GrimmoryDateTime.fromLocal(os.date("*t", timestamp))
            )
        end)

        it("returns nil for incomplete fields", function()
            assert.is_nil(GrimmoryDateTime.fromLocal({ hour = 12 }))
        end)
    end)
end)
