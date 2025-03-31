%%--------------------------------------------------------------------
%% Copyright (c) 2022-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------
-module(emqx_mgmt_api_plugins_proto_v2).

-behaviour(emqx_bpapi).

-export([
    introduced_in/0,
    get_plugins/1,
    install_package/3,
    describe_package/2,
    delete_package/1,
    ensure_action/2
]).

-include_lib("emqx/include/bpapi.hrl").

introduced_in() ->
    "5.1.0".

-spec get_plugins([node()]) -> emqx_rpc:multicall_result().
get_plugins(Nodes) ->
    rpc:multicall(Nodes, emqx_mgmt_api_plugins, get_plugins, [], 15000).

-spec install_package([node()], binary() | string(), binary()) -> emqx_rpc:multicall_result().
install_package(Nodes, Filename, Bin) ->
    rpc:multicall(Nodes, emqx_mgmt_api_plugins, install_package, [Filename, Bin], 25000).

-spec describe_package([node()], binary() | string()) -> emqx_rpc:multicall_result().
describe_package(Nodes, Name) ->
    rpc:multicall(Nodes, emqx_mgmt_api_plugins, describe_package, [Name], 10000).

-spec delete_package(binary() | string()) -> ok | {error, any()}.
delete_package(Name) ->
    emqx_cluster_rpc:multicall(emqx_mgmt_api_plugins, delete_package, [Name], all, 10000).

-spec ensure_action(binary() | string(), 'restart' | 'start' | 'stop') -> ok | {error, any()}.
ensure_action(Name, Action) ->
    emqx_cluster_rpc:multicall(emqx_mgmt_api_plugins, ensure_action, [Name, Action], all, 10000).
