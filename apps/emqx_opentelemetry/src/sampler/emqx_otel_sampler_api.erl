%%--------------------------------------------------------------------
%% Copyright (c) 2020-2024 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_otel_sampler_api).

-behaviour(minirest_api).

-include("emqx_otel_trace.hrl").
-include_lib("hocon/include/hoconsc.hrl").
-include_lib("emqx/include/logger.hrl").

-import(hoconsc, [mk/2, ref/1, ref/2, array/1]).

-export([
    namespace/0,
    api_spec/0,
    paths/0,
    schema/1,
    fields/1
]).

%% operation functions
-export([
    %% creating/getting multiple
    users/2,
    username/2,
    clients/2,
    clientid/2,
    topic_names/2,
    topic_name/2,
    topic_matchings/2,
    topic_matching/2,
    %% for specific one

    %% Purge
    purge_sample_rules/2
]).

%% query functions
-export([
    query_username/2,
    query_clientid/2,
    query_topic_name/2,
    query_topic_matching/2,

    run_fuzzy_filter/2,
    format_result/1
]).

-define(QUERY_USERNAME_FUN, fun ?MODULE:query_username/2).
-define(QUERY_CLIENTID_FUN, fun ?MODULE:query_clientid/2).
-define(QUERY_TOPIC_NAME_FUN, fun ?MODULE:query_topic_name/2).
-define(QUERY_TOPIC_MATCHING_FUN, fun ?MODULE:query_topic_matching/2).

-define(SAMPLE_RULE_USERNAME_QSCHEMA, [{<<"like_username">>, binary}]).
-define(SAMPLE_RULE_CLIENTID_QSCHEMA, [{<<"like_clientid">>, binary}]).
-define(SAMPLE_RULE_TOPIC_NAME_QSCHEMA, [{<<"like_topic_name">>, binary}]).
-define(SAMPLE_RULE_TOPIC_MATCHING_QSCHEMA, [{<<"like_topic_matching">>, binary}]).

-define(TYPE_REF, ref).
-define(TYPE_ARRAY, array).
-define(PAGE_QUERY_EXAMPLE, example_in_data).
-define(PUT_MAP_EXAMPLE, in_put_requestBody).
-define(POST_ARRAY_EXAMPLE, in_post_requestBody).

-define(API_TAGS, [<<"Opentelemetry">>]).
-define(BAD_REQUEST, 'BAD_REQUEST').
-define(NOT_FOUND, 'NOT_FOUND').
-define(INTERNAL_ERROR, 'INTERNAL_ERROR').
-define(ALREADY_EXISTS, 'ALREADY_EXISTS').
%% -define(RESP_BAD_REQUEST(MSG), {400, #{code => ?BAD_REQUEST, message => MSG}}).
-define(RESP_INTERNAL_ERROR(MSG), {500, #{code => ?INTERNAL_ERROR, message => MSG}}).

-define(META_EXAMPLE, #{
    page => 1,
    limit => 100,
    count => 1
}).

namespace() -> undefined.

api_spec() ->
    emqx_dashboard_swagger:spec(?MODULE, #{check_schema => true}).

paths() ->
    [
        "/opentelemetry/sample_rules/clients",
        "/opentelemetry/sample_rules/clients/:clientid",
        "/opentelemetry/sample_rules/users",
        "/opentelemetry/sample_rules/users/:username",
        "/opentelemetry/sample_rules/topic_names",
        "/opentelemetry/sample_rules/topic_names/:topic_name",
        "/opentelemetry/sample_rules/topic_matchings",
        "/opentelemetry/sample_rules/topic_matchings/:topic_matching",
        "/opentelemetry/sample_rules"
    ].

schema("/opentelemetry/sample_rules/clients") ->
    #{
        'operationId' => clients,
        get =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(clientid_rules_get),
                parameters =>
                    [
                        ref(emqx_dashboard_swagger, page),
                        ref(emqx_dashboard_swagger, limit),
                        {like_clientid,
                            mk(
                                binary(),
                                #{
                                    in => query,
                                    required => false,
                                    desc => ?DESC(fuzzy_clientid)
                                }
                            )}
                    ],
                responses =>
                    #{
                        200 => swagger_with_example(
                            {clientid_response_data, ?TYPE_REF},
                            {clientid, ?PAGE_QUERY_EXAMPLE}
                        )
                    }
            },
        post =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(clientid_rules_post),
                'requestBody' => swagger_with_example(
                    {sample_rules_for_clientid, ?TYPE_ARRAY},
                    {clientid, ?POST_ARRAY_EXAMPLE}
                ),
                responses =>
                    #{
                        204 => <<"Created">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad clientid or bad rule schema">>
                        )
                    }
            }
    };
schema("/opentelemetry/sample_rules/clients/:clientid") ->
    #{
        'operationId' => clientid,
        get =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(clientid_get),
                parameters => [ref(clientid)],
                responses =>
                    #{
                        200 => swagger_with_example(
                            {sample_rules_for_clientid, ?TYPE_REF},
                            {clientid, ?PUT_MAP_EXAMPLE}
                        ),
                        404 => emqx_dashboard_swagger:error_codes(
                            [?NOT_FOUND], <<"Not Found">>
                        )
                    }
            },
        put =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(clientid_put),
                parameters => [ref(clientid)],
                'requestBody' => swagger_with_example(
                    {sample_rules_for_clientid, ?TYPE_REF},
                    {clientid, ?PUT_MAP_EXAMPLE}
                ),
                responses =>
                    #{
                        204 => <<"Updated">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad clientid or bad rule schema">>
                        )
                    }
            },
        delete =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(clientid_delete),
                parameters => [ref(clientid)],
                responses =>
                    #{
                        204 => <<"Deleted">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad clientid">>
                        ),
                        404 => emqx_dashboard_swagger:error_codes(
                            [?NOT_FOUND], <<"ClientID Not Found">>
                        )
                    }
            }
    };
schema("/opentelemetry/sample_rules/users") ->
    #{
        'operationId' => users,
        get =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(username_rules_get),
                parameters =>
                    [
                        ref(emqx_dashboard_swagger, page),
                        ref(emqx_dashboard_swagger, limit),
                        {like_username,
                            mk(binary(), #{
                                in => query,
                                required => false,
                                desc => ?DESC(fuzzy_username)
                            })}
                    ],
                responses =>
                    #{
                        200 => swagger_with_example(
                            {username_response_data, ?TYPE_REF},
                            {username, ?PAGE_QUERY_EXAMPLE}
                        )
                    }
            },
        post =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(username_rules_post),
                'requestBody' => swagger_with_example(
                    {sample_rules_for_username, ?TYPE_ARRAY},
                    {username, ?POST_ARRAY_EXAMPLE}
                ),
                responses =>
                    #{
                        204 => <<"Created">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad username or bad rule schema">>
                        ),
                        409 => emqx_dashboard_swagger:error_codes(
                            [?ALREADY_EXISTS], <<"ALREADY_EXISTS">>
                        )
                    }
            }
    };
schema("/opentelemetry/sample_rules/users/:username") ->
    #{
        'operationId' => username,
        get =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(username_get),
                parameters => [ref(username)],
                responses =>
                    #{
                        200 => swagger_with_example(
                            {sample_rules_for_username, ?TYPE_REF},
                            {username, ?PUT_MAP_EXAMPLE}
                        ),
                        404 => emqx_dashboard_swagger:error_codes(
                            [?NOT_FOUND], <<"Not Found">>
                        )
                    }
            },
        put =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(username_put),
                parameters => [ref(username)],
                'requestBody' => swagger_with_example(
                    {sample_rules_for_username, ?TYPE_REF},
                    {username, ?PUT_MAP_EXAMPLE}
                ),
                responses =>
                    #{
                        204 => <<"Updated">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad username or bad rule schema">>
                        )
                    }
            },
        delete =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(username_delete),
                parameters => [ref(username)],
                responses =>
                    #{
                        204 => <<"Deleted">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad username">>
                        ),
                        404 => emqx_dashboard_swagger:error_codes(
                            [?NOT_FOUND], <<"Username Not Found">>
                        )
                    }
            }
    };
schema("/opentelemetry/sample_rules/topic_names") ->
    #{
        'operationId' => topic_names,
        get =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(topic_name_rules_get),
                parameters =>
                    [
                        ref(emqx_dashboard_swagger, page),
                        ref(emqx_dashboard_swagger, limit),
                        {like_topic_name,
                            mk(
                                binary(),
                                #{
                                    in => query,
                                    required => false,
                                    desc => ?DESC(fuzzy_topic_name)
                                }
                            )}
                    ],
                responses =>
                    #{
                        200 => swagger_with_example(
                            {topic_name_response_data, ?TYPE_REF},
                            {topic_name, ?PAGE_QUERY_EXAMPLE}
                        )
                    }
            },
        post =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(topic_name_rules_post),
                'requestBody' => swagger_with_example(
                    {sample_rules_for_topic_name, ?TYPE_ARRAY},
                    {topic_name, ?POST_ARRAY_EXAMPLE}
                ),
                responses =>
                    #{
                        204 => <<"Created">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad topic_name or bad rule schema">>
                        )
                    }
            }
    };
schema("/opentelemetry/sample_rules/topic_names/:topic_name") ->
    #{
        'operationId' => topic_name,
        get =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(topic_name_get),
                parameters => [ref(topic_name)],
                responses =>
                    #{
                        200 => swagger_with_example(
                            {sample_rules_for_topic_name, ?TYPE_REF},
                            {topic_name, ?PUT_MAP_EXAMPLE}
                        ),
                        404 => emqx_dashboard_swagger:error_codes(
                            [?NOT_FOUND], <<"Not Found">>
                        )
                    }
            },
        put =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(topic_name_put),
                parameters => [ref(topic_name)],
                'requestBody' => swagger_with_example(
                    {sample_rules_for_topic_name, ?TYPE_REF},
                    {topic_name, ?PUT_MAP_EXAMPLE}
                ),
                responses =>
                    #{
                        204 => <<"Updated">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad topic_name or bad rule schema">>
                        )
                    }
            },
        delete =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(topic_name_delete),
                parameters => [ref(topic_name)],
                responses =>
                    #{
                        204 => <<"Deleted">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad topic_name">>
                        ),
                        404 => emqx_dashboard_swagger:error_codes(
                            [?NOT_FOUND], <<"Topic Name Not Found">>
                        )
                    }
            }
    };
schema("/opentelemetry/sample_rules/topic_matchings") ->
    #{
        'operationId' => topic_matchings,
        get =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(topic_matching_rules_get),
                parameters =>
                    [
                        ref(emqx_dashboard_swagger, page),
                        ref(emqx_dashboard_swagger, limit),
                        {like_topic_matching,
                            mk(
                                binary(),
                                #{
                                    in => query,
                                    required => false,
                                    desc => ?DESC(fuzzy_topic_matching)
                                }
                            )}
                    ],
                responses =>
                    #{
                        200 => swagger_with_example(
                            {topic_matching_response_data, ?TYPE_REF},
                            {topic_matching, ?PAGE_QUERY_EXAMPLE}
                        )
                    }
            },
        post =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(topic_matching_rules_post),
                'requestBody' => swagger_with_example(
                    {sample_rules_for_topic_matching, ?TYPE_ARRAY},
                    {topic_matching, ?POST_ARRAY_EXAMPLE}
                ),
                responses =>
                    #{
                        204 => <<"Created">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad topic_matching or bad rule schema">>
                        )
                    }
            }
    };
schema("/opentelemetry/sample_rules/topic_matchings/:topic_matching") ->
    #{
        'operationId' => topic_matching,
        get =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(topic_matching_get),
                parameters => [ref(topic_matching)],
                responses =>
                    #{
                        200 => swagger_with_example(
                            {sample_rules_for_topic_matching, ?TYPE_REF},
                            {topic_matching, ?PUT_MAP_EXAMPLE}
                        ),
                        404 => emqx_dashboard_swagger:error_codes(
                            [?NOT_FOUND], <<"Not Found">>
                        )
                    }
            },
        put =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(topic_matching_put),
                parameters => [ref(topic_matching)],
                'requestBody' => swagger_with_example(
                    {sample_rules_for_topic_matching, ?TYPE_REF},
                    {topic_matching, ?PUT_MAP_EXAMPLE}
                ),
                responses =>
                    #{
                        204 => <<"Updated">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad topic_matching or bad rule schema">>
                        )
                    }
            },
        delete =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(topic_matching_delete),
                parameters => [ref(topic_matching)],
                responses =>
                    #{
                        204 => <<"Deleted">>,
                        400 => emqx_dashboard_swagger:error_codes(
                            [?BAD_REQUEST], <<"Bad topic_matching">>
                        ),
                        404 => emqx_dashboard_swagger:error_codes(
                            [?NOT_FOUND], <<"Topic Matching Not Found">>
                        )
                    }
            }
    };
schema("/opentelemetry/sample_rules") ->
    #{
        'operationId' => purge_sample_rules,
        delete =>
            #{
                tags => ?API_TAGS,
                description => ?DESC(purge_sample_rules),
                responses =>
                    #{
                        204 => <<"Deleted">>,
                        500 => emqx_dashboard_swagger:error_codes(
                            [?INTERNAL_ERROR], <<"Internal Service Error">>
                        )
                    }
            }
    }.

fields(sample_rule) ->
    [
        {should_sample,
            mk(
                boolean(),
                #{
                    default => false,
                    desc => ?DESC(should_trace)
                }
            )}
    ];
fields(clientid) ->
    [
        {clientid,
            mk(
                binary(),
                #{
                    in => path,
                    required => true,
                    desc => ?DESC(clientid),
                    example => <<"client1">>
                }
            )}
    ];
fields(username) ->
    [
        {username,
            mk(
                binary(),
                #{
                    in => path,
                    required => true,
                    desc => ?DESC(username),
                    example => <<"user1">>
                }
            )}
    ];
fields(topic_name) ->
    [
        {topic_name,
            mk(
                binary(),
                #{
                    in => path,
                    required => true,
                    desc => ?DESC(topic_name),
                    example => <<"topic/1">>
                }
            )}
    ];
fields(topic_matching) ->
    [
        {topic_matching,
            mk(
                binary(),
                #{
                    in => path,
                    required => true,
                    desc => ?DESC(topic_matching),
                    example => <<"topic/#">>
                }
            )}
    ];
fields(sample_rules_for_username) ->
    fields(sample_rule) ++
        fields(username);
fields(username_response_data) ->
    [
        {data, mk(array(ref(sample_rules_for_username)), #{})},
        {meta, ref(emqx_dashboard_swagger, meta)}
    ];
fields(sample_rules_for_clientid) ->
    fields(sample_rule) ++
        fields(clientid);
fields(clientid_response_data) ->
    [
        {data, mk(array(ref(sample_rules_for_clientid)), #{})},
        {meta, ref(emqx_dashboard_swagger, meta)}
    ];
fields(sample_rules_for_topic_name) ->
    fields(sample_rule) ++
        fields(topic_name);
fields(topic_name_response_data) ->
    [
        {data, mk(array(ref(sample_rules_for_topic_name)), #{})},
        {meta, ref(emqx_dashboard_swagger, meta)}
    ];
fields(sample_rules_for_topic_matching) ->
    fields(sample_rule) ++
        fields(topic_matching);
fields(topic_matching_response_data) ->
    [
        {data, mk(array(ref(sample_rules_for_topic_matching)), #{})},
        {meta, ref(emqx_dashboard_swagger, meta)}
    ].

%%--------------------------------------------------------------------
%% HTTP API
%%--------------------------------------------------------------------

%% ====================
%% Management by ClientId
clients(get, #{query_string := QueryString}) ->
    case
        emqx_mgmt_api:node_query(
            node(),
            ?EMQX_OTEL_SAMPLER_RULE,
            QueryString,
            ?SAMPLE_RULE_CLIENTID_QSCHEMA,
            ?QUERY_CLIENTID_FUN,
            fun ?MODULE:format_result/1
        )
    of
        {error, page_limit_invalid} ->
            {400, #{code => <<"INVALID_PARAMETER">>, message => <<"page_limit_invalid">>}};
        {error, Node, Error} ->
            Message = binfmt("bad rpc call ~p, Reason ~p", [Node, Error]),
            {500, #{code => <<"NODE_DOWN">>, message => Message}};
        Result ->
            {200, Result}
    end;
clients(post, #{body := Body}) when is_list(Body) ->
    case ensure_rules_is_valid(clientid, Body) of
        ok ->
            lists:foreach(
                fun(#{<<"clientid">> := ClientID, <<"should_sample">> := ShouldSample}) ->
                    emqx_otel_sampler:store_rule({clientid, ClientID}, ShouldSample, #{})
                end,
                Body
            ),
            {204};
        {error, {already_exists, Exists}} ->
            {409, #{
                code => <<"ALREADY_EXISTS">>,
                message => binfmt("Client '~ts' already exist", [Exists])
            }}
    end.

clientid(get, #{bindings := #{clientid := ClientID}}) ->
    case emqx_otel_sampler:get_rule({clientid, ClientID}) of
        not_found ->
            {404, #{
                code => <<"NOT_FOUND">>,
                message => binfmt("ClientID '~ts' Not Found", [ClientID])
            }};
        {ok, ShouldSample} ->
            {200, #{
                clientid => ClientID,
                should_sample => ShouldSample
            }}
    end;
clientid(put, #{bindings := #{clientid := ClientID}, body := Body}) ->
    ShouldSample = maps:get(<<"should_sample">>, Body),
    emqx_otel_sampler:store_rule({clientid, ClientID}, ShouldSample, #{}),
    {204};
clientid(delete, #{bindings := #{clientid := ClientID}}) ->
    case emqx_otel_sampler:get_rule({clientid, ClientID}) of
        {ok, _} ->
            emqx_otel_sampler:delete_rule({clientid, ClientID}),
            {204};
        not_found ->
            {404}
    end.

%% ====================
%% Management by Username
users(get, #{query_string := QueryString}) ->
    case
        emqx_mgmt_api:node_query(
            node(),
            ?EMQX_OTEL_SAMPLER_RULE,
            QueryString,
            ?SAMPLE_RULE_USERNAME_QSCHEMA,
            ?QUERY_USERNAME_FUN,
            fun ?MODULE:format_result/1
        )
    of
        {error, page_limit_invalid} ->
            {400, #{code => <<"INVALID_PARAMETER">>, message => <<"page_limit_invalid">>}};
        {error, Node, Error} ->
            Message = binfmt("bad rpc call ~p, Reason ~p", [Node, Error]),
            {500, #{code => <<"NODE_DOWN">>, message => Message}};
        Result ->
            {200, Result}
    end;
users(post, #{body := Body}) when is_list(Body) ->
    case ensure_rules_is_valid(username, Body) of
        ok ->
            lists:foreach(
                fun(#{<<"username">> := Username, <<"should_sample">> := ShouldSample}) ->
                    emqx_otel_sampler:store_rule({username, Username}, ShouldSample, #{})
                end,
                Body
            ),
            {204};
        {error, {already_exists, Exists}} ->
            {409, #{
                code => <<"ALREADY_EXISTS">>,
                message => binfmt("User '~ts' already exist", [Exists])
            }}
    end.

username(get, #{bindings := #{username := Username}}) ->
    case emqx_otel_sampler:get_rule({username, Username}) of
        not_found ->
            {404, #{
                code => <<"NOT_FOUND">>,
                message => binfmt("Username '~ts' Not Found", [Username])
            }};
        {ok, ShouldSample} ->
            {200, #{
                username => Username,
                should_sample => ShouldSample
            }}
    end;
username(put, #{bindings := #{username := Username}, body := Body}) ->
    ShouldSample = maps:get(<<"should_sample">>, Body),
    emqx_otel_sampler:store_rule({username, Username}, ShouldSample, #{}),
    {204};
username(delete, #{bindings := #{username := Username}}) ->
    case emqx_otel_sampler:get_rule({username, Username}) of
        {ok, _} ->
            emqx_otel_sampler:delete_rule({username, Username}),
            {204};
        not_found ->
            {404}
    end.

%% ====================
%% Management by TopicName
topic_names(get, #{query_string := QueryString}) ->
    case
        emqx_mgmt_api:node_query(
            node(),
            ?EMQX_OTEL_SAMPLER_RULE,
            QueryString,
            ?SAMPLE_RULE_TOPIC_NAME_QSCHEMA,
            ?QUERY_TOPIC_NAME_FUN,
            fun ?MODULE:format_result/1
        )
    of
        {error, page_limit_invalid} ->
            {400, #{code => <<"INVALID_PARAMETER">>, message => <<"page_limit_invalid">>}};
        {error, Node, Error} ->
            Message = binfmt("bad rpc call ~p, Reason ~p", [Node, Error]),
            {500, #{code => <<"NODE_DOWN">>, message => Message}};
        Result ->
            {200, Result}
    end;
topic_names(post, #{body := Body}) when is_list(Body) ->
    case ensure_rules_is_valid(topic_name, Body) of
        ok ->
            lists:foreach(
                fun(#{<<"topic_name">> := TopicName, <<"should_sample">> := ShouldSample}) ->
                    emqx_otel_sampler:store_rule({topic_name, TopicName}, ShouldSample, #{})
                end,
                Body
            ),
            {204};
        {error, {already_exists, Exists}} ->
            {409, #{
                code => <<"ALREADY_EXISTS">>,
                message => binfmt("Topic name '~ts' already exist", [Exists])
            }}
    end.

topic_name(get, #{bindings := #{topic_name := TopicName}}) ->
    case emqx_otel_sampler:get_rule({topic_name, TopicName}) of
        not_found ->
            {404, #{
                code => <<"NOT_FOUND">>,
                message => binfmt("Topic Name '~ts' Not Found", [TopicName])
            }};
        {ok, ShouldSample} ->
            {200, #{
                topic_name => TopicName,
                should_sample => ShouldSample
            }}
    end;
topic_name(put, #{bindings := #{topic_name := TopicName}, body := Body}) ->
    ShouldSample = maps:get(<<"should_sample">>, Body),
    emqx_otel_sampler:store_rule({topic_name, TopicName}, ShouldSample, #{}),
    {204};
topic_name(delete, #{bindings := #{topic_name := TopicName}}) ->
    case emqx_otel_sampler:get_rule({topic_name, TopicName}) of
        {ok, _} ->
            emqx_otel_sampler:delete_rule({topic_name, TopicName}),
            {204};
        not_found ->
            {404}
    end.

%% ====================
%% Management by TopicMatching
topic_matchings(get, #{query_string := QueryString}) ->
    case
        emqx_mgmt_api:node_query(
            node(),
            ?EMQX_OTEL_SAMPLER_RULE,
            QueryString,
            ?SAMPLE_RULE_TOPIC_MATCHING_QSCHEMA,
            ?QUERY_TOPIC_MATCHING_FUN,
            fun ?MODULE:format_result/1
        )
    of
        {error, page_limit_invalid} ->
            {400, #{code => <<"INVALID_PARAMETER">>, message => <<"page_limit_invalid">>}};
        {error, Node, Error} ->
            Message = binfmt("bad rpc call ~p, Reason ~p", [Node, Error]),
            {500, #{code => <<"NODE_DOWN">>, message => Message}};
        Result ->
            {200, Result}
    end;
topic_matchings(post, #{body := Body}) when is_list(Body) ->
    case ensure_rules_is_valid(topic_matching, Body) of
        ok ->
            lists:foreach(
                fun(#{<<"topic_matching">> := TopicMatching, <<"should_sample">> := ShouldSample}) ->
                    emqx_otel_sampler:store_rule({topic_matching, TopicMatching}, ShouldSample, #{})
                end,
                Body
            ),
            {204};
        {error, {already_exists, Exists}} ->
            {409, #{
                code => <<"ALREADY_EXISTS">>,
                message => binfmt("Topic matching '~ts' already exist", [Exists])
            }}
    end.

topic_matching(get, #{bindings := #{topic_matching := TopicMatching}}) ->
    case emqx_otel_sampler:get_rule({topic_matching, TopicMatching}) of
        not_found ->
            {404, #{
                code => <<"NOT_FOUND">>,
                message => binfmt("Topic Matching '~ts' Not Found", [TopicMatching])
            }};
        {ok, ShouldSample} ->
            {200, #{
                topic_matching => TopicMatching,
                should_sample => ShouldSample
            }}
    end;
topic_matching(put, #{bindings := #{topic_matching := TopicMatching}, body := Body}) ->
    ShouldSample = maps:get(<<"should_sample">>, Body),
    emqx_otel_sampler:store_rule({topic_matching, TopicMatching}, ShouldSample, #{}),
    {204};
topic_matching(delete, #{bindings := #{topic_matching := TopicMatching}}) ->
    case emqx_otel_sampler:get_rule({topic_matching, TopicMatching}) of
        {ok, _} ->
            emqx_otel_sampler:delete_rule({topic_matching, TopicMatching}),
            {204};
        not_found ->
            {404}
    end.

%% ====================
%% Purge all sample rules
purge_sample_rules(delete, _) ->
    try emqx_otel_sampler:purge_rules() of
        ok -> {204}
    catch
        _:Error ->
            ?RESP_INTERNAL_ERROR(emqx_utils:readable_error_msg(Error))
    end.

%%--------------------------------------------------------------------
%% QueryString to MatchSpec

-spec query_username(atom(), {list(), list()}) -> emqx_mgmt_api:match_spec_and_filter().
query_username(_Tab, {_QString, FuzzyQString}) ->
    #{
        match_spec => emqx_otel_sampler:list_username_rules(),
        fuzzy_fun => fuzzy_filter_fun(FuzzyQString)
    }.

-spec query_clientid(atom(), {list(), list()}) -> emqx_mgmt_api:match_spec_and_filter().
query_clientid(_Tab, {_QString, FuzzyQString}) ->
    #{
        match_spec => emqx_otel_sampler:list_clientid_rules(),
        fuzzy_fun => fuzzy_filter_fun(FuzzyQString)
    }.

-spec query_topic_name(atom(), {list(), list()}) -> emqx_mgmt_api:match_spec_and_filter().
query_topic_name(_Tab, {_QString, FuzzyQString}) ->
    #{
        match_spec => emqx_otel_sampler:list_topic_name_rules(),
        fuzzy_fun => fuzzy_filter_fun(FuzzyQString)
    }.

-spec query_topic_matching(atom(), {list(), list()}) -> emqx_mgmt_api:match_spec_and_filter().
query_topic_matching(_Tab, {_QString, FuzzyQString}) ->
    #{
        match_spec => emqx_otel_sampler:list_topic_matching_rules(),
        fuzzy_fun => fuzzy_filter_fun(FuzzyQString)
    }.

%% Fuzzy username funcs
fuzzy_filter_fun([]) ->
    undefined;
fuzzy_filter_fun(Fuzzy) ->
    {fun ?MODULE:run_fuzzy_filter/2, [Fuzzy]}.

run_fuzzy_filter(_, []) ->
    true;
run_fuzzy_filter(
    E = [{username, Username}, _Rule],
    [{username, like, UsernameSubStr} | Fuzzy]
) ->
    binary:match(Username, UsernameSubStr) /= nomatch andalso run_fuzzy_filter(E, Fuzzy);
run_fuzzy_filter(
    E = [{clientid, ClientId}, _Rule],
    [{clientid, like, ClientIdSubStr} | Fuzzy]
) ->
    binary:match(ClientId, ClientIdSubStr) /= nomatch andalso run_fuzzy_filter(E, Fuzzy);
run_fuzzy_filter(
    E = [{topic_name, TopicName}, _Rule],
    [{topic_name, like, TopicNameSubStr} | Fuzzy]
) ->
    binary:match(TopicName, TopicNameSubStr) /= nomatch andalso run_fuzzy_filter(E, Fuzzy);
run_fuzzy_filter(
    E = [{topic_matching, TopicMatching}, _Rule],
    [{topic_matching, like, TopicMatchingSubStr} | Fuzzy]
) ->
    binary:match(TopicMatching, TopicMatchingSubStr) /= nomatch andalso run_fuzzy_filter(E, Fuzzy).

format_result([{username, Username}, {should_sample, ShouldSample}]) ->
    #{
        username => Username,
        should_sample => ShouldSample
    };
format_result([{clientid, ClientID}, {should_sample, ShouldSample}]) ->
    #{
        clientid => ClientID,
        should_sample => ShouldSample
    };
format_result([{topic_name, TopicName}, {should_sample, ShouldSample}]) ->
    #{
        topic_name => TopicName,
        should_sample => ShouldSample
    };
format_result([{topic_matching, TopicMatching}, {should_sample, ShouldSample}]) ->
    #{
        topic_matching => TopicMatching,
        should_sample => ShouldSample
    }.

%%--------------------------------------------------------------------
%% Internal Helpers
%%--------------------------------------------------------------------

swagger_with_example({Ref, TypeP}, {_Name, _Type} = Example) ->
    emqx_dashboard_swagger:schema_with_examples(
        case TypeP of
            ?TYPE_REF -> ref(?MODULE, Ref);
            ?TYPE_ARRAY -> array(ref(?MODULE, Ref))
        end,
        rules_example(Example)
    ).

%% API examples
-define(CLIENTID_SAMPLE_RULE_EXAMPLE, #{
    clientid => client1,
    should_sample => true
}).
-define(USERNAME_SAMPLE_RULE_EXAMPLE, #{
    username => user1,
    should_sample => true
}).
-define(TOPIC_NAME_SAMPLE_RULE_EXAMPLE, #{
    topic_name => <<"test/topic/1">>,
    should_sample => true
}).
-define(TOPIC_MATCHING_SAMPLE_RULE_EXAMPLE, #{
    topic_matching => <<"test/#">>,
    should_sample => true
}).

rules_example({ExampleName, ExampleType}) ->
    {Summary, Example} =
        case ExampleName of
            clientid -> {<<"ClientID">>, ?CLIENTID_SAMPLE_RULE_EXAMPLE};
            username -> {<<"Username">>, ?USERNAME_SAMPLE_RULE_EXAMPLE};
            topic_name -> {<<"TopicName">>, ?TOPIC_NAME_SAMPLE_RULE_EXAMPLE};
            topic_matching -> {<<"TopicMatching">>, ?TOPIC_MATCHING_SAMPLE_RULE_EXAMPLE}
        end,
    Value =
        case ExampleType of
            ?PAGE_QUERY_EXAMPLE ->
                #{
                    data => [Example],
                    meta => ?META_EXAMPLE
                };
            ?PUT_MAP_EXAMPLE ->
                Example;
            ?POST_ARRAY_EXAMPLE ->
                [Example]
        end,
    #{
        otel_sampler_rule => #{
            summary => Summary,
            value => Value
        }
    }.

ensure_rules_is_valid(Type, Rules) ->
    ensure_rules_is_valid(Type, atom_to_binary(Type), Rules).

ensure_rules_is_valid(_Type, _BinKey, []) ->
    ok;
ensure_rules_is_valid(Type, BinKey, [Rule | Rest]) ->
    #{BinKey := Id, <<"should_sample">> := _ShouldSample} = Rule,
    case emqx_otel_sampler:get_rule({Type, Id}) of
        not_found ->
            ensure_rules_is_valid(Type, BinKey, Rest);
        _ ->
            {error, {already_exists, Id}}
    end.

binfmt(Fmt, Args) -> iolist_to_binary(io_lib:format(Fmt, Args)).
