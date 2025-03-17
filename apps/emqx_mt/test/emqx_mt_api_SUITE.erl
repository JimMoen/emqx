%%--------------------------------------------------------------------
%% Copyright (c) 2024-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------

-module(emqx_mt_api_SUITE).

-compile(nowarn_export_all).
-compile(export_all).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("snabbkaffe/include/snabbkaffe.hrl").
-include_lib("emqx/include/asserts.hrl").
-include_lib("emqx/include/emqx_mqtt.hrl").
-include_lib("emqx_utils/include/emqx_message.hrl").

-define(NEW_CLIENTID(I),
    iolist_to_binary("c-" ++ atom_to_list(?FUNCTION_NAME) ++ "-" ++ integer_to_list(I))
).

-define(NEW_USERNAME(), iolist_to_binary("u-" ++ atom_to_list(?FUNCTION_NAME))).

%%------------------------------------------------------------------------------
%% CT Boilerplate
%%------------------------------------------------------------------------------

all() ->
    emqx_common_test_helpers:all(?MODULE).

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(TestCase, Config) ->
    Apps = emqx_cth_suite:start(
        [
            emqx,
            {emqx_conf, "mqtt.client_attrs_init = [{expression = username, set_as_attr = tns}]"},
            {emqx_mt, "multi_tenancy.default_max_sessions = 10"},
            emqx_management,
            emqx_mgmt_api_test_util:emqx_dashboard()
        ],
        #{work_dir => emqx_cth_suite:work_dir(TestCase, Config)}
    ),
    snabbkaffe:start_trace(),
    [{apps, Apps} | Config].

end_per_testcase(_TestCase, Config) ->
    Apps = ?config(apps, Config),
    snabbkaffe:stop(),
    ok = emqx_cth_suite:stop(Apps),
    ok.

%%------------------------------------------------------------------------------
%% Helper fns
%%------------------------------------------------------------------------------

connect(ClientId, Username) ->
    Opts = [
        {clientid, ClientId},
        {username, Username},
        {password, "123456"},
        {proto_ver, v5}
    ],
    {ok, Pid} = emqtt:start_link(Opts),
    monitor(process, Pid),
    unlink(Pid),
    case emqtt:connect(Pid) of
        {ok, _} ->
            Pid;
        {error, _Reason} = E ->
            stop_client(Pid),
            erlang:error(E)
    end.

stop_client(Pid) ->
    catch emqtt:stop(Pid),
    receive
        {'DOWN', _, process, Pid, _, _} -> ok
    after 3000 ->
        exit(Pid, kill)
    end.

url(Path) ->
    emqx_mgmt_api_test_util:api_path(["mt", Path]).

ns_url(Ns, Path) ->
    emqx_mgmt_api_test_util:api_path(["mt", "ns", Ns, Path]).

count_clients(Ns) ->
    URL = ns_url(Ns, "client_count"),
    simple_request(#{method => get, url => URL}).

list_clients(Ns, QueryParams) ->
    URL = ns_url(Ns, "client_list"),
    simple_request(#{method => get, url => URL, query_params => QueryParams}).

list_nss(QueryParams) ->
    URL = url("ns_list"),
    simple_request(#{method => get, url => URL, query_params => QueryParams}).

maybe_json_decode(X) ->
    case emqx_utils_json:safe_decode(X) of
        {ok, Decoded} -> Decoded;
        {error, _} -> X
    end.

simplify_result(Res) ->
    case Res of
        {error, {{_, StatusCode, _}, Body}} ->
            {StatusCode, Body};
        {ok, {{_, StatusCode, _}, Body}} ->
            {StatusCode, Body}
    end.

simple_request(Params) ->
    emqx_mgmt_api_test_util:simple_request(Params).

simple_request(Method, Path, Body, QueryParams) ->
    emqx_mgmt_api_test_util:simple_request(Method, Path, Body, QueryParams).

simple_request(Method, Path, Body) ->
    emqx_mgmt_api_test_util:simple_request(Method, Path, Body).

list_explicit_nss(QueryParams) ->
    URL = emqx_mgmt_api_test_util:api_path(["mt", "explicit_ns_list"]),
    simple_request(#{method => get, url => URL, query_params => QueryParams}).

create_explicit_ns(Ns) ->
    Path = emqx_mgmt_api_test_util:api_path(["mt", "ns", Ns, "explicit"]),
    Res = simple_request(post, Path, ""),
    ct:pal("create explicit ns result:\n  ~p", [Res]),
    Res.

delete_explicit_ns(Ns) ->
    Path = emqx_mgmt_api_test_util:api_path(["mt", "ns", Ns, "explicit"]),
    Res = simple_request(delete, Path, ""),
    ct:pal("delete explicit ns result:\n  ~p", [Res]),
    Res.

get_explicit_ns_config(Ns) ->
    Path = emqx_mgmt_api_test_util:api_path(["mt", "ns", Ns, "config"]),
    Res = simple_request(get, Path, ""),
    ct:pal("get explicit ns config result:\n  ~p", [Res]),
    Res.

update_explicit_ns_config(Ns, Body) ->
    Path = emqx_mgmt_api_test_util:api_path(["mt", "ns", Ns, "config"]),
    Res = simple_request(put, Path, Body),
    ct:pal("update explicit ns config result:\n  ~p", [Res]),
    Res.

disable_tenant_limiter(Ns) ->
    Body = #{<<"limiter">> => #{<<"tenant">> => <<"disabled">>}},
    update_explicit_ns_config(Ns, Body).

disable_client_limiter(Ns) ->
    Body = #{<<"limiter">> => #{<<"client">> => <<"disabled">>}},
    update_explicit_ns_config(Ns, Body).

tenant_limiter_params() ->
    tenant_limiter_params(_Overrides = #{}).

tenant_limiter_params(Overrides) ->
    Defaults = #{
        <<"bytes">> => #{
            <<"rate">> => <<"10MB/10s">>,
            <<"burst">> => <<"200MB/1m">>
        },
        <<"messages">> => #{
            <<"rate">> => <<"3000/1s">>,
            <<"burst">> => <<"40/1m">>
        }
    },
    Merged = emqx_utils_maps:deep_merge(Defaults, Overrides),
    #{<<"limiter">> => #{<<"tenant">> => Merged}}.

client_limiter_params() ->
    client_limiter_params(_Overrides = #{}).

client_limiter_params(Overrides) ->
    Defaults = #{
        <<"bytes">> => #{
            <<"rate">> => <<"10MB/10s">>,
            <<"burst">> => <<"200MB/1m">>
        },
        <<"messages">> => #{
            <<"rate">> => <<"3000/1s">>,
            <<"burst">> => <<"40/1m">>
        }
    },
    Merged = emqx_utils_maps:deep_merge(Defaults, Overrides),
    #{<<"limiter">> => #{<<"client">> => Merged}}.

set_limiter_for_zone(Key, Value) ->
    KeyBin = atom_to_binary(Key, utf8),
    MqttConf0 = emqx_config:fill_defaults(#{<<"mqtt">> => emqx:get_raw_config([<<"mqtt">>])}),
    MqttConf1 = emqx_utils_maps:deep_put([<<"mqtt">>, <<"limiter">>, KeyBin], MqttConf0, Value),
    {ok, _} = emqx:update_config([mqtt], maps:get(<<"mqtt">>, MqttConf1)),
    ok = emqx_limiter:update_zone_limiters().

set_limiter_for_listener(Key, Value) ->
    KeyBin = atom_to_binary(Key, utf8),
    emqx:update_config(
        [listeners, tcp, default],
        {update, #{
            KeyBin => Value
        }}
    ),
    ok.

spawn_publisher(ClientId, Username, PayloadSize, QoS) ->
    TestPid = self(),
    LoopPid = spawn_link(fun() ->
        C = connect(ClientId, Username),
        TestPid ! {client, C},
        receive
            go -> run_publisher(C, PayloadSize, QoS)
        end
    end),
    receive
        {client, C} ->
            {LoopPid, C}
    after 1_000 ->
        ct:fail("client didn't start properly")
    end.

run_publisher(C, PayloadSize, QoS) ->
    _ = emqtt:publish(C, <<"test">>, binary:copy(<<"a">>, PayloadSize), QoS),
    receive
        die ->
            ok
    after 10 ->
        run_publisher(C, PayloadSize, QoS)
    end.

assert_limited(Opts) ->
    #{
        clientid := ClientId,
        username := Username,
        qos := QoS,
        payload_size := PayloadSize,
        event_matcher := EventMatcher,
        timeout := Timeout
    } = Opts,
    {LoopPid, _C} = spawn_publisher(ClientId, Username, PayloadSize, QoS),
    {_, {ok, _}} =
        snabbkaffe:wait_async_action(
            fun() -> LoopPid ! go end,
            EventMatcher,
            Timeout
        ),
    MRef = monitor(process, LoopPid),
    LoopPid ! die,
    receive
        {'DOWN', MRef, process, LoopPid, _} ->
            ok
    after 1_000 ->
        ct:fail("loop pid didn't die")
    end.

%%------------------------------------------------------------------------------
%% Test cases
%%------------------------------------------------------------------------------

t_list_apis(_Config) ->
    N = 9,
    ClientIds = [?NEW_CLIENTID(I) || I <- lists:seq(1, N)],
    Ns = ?NEW_USERNAME(),
    Clients = [connect(ClientId, Ns) || ClientId <- ClientIds],
    ?retry(200, 50, ?assertEqual({ok, N}, emqx_mt:count_clients(Ns))),
    ?assertMatch({200, #{<<"count">> := N}}, count_clients(Ns)),
    {200, ClientIds0} = list_clients(Ns, #{<<"limit">> => integer_to_binary(N div 2)}),
    LastClientId = lists:last(ClientIds0),
    {200, ClientIds1} =
        list_clients(Ns, #{
            <<"last_clientid">> => LastClientId,
            <<"limit">> => integer_to_binary(N)
        }),
    ?assertEqual(ClientIds, ClientIds0 ++ ClientIds1),
    ok = lists:foreach(fun stop_client/1, Clients),
    ?retry(
        200,
        50,
        ?assertMatch(
            {200, #{<<"count">> := 0}},
            count_clients(Ns)
        )
    ),
    ?assertMatch(
        {200, []},
        list_clients(Ns, #{})
    ),
    ?assertMatch(
        {200, [Ns]},
        list_nss(#{})
    ),
    ?assertMatch(
        {200, [Ns]},
        list_nss(#{<<"limit">> => <<"2">>})
    ),
    ?assertMatch(
        {200, []},
        list_nss(#{<<"last_ns">> => Ns, <<"limit">> => <<"1">>})
    ),
    ok.

%% Smoke CRUD operations test for tenant limiter.
%% Configuration management is tested in separate, specific test cases.
t_explicit_namespace_management(_Config) ->
    ?assertMatch({200, []}, list_explicit_nss(#{})),

    Ns1 = <<"tns1">>,
    Ns2 = <<"tns2">>,
    ?assertMatch({204, _}, delete_explicit_ns(Ns1)),
    ?assertMatch({204, _}, delete_explicit_ns(Ns2)),
    ?assertMatch({404, _}, get_explicit_ns_config(Ns1)),
    ?assertMatch({404, _}, get_explicit_ns_config(Ns2)),
    ?assertMatch({200, []}, list_explicit_nss(#{})),

    ?assertMatch({204, _}, create_explicit_ns(Ns1)),
    ?assertMatch({204, _}, delete_explicit_ns(Ns2)),
    ?assertMatch({200, _}, get_explicit_ns_config(Ns1)),
    ?assertMatch({404, _}, get_explicit_ns_config(Ns2)),
    ?assertMatch({200, [Ns1]}, list_explicit_nss(#{})),

    ?assertMatch({204, _}, create_explicit_ns(Ns2)),
    ?assertMatch({200, [Ns1, Ns2]}, list_explicit_nss(#{})),
    ?assertMatch({200, _}, get_explicit_ns_config(Ns1)),
    ?assertMatch({200, _}, get_explicit_ns_config(Ns2)),

    ?assertMatch({200, [Ns1]}, list_explicit_nss(#{<<"limit">> => <<"1">>})),
    ?assertMatch({200, [Ns2]}, list_explicit_nss(#{<<"last_ns">> => Ns1})),
    ?assertMatch({200, []}, list_explicit_nss(#{<<"last_ns">> => Ns2})),

    ?assertMatch({204, _}, delete_explicit_ns(Ns1)),
    %% Idempotency
    ?assertMatch({204, _}, delete_explicit_ns(Ns1)),
    ?assertMatch({200, [Ns2]}, list_explicit_nss(#{})),
    ?assertMatch({404, _}, get_explicit_ns_config(Ns1)),
    ?assertMatch({200, _}, get_explicit_ns_config(Ns2)),
    ?assertMatch({204, _}, delete_explicit_ns(Ns2)),
    ?assertMatch({200, []}, list_explicit_nss(#{})),
    ?assertMatch({404, _}, get_explicit_ns_config(Ns1)),
    ?assertMatch({404, _}, get_explicit_ns_config(Ns2)),

    ok.

%% Smoke CRUD operations test for tenant limiter.
t_tenant_limiter(_Config) ->
    Ns1 = <<"tns">>,
    Params1 = tenant_limiter_params(),

    %% Must create the explicit namespace first
    ?assertMatch({404, _}, get_explicit_ns_config(Ns1)),
    ?assertMatch({404, _}, update_explicit_ns_config(Ns1, Params1)),
    ?assertMatch({404, _}, disable_tenant_limiter(Ns1)),

    ?assertMatch({204, _}, create_explicit_ns(Ns1)),

    ?assertMatch(
        {200, #{
            <<"limiter">> := #{
                <<"tenant">> := #{
                    <<"bytes">> := #{<<"rate">> := <<"10MB/10s">>, <<"burst">> := <<"200MB/1m">>},
                    <<"messages">> := #{<<"rate">> := <<"3000/1s">>, <<"burst">> := <<"40/1m">>}
                }
            }
        }},
        update_explicit_ns_config(Ns1, Params1)
    ),
    %% Idempotency
    ?assertMatch(
        {200, #{
            <<"limiter">> := #{
                <<"tenant">> := #{
                    <<"bytes">> := #{<<"rate">> := <<"10MB/10s">>, <<"burst">> := <<"200MB/1m">>},
                    <<"messages">> := #{<<"rate">> := <<"3000/1s">>, <<"burst">> := <<"40/1m">>}
                }
            }
        }},
        update_explicit_ns_config(Ns1, Params1)
    ),
    ?assertMatch(
        {200, #{
            <<"limiter">> := #{
                <<"tenant">> := #{
                    <<"bytes">> := #{<<"rate">> := <<"10MB/10s">>, <<"burst">> := <<"200MB/1m">>},
                    <<"messages">> := #{<<"rate">> := <<"3000/1s">>, <<"burst">> := <<"40/1m">>}
                }
            }
        }},
        get_explicit_ns_config(Ns1)
    ),
    Params2 = tenant_limiter_params(#{
        <<"bytes">> => #{
            <<"rate">> => <<"infinity">>,
            <<"burst">> => <<"0/1d">>
        },
        <<"messages">> => #{
            <<"burst">> => <<"60/60s">>
        }
    }),
    ?assertMatch(
        {200, #{
            <<"limiter">> := #{
                <<"tenant">> := #{
                    <<"bytes">> := #{<<"rate">> := <<"infinity">>, <<"burst">> := <<"0/1d">>},
                    <<"messages">> := #{<<"rate">> := <<"3000/1s">>, <<"burst">> := <<"60/1m">>}
                }
            }
        }},
        update_explicit_ns_config(Ns1, Params2)
    ),
    ?assertMatch(
        {200, #{
            <<"limiter">> := #{
                <<"tenant">> := #{
                    <<"bytes">> := #{<<"rate">> := <<"infinity">>, <<"burst">> := <<"0/1d">>},
                    <<"messages">> := #{<<"rate">> := <<"3000/1s">>, <<"burst">> := <<"60/1m">>}
                }
            }
        }},
        get_explicit_ns_config(Ns1)
    ),

    ?assertMatch(
        {200, #{<<"limiter">> := #{<<"tenant">> := <<"disabled">>}}},
        disable_tenant_limiter(Ns1)
    ),
    ?assertMatch(
        {200, #{<<"limiter">> := #{<<"tenant">> := <<"disabled">>}}},
        get_explicit_ns_config(Ns1)
    ),

    ok.

%% Smoke CRUD operations test for client limiter.
t_client_limiter(_Config) ->
    Ns1 = <<"tns">>,
    Params1 = client_limiter_params(),

    %% Must create the explicit namespace first
    ?assertMatch({404, _}, get_explicit_ns_config(Ns1)),
    ?assertMatch({404, _}, update_explicit_ns_config(Ns1, Params1)),
    ?assertMatch({404, _}, disable_client_limiter(Ns1)),

    ?assertMatch({204, _}, create_explicit_ns(Ns1)),

    ?assertMatch(
        {200, #{
            <<"limiter">> := #{
                <<"client">> := #{
                    <<"bytes">> := #{<<"rate">> := <<"10MB/10s">>, <<"burst">> := <<"200MB/1m">>},
                    <<"messages">> := #{<<"rate">> := <<"3000/1s">>, <<"burst">> := <<"40/1m">>}
                }
            }
        }},
        update_explicit_ns_config(Ns1, Params1)
    ),
    %% Idempotency
    ?assertMatch(
        {200, #{
            <<"limiter">> := #{
                <<"client">> := #{
                    <<"bytes">> := #{<<"rate">> := <<"10MB/10s">>, <<"burst">> := <<"200MB/1m">>},
                    <<"messages">> := #{<<"rate">> := <<"3000/1s">>, <<"burst">> := <<"40/1m">>}
                }
            }
        }},
        update_explicit_ns_config(Ns1, Params1)
    ),
    ?assertMatch(
        {200, #{
            <<"limiter">> := #{
                <<"client">> := #{
                    <<"bytes">> := #{<<"rate">> := <<"10MB/10s">>, <<"burst">> := <<"200MB/1m">>},
                    <<"messages">> := #{<<"rate">> := <<"3000/1s">>, <<"burst">> := <<"40/1m">>}
                }
            }
        }},
        get_explicit_ns_config(Ns1)
    ),
    Params2 = client_limiter_params(#{
        <<"bytes">> => #{
            <<"rate">> => <<"infinity">>,
            <<"burst">> => <<"0/1d">>
        },
        <<"messages">> => #{
            <<"burst">> => <<"60/60s">>
        }
    }),
    ?assertMatch(
        {200, #{
            <<"limiter">> := #{
                <<"client">> := #{
                    <<"bytes">> := #{<<"rate">> := <<"infinity">>, <<"burst">> := <<"0/1d">>},
                    <<"messages">> := #{<<"rate">> := <<"3000/1s">>, <<"burst">> := <<"60/1m">>}
                }
            }
        }},
        update_explicit_ns_config(Ns1, Params2)
    ),
    ?assertMatch(
        {200, #{
            <<"limiter">> := #{
                <<"client">> := #{
                    <<"bytes">> := #{<<"rate">> := <<"infinity">>, <<"burst">> := <<"0/1d">>},
                    <<"messages">> := #{<<"rate">> := <<"3000/1s">>, <<"burst">> := <<"60/1m">>}
                }
            }
        }},
        get_explicit_ns_config(Ns1)
    ),

    ?assertMatch(
        {200, #{<<"limiter">> := #{<<"client">> := <<"disabled">>}}},
        disable_client_limiter(Ns1)
    ),
    ?assertMatch(
        {200, #{<<"limiter">> := #{<<"client">> := <<"disabled">>}}},
        get_explicit_ns_config(Ns1)
    ),

    ok.

%% Verifies that the channel limiters are adjusted when client and/or tenant limiters are
%% configured.
t_adjust_limiters(Config) when is_list(Config) ->
    Ns = atom_to_binary(?FUNCTION_NAME),
    ?check_trace(
        begin
            ?assertMatch({204, _}, create_explicit_ns(Ns)),

            %% 1) Client limiter completely replaces listener limiter.
            set_limiter_for_listener(messages_rate, <<"infinity">>),
            set_limiter_for_listener(bytes_rate, <<"infinity">>),
            ClientParams1 = client_limiter_params(#{
                <<"bytes">> => #{<<"rate">> => <<"1/500ms">>, <<"burst">> => <<"0/1s">>},
                <<"messages">> => #{<<"rate">> => <<"1/500ms">>, <<"burst">> => <<"0/1s">>}
            }),
            ?assertMatch({200, _}, update_explicit_ns_config(Ns, ClientParams1)),
            Username = Ns,
            ClientId1 = ?NEW_CLIENTID(1),
            assert_limited(#{
                clientid => ClientId1,
                username => Username,
                qos => 1,
                payload_size => 100,
                event_matcher => ?match_event(#{
                    ?snk_kind := limiter_exclusive_try_consume, success := false
                }),
                timeout => 1_000
            }),
            {200, _} = disable_client_limiter(Ns),
            %% Tenant limiter composes with zone limiter.
            set_limiter_for_zone(messages_rate, <<"infinity">>),
            set_limiter_for_zone(bytes_rate, <<"infinity">>),
            TenantParams1 = tenant_limiter_params(#{
                <<"bytes">> => #{<<"rate">> => <<"1/500ms">>, <<"burst">> => <<"0/1s">>},
                <<"messages">> => #{<<"rate">> => <<"1/500ms">>, <<"burst">> => <<"0/1s">>}
            }),
            ?assertMatch({200, _}, update_explicit_ns_config(Ns, TenantParams1)),
            ClientId2 = ?NEW_CLIENTID(2),
            assert_limited(#{
                clientid => ClientId2,
                username => Username,
                qos => 1,
                payload_size => 100,
                event_matcher => ?match_event(#{
                    ?snk_kind := limiter_shared_try_consume, success := false
                }),
                timeout => 1_000
            }),
            %% Other way around
            set_limiter_for_zone(messages_rate, <<"1/500ms">>),
            set_limiter_for_zone(bytes_rate, <<"1/500ms">>),
            TenantParams2 = tenant_limiter_params(#{
                <<"bytes">> => #{<<"rate">> => <<"infinity">>, <<"burst">> => <<"0/1s">>},
                <<"messages">> => #{<<"rate">> => <<"infinity">>, <<"burst">> => <<"0/1s">>}
            }),
            ?assertMatch({200, _}, update_explicit_ns_config(Ns, TenantParams2)),
            ClientId3 = ?NEW_CLIENTID(3),
            assert_limited(#{
                clientid => ClientId3,
                username => Username,
                qos => 1,
                payload_size => 100,
                event_matcher => ?match_event(#{
                    ?snk_kind := limiter_shared_try_consume, success := false
                }),
                timeout => 1_000
            }),
            {200, _} = disable_tenant_limiter(Ns),

            %% Check that, if we delete an explicit namespace with live clients, they
            %% still can publish without crashing.
            set_limiter_for_listener(messages_rate, <<"infinity">>),
            set_limiter_for_listener(bytes_rate, <<"infinity">>),
            set_limiter_for_zone(messages_rate, <<"infinity">>),
            set_limiter_for_zone(bytes_rate, <<"infinity">>),
            TenantAndClientParams1 = emqx_utils_maps:deep_merge(ClientParams1, TenantParams1),
            ?assertMatch({200, _}, update_explicit_ns_config(Ns, TenantAndClientParams1)),
            ClientId4 = ?NEW_CLIENTID(4),
            C = connect(ClientId4, Username),
            ?assertMatch({204, _}, delete_explicit_ns(Ns)),
            ?assertMatch({200, []}, list_explicit_nss(#{})),
            Topic = <<"test">>,
            emqx:subscribe(Topic, #{qos => 1}),
            {ok, #{reason_code := ?RC_SUCCESS}} = emqtt:publish(C, Topic, <<"hi1">>, [{qos, 1}]),
            {ok, #{reason_code := ?RC_SUCCESS}} = emqtt:publish(C, Topic, <<"hi2">>, [{qos, 1}]),
            ?assertReceive({deliver, Topic, #message{payload = <<"hi1">>}}),
            ?assertReceive({deliver, Topic, #message{payload = <<"hi2">>}}),

            ok
        end,
        fun(Trace) ->
            ?assertMatch([_, _, _, _], ?of_kind("channel_limiter_adjusted", Trace)),
            ok
        end
    ),
    ok.
