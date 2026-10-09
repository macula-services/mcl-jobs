%%% @doc Event `profile_described_v1'.
-module(profile_described_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_citizen_did/1, get_headline/1, get_skills/1, get_location/1, get_described_at/1]).

-record(profile_described_v1, {
    citizen_did :: binary(),
    headline :: binary(),
    skills :: [binary()],
    location :: binary(),
    described_at :: integer()
}).

-opaque t() :: #profile_described_v1{}.
-export_type([t/0]).

-spec event_type() -> binary().
event_type() -> <<"profile_described_v1">>.

-spec new(map()) -> t().
new(#{citizen_did := Did, headline := H, skills := S, location := L} = Params) ->
    #profile_described_v1{
        citizen_did = Did, headline = H, skills = S, location = L,
        described_at = maps:get(described_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{citizen_did := Did, headline := H, skills := S, location := L, described_at := At})
  when is_binary(Did), is_binary(H), is_list(S), is_binary(L), is_integer(At) ->
    {ok, #profile_described_v1{citizen_did = Did, headline = H, skills = S, location = L,
                               described_at = At}};
from_map(_) ->
    {error, invalid_profile_described_event}.

-spec to_map(t()) -> map().
to_map(#profile_described_v1{citizen_did = Did, headline = H, skills = S, location = L,
                             described_at = At}) ->
    #{event_type => <<"profile_described_v1">>, citizen_did => Did,
      headline => H, skills => S, location => L, described_at => At}.

-spec get_citizen_did(t()) -> binary().
get_citizen_did(#profile_described_v1{citizen_did = V}) -> V.

-spec get_headline(t()) -> binary().
get_headline(#profile_described_v1{headline = V}) -> V.

-spec get_skills(t()) -> [binary()].
get_skills(#profile_described_v1{skills = V}) -> V.

-spec get_location(t()) -> binary().
get_location(#profile_described_v1{location = V}) -> V.

-spec get_described_at(t()) -> integer().
get_described_at(#profile_described_v1{described_at = V}) -> V.
