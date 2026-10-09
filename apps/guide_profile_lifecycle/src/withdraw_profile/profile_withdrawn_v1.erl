%%% @doc Event `profile_withdrawn_v1'.
-module(profile_withdrawn_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_citizen_did/1, get_withdrawn_at/1]).

-record(profile_withdrawn_v1, {
    citizen_did :: binary(),
    withdrawn_at :: integer()
}).

-opaque t() :: #profile_withdrawn_v1{}.
-export_type([t/0]).

-spec event_type() -> binary().
event_type() -> <<"profile_withdrawn_v1">>.

-spec new(map()) -> t().
new(#{citizen_did := Did} = Params) ->
    #profile_withdrawn_v1{
        citizen_did = Did,
        withdrawn_at = maps:get(withdrawn_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{citizen_did := Did, withdrawn_at := At}) when is_binary(Did), is_integer(At) ->
    {ok, #profile_withdrawn_v1{citizen_did = Did, withdrawn_at = At}};
from_map(_) ->
    {error, invalid_profile_withdrawn_event}.

-spec to_map(t()) -> map().
to_map(#profile_withdrawn_v1{citizen_did = Did, withdrawn_at = At}) ->
    #{event_type => <<"profile_withdrawn_v1">>, citizen_did => Did, withdrawn_at => At}.

-spec get_citizen_did(t()) -> binary().
get_citizen_did(#profile_withdrawn_v1{citizen_did = V}) -> V.

-spec get_withdrawn_at(t()) -> integer().
get_withdrawn_at(#profile_withdrawn_v1{withdrawn_at = V}) -> V.
