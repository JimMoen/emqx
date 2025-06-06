%%--------------------------------------------------------------------
%% Copyright (c) 2020-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------

%% this module is only intended to be mocked
-module(emqx_connector_dummy_impl).
-behavior(emqx_resource).

-export([
    resource_type/0,
    query_mode/1,
    callback_mode/0,
    on_start/2,
    on_stop/2,
    on_add_channel/4,
    on_get_channel_status/3
]).

resource_type() -> dummy.
query_mode(_) -> error(unexpected).
callback_mode() -> error(unexpected).
on_start(_, _) -> error(unexpected).
on_stop(_, _) -> error(unexpected).
on_add_channel(_, _, _, _) -> error(unexpected).
on_get_channel_status(_, _, _) -> error(unexpected).
