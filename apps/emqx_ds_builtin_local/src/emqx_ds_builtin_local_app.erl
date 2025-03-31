%%--------------------------------------------------------------------
%% Copyright (c) 2024-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------
-module(emqx_ds_builtin_local_app).

%% API:
-export([]).

%% behavior callbacks:
-export([start/2]).

%%================================================================================
%% behavior callbacks
%%================================================================================

start(_StartType, _StartArgs) ->
    emqx_ds:register_backend(builtin_local, emqx_ds_builtin_local),
    emqx_ds_builtin_local_sup:start_top().

%%================================================================================
%% Internal exports
%%================================================================================

%%================================================================================
%% Internal functions
%%================================================================================
