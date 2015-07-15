cjson = require "cjson"

local _M = { _VERSION = '0.0.1' }

local mt = { __index = _M }

function _M.new(self, args)
    if type(args) ~= 'table' then
        args = {}
    end

    local params = {
        max_batch_array_size      = args.max_batch_array_size      or nil,
        allow_single_request      = args.allow_single_request == nil  and true or args.allow_single_request,
        before_subrequest         = args.before_subrequest         or function (self, ctx) end,
        after_subrequest          = args.after_subrequest          or function (self, ctx) end,
    }

    return setmetatable(params, mt)
end

function _M.batch_request(self, params)
    if not params.path then
        return nil, "parameter 'path' must be specified"
    end

    local ctx =  {
        path        = params.path,
        raw_request = params.request,
        method      = params.method or ngx.HTTP_POST
    }

    local success, ret = pcall(function()
    
        local success, request = pcall(function()
            return cjson.decode(params.request)
        end)
        if (not success) then
            self:raise_invalid_error("Invalid Request:" .. request)
        end

        if type(request) ~= "table" then
            self:raise_invalid_error("Invalid Request: request should be object")
        end

        ctx.request = request

        local is_array = self:_is_array(request)
        if is_array == 0 then
            -- empty
            self:raise_invalid_error("Invalid Request: table is empty")
        elseif is_array == -1 then
            ctx.is_batch = 0;
            -- single request
            if self.allow_single_request then
                return self:_single_request(ctx), false
            else
                self:raise_invalid_error("Invalid Request: only access batch request.")
            end
        else
            ctx.is_batch = 1;
            -- batch request
            if (self.max_batch_array_size and #request > self.max_batch_array_size) then
                self:raise_invalid_error("Invalid Request: batch request array size (" .. #request .. ") is over max size (" .. self.max_batch_array_size .. ")")
            end
            return self:_batch_request(ctx), false
        end
    end)
    
    if success then
        return ret
    elseif type(ret) == 'table' and ret.invalid_error then
        return cjson.encode(self:invalid_error_response(ctx, ret.invalid_error))
    else
        -- catch lua error
       return nil, ret
    end

end

function _M._single_request(self, ctx)


    local subreq_req = {
        self:_get_path(ctx, ctx.request),
        { method = ctx.method, body = cjson.encode(ctx.request) }
    }

    ctx.subreq_reqs = { subreq_req }

    self:before_subrequest(ctx)

    local subreq_resp =  ngx.location.capture(subreq_req[1], subreq_req[2])

    ctx.subreq_resps = { subreq_resps }

    self:after_subrequest(ctx)
    
    local client_res
    if subreq_resp.status == ngx.HTTP_OK then
        return subreq_resp.body
    else
        local error_body = self:subrequest_error_response(ctx, ctx.request, subreq_resp)
        return cjson.encode(error_body)
    end
end

function _M._batch_request(self, ctx)
    ctx.subreq_reqs = {}
    for i, req in ipairs(ctx.request) do
        table.insert(ctx.subreq_reqs, {
            self:_get_path(ctx, req),
            { method = ctx.method, body = cjson.encode(req) }
        })
    end

    -- subrequests
    self:before_subrequest(ctx)
    
    ctx.subreq_resps = { ngx.location.capture_multi(ctx.subreq_reqs) }
    
    self:after_subrequest(ctx)
    
    -- response
    local res = {}
    for i, subreq_resp in ipairs(ctx.subreq_resps) do
        if subreq_resp.status == ngx.HTTP_OK then
            table.insert(res, subreq_resp.body)
        else
            local error_body = self:subrequest_error_response(ctx, ctx.request[i], subreq_resp)
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

function _M._get_path(self, ctx, req)
    if type(ctx.path) == 'function' then
        return ctx.path(self, ctx, req)
    else 
        return ctx.path
    end
end

function _M.subrequest_error_response(self, ctx, req, res)
    if type(req) == "table" then
        id = req.id or cjson.null
    else
        id = cjson.null
    end

    return {
        id = id,
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

function _M.invalid_error_response(self, ctx, message)
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
            message = message,
        }
    }
end

function _M.raise_invalid_error(self, message)
    error({invalid_error = message})
end


-- Determine with a Lua table can be treated as an array.
-- Explicitly returns "not an array" for very sparse arrays.
-- Returns:
-- -1   Not an array
-- 0    Empty table
-- >0   Highest index in the array
function _M._is_array(self, table)
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

return _M
