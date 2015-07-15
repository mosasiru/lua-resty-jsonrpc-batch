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
#
add_response_body_check(sub {
        my ($block, $body, $req_idx, $repeated_req_idx, $dry_run) = @_;
        my $test_name = $block->name . " - response body check " . $req_idx;
        note explain $body;
        my $res = $json->decode($body);
        cmp_deeply $res, $block->exp_response_json, $test_name,
            or note explain $res;
 
    });

run_tests();

__DATA__

=== TEST 1: basic
--- http_config eval: $::HttpConfig
--- config
    location /api {
        echo -n $request_body;
    }
    location /t {
        lua_need_request_body on;
        
        content_by_lua '
            client = batch:new()
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
--- request eval
use JSON::XS;
my $body = JSON::XS->new->canonical->encode([
    {
        id => 1,
        jsonrpc => "2.0",
        params => {},
        method => "aa"
    },
    {
        id => 2,
        jsonrpc => "2.0",
        params => {},
        method => "bb"
    },
]);
"POST /t
$body"
--- exp_response_json eval
[
    {
        id => 1,
        jsonrpc => "2.0",
        params => {},
        method => "aa"
    },
    {
        id => 2,
        jsonrpc => "2.0",
        params => {},
        method => "bb"
    },
]
--- no_error_log
[error]


=== TEST 2: basic 2
--- http_config eval: $::HttpConfig
--- config
    location /api {
        echo -n $request_body;
    }
    location /t {
        lua_need_request_body on;
        
        content_by_lua '
            client = batch:new()
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
--- request eval
use JSON::XS;
my $body = JSON::XS->new->canonical->encode([
    {
        id => 1,
        jsonrpc => "2.0",
        params => {},
        method => "aa"
    }
]);
"POST /t
$body"
--- exp_response_json eval
[
    {
        id => 1,
        jsonrpc => "2.0",
        params => {},
        method => "aa"
    }
]
--- no_error_log
[error]


=== TEST 3: through invalid single request
--- http_config eval: $::HttpConfig
--- config
    location /api {
        echo -n $request_body;
    }
    location /t {
        lua_need_request_body on;
        
        content_by_lua '
            client = batch:new()
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
--- request eval
use JSON::XS;
my $body = JSON::XS->new->canonical->encode([
    1,
    undef
]);
"POST /t
$body"
--- exp_response_json eval
[
    1,
    undef
]
--- no_error_log
[error]

=== TEST 4: include error upstream
--- http_config eval: $::HttpConfig
--- config
    location /api/ok {
        echo -n $request_body;
    }
    location /api/ng {
        return 404;
    }
    location /t {
        lua_need_request_body on;
        
        content_by_lua '
            client = batch:new()
            local res, err = client:batch_request({
                path = function(self, ctx, req)
                    return "/api/" .. req.method
                end,
                request = ngx.var.request_body,
            })
            if err then
                ngx.exit(500)
            end
            ngx.say(res)
        ';
    }
--- request eval
use JSON::XS;
my $body = JSON::XS->new->canonical->encode([
    {
        id => 1,
        jsonrpc => "2.0",
        params => { a => 1},
        method => "ng"
    },
    {
        id => 2,
        jsonrpc => "2.0",
        params => { b => 2},
        method => "ok"
    },
    {
        id => 3,
        jsonrpc => "2.0",
        params => { c => 3},
        method => "ng"
    },
]);

"POST /t
$body"
--- exp_response_json eval
[
    {
        id => 1,
        jsonrpc => "2.0",
        error => {
            code => "-32603",
            message => "Internal Error",
            data => {
                code => "404",
                message => "",
            },
        },
    },
    {
        id => 2,
        jsonrpc => "2.0",
        params => { b => 2},
        method => "ok"
    },
    {
        id => 3,
        jsonrpc => "2.0",
        error => {
            code => "-32603",
            message => "Internal Error",
            data => {
                code => "404",
                message => "",
            }
        }
    },
]
--- no_error_log
[error]

=== TEST 5: method:GET
--- http_config eval: $::HttpConfig
--- config
    location /api {
        if ($echo_request_method !~ ^(POST)$ ) {
            return 405 $echo_request_method;
        }
        echo -n $request_body;
    }
    location /t {
        lua_need_request_body on;
        
        content_by_lua '
            client = batch:new()
            local res, err = client:batch_request({
                path    = "/api",
                request = ngx.var.request_body,
                method  = ngx.HTTP_GET,
            })
            if err then
                ngx.exit(500)
            end
            ngx.say(res)
        ';
    }
--- request eval
use JSON::XS;
my $body = JSON::XS->new->canonical->encode([
    {
        id => 1,
        jsonrpc => "2.0",
        params => {},
        method => "a"
    }
]);
"POST /t
$body"
--- exp_response_json eval
[
    {
        id => 1,
        jsonrpc => "2.0",
        error => {
            code => "-32603",
            message => "Internal Error",
            data => {
                code => "405",
                message => "GET",
            }
        }
    }
]
--- no_error_log
[error]
    
