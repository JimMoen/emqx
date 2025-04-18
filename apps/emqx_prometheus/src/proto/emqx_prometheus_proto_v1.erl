%%--------------------------------------------------------------------
%% Copyright (c) 2022-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_prometheus_proto_v1).

-behaviour(emqx_bpapi).

-export([
    introduced_in/0,
    deprecated_since/0,
    start/1,
    stop/1
]).

-include_lib("emqx/include/bpapi.hrl").

deprecated_since() -> "5.0.10".

introduced_in() ->
    "5.0.0".

-spec start([node()]) -> emqx_rpc:multicall_result().
start(Nodes) ->
    rpc:multicall(Nodes, emqx_prometheus, do_start, [], 5000).

-spec stop([node()]) -> emqx_rpc:multicall_result().
stop(Nodes) ->
    rpc:multicall(Nodes, emqx_prometheus, do_stop, [], 5000).
