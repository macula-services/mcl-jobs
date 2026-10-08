%%% @doc Command `archive_organisation_v1'.
%%%
%%% The end of an organisation. Terminal: an archived organisation takes no further command.
%%% @end
-module(archive_organisation_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_organisation_id/1]).

-record(archive_organisation_v1, {
    organisation_id :: binary()
}).

-opaque t() :: #archive_organisation_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> archive_organisation_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(Params) -> from_map(Params).

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{organisation_id := Id}) when is_binary(Id) ->
    {ok, #archive_organisation_v1{organisation_id = Id}};
from_map(_) ->
    {error, missing_organisation_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#archive_organisation_v1{organisation_id = Id}) when byte_size(Id) > 0 -> ok;
validate(_) -> {error, missing_organisation_id}.

-spec to_map(t()) -> map().
to_map(#archive_organisation_v1{organisation_id = Id}) ->
    #{command_type => archive_organisation_v1, organisation_id => Id}.

-spec stream_id(t()) -> binary().
stream_id(#archive_organisation_v1{organisation_id = Id}) ->
    organisation_aggregate:stream_id(Id).

-spec get_organisation_id(t()) -> binary().
get_organisation_id(#archive_organisation_v1{organisation_id = V}) -> V.
