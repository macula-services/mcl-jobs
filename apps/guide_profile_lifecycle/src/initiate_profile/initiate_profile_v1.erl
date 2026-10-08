%%% @doc Command `initiate_profile_v1'.
%%%
%%% The birth of a citizen's profile. One per citizen: the citizen's DID keys the stream.
%%% @end
-module(initiate_profile_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_citizen_did/1]).

-record(initiate_profile_v1, {
    citizen_did :: binary()
}).

-opaque t() :: #initiate_profile_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> initiate_profile_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(Params) -> from_map(Params).

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{citizen_did := Did}) when is_binary(Did) ->
    {ok, #initiate_profile_v1{citizen_did = Did}};
from_map(_) ->
    {error, missing_citizen_did}.

-spec validate(t()) -> ok | {error, term()}.
validate(#initiate_profile_v1{citizen_did = Did}) when byte_size(Did) > 0 -> ok;
validate(_) -> {error, missing_citizen_did}.

-spec to_map(t()) -> map().
to_map(#initiate_profile_v1{citizen_did = Did}) ->
    #{command_type => initiate_profile_v1, citizen_did => Did}.

-spec stream_id(t()) -> binary().
stream_id(#initiate_profile_v1{citizen_did = Did}) ->
    profile_aggregate:stream_id(Did).

-spec get_citizen_did(t()) -> binary().
get_citizen_did(#initiate_profile_v1{citizen_did = V}) -> V.
