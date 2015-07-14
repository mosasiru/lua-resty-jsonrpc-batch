cjson = require "cjson"

local _M = { _VERSION = '0.0.1' }

local mt = { __index = _M }

local function default_subrequest_error_response(ctx, req, res)
    local id
    if type(req) == "table" then
        id = req.id or cjson.null
    else
        id = cjson.null
    end

    return {
        id =  id,
        jsonrpc = "2.0",
        error = {
            code    = -32603,
            message = "Internal Error",
            data = {
                code = res.status,
                message = res.body,
            }
        }
    }
end

local function default_invalid_error_response(ctx)
    ngx.log(ngx.ERR, ctx.invalid_error)

    local id
    if type(ctx.request) == "table" then
        id = ctx.request.id or cjson.null
    else
        id = cjson.null
    end

    return {
        id = id,
        jsonrpc = "2.0",
        error = {
            code    = -32600,
            message = ctx.invalid_error,
        }
    }
end

function _M.new(self, args)
    if type(args) ~= 'table' then
        args = {}
    end

    local params = {
        max_batch_array_size      = args.max_batch_array_size      or nil,
        allow_single_request      = args.allow_single_request == nil  and true or args.allow_single_request,
        before_subrequest         = args.before_subrequest         or function (request) end,
        after_subrequest          = args.after_subrequest          or function (subreq_resps, request) end,
        subrequest_error_response = args.subrequest_error_response or default_subrequest_error_response,
        invalid_error_response    = args.invalid_error_response    or default_invalid_error_response,
    }

    return setmetatable(params, mt)
end


local function _path(ctx, path, req)
    if type(path) == 'function' then
        return path(ctx, req)
    else 
        return path
    end
end

-- Determine with a Lua table can be treated as an array.
-- Explicitly returns "not an array" for very sparse arrays.
-- Returns:
-- -1   Not an array
-- 0    Empty table
-- >0   Highest index in the array
local function _is_array(table)
    local max = 0
    local count = 0
    for k, v in pairs(table) do
        if type(k) == "number" then
            if k > max then max = k end
            count = count + 1
        else
            return -1
        end
    end
    if max > count * 2 then
        return -1
    end

    return max
end

function _M._single_request(self, ctx)
    local subreq_req = {
        _path(ctx, ctx.path, ctx.request),
        { method = ctx.method, body = cjson.encode(ctx.request) }
    }
    ctx.subreq_reqs = { subreq_req }

    self.before_subrequest(ctx)

    local subreq_resp =  ngx.location.capture(subreq_req[1], subreq_req[2])

    ctx.subreq_resps = { subreq_resps }

    self.after_subrequest(ctx)
    
    local client_res
    if subreq_resp.status == ngx.HTTP_OK then
        return subreq_resp.body
    else
        local error_body = self.subrequest_error_response(ctx, subreq_req, subreq_resp)
        return cjson.encode(error_body)
    end
end

function _M._batch_request(self, ctx)
    ctx.subreq_reqs = {}
    for i, req in ipairs(ctx.request) do
        table.insert(ctx.subreq_reqs, {
            _path(ctx, ctx.path, req),
            { method = ctx.method, body = cjson.encode(req) }
        })
    end

    -- subrequests
    self.before_subrequest(ctx)
    
    ctx.subreq_resps = { ngx.location.capture_multi(ctx.subreq_reqs) }
    
    self.after_subrequest(ctx)
    
    -- response
    local res = {}
    for i, subreq_resp in ipairs(ctx.subreq_resps) do
        if subreq_resp.status == ngx.HTTP_OK then
            table.insert(res, subreq_resp.body)
        else
            local error_body = self.subrequest_error_response(ctx, ctx.subreq_reqs[i], subreq_resp)
            table.insert(res, cjson.encode(error_body))
        end
    end
    
    
    -- build json
    local res_body =  "[" .. table.concat(res, ",") .. "]"
    if (res_body == "[]") then
        return ""
    end
    return res_body
end
function _M.batch_request(self, params)

    if not params.path then
        return nil, "parameter 'path' must be specified"
    end

    local method = params.method or ngx.HTTP_POST;

    local ctx = {
        path        = params.path,
        request_raw = params.request,
        method      = method,
    }
    local success, ret = pcall(function()
    
        local success, request = pcall(function()
            return cjson.decode(params.request)
        end)
        if (not success) then
            ctx.invalid_error = "Invalid Request:" .. request
            error()
        end

        if type(request) ~= "table" then
            ctx.invalid_error = "Invalid Request: type is " ..  type(request)
            error()
        end

        ctx.request = request

        local is_array = _is_array(request)
        if is_array == 0 then
            -- empty
            ctx.invalid_error = "Invalid Request: table is empty"
            error()
        elseif is_array == -1 then
            ctx.is_batch = 0;
            -- single request
            if self.allow_single_request then
                return self:_single_request(ctx), false
            else
                ctx.invalid_error = "Invalid Request: only access batch request."
                error()
            end
        else
            ctx.is_batch = 1;
            -- batch request
            if (self.max_batch_array_size and #request > self.max_batch_array_size) then
                ctx.invalid_error = "Invalid Request: batch request array size (" .. #request .. ") is over max size (" .. self.max_batch_array_size .. ")"
                error()
            end
            return self:_batch_request(ctx), false
        end
    end)
    
    if ctx.invalid_error then
        return cjson.encode(self.invalid_error_response(ctx, ret))
    elseif success then
        return ret
    elseif success then
        -- catch lua error
       return nil, ret
    end

end

return _M
