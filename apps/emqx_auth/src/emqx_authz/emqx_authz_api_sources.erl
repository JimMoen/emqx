%%--------------------------------------------------------------------
%% Copyright (c) 2020-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------

-module(emqx_authz_api_sources).

-behaviour(minirest_api).

-include("emqx_authz.hrl").
-include_lib("emqx/include/logger.hrl").
-include_lib("hocon/include/hoconsc.hrl").

-import(hoconsc, [mk/1, mk/2, ref/2, enum/1]).

-define(BAD_REQUEST, 'BAD_REQUEST').
-define(NOT_FOUND, 'NOT_FOUND').

-define(join(List), lists:join(", ", List)).

-export([
    get_raw_sources/0,
    get_raw_source/1,
    source_status/2,
    lookup_from_local_node/1,
    lookup_from_all_nodes/1
]).

-export([
    api_spec/0,
    paths/0,
    schema/1,
    fields/1,
    namespace/0
]).

-export([
    sources/2,
    source/2,
    source_move/2,
    sources_order/2,
    aggregate_metrics/1
]).

-export([with_source/2]).

-define(TAGS, [<<"Authorization">>]).

namespace() ->
    undefined.

api_spec() ->
    emqx_dashboard_swagger:spec(?MODULE, #{check_schema => true}).

paths() ->
    [
        "/authorization/sources",
        "/authorization/sources/:type",
        "/authorization/sources/:type/status",
        "/authorization/sources/:type/move",
        "/authorization/sources/order"
    ].

fields(sources) ->
    emqx_authz_schema:sources_fields();
fields(position) ->
    [
        {position,
            mk(
                string(),
                #{
                    desc => ?DESC(position),
                    required => true,
                    in => body
                }
            )}
    ];
fields(request_sources_order) ->
    [
        {type,
            mk(enum(emqx_authz_schema:source_types()), #{
                desc => ?DESC(source_type),
                required => true,
                example => "file"
            })}
    ].

%%--------------------------------------------------------------------
%% Schema for each URI
%%--------------------------------------------------------------------
schema("/authorization/sources") ->
    #{
        'operationId' => sources,
        get =>
            #{
                description => ?DESC(authorization_sources_get),
                tags => ?TAGS,
                responses =>
                    #{
                        200 => ref(?MODULE, sources)
                    }
            },
        post =>
            #{
                description => ?DESC(authorization_sources_post),
                tags => ?TAGS,
                'requestBody' => mk(
                    emqx_authz_schema:api_source_type(),
                    #{desc => ?DESC(source_config)}
                ),
                responses =>
                    #{
                        204 => <<"Authorization source created successfully">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST],
                            <<"Bad Request">>
                        )
                    }
            }
    };
schema("/authorization/sources/:type") ->
    #{
        'operationId' => source,
        get =>
            #{
                description => ?DESC(authorization_sources_type_get),
                tags => ?TAGS,
                parameters => parameters_field(),
                responses =>
                    #{
                        200 => mk(
                            emqx_authz_schema:api_source_type(),
                            #{desc => ?DESC(source)}
                        ),
                        404 => emqx_dashboard_swagger:error_codes([?NOT_FOUND], <<"Not Found">>)
                    }
            },
        put =>
            #{
                description => ?DESC(authorization_sources_type_put),
                tags => ?TAGS,
                parameters => parameters_field(),
                'requestBody' => mk(emqx_authz_schema:api_source_type()),
                responses =>
                    #{
                        204 => <<"Authorization source updated successfully">>,
                        400 => emqx_dashboard_swagger:error_codes([?BAD_REQUEST], <<"Bad Request">>)
                    }
            },
        delete =>
            #{
                description => ?DESC(authorization_sources_type_delete),
                tags => ?TAGS,
                parameters => parameters_field(),
                responses =>
                    #{
                        204 => <<"Deleted successfully">>,
                        400 => emqx_dashboard_swagger:error_codes([?BAD_REQUEST], <<"Bad Request">>)
                    }
            }
    };
schema("/authorization/sources/:type/status") ->
    #{
        'operationId' => source_status,
        get =>
            #{
                description => ?DESC(authorization_sources_type_status_get),
                tags => ?TAGS,
                parameters => parameters_field(),
                responses =>
                    #{
                        200 => emqx_dashboard_swagger:schema_with_examples(
                            hoconsc:ref(emqx_authz_schema, "metrics_status_fields"),
                            status_metrics_example()
                        ),
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad request">>
                        ),
                        404 => emqx_dashboard_swagger:error_codes([?NOT_FOUND], <<"Not Found">>)
                    }
            }
    };
schema("/authorization/sources/:type/move") ->
    #{
        'operationId' => source_move,
        post =>
            #{
                description => ?DESC(authorization_sources_type_move_post),
                tags => ?TAGS,
                parameters => parameters_field(),
                'requestBody' =>
                    emqx_dashboard_swagger:schema_with_examples(
                        ref(?MODULE, position),
                        position_example()
                    ),
                responses =>
                    #{
                        204 => <<"No Content">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad Request">>
                        ),
                        404 => emqx_dashboard_swagger:error_codes([?NOT_FOUND], <<"Not Found">>)
                    }
            }
    };
schema("/authorization/sources/order") ->
    #{
        'operationId' => sources_order,
        put => #{
            tags => ?TAGS,
            description => ?DESC(authorization_sources_order_put),
            'requestBody' => mk(
                hoconsc:array(ref(?MODULE, request_sources_order)),
                #{}
            ),
            responses => #{
                204 => <<"Authorization sources order updated">>,
                400 => emqx_dashboard_swagger:error_codes([?BAD_REQUEST], <<"Bad Request">>)
            }
        }
    }.

%%--------------------------------------------------------------------
%% Operation functions
%%--------------------------------------------------------------------

sources(Method, #{bindings := #{type := Type} = Bindings} = Req) when
    is_atom(Type)
->
    sources(Method, Req#{bindings => Bindings#{type => atom_to_binary(Type, utf8)}});
sources(get, _) ->
    Sources = lists:foldl(
        fun(Source0, AccIn) ->
            try emqx_authz:maybe_read_source_files(Source0) of
                Source1 ->
                    Source2 = emqx_utils:redact(Source1),
                    lists:append(AccIn, [Source2])
            catch
                _Error:_Reason ->
                    lists:append(AccIn, [Source0])
            end
        end,
        [],
        get_raw_sources()
    ),
    {200, #{sources => Sources}};
sources(post, #{body := Body}) ->
    update_config(?CMD_PREPEND, Body).

source(Method, #{bindings := #{type := Type} = Bindings} = Req) when
    is_atom(Type)
->
    source(Method, Req#{bindings => Bindings#{type => atom_to_binary(Type, utf8)}});
source(get, #{bindings := #{type := Type}}) ->
    with_source(
        Type,
        fun(Source0) ->
            try emqx_authz:maybe_read_source_files(Source0) of
                Source1 ->
                    Source2 = emqx_utils:redact(Source1),
                    {200, Source2}
            catch
                _Error:Reason ->
                    {500, #{
                        code => <<"INTERNAL_ERROR">>,
                        message => bin(Reason)
                    }}
            end
        end
    );
source(put, #{bindings := #{type := Type}, body := #{<<"type">> := Type} = Body}) ->
    with_source(
        Type,
        fun(RawConf) ->
            Conf = emqx_utils:deobfuscate(Body, RawConf),
            update_config({?CMD_REPLACE, Type}, Conf)
        end
    );
source(put, #{bindings := #{type := Type}, body := #{<<"type">> := _OtherType}}) ->
    with_source(
        Type,
        fun(_) ->
            {400, #{code => <<"BAD_REQUEST">>, message => <<"Type mismatch">>}}
        end
    );
source(delete, #{bindings := #{type := Type}}) ->
    with_source(
        Type,
        fun(_) ->
            update_config({?CMD_DELETE, Type}, #{})
        end
    ).

source_status(get, #{bindings := #{type := Type}}) ->
    with_source(
        atom_to_binary(Type, utf8),
        fun(_) -> lookup_from_all_nodes(Type) end
    ).

source_move(Method, #{bindings := #{type := Type} = Bindings} = Req) when
    is_atom(Type)
->
    source_move(Method, Req#{bindings => Bindings#{type => atom_to_binary(Type, utf8)}});
source_move(post, #{bindings := #{type := Type}, body := #{<<"position">> := Position}}) ->
    with_source(
        Type,
        fun(_Source) ->
            case parse_position(Position) of
                {ok, NPosition} ->
                    try emqx_authz:move(Type, NPosition) of
                        {ok, _} ->
                            {204};
                        {error, {not_found_source, _Type}} ->
                            {404, #{
                                code => <<"NOT_FOUND">>,
                                message => <<"source ", Type/binary, " not found">>
                            }};
                        {error, {emqx_conf_schema, _}} ->
                            {400, #{
                                code => <<"BAD_REQUEST">>,
                                message => <<"BAD_SCHEMA">>
                            }};
                        {error, Reason} ->
                            {400, #{
                                code => <<"BAD_REQUEST">>,
                                message => bin(Reason)
                            }}
                    catch
                        error:{unknown_authz_source_type, Unknown} ->
                            NUnknown = bin(Unknown),
                            {400, #{
                                code => <<"BAD_REQUEST">>,
                                message => <<"Unknown authz Source Type: ", NUnknown/binary>>
                            }}
                    end;
                {error, Reason} ->
                    {400, #{
                        code => <<"BAD_REQUEST">>,
                        message => bin(Reason)
                    }}
            end
        end
    ).

sources_order(put, #{body := AuthzOrder}) ->
    SourcesOrder = [Type || #{<<"type">> := Type} <- AuthzOrder],
    case emqx_authz:reorder(SourcesOrder) of
        {ok, _} ->
            {204};
        {error, {_PrePostConfUpd, _, #{not_found := NotFound, not_reordered := NotReordered}}} ->
            NotFoundFmt = "Authorization sources: ~ts are not found",
            NotReorderedFmt = "No positions are specified for authorization sources: ~ts",
            Msg =
                case {NotFound, NotReordered} of
                    {[_ | _], []} ->
                        binfmt(NotFoundFmt, [?join(NotFound)]);
                    {[], [_ | _]} ->
                        binfmt(NotReorderedFmt, [?join(NotReordered)]);
                    _ ->
                        binfmt(NotFoundFmt ++ ", " ++ NotReorderedFmt, [
                            ?join(NotFound), ?join(NotReordered)
                        ])
                end,
            {400, #{code => <<"BAD_REQUEST">>, message => Msg}};
        {error, Reason} ->
            {400, #{code => <<"BAD_REQUEST">>, message => bin(Reason)}}
    end.

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

lookup_from_local_node(Type) ->
    NodeId = node(self()),
    try emqx_authz:lookup_state(Type) of
        #{resource_id := ResourceId} ->
            Metrics = emqx_metrics_worker:get_metrics(authz_metrics, Type),
            case emqx_resource:get_instance(ResourceId) of
                {error, not_found} ->
                    {error, {NodeId, not_found_resource}};
                {ok, _, #{status := Status}} ->
                    {ok, {NodeId, Status, Metrics, emqx_resource:get_metrics(ResourceId)}}
            end;
        _ ->
            Metrics = emqx_metrics_worker:get_metrics(authz_metrics, Type),
            %% for authz file/authz mnesia
            {ok, {NodeId, connected, Metrics, #{}}}
    catch
        _:Reason -> {error, {NodeId, list_to_binary(io_lib:format("~p", [Reason]))}}
    end.

lookup_from_all_nodes(Type) ->
    Nodes = mria:running_nodes(),
    case is_ok(emqx_authz_proto_v1:lookup_from_all_nodes(Nodes, Type)) of
        {ok, ResList} ->
            {StatusMap, MetricsMap, ResourceMetricsMap, ErrorMap} = make_result_map(ResList),
            AggregateStatus = aggregate_status(maps:values(StatusMap)),
            AggregateMetrics = aggregate_metrics(maps:values(MetricsMap)),
            AggregateResourceMetrics = aggregate_metrics(maps:values(ResourceMetricsMap)),
            Fun = fun(_, V1) -> restructure_map(V1) end,
            MKMap = fun(Name) -> fun({Key, Val}) -> #{node => Key, Name => Val} end end,
            HelpFun = fun(M, Name) -> lists:map(MKMap(Name), maps:to_list(M)) end,
            {200, #{
                node_resource_metrics => HelpFun(maps:map(Fun, ResourceMetricsMap), metrics),
                resource_metrics =>
                    case maps:size(AggregateResourceMetrics) of
                        0 -> #{};
                        _ -> restructure_map(AggregateResourceMetrics)
                    end,
                node_metrics => HelpFun(maps:map(Fun, MetricsMap), metrics),
                metrics => restructure_map(AggregateMetrics),

                node_status => HelpFun(StatusMap, status),
                status => AggregateStatus,
                node_error => HelpFun(maps:map(Fun, ErrorMap), reason)
            }};
        {error, ErrL} ->
            {400, #{
                code => <<"INTERNAL_ERROR">>,
                message => bin_t(io_lib:format("~p", [ErrL]))
            }}
    end.

aggregate_status([]) ->
    empty_metrics_and_status;
aggregate_status(AllStatus) ->
    Head = fun([A | _]) -> A end,
    HeadVal = Head(AllStatus),
    AllRes = lists:all(fun(Val) -> Val == HeadVal end, AllStatus),
    case AllRes of
        true -> HeadVal;
        false -> inconsistent
    end.

aggregate_metrics([]) ->
    #{};
aggregate_metrics([HeadMetrics | AllMetrics]) ->
    ErrorLogger = fun(Reason) -> ?SLOG(info, #{msg => "bad_metrics_value", error => Reason}) end,
    Fun = fun(ElemMap, AccMap) ->
        emqx_utils_maps:best_effort_recursive_sum(AccMap, ElemMap, ErrorLogger)
    end,
    lists:foldl(Fun, HeadMetrics, AllMetrics).

make_result_map(ResList) ->
    Fun =
        fun(Elem, {StatusMap, MetricsMap, ResourceMetricsMap, ErrorMap}) ->
            case Elem of
                {ok, {NodeId, Status, Metrics, ResourceMetrics}} ->
                    {
                        maps:put(NodeId, Status, StatusMap),
                        maps:put(NodeId, Metrics, MetricsMap),
                        maps:put(NodeId, ResourceMetrics, ResourceMetricsMap),
                        ErrorMap
                    };
                {error, {NodeId, Reason}} ->
                    {StatusMap, MetricsMap, ResourceMetricsMap, maps:put(NodeId, Reason, ErrorMap)}
            end
        end,
    lists:foldl(Fun, {maps:new(), maps:new(), maps:new(), maps:new()}, ResList).

restructure_map(#{
    counters := #{
        ignore := Ignore,
        deny := Failed,
        total := Total,
        allow := Succ,
        nomatch := Nomatch
    },
    rate := #{total := #{current := Rate, last5m := Rate5m, max := RateMax}}
}) ->
    #{
        total => Total,
        allow => Succ,
        deny => Failed,
        nomatch => Nomatch,
        ignore => Ignore,
        rate => Rate,
        rate_last5m => Rate5m,
        rate_max => RateMax
    };
restructure_map(#{
    counters := #{failed := Failed, matched := Match, success := Succ},
    rate := #{matched := #{current := Rate, last5m := Rate5m, max := RateMax}}
}) ->
    #{
        matched => Match,
        success => Succ,
        failed => Failed,
        rate => Rate,
        rate_last5m => Rate5m,
        rate_max => RateMax
    };
restructure_map(Error) ->
    Error.

bin_t(S) when is_list(S) ->
    list_to_binary(S).

is_ok(ResL) ->
    case
        lists:filter(
            fun
                ({ok, _}) -> false;
                (_) -> true
            end,
            ResL
        )
    of
        [] -> {ok, [Res || {ok, Res} <- ResL]};
        ErrL -> {error, ErrL}
    end.

get_raw_sources() ->
    RawSources = emqx:get_raw_config([authorization, sources], []),
    Schema = emqx_hocon:make_schema(emqx_authz_schema:authz_fields()),
    Conf = #{<<"sources">> => RawSources},
    #{<<"sources">> := Sources} = hocon_tconf:make_serializable(Schema, Conf, #{}),
    format_for_api(Sources).

format_for_api(Sources) ->
    lists:map(fun emqx_authz:format_for_api/1, Sources).

get_raw_source(Type) ->
    lists:filter(
        fun(#{<<"type">> := T}) ->
            T =:= Type
        end,
        get_raw_sources()
    ).

-spec with_source(binary(), fun((map()) -> term())) -> term().
with_source(Type, ContF) ->
    case get_raw_source(Type) of
        [] ->
            {404, #{code => <<"NOT_FOUND">>, message => <<"Not found: ", Type/binary>>}};
        [Source] ->
            ContF(Source)
    end.

update_config(Cmd, Sources) ->
    case emqx_authz:update(Cmd, Sources) of
        {ok, _} ->
            {204};
        {error, {pre_config_update, emqx_authz, Reason}} ->
            {400, #{
                code => <<"BAD_REQUEST">>,
                message => bin(Reason)
            }};
        {error, {post_config_update, emqx_authz, Reason}} ->
            {400, #{
                code => <<"BAD_REQUEST">>,
                message => bin(Reason)
            }};
        %% TODO: The `Reason` may cann't be trans to json term. (i.e. ecpool start failed)
        {error, {emqx_conf_schema, _}} ->
            {400, #{
                code => <<"BAD_REQUEST">>,
                message => <<"BAD_SCHEMA">>
            }};
        {error, Reason} ->
            {400, #{
                code => <<"BAD_REQUEST">>,
                message => bin(Reason)
            }}
    end.

parameters_field() ->
    [
        {type,
            mk(
                enum(emqx_authz_schema:source_types()),
                #{in => path, desc => ?DESC(source_type)}
            )}
    ].

parse_position(<<"front">>) ->
    {ok, ?CMD_MOVE_FRONT};
parse_position(<<"rear">>) ->
    {ok, ?CMD_MOVE_REAR};
parse_position(<<"before:">>) ->
    {error, <<"Invalid parameter. Cannot be placed before an empty target">>};
parse_position(<<"after:">>) ->
    {error, <<"Invalid parameter. Cannot be placed after an empty target">>};
parse_position(<<"before:", Before/binary>>) ->
    {ok, ?CMD_MOVE_BEFORE(Before)};
parse_position(<<"after:", After/binary>>) ->
    {ok, ?CMD_MOVE_AFTER(After)};
parse_position(_) ->
    {error, <<"Invalid parameter. Unknow position">>}.

position_example() ->
    #{
        front =>
            #{
                summary => <<"front example">>,
                value => #{<<"position">> => <<"front">>}
            },
        rear =>
            #{
                summary => <<"rear example">>,
                value => #{<<"position">> => <<"rear">>}
            },
        relative_before =>
            #{
                summary => <<"relative example">>,
                value => #{<<"position">> => <<"before:file">>}
            },
        relative_after =>
            #{
                summary => <<"relative example">>,
                value => #{<<"position">> => <<"after:file">>}
            }
    }.

bin(Term) -> binfmt("~p", [Term]).

binfmt(Fmt, Args) -> iolist_to_binary(io_lib:format(Fmt, Args)).

status_metrics_example() ->
    #{
        'metrics_example' => #{
            summary => <<"Showing a typical metrics example">>,
            value =>
                #{
                    resource_metrics => #{
                        matched => 0,
                        success => 0,
                        failed => 0,
                        rate => 0.0,
                        rate_last5m => 0.0,
                        rate_max => 0.0
                    },
                    node_resource_metrics => [
                        #{
                            node => node(),
                            metrics => #{
                                matched => 0,
                                success => 0,
                                failed => 0,
                                rate => 0.0,
                                rate_last5m => 0.0,
                                rate_max => 0.0
                            }
                        }
                    ],
                    metrics => #{
                        total => 0,
                        allow => 0,
                        deny => 0,
                        nomatch => 0,
                        rate => 0.0,
                        rate_last5m => 0.0,
                        rate_max => 0.0
                    },
                    node_metrics => [
                        #{
                            node => node(),
                            metrics => #{
                                total => 0,
                                allow => 0,
                                deny => 0,
                                nomatch => 0,
                                rate => 0.0,
                                rate_last5m => 0.0,
                                rate_max => 0.0
                            }
                        }
                    ],

                    status => connected,
                    node_status => [
                        #{
                            node => node(),
                            status => connected
                        }
                    ]
                }
        }
    }.
