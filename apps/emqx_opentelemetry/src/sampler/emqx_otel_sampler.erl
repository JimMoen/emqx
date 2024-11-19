%%--------------------------------------------------------------------
%% Copyright (c) 2023-2024 EMQ Technologies Co., Ltd. All Rights Reserved.
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
-module(emqx_otel_sampler).

-behaviour(otel_sampler).

-include("emqx_otel_trace.hrl").
-include_lib("emqx/include/logger.hrl").
-include_lib("emqx/include/emqx_mqtt.hrl").
-include_lib("opentelemetry/include/otel_sampler.hrl").
-include_lib("opentelemetry_api/include/opentelemetry.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

-define(EMQX_OTEL_SAMPLE_CLIENTID, 1).
-define(EMQX_OTEL_SAMPLE_USERNAME, 2).
-define(EMQX_OTEL_SAMPLE_TOPIC_NAME, 3).
-define(EMQX_OTEL_SAMPLE_TOPIC_MATCHING, 4).

-define(META_KEY, 'emqx.meta').

-record(?EMQX_OTEL_SAMPLER_RULE, {
    type ::
        {?EMQX_OTEL_SAMPLE_CLIENTID, binary()}
        | {?EMQX_OTEL_SAMPLE_USERNAME, binary()}
        | {?EMQX_OTEL_SAMPLE_TOPIC_NAME, binary()}
        | {?EMQX_OTEL_SAMPLE_TOPIC_MATCHING, binary()},
    should_sample :: boolean(),
    extra :: map()
}).

-export([
    init_tables/0,
    store_rule/3,
    purge_rules/0,
    get_rule/1,
    delete_rule/1,
    list_username_rules/0,
    list_clientid_rules/0,
    list_topic_name_rules/0,
    list_topic_matching_rules/0,
    record_count/0
]).

%% OpenTelemetry Sampler Callback
-export([setup/1, description/1, should_sample/7]).

%% 2^64 - 1 =:= (2#1 bsl 64 -1)
-define(MAX_VALUE, 18446744073709551615).

%%--------------------------------------------------------------------
%% Mnesia bootstrap
%%--------------------------------------------------------------------

-spec create_tables() -> [mria:table()].
create_tables() ->
    ok = mria:create_table(
        ?EMQX_OTEL_SAMPLER_RULE,
        [
            {type, ordered_set},
            {storage, disc_copies},
            {local_content, true},
            {record_name, ?EMQX_OTEL_SAMPLER_RULE},
            {attributes, record_info(fields, ?EMQX_OTEL_SAMPLER_RULE)}
        ]
    ),
    [?EMQX_OTEL_SAMPLER_RULE].

%% Init
-spec init_tables() -> ok.
init_tables() ->
    ok = mria:wait_for_tables(create_tables()).

%% @doc Update sample rule
-spec store_rule(
    {clientid, binary()}
    | {username, binary()}
    | {topic_name, binary()}
    | {topic_matching, binary()},
    boolean(),
    map()
) -> ok.
store_rule({clientid, ClientId}, ShouldSample, Extra) ->
    Record = #?EMQX_OTEL_SAMPLER_RULE{
        type = {?EMQX_OTEL_SAMPLE_CLIENTID, ClientId},
        should_sample = ShouldSample,
        extra = Extra
    },
    mria:dirty_write(Record);
store_rule({username, Username}, ShouldSample, Extra) ->
    Record = #?EMQX_OTEL_SAMPLER_RULE{
        type = {?EMQX_OTEL_SAMPLE_USERNAME, Username},
        should_sample = ShouldSample,
        extra = Extra
    },
    mria:dirty_write(Record);
store_rule({topic_name, TopicName}, ShouldSample, Extra) ->
    Record = #?EMQX_OTEL_SAMPLER_RULE{
        type = {?EMQX_OTEL_SAMPLE_TOPIC_NAME, TopicName},
        should_sample = ShouldSample,
        extra = Extra
    },
    mria:dirty_write(Record);
store_rule({topic_matching, TopicFilter}, ShouldSample, Extra) ->
    Record = #?EMQX_OTEL_SAMPLER_RULE{
        type = {?EMQX_OTEL_SAMPLE_TOPIC_MATCHING, TopicFilter},
        should_sample = ShouldSample,
        extra = Extra
    },
    mria:dirty_write(Record).

-spec purge_rules() -> ok.
purge_rules() ->
    ok = lists:foreach(
        fun(Key) ->
            ok = mria:dirty_delete(?EMQX_OTEL_SAMPLER_RULE, Key)
        end,
        mnesia:dirty_all_keys(?EMQX_OTEL_SAMPLER_RULE)
    ).

get_rule({clientid, ClientId}) ->
    do_get_rule({?EMQX_OTEL_SAMPLE_CLIENTID, ClientId});
get_rule({username, Username}) ->
    do_get_rule({?EMQX_OTEL_SAMPLE_USERNAME, Username});
get_rule({topic_name, TopicName}) ->
    do_get_rule({?EMQX_OTEL_SAMPLE_TOPIC_NAME, TopicName});
get_rule({topic_matching, TopicFilter}) ->
    do_get_rule({?EMQX_OTEL_SAMPLE_TOPIC_MATCHING, TopicFilter}).

do_get_rule(Key) ->
    case mnesia:dirty_read(?EMQX_OTEL_SAMPLER_RULE, Key) of
        [#?EMQX_OTEL_SAMPLER_RULE{should_sample = ShouldSample}] -> {ok, ShouldSample};
        [] -> not_found
    end.

delete_rule({clientid, ClientId}) ->
    mria:dirty_delete(?EMQX_OTEL_SAMPLER_RULE, {?EMQX_OTEL_SAMPLE_CLIENTID, ClientId});
delete_rule({username, Username}) ->
    mria:dirty_delete(?EMQX_OTEL_SAMPLER_RULE, {?EMQX_OTEL_SAMPLE_USERNAME, Username});
delete_rule({topic_name, TopicName}) ->
    mria:dirty_delete(?EMQX_OTEL_SAMPLER_RULE, {?EMQX_OTEL_SAMPLE_TOPIC_NAME, TopicName});
delete_rule({topic_matching, TopicFilter}) ->
    mria:dirty_delete(?EMQX_OTEL_SAMPLER_RULE, {?EMQX_OTEL_SAMPLE_TOPIC_MATCHING, TopicFilter}).

-spec list_clientid_rules() -> ets:match_spec().
list_clientid_rules() ->
    ets:fun2ms(
        fun(
            #?EMQX_OTEL_SAMPLER_RULE{
                type = {?EMQX_OTEL_SAMPLE_CLIENTID, ClientId},
                should_sample = ShouldSample
            }
        ) ->
            [{clientid, ClientId}, {should_sample, ShouldSample}]
        end
    ).

-spec list_username_rules() -> ets:match_spec().
list_username_rules() ->
    ets:fun2ms(
        fun(
            #?EMQX_OTEL_SAMPLER_RULE{
                type = {?EMQX_OTEL_SAMPLE_USERNAME, Username},
                should_sample = ShouldSample
            }
        ) ->
            [{username, Username}, {should_sample, ShouldSample}]
        end
    ).

-spec list_topic_name_rules() -> ets:match_spec().
list_topic_name_rules() ->
    ets:fun2ms(
        fun(
            #?EMQX_OTEL_SAMPLER_RULE{
                type = {?EMQX_OTEL_SAMPLE_TOPIC_NAME, TopicName},
                should_sample = ShouldSample,
                extra = '_'
            }
        ) ->
            [{topic_name, TopicName}, {should_sample, ShouldSample}]
        end
    ).

-spec list_topic_matching_rules() -> ets:match_spec().
list_topic_matching_rules() ->
    ets:fun2ms(
        fun(
            #?EMQX_OTEL_SAMPLER_RULE{
                type = {?EMQX_OTEL_SAMPLE_TOPIC_MATCHING, TopicFilter},
                should_sample = ShouldSample
            }
        ) ->
            [{topic_matching, TopicFilter}, {should_sample, ShouldSample}]
        end
    ).

-spec record_count() -> non_neg_integer().
record_count() ->
    mnesia:table_info(?EMQX_OTEL_SAMPLER_RULE, size).

%%--------------------------------------------------------------------
%% OpenTelemetry Sampler Callback
%%--------------------------------------------------------------------

setup(
    #{
        mqtt_publish_trace_level := Level,
        sample_ratio := Ratio
    } = InitOpts
) ->
    IdUpper =
        case Ratio of
            R when R =:= +0.0 ->
                0;
            R when R =:= 1.0 ->
                ?MAX_VALUE;
            R when R >= 0.0 andalso R =< 1.0 ->
                trunc(R * ?MAX_VALUE)
        end,

    Opts = (maps:with(
        [
            client_connect,
            client_disconnect,
            client_subscribe,
            client_unsubscribe,
            client_publish,
            attribute_meta_value
        ],
        InitOpts
    ))#{
        response_trace_qos => level_to_qos(Level),
        id_upper => IdUpper
    },

    ?SLOG(debug, #{
        msg => "emqx_otel_sampler_setup",
        opts => Opts
    }),

    Opts.

-compile({inline, [level_to_qos/1]}).
level_to_qos(basic) -> ?QOS_0;
level_to_qos(first_ack) -> ?QOS_1;
level_to_qos(all) -> ?QOS_2.

%% TODO: description
description(_Opts) ->
    <<"AttributeSampler">>.

%% TODO: remote sampled
should_sample(
    Ctx,
    TraceId,
    _Links,
    SpanName,
    _SpanKind,
    Attributes,
    #{
        attribute_meta_value := MetaValue
    } = Opts
) when
    SpanName =:= ?CLIENT_CONNECT_SPAN_NAME orelse
        SpanName =:= ?CLIENT_DISCONNECT_SPAN_NAME orelse
        SpanName =:= ?CLIENT_SUBSCRIBE_SPAN_NAME orelse
        SpanName =:= ?CLIENT_UNSUBSCRIBE_SPAN_NAME orelse
        SpanName =:= ?CLIENT_PUBLISH_SPAN_NAME
->
    Desicion =
        decide_by_match_rule(Attributes, Opts) orelse
            decide_by_traceid_ratio(TraceId, SpanName, Opts),
    {
        decide(Desicion),
        #{?META_KEY => MetaValue},
        otel_span:tracestate(otel_tracer:current_span_ctx(Ctx))
    };
%% None Root Span, decide by Parent or Publish Response Tracing Level
should_sample(
    Ctx,
    _TraceId,
    _Links,
    SpanName,
    _SpanKind,
    _Attributes,
    #{
        response_trace_qos := QoS,
        attribute_meta_value := MetaValue
    } = _Opts
) ->
    Desicion =
        parent_sampled(otel_tracer:current_span_ctx(Ctx)) andalso
            match_by_span_name(SpanName, QoS),
    {
        decide(Desicion),
        #{?META_KEY => MetaValue},
        otel_span:tracestate(otel_tracer:current_span_ctx(Ctx))
    }.

-compile({inline, [match_by_span_name/2]}).
match_by_span_name(?BROKER_PUBACK_SPAN_NAME, TraceQoS) -> ?QOS_1 =< TraceQoS;
match_by_span_name(?CLIENT_PUBACK_SPAN_NAME, TraceQoS) -> ?QOS_1 =< TraceQoS;
match_by_span_name(?BROKER_PUBREC_SPAN_NAME, TraceQoS) -> ?QOS_1 =< TraceQoS;
match_by_span_name(?CLIENT_PUBREC_SPAN_NAME, TraceQoS) -> ?QOS_1 =< TraceQoS;
match_by_span_name(?BROKER_PUBREL_SPAN_NAME, TraceQoS) -> ?QOS_2 =< TraceQoS;
match_by_span_name(?CLIENT_PUBREL_SPAN_NAME, TraceQoS) -> ?QOS_2 =< TraceQoS;
match_by_span_name(?BROKER_PUBCOMP_SPAN_NAME, TraceQoS) -> ?QOS_2 =< TraceQoS;
match_by_span_name(?CLIENT_PUBCOMP_SPAN_NAME, TraceQoS) -> ?QOS_2 =< TraceQoS;
%% other sub spans, sample by parent, set mask as true
match_by_span_name(_, _) -> true.

decide_by_match_rule(Attributes, _) ->
    by_clientid(Attributes) orelse
        by_message_from(Attributes) orelse
        by_username(Attributes) orelse
        by_topic_name(Attributes) orelse
        by_topic_filter(Attributes).

decide_by_traceid_ratio(_, _, #{id_upper := ?MAX_VALUE}) ->
    true;
decide_by_traceid_ratio(TraceId, SpanName, #{id_upper := IdUpperBound} = Opts) ->
    case maps:get(span_name_to_config_key(SpanName), Opts, false) of
        true ->
            Lower64Bits = TraceId band ?MAX_VALUE,
            Lower64Bits =< IdUpperBound;
        false ->
            %% Event ration sampler not enabled.
            false
    end.

span_name_to_config_key(?CLIENT_CONNECT_SPAN_NAME) ->
    client_connect;
span_name_to_config_key(?CLIENT_DISCONNECT_SPAN_NAME) ->
    client_disconnect;
span_name_to_config_key(?CLIENT_SUBSCRIBE_SPAN_NAME) ->
    client_subscribe;
span_name_to_config_key(?CLIENT_UNSUBSCRIBE_SPAN_NAME) ->
    client_unsubscribe;
span_name_to_config_key(?CLIENT_PUBLISH_SPAN_NAME) ->
    client_publish.

by_clientid(#{'client.clientid' := ClientId}) ->
    read_should_sample({?EMQX_OTEL_SAMPLE_CLIENTID, ClientId});
by_clientid(_) ->
    false.

by_message_from(#{'message.from' := ClientId}) ->
    read_should_sample({?EMQX_OTEL_SAMPLE_CLIENTID, ClientId});
by_message_from(_) ->
    false.

by_username(#{'client.username' := Username}) ->
    read_should_sample({?EMQX_OTEL_SAMPLE_USERNAME, Username});
by_username(_) ->
    false.

by_topic_name(#{'message.topic' := TopicName}) ->
    read_should_sample({?EMQX_OTEL_SAMPLE_TOPIC_NAME, TopicName});
by_topic_name(_) ->
    false.

-dialyzer({nowarn_function, by_topic_filter/1}).
by_topic_filter(#{'message.topic' := TopicName}) ->
    case
        mnesia:dirty_match_object(#?EMQX_OTEL_SAMPLER_RULE{
            type = {?EMQX_OTEL_SAMPLE_TOPIC_MATCHING, '_'},
            _ = '_'
        })
    of
        [] ->
            false;
        Rules ->
            lists:any(
                fun(Rule) -> match_topic_filter(TopicName, Rule) end, Rules
            )
    end;
by_topic_filter(_) ->
    false.

read_should_sample(Key) ->
    case mnesia:dirty_read(?EMQX_OTEL_SAMPLER_RULE, Key) of
        [] -> false;
        [#?EMQX_OTEL_SAMPLER_RULE{should_sample = ShouldSample}] -> ShouldSample
    end.

-dialyzer({nowarn_function, match_topic_filter/2}).
match_topic_filter(TopicName, #?EMQX_OTEL_SAMPLER_RULE{
    type = {?EMQX_OTEL_SAMPLE_TOPIC_MATCHING, TopicFilter},
    should_sample = ShouldSample
}) ->
    emqx_topic:match(TopicName, TopicFilter) andalso ShouldSample.

-compile({inline, [parent_sampled/1]}).
parent_sampled(#span_ctx{trace_flags = TraceFlags}) when
    ?IS_SAMPLED(TraceFlags)
->
    true;
parent_sampled(_) ->
    false.

-compile({inline, [decide/1]}).
decide(true) ->
    ?RECORD_AND_SAMPLE;
decide(false) ->
    ?DROP.
