%%% @doc Event `organisation_initiated_v1'.
-module(organisation_initiated_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_organisation_id/1, get_name/1, get_initiated_at/1]).

-record(organisation_initiated_v1, {
    organisation_id :: binary(),
    name :: binary(),
    initiated_at :: integer()
}).

-opaque t() :: #organisation_initiated_v1{}.
-export_type([t/0]).

-spec event_type() -> binary().
event_type() -> <<"organisation_initiated_v1">>.

-spec new(map()) -> t().
new(#{organisation_id := Id, name := Name} = Params) ->
    #organisation_initiated_v1{
        organisation_id = Id,
        name = Name,
        initiated_at = maps:get(initiated_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{organisation_id := Id, name := Name, initiated_at := At})
  when is_binary(Id), is_binary(Name), is_integer(At) ->
    {ok, #organisation_initiated_v1{organisation_id = Id, name = Name, initiated_at = At}};
from_map(_) ->
    {error, invalid_organisation_initiated_event}.

-spec to_map(t()) -> map().
to_map(#organisation_initiated_v1{organisation_id = Id, name = Name, initiated_at = At}) ->
    #{event_type => <<"organisation_initiated_v1">>,
      organisation_id => Id, name => Name, initiated_at => At}.

-spec get_organisation_id(t()) -> binary().
get_organisation_id(#organisation_initiated_v1{organisation_id = V}) -> V.

-spec get_name(t()) -> binary().
get_name(#organisation_initiated_v1{name = V}) -> V.

-spec get_initiated_at(t()) -> integer().
get_initiated_at(#organisation_initiated_v1{initiated_at = V}) -> V.
