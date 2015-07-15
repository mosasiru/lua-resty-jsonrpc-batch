package = "lua-resty-jsonrpc-batch"
version = "0.0.1-2"
source = {
   url = "git://github.com/mosasiru/lua-resty-jsonrpc-batch",
   tag = "v0.0.1"
}
description = {
   summary = "The Lua-Openresty implementation of JSON-RPC 2.0 Batch Request.",
   detailed = "The Lua-Openresty implementation of [JSON-RPC 2.0](http://www.jsonrpc.org/specification) Batch Request (http://www.jsonrpc.org/specification#batch).",
   homepage = "https://github.com/mosasiru/lua-resty-jsonrpc-batch",
   license = "Apache License, Version 2.0"
}
dependencies = {
   "lua >= 5.1",
   "lua-cjson >= 2.1.0",
}
build = {
   type = "builtin",
   modules = {
      ["lib.resty.jsonrpc.batch"] = "lib/resty/jsonrpc/batch.lua"
   }
}
