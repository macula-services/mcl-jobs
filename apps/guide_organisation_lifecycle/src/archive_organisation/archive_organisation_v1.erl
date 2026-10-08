%%% @doc Command `archive_organisation_v1'.
%%%
%%% The end of an organisation. Terminal: an archived organisation takes no
%%% further command. archived_by is the node asking; the aggregate allows it
%%% only when that is the node that initiated the organisation.
%%% @end
-module(archive_organisation_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_organisation_id/1, get_archived_by/1]).

-record(archive_organisation_v1, {
    organisation_id :: binary(),
    archived_by :: <<_:256>>
}).

-opaque t() :: #archive_organisation_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> archive_organisation_v1.

%% @doc A command that exists is a valid one: new/1 validates.
-spec new(map()) -> {ok, t()} | {error, term()}.
new(Params) -> checked(from_map(Params)).

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{archived_by := <<_:256>> = By, organisation_id := Id}) when is_binary(Id) ->
    {ok, #archive_organisation_v1{organisation_id = Id, archived_by = By}};
from_map(#{archived_by := <<_:256>>}) ->
    {error, invalid_organisation_id};
from_map(_) ->
    {error, no_caller}.

-spec validate(t()) -> ok | {error, term()}.
validate(#archive_organisation_v1{organisation_id = Id}) ->
    id_verdict(organisation_aggregate:valid_id(Id)).

-spec to_map(t()) -> map().
to_map(#archive_organisation_v1{organisation_id = Id, archived_by = By}) ->
    #{command_type => archive_organisation_v1, organisation_id => Id, archived_by => By}.

-spec stream_id(t()) -> binary().
stream_id(#archive_organisation_v1{organisation_id = Id}) ->
    organisation_aggregate:stream_id(Id).

-spec get_organisation_id(t()) -> binary().
get_organisation_id(#archive_organisation_v1{organisation_id = V}) -> V.

-spec get_archived_by(t()) -> <<_:256>>.
get_archived_by(#archive_organisation_v1{archived_by = V}) -> V.

checked({ok, Cmd}) -> validated(validate(Cmd), Cmd);
checked({error, _} = E) -> E.

validated(ok, Cmd) -> {ok, Cmd};
validated({error, _} = E, _Cmd) -> E.

id_verdict(true) -> ok;
id_verdict(false) -> {error, invalid_organisation_id}.
