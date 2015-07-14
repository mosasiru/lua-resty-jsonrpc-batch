# vim:set ft= ts=4 sw=4 et:

use Test::More;
use Test::Deep;
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);
use JSON::XS;
my $json = JSON::XS->new->utf8->canonical;

repeat_each(1);

plan tests => repeat_each() * (2 * blocks());

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
my $body = JSON::XS->new->canonical->encode({
    id => 1,
    jsonrpc => "2.0",
    params => {},
    method => "aa"
});
"POST /t
$body"
--- exp_response_json eval
{
    id => 1,
    jsonrpc => "2.0",
    params => {},
    method => "aa"
}

=== TEST 2: dispatch error
--- http_config eval: $::HttpConfig
--- config
    location /api {
        return 404;
    }
    location /t {
        lua_need_request_body on;
        
        content_by_lua '
            client = batch:new({
                allow_single_request = true,
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
--- request eval
use JSON::XS;
my $body = JSON::XS->new->canonical->encode({
    id => 1,
    jsonrpc => "2.0",
    params => {},
    method => "aa"
});
"POST /t
$body"
--- exp_response_json eval
{
    id => undef,
    jsonrpc => "2.0",
    error => {
        code => "-32603",
        message => "Internal Error",
        data => {
            code => "404",
            message => "",
        }
    }
}
