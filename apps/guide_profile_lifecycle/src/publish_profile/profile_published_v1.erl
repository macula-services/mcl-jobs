%%% @doc Event `profile_published_v1'.
-module(profile_published_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_citizen_did/1, get_published_at/1]).

-record(profile_published_v1, {
    citizen_did :: binary(),
    published_at :: integer()
}).

-opaque t() :: #profile_published_v1{}.
-export_type([t/0]).

-spec event_type() -> binary().
event_type() -> <<"profile_published_v1">>.

-spec new(map()) -> t().
new(#{citizen_did := Did} = Params) ->
    #profile_published_v1{
        citizen_did = Did,
        published_at = maps:get(published_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{citizen_did := Did, published_at := At}) when is_binary(Did), is_integer(At) ->
    {ok, #profile_published_v1{citizen_did = Did, published_at = At}};
from_map(_) ->
    {error, invalid_profile_published_event}.

-spec to_map(t()) -> map().
to_map(#profile_published_v1{citizen_did = Did, published_at = At}) ->
    #{event_type => <<"profile_published_v1">>, citizen_did => Did, published_at => At}.

-spec get_citizen_did(t()) -> binary().
get_citizen_did(#profile_published_v1{citizen_did = V}) -> V.

-spec get_published_at(t()) -> integer().
get_published_at(#profile_published_v1{published_at = V}) -> V.
