# lua-resty-jsonrpc-batch

The Lua-Openresty implementation of [JSON-RPC 2.0](http://www.jsonrpc.org/specification) Batch Request (http://www.jsonrpc.org/specification#batch).

The batch request is non-blocking and proceeded paralelly because this module makes use of location.capture_multi of ngx_lua. So the performance is high while the implementation is simple.

This module parses a batch request, validate it, and makes multi subrequest to upstream servers.
Note that you must have a upstream JSON-RPC server as you like, but upstream servers need not apply for JSON-RPC batch request.

## Installation

## Synopsis

#### Basic Usage

```lua
server {
    location /api {
        -- jsonrpc endpoint
    }
    location /api/batch {
        lua_need_request_body on;

        content_by_lua '
            local jsonrpc_batch = require "resty.jsonrpc.batch"
            client = jsonrpc_batch.new()
            -- multi subrequest to /api
            local res, err = client:batch_request({
                path = "/api",
                json = ngx.var.request_body,
            });
            if err then
                ngx.log(ngx.CRIT, err);
                ngx.exit(500);
            end
            ngx.say(res);
        ';
    }
}
```

#### Advanced Usage


```lua
server {
    -- logging upstream response time
    set $jsonrpc_upstream_response_time  -;

    init_by_lua '
        local jsonrpc_batch = require "resty.jsonrpc.batch"
        -- make limitation to batch request array size
        client = jsonrpc_batch.new({
            max_batch_array_size = 10,
        })

        function client.before_subrequest(self, ctx, req)
            ctx.start_at = ngx.now()
        end
        function client.after_subrequest(self, ctx, resps, req)
            local apptime = string.format("%.3f", ngx.now() - ctx.start_at)
            ngx.var.jsonrpc_upstream_response_time = apptime
        end
    ';


    location /api/method/.* {
        -- jsonrpc endpoint
    }

    location /api/batch {
        lua_need_request_body on;

        content_by_lua '
            local endpoint = function(req)
                local version = ngx.var.version
                return "/api/method/" .. req.method
            end

            -- you can change the endpoint per request
            local res, err = client:batch_request({
                path = endpoint,
                json = ngx.var.request_body,
            });
            if err then
                ngx.log(ngx.CRIT, err);
                ngx.exit(500);
            end
            ngx.say(res);
        ';
    }
}
```

## Author

* Yusuke Enomoto ([mosa_siru](https://twitter.com/mosa_siru))

## License

Copyright 2014- Yusuke Enomoto (mosa_siru)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
