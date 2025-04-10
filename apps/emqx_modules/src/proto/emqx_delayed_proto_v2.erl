%%--------------------------------------------------------------------
%%Copyright (c) 2022-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_delayed_proto_v2).

-behaviour(emqx_bpapi).

-export([
    introduced_in/0,
    get_delayed_message/2,
    delete_delayed_message/2,

    %% Introduced in v2:
    clear_all/1
]).

-include_lib("emqx/include/bpapi.hrl").

introduced_in() ->
    "5.2.1".

-spec get_delayed_message(node(), binary()) ->
    emqx_delayed:with_id_return(map()) | emqx_rpc:badrpc().
get_delayed_message(Node, Id) ->
    rpc:call(Node, emqx_delayed, get_delayed_message, [Id]).

-spec delete_delayed_message(node(), binary()) -> emqx_delayed:with_id_return() | emqx_rpc:badrpc().
delete_delayed_message(Node, Id) ->
    rpc:call(Node, emqx_delayed, delete_delayed_message, [Id]).

%% Introduced in v2:

-spec clear_all([node()]) -> emqx_rpc:erpc_multicall(ok).
clear_all(Nodes) ->
    erpc:multicall(Nodes, emqx_delayed, clear_all_local, []).
