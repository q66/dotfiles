-- theme and font
ui.set_theme("light", {
    font = "M+ 1m medium", fontsize = 9
})

-- disable tab bar
ui.tabs = false

-- default settings for all lexers: 4 space indent, no tabs, visible trailing
-- whitespace, visible guide on the right to be careful about 79 columns
local set_bufcfg = function(buf)
    buf.tab_width = 4
    buf.use_tabs = false
    buf.view_ws = buf.WS_VISIBLEONLYININDENT
    buf.edge_mode = buf.EDGE_LINE
    buf.edge_column = 79
end
events.connect(events.LEXER_LOADED, function()
    for i = 1, #_BUFFERS do
        set_bufcfg(_BUFFERS[i])
    end
end)

-- open terminal here on ctrl+shift+T
keys.cT = function()
    local path = "~"
    if buffer.filename then
        path = buffer.filename:match(".+/")
    end
    io.popen("sakura --working-directory=\"" .. path .. "\" &")
end

-- menubar/context menu bufferlist
--
-- displays a dropdown menu thingy to switch buffers as the last item of
-- menubar + also the same thing in right-click context menu of each view
-- also displays an asterisk on the left of filename when the buffer is
-- currently modified, and keeps track of buffers being opened, switched etc.
events.connect(events.INITIALIZED, function()
    -- in INITIALIZED event, so that menus are ready for use
    -- also allows us to properly repopulate the bufferlist when required
    -- without hooking an explicit reset callback

    local buflist = {}
    local bufmap = {}
    local curmod = {}
    local mb_idx, ctxm_idx
    -- used for FILE_OPENED to know what to modify
    local lastbuf

    -- get the location of the current buffer and the filename, with fallbacks
    local get_bfname = function(fname)
        if not fname then
            return lfs.currentdir() .. "/", "Untitled"
        end
        return fname:match(".+/"), fname:match(".+/(.+)")
    end

    -- get the title of the current buffer in menu
    local get_buftitle = function(buf)
        local fpath, fname = get_bfname(
            (type(buf) == "string") and buf or buf.filename
        )
        -- menus don't show single underscores
        return ("%s (%s)"):format(fname, fpath):gsub("_", "__")
    end

    -- refresh the buffer list
    local refresh_menu = function()
        local mbar, ctxm = textadept.menu.menubar, textadept.menu.context_menu
        if not mb_idx then
            mb_idx = #mbar + 1
        end
        if not ctxm_idx then
            ctxm_idx = #ctxm + 1
        end
        buflist.title = get_buftitle(view.buffer)
        -- let's have the list nicely in order to make it easy to search
        -- but this makes it harder with FILE_OPENED event as we need to
        -- keep track of last opened buffer (to know which one the file
        -- spawns in)
        table.sort(buflist, function(a, b)
            return a[1] < b[1]
        end)
        -- add star before modified stuff
        local oldtitle = buflist.title
        if view.buffer.modify then
            buflist.title = "* " .. buflist.title
        end
        curmod = {}
        for i = 1, #_BUFFERS do
            local buf = _BUFFERS[i]
            local buftbl = bufmap[buf]
            if buf.modify and buftbl then
                curmod[buf] = buf
                buftbl[1] = "* " .. buftbl[1]
            end
        end
        -- update menus
        mbar[mb_idx] = buflist
        ctxm[ctxm_idx] = buflist
        -- restore previous titles
        buflist.title = oldtitle
        for i, buf in pairs(curmod) do
            bufmap[buf][1] = bufmap[buf][1]:sub(3)
        end
    end

    -- add new buffer to the list
    local add_buffer = function(buf)
        local buft = get_buftitle(buf)
        buflist[#buflist + 1] = { buft, function()
            view:goto_buffer(buf)
        end }
        bufmap[buf] = buflist[#buflist]
    end

    -- this is before filename is actually properly set
    events.connect(events.BUFFER_NEW, function()
        add_buffer(_BUFFERS[#_BUFFERS])
        lastbuf = buflist[#buflist]
        refresh_menu()
    end)

    -- after opening in a new buffer, so set filename and refresh
    events.connect(events.FILE_OPENED, function(fname)
        if not fname or not lastbuf then
            return
        end
        lastbuf[1] = get_buftitle(fname)
        lastbuf = nil
        refresh_menu()
    end)

    -- happens after saving a file
    events.connect(events.FILE_AFTER_SAVE, function(fname, saved_as)
        if saved_as then
            -- some filename changed... just refresh the entire thing
            buflist, bufmap, curmod = {}, {}, {}
            for i = 1, #_BUFFERS do
                add_buffer(_BUFFERS[i])
            end
        end
        refresh_menu()
    end)

    events.connect(events.BUFFER_DELETED, function()
        -- we have no way of knowing which buffer exactly was deleted
        -- oh well, we just refresh the buffer list entierly, no big deal
        buflist, bufmap, curmod = {}, {}, {}
        for i = 1, #_BUFFERS do
            add_buffer(_BUFFERS[i])
        end
        refresh_menu()
    end)

    -- happens when we switch to another view
    events.connect(events.VIEW_AFTER_SWITCH, function()
        refresh_menu()
    end)

    -- happens when we switch to another buffer in a view
    events.connect(events.BUFFER_AFTER_SWITCH, function()
        refresh_menu()
    end)

    events.connect(events.UPDATE_UI, function(updated)
        if updated ~= buffer.UPDATE_CONTENT then
            return
        end
        for i = 1, #_BUFFERS do
            local buf = _BUFFERS[i]
            -- if any buffer previously modified is no more modfied
            -- or vice versa, just refresh the entire thing and return,
            -- could perhaps just refresh without checking but that could
            -- get expensive
            if buf.modify then
                if not curmod[buf] then
                    refresh_menu()
                    return
                end
            else
                if curmod[buf] then
                    refresh_menu()
                    return
                end
            end
        end
    end)

    -- populate initial buffer list
    for i = 1, #_BUFFERS do
        add_buffer(_BUFFERS[i])
    end
    refresh_menu()
end)
