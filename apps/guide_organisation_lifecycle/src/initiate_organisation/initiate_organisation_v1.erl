%%% @doc Command `initiate_organisation_v1'.
%%%
%%% The birth of an organisation: its id keys the stream, its name is how
%%% people know it. An organisation is not a person; a profile appointed to
%%% act for one (a recruiter) is a later desk, not this one.
%%% @end
-module(initiate_organisation_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_organisation_id/1, get_name/1]).

-record(initiate_organisation_v1, {
    organisation_id :: binary(),
    name :: binary()
}).

-opaque t() :: #initiate_organisation_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> initiate_organisation_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(Params) -> from_map(Params).

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{organisation_id := Id, name := Name}) when is_binary(Id), is_binary(Name) ->
    {ok, #initiate_organisation_v1{organisation_id = Id, name = Name}};
from_map(#{organisation_id := Id}) when is_binary(Id) ->
    {error, missing_name};
from_map(_) ->
    {error, missing_organisation_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#initiate_organisation_v1{organisation_id = <<>>}) -> {error, missing_organisation_id};
validate(#initiate_organisation_v1{name = <<>>}) -> {error, missing_name};
validate(#initiate_organisation_v1{}) -> ok.

-spec to_map(t()) -> map().
to_map(#initiate_organisation_v1{organisation_id = Id, name = Name}) ->
    #{command_type => initiate_organisation_v1, organisation_id => Id, name => Name}.

-spec stream_id(t()) -> binary().
stream_id(#initiate_organisation_v1{organisation_id = Id}) ->
    organisation_aggregate:stream_id(Id).

-spec get_organisation_id(t()) -> binary().
get_organisation_id(#initiate_organisation_v1{organisation_id = V}) -> V.

-spec get_name(t()) -> binary().
get_name(#initiate_organisation_v1{name = V}) -> V.
