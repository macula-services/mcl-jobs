%%% @doc Command `initiate_organisation_v1'.
%%%
%%% The birth of an organisation: its id keys the stream, its name is how
%%% people know it, and initiated_by is the node that brought it into being,
%%% the only one that may archive it. An organisation is not a person; a
%%% profile appointed to act for one (a recruiter) is a later desk.
%%% @end
-module(initiate_organisation_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_organisation_id/1, get_name/1, get_initiated_by/1]).

-define(MAX_NAME_BYTES, 200).

-record(initiate_organisation_v1, {
    organisation_id :: binary(),
    name :: binary(),
    initiated_by :: <<_:256>>
}).

-opaque t() :: #initiate_organisation_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> initiate_organisation_v1.

%% @doc A command that exists is a valid one: new/1 validates.
-spec new(map()) -> {ok, t()} | {error, term()}.
new(Params) -> checked(from_map(Params)).

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{initiated_by := <<_:256>> = By, organisation_id := Id, name := Name})
  when is_binary(Id), is_binary(Name) ->
    {ok, #initiate_organisation_v1{organisation_id = Id, name = Name, initiated_by = By}};
from_map(#{initiated_by := <<_:256>>, organisation_id := Id}) when is_binary(Id) ->
    {error, missing_name};
from_map(#{initiated_by := <<_:256>>}) ->
    {error, invalid_organisation_id};
from_map(_) ->
    {error, no_caller}.

-spec validate(t()) -> ok | {error, term()}.
validate(#initiate_organisation_v1{organisation_id = Id, name = Name}) ->
    named(organisation_aggregate:valid_id(Id), Name).

-spec to_map(t()) -> map().
to_map(#initiate_organisation_v1{organisation_id = Id, name = Name, initiated_by = By}) ->
    #{command_type => initiate_organisation_v1,
      organisation_id => Id, name => Name, initiated_by => By}.

-spec stream_id(t()) -> binary().
stream_id(#initiate_organisation_v1{organisation_id = Id}) ->
    organisation_aggregate:stream_id(Id).

-spec get_organisation_id(t()) -> binary().
get_organisation_id(#initiate_organisation_v1{organisation_id = V}) -> V.

-spec get_name(t()) -> binary().
get_name(#initiate_organisation_v1{name = V}) -> V.

-spec get_initiated_by(t()) -> <<_:256>>.
get_initiated_by(#initiate_organisation_v1{initiated_by = V}) -> V.

checked({ok, Cmd}) -> validated(validate(Cmd), Cmd);
checked({error, _} = E) -> E.

validated(ok, Cmd) -> {ok, Cmd};
validated({error, _} = E, _Cmd) -> E.

named(false, _Name) -> {error, invalid_organisation_id};
named(true, <<>>) -> {error, missing_name};
named(true, Name) -> printable(byte_size(Name) =< ?MAX_NAME_BYTES, Name).

%% A name is well-formed UTF-8 with no control characters: it is shown to
%% people, and nothing in it may steer a terminal or a log line.
printable(false, _Name) -> {error, invalid_name};
printable(true, Name) ->
    plain(unicode:characters_to_list(Name, utf8)).

plain(Chars) when is_list(Chars) ->
    name_verdict(lists:all(fun(C) -> C >= 16#20 andalso not (C >= 16#7F andalso C =< 16#9F) end, Chars));
plain(_Malformed) ->
    {error, invalid_name}.

name_verdict(true) -> ok;
name_verdict(false) -> {error, invalid_name}.
