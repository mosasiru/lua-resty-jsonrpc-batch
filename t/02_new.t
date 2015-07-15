# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each(1);

plan tests => repeat_each() * (3 * blocks());

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: basic
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local batch = require "resty.jsonrpc.batch"
            local client = batch:new()
            ngx.say(client.max_batch_array_size == nil)
            ngx.say(client.allow_single_request)
            ngx.say(type(client.before_subrequest))
            ngx.say(type(client.after_subrequest))
        ';
    }
--- request
    GET /t
--- response_body
true
true
function
function
--- no_error_log
[error]

=== TEST 2: max_batch_array_size
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local batch = require "resty.jsonrpc.batch"
            local client = batch:new({
                max_batch_array_size = 10,
                allow_single_request = false,
                before_subrequest = function () return 1 end,
                after_subrequest = function () return 2 end,

            })
            ngx.say(client.max_batch_array_size)
            ngx.say(client.allow_single_request)
            ngx.say(client.before_subrequest())
            ngx.say(client.after_subrequest())
        ';
    }
--- request
    GET /t
--- response_body
10
false
1
2
--- no_error_log
[error]
