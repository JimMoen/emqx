%%--------------------------------------------------------------------
%% Copyright (c) 2017-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------

%% @doc The CoAP Gateway implement
-module(emqx_gateway_coap).

-include_lib("emqx/include/logger.hrl").
-include_lib("emqx_gateway/include/emqx_gateway.hrl").

%% define a gateway named coap
-gateway(#{
    name => coap,
    callback_module => ?MODULE,
    config_schema_module => emqx_coap_schema
}).

%% callback_module must implement the emqx_gateway_impl behaviour
-behaviour(emqx_gateway_impl).

%% callback for emqx_gateway_impl
-export([
    on_gateway_load/2,
    on_gateway_update/3,
    on_gateway_unload/2
]).

-import(
    emqx_gateway_utils,
    [
        normalize_config/1,
        start_listeners/4,
        stop_listeners/2,
        update_gateway/5
    ]
).

-define(MOD_CFG, #{
    frame_mod => emqx_coap_frame,
    chann_mod => emqx_coap_channel
}).

%%--------------------------------------------------------------------
%% emqx_gateway_impl callbacks
%%--------------------------------------------------------------------

on_gateway_load(
    _Gateway = #{
        name := GwName,
        config := Config
    },
    Ctx
) ->
    Listeners = normalize_config(Config),
    ModCfg = maps:merge(connection_opts(Config), ?MOD_CFG),
    case
        start_listeners(
            Listeners, GwName, Ctx, ModCfg
        )
    of
        {ok, ListenerPids} ->
            {ok, ListenerPids, #{ctx => Ctx}};
        {error, {Reason, Listener}} ->
            throw(
                {badconf, #{
                    key => listeners,
                    value => Listener,
                    reason => Reason
                }}
            )
    end.

on_gateway_update(Config, Gateway = #{config := OldConfig}, GwState = #{ctx := Ctx}) ->
    GwName = maps:get(name, Gateway),
    try
        ModCfg = maps:merge(connection_opts(Config), ?MOD_CFG),
        {ok, NewPids} = update_gateway(Config, OldConfig, GwName, Ctx, ModCfg),
        {ok, NewPids, GwState}
    catch
        Class:Reason:Stk ->
            logger:error(
                "Failed to update ~ts; "
                "reason: {~0p, ~0p} stacktrace: ~0p",
                [GwName, Class, Reason, Stk]
            ),
            {error, Reason}
    end.

on_gateway_unload(
    _Gateway = #{
        name := GwName,
        config := Config
    },
    _GwState
) ->
    Listeners = normalize_config(Config),
    stop_listeners(GwName, Listeners).

connection_opts(#{connection_required := false}) ->
    #{};
connection_opts(_) ->
    #{
        connection_mod => esockd_udp_proxy,
        esockd_proxy_opts => #{
            connection_mod => emqx_coap_proxy_conn
        }
    }.
