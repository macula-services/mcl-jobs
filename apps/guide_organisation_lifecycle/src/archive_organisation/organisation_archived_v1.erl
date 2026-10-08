%%% @doc Event `organisation_archived_v1'.
-module(organisation_archived_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_organisation_id/1, get_archived_by/1, get_archived_at/1]).

-record(organisation_archived_v1, {
    organisation_id :: binary(),
    archived_by :: binary(),
    archived_at :: integer()
}).

-opaque t() :: #organisation_archived_v1{}.
-export_type([t/0]).

-spec event_type() -> binary().
event_type() -> <<"organisation_archived_v1">>.

-spec new(map()) -> t().
new(#{organisation_id := Id, archived_by := By} = Params) ->
    #organisation_archived_v1{
        organisation_id = Id,
        archived_by = By,
        archived_at = maps:get(archived_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{organisation_id := Id, archived_by := By, archived_at := At})
  when is_binary(Id), is_binary(By), is_integer(At) ->
    {ok, #organisation_archived_v1{organisation_id = Id, archived_by = By, archived_at = At}};
from_map(_) ->
    {error, invalid_organisation_archived_event}.

-spec to_map(t()) -> map().
to_map(#organisation_archived_v1{organisation_id = Id, archived_by = By, archived_at = At}) ->
    #{event_type => <<"organisation_archived_v1">>,
      organisation_id => Id, archived_by => By, archived_at => At}.

-spec get_organisation_id(t()) -> binary().
get_organisation_id(#organisation_archived_v1{organisation_id = V}) -> V.

-spec get_archived_by(t()) -> binary().
get_archived_by(#organisation_archived_v1{archived_by = V}) -> V.

-spec get_archived_at(t()) -> integer().
get_archived_at(#organisation_archived_v1{archived_at = V}) -> V.
