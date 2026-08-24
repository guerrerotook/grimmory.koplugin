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

package.preload["readcollection"] = function()
    return {
        coll = {},
        coll_settings = {},
    }
end

package.preload["ffi/MD5"] = function()
    return {
        sum = function() return "" end,
    }
end

package.preload["util"] = function()
    return {}
end

package.preload["gettext"] = function()
    return function(text) return text end
end

local GrimmorySynchronize = require("grimmory/synchronize")

---@return table
local function make_session(overrides)
    local session = {
        grimmory_id = 42,
        book_md5 = "md5",
        book_path = "/books/book.epub",
        start_time = 1000,
        end_time = 2000,
        start_page = 10,
        end_page = 20,
        page_count = 100,
        start_progress = 10,
        end_progress = 20,
        start_xpointer = nil,
        end_xpointer = nil,
    }

    for key, value in pairs(overrides or {}) do
        session[key] = value
    end

    return session
end

---@return GrimmorySynchronize
local function make_synchronize(sessions, api_overrides, settings_overrides)
    local settings = {
        getSyncReadingSessions = function() return true end,
        getSessionThresholdSeconds = function() return 30 end,
        getSessionThresholdPages = function() return 0 end,
    }

    for key, value in pairs(settings_overrides or {}) do
        settings[key] = value
    end

    local api = {
        recordSession = spy.new(function() return true, nil, 202 end),
        hasRecordedSession = spy.new(function() return true, false end),
    }

    for key, value in pairs(api_overrides or {}) do
        api[key] = value
    end

    local repository = {
        getPendingSessions = function() return sessions end,
        updateBookSyncTimestamp = spy.new(function() end),
    }

    local reading_annotations = {
        resolveXPointersToCFI = spy.new(function() return {} end),
    }

    return GrimmorySynchronize:new({
        settings = settings,
        api = api,
        repository = repository,
        reading_annotations = reading_annotations,
    })
end

---@return GrimmorySynchronize
local function make_annotation_synchronize(local_annotations, modified_ids, api_overrides, settings_overrides)
    local settings = {
        getSyncAnnotations = function() return true end,
    }

    for key, value in pairs(settings_overrides or {}) do
        settings[key] = value
    end

    local api = {
        createAnnotation = spy.new(function() return true, {} end),
        updateAnnotation = spy.new(function() return true end),
        deleteAnnotation = spy.new(function() return true end),
        getAnnotations = spy.new(function() return true, {} end),
    }

    for key, value in pairs(api_overrides or {}) do
        api[key] = value
    end

    local doc_metadata = {
        getModifiedGrimmoryAnnotations = function() return modified_ids or {} end,
        removeModifiedGrimmoryAnnotation = spy.new(function() end),
    }

    local reading_annotations = {
        getAnnotations = function() return local_annotations or {} end,
        applyAnnotations = spy.new(function() end),
    }

    return GrimmorySynchronize:new({
        settings = settings,
        api = api,
        doc_metadata = doc_metadata,
        reading_annotations = reading_annotations,
    })
end

describe("GrimmorySynchronize", function()
    describe("pushBookAnnotations", function()
        it("updates annotations that were modified locally", function()
            local synchronize = make_annotation_synchronize(
                { { id = 27, cfi = "cfi", text = "text", color = "#4ADE80", style = "underline", note = "note" } },
                { 27 },
                {
                    getAnnotations = spy.new(function()
                        return true, { { id = 27, cfi = "cfi", text = "text" } }
                    end),
                }
            )

            synchronize:pushBookAnnotations("/books/book.epub", 1)

            assert.spy(synchronize.api.updateAnnotation).was.called_with(
                synchronize.api, 27, "#4ADE80", "underline", "note"
            )
            assert.spy(synchronize.api.deleteAnnotation).was_not.called()
            assert.spy(synchronize.api.createAnnotation).was_not.called()
            assert.spy(synchronize.doc_metadata.removeModifiedGrimmoryAnnotation).was.called_with(
                synchronize.doc_metadata, "/books/book.epub", 27
            )
        end)

        it("keeps the modification flag when the update fails", function()
            local synchronize = make_annotation_synchronize(
                { { id = 27, cfi = "cfi", text = "text" } },
                { 27 },
                {
                    getAnnotations = spy.new(function()
                        return true, { { id = 27, cfi = "cfi", text = "text" } }
                    end),
                    updateAnnotation = spy.new(function() return false end),
                }
            )

            synchronize:pushBookAnnotations("/books/book.epub", 1)

            assert.spy(synchronize.doc_metadata.removeModifiedGrimmoryAnnotation).was_not.called()
        end)

        it("recreates annotations whose position changed, as the server cannot update it", function()
            local calls = {}

            local synchronize = make_annotation_synchronize(
                { { id = 27, cfi = "new-cfi", text = "text" } },
                { 27 },
                {
                    getAnnotations = spy.new(function()
                        return true, { { id = 27, cfi = "old-cfi", text = "text" } }
                    end),
                    createAnnotation = spy.new(function()
                        table.insert(calls, "create")
                        return true, {}
                    end),
                    deleteAnnotation = spy.new(function()
                        table.insert(calls, "delete")
                        return true
                    end),
                }
            )

            synchronize:pushBookAnnotations("/books/book.epub", 1)

            assert.spy(synchronize.api.updateAnnotation).was_not.called()
            assert.spy(synchronize.api.deleteAnnotation).was.called_with(synchronize.api, 27)
            assert.spy(synchronize.api.createAnnotation).was.called(1)
            assert.are.same({ "create", "delete" }, calls)
        end)

        it("keeps a moved annotation on the server when its replacement fails", function()
            local synchronize = make_annotation_synchronize(
                { { id = 27, cfi = "new-cfi", text = "text" } },
                { 27 },
                {
                    getAnnotations = spy.new(function()
                        return true, { { id = 27, cfi = "old-cfi", text = "text" } }
                    end),
                    createAnnotation = spy.new(function() return false, "boom" end),
                }
            )

            synchronize:pushBookAnnotations("/books/book.epub", 1)

            -- Dropping the old copy here would leave the highlight
            -- nowhere: gone from the server and dropped locally by the
            -- next pull.
            assert.spy(synchronize.api.deleteAnnotation).was_not.called()
            assert.spy(synchronize.doc_metadata.removeModifiedGrimmoryAnnotation).was_not.called()
        end)

        it("deletes annotations that were removed locally", function()
            local synchronize = make_annotation_synchronize({}, { 27 })

            synchronize:pushBookAnnotations("/books/book.epub", 1)

            assert.spy(synchronize.api.deleteAnnotation).was.called_with(synchronize.api, 27)
            assert.spy(synchronize.api.updateAnnotation).was_not.called()
            assert.spy(synchronize.doc_metadata.removeModifiedGrimmoryAnnotation).was.called_with(
                synchronize.doc_metadata, "/books/book.epub", 27
            )
        end)

        it("creates annotations that have no Grimmory ID", function()
            local synchronize = make_annotation_synchronize(
                { { cfi = "cfi", chapter = "chapter", text = "text", color = "#FFC107", style = "highlight" } }
            )

            synchronize:pushBookAnnotations("/books/book.epub", 7)

            assert.spy(synchronize.api.createAnnotation).was.called_with(
                synchronize.api, 7, "cfi", "chapter", "text", "#FFC107", "highlight", nil
            )
        end)
    end)

    describe("synchronizeBookAnnotations", function()
        it("pushes and pulls annotations", function()
            local synchronize = make_annotation_synchronize({})

            synchronize:synchronizeBookAnnotations("/books/book.epub", 7)

            assert.spy(synchronize.api.getAnnotations).was.called_with(synchronize.api, 7)
            assert.spy(synchronize.reading_annotations.applyAnnotations).was.called(1)
        end)

        it("does nothing when annotation sync is disabled", function()
            local synchronize = make_annotation_synchronize(
                {},
                { 27 },
                nil,
                { getSyncAnnotations = function() return false end }
            )

            synchronize:synchronizeBookAnnotations("/books/book.epub", 7)

            assert.spy(synchronize.api.getAnnotations).was_not.called()
            assert.spy(synchronize.api.deleteAnnotation).was_not.called()
            assert.spy(synchronize.reading_annotations.applyAnnotations).was_not.called()
        end)

        it("does nothing when the book is not associated with Grimmory", function()
            local synchronize = make_annotation_synchronize({})

            synchronize:synchronizeBookAnnotations("/books/book.epub", nil)

            assert.spy(synchronize.api.getAnnotations).was_not.called()
            assert.spy(synchronize.reading_annotations.applyAnnotations).was_not.called()
        end)
    end)

    describe("pushBookSessions", function()
        it("sends the book type derived from the book path", function()
            local synchronize = make_synchronize({
                make_session({ book_path = "/books/comic.cbz" })
            })

            synchronize:pushBookSessions(1, function() end)

            assert.spy(synchronize.api.recordSession).was.called_with(
                synchronize.api,
                42, 1000, 2000, 10, 20, "10", "20", "CBX"
            )
        end)

        it("omits the book type for unknown extensions", function()
            local synchronize = make_synchronize({
                make_session({ book_path = "/books/book.txt" })
            })

            synchronize:pushBookSessions(1, function() end)

            assert.spy(synchronize.api.recordSession).was.called_with(
                synchronize.api,
                42, 1000, 2000, 10, 20, "10", "20", nil
            )
        end)

        it("sends page numbers as locations for reflowable books", function()
            -- Grimmory only renders locations it recognises as pages, so
            -- a CFI would be stored and then shown as "-".
            local synchronize = make_synchronize({
                make_session({
                    start_xpointer = "/body/DocFragment[1]/p[1]",
                    end_xpointer = "/body/DocFragment[2]/p[3]",
                })
            })

            synchronize:pushBookSessions(1, function() end)

            assert.spy(synchronize.api.recordSession).was.called_with(
                synchronize.api,
                42, 1000, 2000, 10, 20, "10", "20", "EPUB"
            )
            assert.spy(synchronize.reading_annotations.resolveXPointersToCFI).was_not.called()
        end)

        it("omits locations when the pages are unknown", function()
            local synchronize = make_synchronize({
                make_session({ start_page = 0, end_page = 0 })
            })

            synchronize:pushBookSessions(1, function() end)

            assert.spy(synchronize.api.recordSession).was.called_with(
                synchronize.api,
                42, 1000, 2000, 10, 20, nil, nil, "EPUB"
            )
        end)

        it("advances the watermark for sessions below the time threshold", function()
            local synchronize = make_synchronize(
                { make_session({ start_time = 1000, end_time = 1010 }) },
                nil,
                { getSessionThresholdSeconds = function() return 30 end }
            )

            local states = {}
            synchronize:pushBookSessions(1, function(progress)
                table.insert(states, progress.state)
            end)

            assert.are.same({ "session-skip" }, states)
            assert.spy(synchronize.api.recordSession).was_not.called()
            assert.spy(synchronize.repository.updateBookSyncTimestamp).was.called_with(
                synchronize.repository, 1, "sessions", 1010
            )
        end)

        it("advances the watermark for sessions below the page threshold", function()
            local synchronize = make_synchronize(
                { make_session({ start_page = 10, end_page = 10 }) },
                nil,
                { getSessionThresholdPages = function() return 5 end }
            )

            local states = {}
            synchronize:pushBookSessions(1, function(progress)
                table.insert(states, progress.state)
            end)

            assert.are.same({ "session-skip" }, states)
            assert.spy(synchronize.api.recordSession).was_not.called()
            assert.spy(synchronize.repository.updateBookSyncTimestamp).was.called_with(
                synchronize.repository, 1, "sessions", 2000
            )
        end)

        it("treats an ambiguous failure as recorded when the session exists remotely", function()
            local synchronize = make_synchronize(
                { make_session() },
                {
                    recordSession = spy.new(function() return false, "timeout", 0 end),
                    hasRecordedSession = spy.new(function() return true, true end),
                }
            )

            local states = {}
            synchronize:pushBookSessions(1, function(progress)
                table.insert(states, progress.state)
            end)

            assert.are.same({ "session-recorded" }, states)
            assert.spy(synchronize.api.hasRecordedSession).was.called_with(
                synchronize.api, 42, 1000, 1000
            )
            assert.spy(synchronize.repository.updateBookSyncTimestamp).was.called_with(
                synchronize.repository, 1, "sessions", 2000
            )
        end)

        it("reports an error when an ambiguous failure was not recorded remotely", function()
            local synchronize = make_synchronize(
                { make_session() },
                {
                    recordSession = spy.new(function() return false, "timeout", 0 end),
                    hasRecordedSession = spy.new(function() return true, false end),
                }
            )

            local states = {}
            synchronize:pushBookSessions(1, function(progress)
                table.insert(states, progress.state)
            end)

            assert.are.same({ "session-error" }, states)
            assert.spy(synchronize.repository.updateBookSyncTimestamp).was_not.called()
        end)

        it("does not verify failures that returned a HTTP status", function()
            local synchronize = make_synchronize(
                { make_session() },
                {
                    recordSession = spy.new(function() return false, "bad request", 400 end),
                }
            )

            local states = {}
            synchronize:pushBookSessions(1, function(progress)
                table.insert(states, progress.state)
            end)

            assert.are.same({ "session-error" }, states)
            assert.spy(synchronize.api.hasRecordedSession).was_not.called()
        end)

        it("stops at the first failing session so it can be retried later", function()
            local synchronize = make_synchronize(
                {
                    make_session({ end_time = 2000 }),
                    make_session({ start_time = 3000, end_time = 4000 }),
                },
                {
                    recordSession = spy.new(function() return false, "bad request", 500 end),
                }
            )

            local states = {}
            synchronize:pushBookSessions(1, function(progress)
                table.insert(states, progress.state)
            end)

            assert.are.same({ "session-error" }, states)
            assert.spy(synchronize.api.recordSession).was.called(1)
        end)

        it("does nothing when session sync is disabled", function()
            local synchronize = make_synchronize(
                { make_session() },
                nil,
                { getSyncReadingSessions = function() return false end }
            )

            synchronize:pushBookSessions(1, function() end)

            assert.spy(synchronize.api.recordSession).was_not.called()
        end)
    end)
end)
