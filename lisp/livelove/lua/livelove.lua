-- Inspired by `lurker`

local function lua_encode(...)
    -- Forward declaration for mutual recursion
    local encode_value

    local function encode_string(str)
        -- Handle special characters and escape sequences for Lua
        local escaped = str:gsub('[%z\1-\31\\\']', function(c)
            local special = {
                ["\\"] = "\\\\",
                ["'"] = "\\'",
                ["\b"] = "\\b",
                ["\f"] = "\\f",
                ["\n"] = "\\n",
                ["\r"] = "\\r",
                ["\t"] = "\\t",
            }
            return special[c] or string.format("\\%03d", c:byte())
        end)
        return "'" .. escaped .. "'"
    end

    local function encode_table(t)
        local parts = {}
        local is_array = true
        local n = 0

        -- Check if it's an array
        for k in pairs(t) do
            if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
                is_array = false
                break
            end
            n = math.max(n, k)
        end

        if is_array then
            for i = 1, n do
                parts[i] = encode_value(t[i])
            end
            return "{" .. table.concat(parts, ", ") .. "}"
        else
            for k, v in pairs(t) do
                local key
                if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                    -- If key is a valid Lua identifier, use table.key syntax
                    key = k
                else
                    -- Otherwise use table['key'] syntax
                    key = "[" .. encode_value(k) .. "]"
                end
                table.insert(parts, key .. " = " .. encode_value(v))
            end
            return "{" .. table.concat(parts, ", ") .. "}"
        end
    end

    encode_value = function(val)
        local val_type = type(val)

        if val == nil then
            return "nil"
        elseif val_type == "string" then
            return encode_string(val)
        elseif val_type == "number" then
            if val ~= val then -- NaN
                return "0/0" -- Lua's way of representing NaN
            elseif val == math.huge then
                return "math.huge"
            elseif val == -math.huge then
                return "-math.huge"
            else
                return tostring(val)
            end
        elseif val_type == "boolean" then
            return tostring(val)
        elseif val_type == "table" then
            return encode_table(val)
        else
            error("Cannot encode value of type " .. val_type)
        end
    end

    local args = {...}
    if #args == 1 then
        return encode_value(args[1])
    else
        local encoded = {}
        for i, arg in ipairs(args) do
            encoded[i] = encode_value(arg)
        end
        return table.concat(encoded, ", ")
    end
end

local function json_encode(val)
  -- Forward declaration for mutual recursion
  local encode_value

    local function to_string_number(num)
        if num == math.floor(num) then
            return tostring(num)
        end

        -- Format with 3 decimal places
        local str = string.format("%.3f", num)

        -- Remove trailing zeros after decimal point
        str = string.gsub(str, "%.?0+$", "")

        return str
    end

  local function encode_string(str)
    -- Handle special characters and escape sequences
    local escaped = str:gsub('[%z\1-\31\\"/]', function(c)
      local special = {
        ['"'] = '\\"',
        ["\\"] = "\\\\",
        ["/"] = "\\/",
        ["\b"] = "\\b",
        ["\f"] = "\\f",
        ["\n"] = "\\n",
        ["\r"] = "\\r",
        ["\t"] = "\\t",
      }
      return special[c] or string.format("\\u%04x", c:byte())
    end)
    return '"' .. escaped .. '"'
  end

  local function encode_table(t)
    local parts = {}
    local is_array = true
    local n = 0

    -- Check if it's an array
    for k in pairs(t) do
      if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
        is_array = false
        break
      end
      n = math.max(n, k)
    end

    if is_array then
      for i = 1, n do
        parts[i] = encode_value(t[i] or nil)
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      for k, v in pairs(t) do
        if type(k) == "string" then
          table.insert(parts, encode_string(k) .. ":" .. encode_value(v))
        end
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end

  encode_value = function(val)
    local val_type = type(val)

    if val == nil then
      return "null"
    elseif val_type == "string" then
      return encode_string(val)
    elseif val_type == "number" then
      if val ~= val then -- NaN
        return "null"
      else
        return to_string_number(val)
      end
    elseif val_type == "boolean" then
      return tostring(val)
    elseif val_type == "table" then
      return encode_table(val)
    else
      return "<unknown>"
    end
  end

  return encode_value(val)
end

-- From `lume`
local function format(str, vars)
  if not vars then
    return str
  end
  local f = function(x)
    return tostring(vars[x] or vars[tonumber(x)] or "{" .. x .. "}")
  end
  return (str:gsub("{(.-)}", f))
end

-- From `lume`
local function trim(str)
  return str:match("^[%s]*(.-)[%s]*$")
end

local function values_equal(v1, v2)
  if type(v1) ~= type(v2) then
    return false
  end

  if type(v1) == "table" then
    for k, v in pairs(v1) do
      if not values_equal(v, v2[k]) then
        return false
      end
    end
    for k, v in pairs(v2) do
      if v1[k] == nil then
        return false
      end
    end
    return true
  end

  return v1 == v2
end

-- Helpers Above

local livelove = { _version = "1.0.0" }
livelove.live_vars = true

local lovecallbacknames = {
  "update",
  "load",
  "draw",
  "mousepressed",
  "mousereleased",
  "keypressed",
  "keyreleased",
  "focus",
  "quit",
}

local debug_bridge = {
  documents = {}
}

assets = {}

function livelove.asset(path, on_update)
  if assets[path] == nil then
    assets[path] = {
      value = love.filesystem.read(path),
      on_update = on_update
    }
  else
    -- always update
    assets[path].on_update = on_update
  end
  return assets[path]
end

function livelove.init()
  livelove.print("Initializing livelove")
  livelove.preswap = function() end
  livelove.postswap = function() end
  livelove.initialized = true
  livelove.funcwrappers = {}
  livelove.lovefuncs = {}
  livelove.state = "init"

  livelove.pending_reload = nil
  livelove.channel = love.thread.newChannel()
  livelove.local_channel = love.thread.newChannel()
  livelove.thread = love.thread.newThread([[
    local socket = require("socket")

    local channel, local_channel = ...

    local client = socket.tcp()
    client:connect("127.0.0.1", 12345)
    client:settimeout(0)
    local buffer = ""

    while true do
      -- Check for outgoing messages from the main thread
      local message = local_channel:pop()
      if message then
        client:send(message)
      end

      while true do
        local data = client:receive("*l")
        if not data then break end

        buffer = buffer .. data .. "\n"

        local endpos = buffer:find("\n%-%-%-END%-%-%-\n")
        if endpos then
          local frame = buffer:sub(1, endpos-1)
          buffer = buffer:sub(endpos + 10)
          channel:push(frame)
        end
      end

      socket.sleep(0.001) -- Tiny sleep to prevent tight loop
    end
  ]])

  livelove.thread:start(livelove.channel, livelove.local_channel)

  return livelove
end

function livelove.onerror(e, nostacktrace)
  local stacktrace = nostacktrace and "" or trim((debug.traceback("", 2):gsub("\t", "")))
  local msg = format("{1}\n\n{2}", { e, stacktrace })
  livelove.print("ERROR: {1}", { msg })
end

function livelove.exitinitstate()
  livelove.state = "normal"
  if livelove.initialized then
    livelove.initwrappers()
  end
end

local function get_path_suffixes(full_path)
    local suffixes = {}
    local parts = {}

    -- Split path by forward and backward slashes
    for part in full_path:gmatch("[^/\\]+") do
        table.insert(parts, part)
    end

    -- Build suffixes from shortest to longest
    for i = #parts, 1, -1 do
        local suffix = table.concat(parts, "/", i)
        table.insert(suffixes, suffix)
    end

    return suffixes
end

-- Updated asset checking function
local function try_update_asset(full_path, content)
    local suffixes = get_path_suffixes(full_path)

    for _, suffix in ipairs(suffixes) do
        if assets[suffix] ~= nil then
            assets[suffix].value = content
            assets[suffix].on_update()
            livelove.print("Swapped Asset: {1}", {suffix})
            return true -- Asset was found and updated
        end
    end

    return false -- No matching asset was found
end

-- Evaluate CODE against the globals in a persistent session env and reply
-- with EVAL_RESULT. Tries an expression first, then a statement.
livelove.eval_env = nil
function livelove.handle_eval(code)
    livelove.eval_env = livelove.eval_env or setmetatable({}, { __index = _G })
    local fn, err = load("return " .. code, "livelove-eval", "t", livelove.eval_env)
    if not fn then
        fn, err = load(code, "livelove-eval", "t", livelove.eval_env)
    end
    local reply
    if not fn then
        reply = json_encode({ error = err })
    else
        local ok, result = pcall(fn)
        if not ok then
            reply = json_encode({ error = tostring(result) })
        else
            local enc_ok, encoded = pcall(lua_encode, result)
            reply = json_encode({ value = enc_ok and encoded or tostring(result) })
        end
    end
    livelove.local_channel:push("EVAL_RESULT\n" .. reply .. "\n---END---\n")
end

-- Handle a GAME_CONTROL command sent from the editor.
function livelove.handle_control(cmd)
    if cmd == "live_vars_on" then
        livelove.live_vars = true
    elseif cmd == "live_vars_off" then
        livelove.live_vars = false
    else
        livelove.print("Unknown GAME_CONTROL: {1}", { cmd })
    end
end

function livelove.instantupdate()
    if livelove.state == "init" then
        livelove.exitinitstate()
    end

    -- Process messages from channel
    while true do
        local message = livelove.channel:pop()
        if not message then break end

        message = trim(message)
        local path, content = message:match("([^\n]*)\n(.+)")

        if path then
            if path == "EVAL" then
                livelove.handle_eval(content)
            elseif path == "GAME_CONTROL" then
                livelove.handle_control(content)
            elseif path:match("ASSET_FILE_UPDATE:(.+)") then
                path = path:match("ASSET_FILE_UPDATE:(.+)")
                try_update_asset(path, content)
            else
                path = path:match("FILE_UPDATE:(.+)")
                if path and content then
                    debug_bridge.documents[path] = { line_values = {}, line_changed = {}, var_lookup = {} }
                    livelove.pending_reload = { path = path, content = content }
                end
            end
        end
    end

  if livelove.live_vars then
    local updates = {}
    local didUpdate = false

    for uri, info in pairs(debug_bridge.documents) do
      for i, has_changed in pairs(info.line_changed) do
        if has_changed == true then
          info.line_changed[i] = nil
          local obj = info.line_values[i]

          local function process_table(obj, prefix, scope_vars)
            for var_name, value in pairs(obj) do
              local full_name = prefix and (prefix .. "." .. var_name) or var_name

              if type(value) == "table" then
                -- Recurse into nested tables
                process_table(value, full_name, scope_vars)
              else
                -- Add non-table values to the scope
                if type(value) == "string" then
                  value = value:sub(0, 255)
                end
                local encoded_value = json_encode(value)
                if encoded_value ~= "<unknown>" then
                  scope_vars[full_name] = encoded_value
                  didUpdate = true
                end
              end
            end
          end

          -- Process all variables in the current scope
          if obj and obj.values then
            for var_name, value in pairs(obj.values) do
              if type(value) == "table" then
                process_table(value, var_name, updates)
              else
                if type(value) == "string" then
                  value = value:sub(0, 255)
                end
                local encoded_value = json_encode(value)
                if encoded_value ~= "<unknown>" then
                  updates[var_name] = encoded_value
                  didUpdate = true
                end
              end
            end
          end
        end
      end

      -- Send the changed variables if there were any.
      if didUpdate then
        local msg = string.format(
          "VARS_UPDATE\n%s\n---END---\n",
          json_encode({ updates = { { variables = updates } }, uri = uri })
        )
        livelove.local_channel:push(msg)
      end
    end
  end

end

function livelove.modname(f)
  return (f:gsub("%.lua$", ""):gsub("[/\\]", "."))
end

livelove.prev_proposed_content = nil
livelove.prev_proposed_path = nil
livelove.proposed_content = nil
livelove.proposed_path = nil
livelove.had_draw_error = false
livelove.last_working_files = {}
livelove.healing = false

function livelove.wrap_with_timeout(func, timeout)
    return function(...)
        local args = {...}
        local co = coroutine.create(function()
            return func(unpack(args))
        end)

        local start_time = love.timer.getTime()
        local ok, result = coroutine.resume(co)

        while coroutine.status(co) ~= "dead" do
            if love.timer.getTime() - start_time > timeout then
                error("Function timed out after " .. timeout .. " seconds")
            end
            ok, result = coroutine.resume(co)
        end

        if not ok then
            error(result)
        end
        return result
    end
end

function livelove.initwrappers()
  for _, v in pairs(lovecallbacknames) do
    if v == "draw" then
      livelove.funcwrappers["draw"] = function(...)
        local args = { ... }

        if livelove.healing then
          return
        end

        local had_error = livelove.had_draw_error

        -- Save current canvas state
        local currentCanvas = love.graphics.getCanvas()

        -- If we had an error, skip draw until next reload
        if livelove.had_draw_error then
          if livelove.pending_reload then
            local ok, err = pcall(function()
              livelove.postdraw()
            end)
            love["draw"](unpack(args))
            if ok then
              livelove.had_draw_error = false
            end
            return ok, err
          end
        end

        local ok, err = xpcall(function()
          return livelove.wrap_with_timeout(
            function()
              return livelove.lovefuncs[v] and livelove.lovefuncs[v](unpack(args))
            end,
            1.0  -- 1 second timeout
          )()
        end, function(err)
          livelove.had_draw_error = true

          -- If it's a shader error, set the flag and clear everything
          if err:match("Shader") then
            collectgarbage("collect")
          end

          -- Ensure canvas is reset
          love.graphics.setCanvas(currentCanvas)

          return err
        end)

        if err then
          livelove.pending_reload = nil
          livelove.onerror(err)

          if livelove.last_working_files[livelove.prev_proposed_path] then
            local path, content = livelove.prev_proposed_path, livelove.last_working_files[livelove.prev_proposed_path]
            livelove.proposed_content = content
            livelove.prev_proposed_content = content
            livelove.healing = true
            local ok, err = pcall(function()
              livelove._postdraw(path, content)
            end)
            if ok then
              livelove.had_draw_error = false
              livelove.healing = false
            end
            -- healing? dont get in infinite loops
            love["draw"](unpack(args))
            return ok, err
          end
        end

        -- Executes once before the actual error?
        if ok and not livelove.had_draw_error and not had_error then
          -- Ensure canvas is reset after successful draw
          love.graphics.setCanvas(currentCanvas)
          if livelove.proposed_path then
            -- this could be smarter - have a "dirty" lookup if it gets modified
            local p = livelove.prev_proposed_path or livelove.proposed_path
            local c = livelove.prev_proposed_content or livelove.proposed_content
            livelove.last_working_files[p] = c
          end
        end

        return ok, err
      end
    elseif v == "quit" then
      -- Special handling for quit to ensure it always works
      livelove.funcwrappers["quit"] = function(...)
        local args = { ... }
        if livelove.lovefuncs["quit"] then
          return livelove.lovefuncs["quit"](unpack(args))
        end
        return false
      end
    else
      livelove.funcwrappers[v] = function(...)
        local args = { ... }
        return xpcall(function()
          return livelove.wrap_with_timeout(
            function()
              return livelove.lovefuncs[v] and livelove.lovefuncs[v](unpack(args))
            end,
            1.0  -- 1 second timeout
          )()
        end, livelove.onerror)
      end
    end
    livelove.lovefuncs[v] = love[v]
  end
  livelove.updatewrappers()
end

function livelove.hotswapinstant(f, content)
  if f:find("livelove.lua") or f:find(".vscode") then
    return
  end

  livelove.print("Hotswapping '{1}'...", { f })

  if livelove.preswap(f) then
    livelove.print("Hotswap of '{1}' aborted by preswap", { f })
    return
  end

  local modname = livelove.modname(f)
  local chunk, err = load(content, modname)
  if not chunk then
    livelove.print("Failed to swap '{1}' : {2}", { f, err })
        io.write(content)
        io.flush() -- Make sure it's all sent to stdout
    if livelove.initialized then
      livelove.onerror(err, true)
      return
    end
  else
    local ok, err = pcall(chunk)
    if ok then
      -- Mark content as proposed - will be confirmed as good after successful draw
      livelove.prev_proposed_path = livelove.proposed_path
      livelove.proposed_path = f
      livelove.prev_proposed_content = livelove.proposed_content
      livelove.proposed_content = content
      package.loaded[modname] = _G[modname] or true
      if livelove.pending_reload ~= nil then
        return
      end

      livelove.print("Swapped '{1}'", { f })
    else
      livelove.print("Failed to swap '{1}' : {2}", { f, err })
      if livelove.initialized then
        livelove.onerror(err, true)
        return
      end
    end
  end

  livelove.postswap(f)
  if livelove.initialized then
    livelove.updatewrappers()
  end
end

function livelove.updatewrappers()
  for _, v in pairs(lovecallbacknames) do
    -- don't cause infinite loop if solving error
    if v ~= "draw" or not livelove.had_draw_error then
      if love[v] ~= livelove.funcwrappers[v] then
        livelove.lovefuncs[v] = love[v]
        love[v] = livelove.funcwrappers[v]
      end
    end
  end
end

function livelove.reset()
  -- Force end any active canvas
  love.graphics.setCanvas()
  love.graphics.setShader()
  love.graphics.reset()
  return true
end

-- Wait until next draw
function livelove.postdraw()
  if livelove.pending_reload and not livelove.healing then
    local path = livelove.pending_reload.path
    local content = livelove.pending_reload.content
    livelove.pending_reload = nil
    livelove._postdraw(path, content)
  end
end


function livelove._postdraw(path, content)
  livelove.reset()
  livelove.hotswapinstant(path, content)
end

function livelove.print(...)
  print("[livelove] " .. format(...))
end

function livelove.record_result(uri, line_number, variables)
  --livelove.print("Record result: {1}", {start_line})
  debug_bridge.documents[uri] = debug_bridge.documents[uri] or { line_values = {}, line_changed = {}, var_lookup = {} }
  local prev_value = debug_bridge.documents[uri].line_values[line_number]

  -- Check if value has changed
  local has_changes = false
  if not prev_value then
    has_changes = true
  else
    for var_name, new_value in pairs(variables) do
      if not values_equal(new_value, prev_value.values[var_name]) then
        has_changes = true
        break
      end
    end
  end

  if has_changes then
    debug_bridge.documents[uri].line_values[line_number] = {
      values = variables
    }
    for var_name, new_value in pairs(variables) do
      debug_bridge.documents[uri].var_lookup[var_name] = new_value
    end
    debug_bridge.documents[uri].line_changed[line_number] = true
  end
end

return livelove.init()
