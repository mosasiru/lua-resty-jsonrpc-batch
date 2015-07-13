local cjson = require "cjson"

local _M = { _VERSION = '0.01' }

local mt = { __index = _M }

function _M.new(self)
    return setmetatable({
        max_batch_request_array_size = self.max_batch_request_array_size
    }, mt)
end

function _M.subrequest_error_response(self, res, req)
    return {
        id =  req.id,
        jsonrpc = "2.0",
        error = {
            code    = -32603,
            message = "Internal Error" ,
            data = {
                code = res.status,
                message = res.body,
            }
        }
    }
end

function _M.before_subrequest(self, client_req)
end

function _M.after_subrequest(self, subreq_resps, client_req)
end

local function _path(path, req)
    if type(path) == 'function' then
        return path(req)
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

function _M.batch_request(self, params)

    if not params.path then
        return nil, "parameter 'path' must be specified"
    end

    local method = params.method or ngx.HTTP_POST;

    local success, ret = pcall(function()
    
        local success, client_req = pcall(function()
            return cjson.decode(params.json)
        end)
        if (not success) then
            error("Invalid request:" .. client_req)
        end

        if type(client_req) ~= "table" then
            error("Invalid request: type is " ..  type(client_req))
        end

        local is_array = _is_array(client_req)
    
        if is_array == 0 then
            -- empty
            error("Invalid request: table is empty")
        elseif is_array == -1 then
            -- single request
            local ctx = {}
            self:before_subrequest(ctx, client_req)
            local subreq_resp = ngx.location.capture(
                _path(params.path, client_req),
                { method = method, body = body }
            )
            self:after_subrequest(ctx, {subreq_resp}, client_req)
    
            local client_res
            if subreq_resp.status == ngx.HTTP_OK then
                client_res = subreq_resp.body
            else
                local error_body = self:subrequest_error_response(subreq_resp, client_req)
                client_res = cjson.encode(error_body)
            end
            return client_res
        end
    
        -- batch request
        if (self.max_batch_request_array_size and #client_req > self.max_batch_request_array_size) then
            error("Invalid request: batch request array size (" .. #client_req .. ") is over max size (" .. self.max_batch_request_array_size .. ")")
        end
        local subreq_reqs = {}
        for i, req in ipairs(client_req) do
            table.insert(subreq_reqs, {
                _path(params.path, req),
                { method = method, body = cjson.encode(req) }
            })
        end
    
        -- subrequests
        local ctx = {}

        self:before_subrequest(ctx, client_req)
    
        local subreq_resps = { ngx.location.capture_multi(subreq_reqs) }
    
        self:after_subrequest(ctx, subreq_resps, client_req)
    
        -- response
        local res = {}
        for i, subreq_resp in ipairs(subreq_resps) do
            if subreq_resp.status == ngx.HTTP_OK then
                table.insert(res, subreq_resp.body)
            else
                local error_body = self:subrequest_error_response(subreq_resp, client_req)
                table.insert(res, cjson.encode(error_body))
            end
        end
    
    
        -- build json
        local res_body =  "[" .. table.concat(res, ",") .. "]"
        if (res_body == "[]") then
            return ""
        end
        return res_body
       
    end)
    
    if ( success ) then
        return ret
    else
        -- catch lua error
        if string.match(ret, "Invalid request:") then
            ngx.log(ngx.ERR, ret)
            return '{"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid request"}, "id": null}'
        else
            return nil, ret
        end
    end

end

return _M
