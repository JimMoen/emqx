%%--------------------------------------------------------------------
%% Copyright (c) 2025 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------

-module(emqx_limiter_composite_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").

%%--------------------------------------------------------------------
%% Setups
%%--------------------------------------------------------------------

all() ->
    emqx_common_test_helpers:all(?MODULE).

init_per_suite(Config) ->
    Apps = emqx_cth_suite:start([emqx], #{work_dir => emqx_cth_suite:work_dir(Config)}),
    [{apps, Apps} | Config].

end_per_suite(Config) ->
    emqx_cth_suite:stop(?config(apps, Config)).

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, Config) ->
    Groups = emqx_limiter_registry:list_groups(),
    lists:foreach(
        fun(Group) ->
            emqx_limiter:delete_group(Group)
        end,
        Groups
    ),
    Config.

%%--------------------------------------------------------------------
%% Tests
%%--------------------------------------------------------------------

t_try_consume_put_back(_) ->
    ok = emqx_limiter:create_group(exclusive, group1, [
        {limiter1, #{capacity => 2, interval => 1000, burst_capacity => 0}},
        {limiter2, #{capacity => 1, interval => 1000, burst_capacity => 0}}
    ]),

    Client0 = emqx_limiter_composite:new([
        emqx_limiter:connect({group1, limiter1}),
        emqx_limiter:connect({group1, limiter2})
    ]),

    %% Try to consume 2 tokens, but the second limiter has only 1 available
    {false, Client1, _} = emqx_limiter_client:try_consume(Client0, 2),

    %% Check that 2 tokens were put back into the first limiter are available
    {true, Client2} = emqx_limiter_client:try_consume(Client1, 1),
    {false, Client3, _} = emqx_limiter_client:try_consume(Client2, 1),

    %% Verify put_back works
    Client4 = emqx_limiter_client:put_back(Client3, 1),
    {true, Client5} = emqx_limiter_client:try_consume(Client4, 1),
    {false, _Client6, _} = emqx_limiter_client:try_consume(Client5, 1).
