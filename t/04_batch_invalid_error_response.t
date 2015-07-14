# vim:set ft= ts=4 sw=4 et:

use Test::More;
use Test::Deep;
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);
use JSON::XS;
my $json = JSON::XS->new->utf8->canonical;

repeat_each(1);

plan tests => repeat_each() * (3 * blocks());

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    init_by_lua '
        batch = require "resty.jsonrpc.batch"
    ';
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: basic
--- http_config eval: $::HttpConfig
--- config
    location /api {
        echo -n a;
    }
    location /t {
        lua_need_request_body on;
        
        content_by_lua '

            client = batch:new({
                invalid_error_response = function(ctx)
                    return ctx.invalid_error
                end
            })
            local res, err = client:batch_request({
                path    = "/api",
                request = ngx.var.request_body,
            })
            if err then
                ngx.exit(500)
            end
            ngx.say(res)
        ';
    }
--- request
POST /t\n
--- response_body_like
Invalid Request:.*
--- no_error_log
[error]
