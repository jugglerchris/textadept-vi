-- Functions for manipulating views
local M = {}

local function unsplit_other(ts)
    if ts.vertical == nil then
        -- Ensure this view is focused (so we don't delete the focused view)
        for k,v in ipairs(_G._VIEWS) do
            if ts == v then
                ui.goto_view(k)
                break
            end
        end
        view.unsplit(ts)
    else
        unsplit_other(ts[1])
    end
end

local function close_siblings_of(v, ts)
    local v = view
    local ts = ts or ui.get_split_table()

    if ts.vertical == nil then
        -- This is just a view
        return false
    else
        if ts[1] == v then
            -- We can't quite just close the current view.  Pick the first
            -- on the other side.
            return unsplit_other(ts[2])
        else if ts[2] == v then
            return unsplit_other(ts[1])
        else
            return close_siblings_of(v, ts[1]) or close_siblings_of(v, ts[2])
        end end
    end
end
M.close_siblings_of = close_siblings_of

--
-- Find the view's parent split (in ui.get_split_table())
local function find_view_parent(v, ts)
    local ts = ts or ui.get_split_table()

    if ts[1] and ts[2] then
        -- This is a split
        if ts[1] == v or ts[2] == v then return ts end
        return find_view_parent(v, ts[1]) or find_view_parent(v, ts[2])
    else
        -- Must be a view - which can't be v's parent.
        return nil
    end
end

--
-- Find the view's parent's size (either vertical or horizontal, depending
-- on the split)
local function find_view_parent_size(v, split, width, height)
    local ts, w, h
    if split == nil then
        ts = ui.get_split_table()
        w = ui.size[1]
        h = ui.size[2] - 2  -- Top and bottom lines used by UI
    else
        ts = split
        w = width
        h = height
    end

    if ts[1] and ts[2] then
        -- This is a split.  Calculate the subsplit sizes
        local w1, h1, w2, h2 = w, h, w, h
        if ts.vertical then
            w1 = ts.size
            w2 = w - ts.size - 1
        else
            h1 = ts.size
            h2 = h - ts.size - 1
        end
        if ts[1] == v or ts[2] == v then
            -- This is v's parent
            if ts.vertical then return w else return h end
        else
            -- recurse
            return find_view_parent_size(v, ts[1], w1, h1) or
                   find_view_parent_size(v, ts[2], w2, h2)
        end
    else
        -- Must be a view - which can't be v's parent.
        return
    end
end
-- Grow (or shrink, with a negative increment) a view's size.
function M.grow_view(v, inc)
    local parent = find_view_parent(v)

    -- Do nothing if no split
    if perent == nil then return end

    local is_first = v == parent[1]
    local parent_size = find_view_parent_size(v)

    if not is_first then inc = -inc end
    local new_size = v.size + inc
    if new_size < 1 then new_size = 1 end
    if new_size >= (parent_size-1) then new_size = parent_size - 2 end
    v.size = new_size
end

return M