%%--------------------------------------------------------------------
%% Copyright (c) 2021-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
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

%% @doc This supervisor manages workers which should never need a restart
%% due to config changes or when joining a cluster.
-module(emqx_machine_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Terminator = child_worker(emqx_machine_terminator, [], transient),
    BootApps = child_worker(emqx_machine_boot, post_boot, [], temporary),
    GlobalGC = child_worker(emqx_global_gc, [], permanent),
    ReplicantHealthProbe = child_worker(emqx_machine_replicant_health_probe, [], transient),
    Children = [Terminator, ReplicantHealthProbe, BootApps, GlobalGC],
    SupFlags = #{
        strategy => one_for_one,
        intensity => 100,
        period => 10
    },
    {ok, {SupFlags, Children}}.

child_worker(M, Args, Restart) ->
    child_worker(M, start_link, Args, Restart).

child_worker(M, Func, Args, Restart) ->
    #{
        id => M,
        start => {M, Func, Args},
        restart => Restart,
        shutdown => 5000,
        type => worker,
        modules => [M]
    }.
