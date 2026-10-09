%%% @doc Command `withdraw_profile_v1'.
%%%
%%% Takes the profile out of the realm's sight again: only its owner sees it
%%% until it is published again.
%%% @end
-module(withdraw_profile_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_citizen_did/1]).

-record(withdraw_profile_v1, {
    citizen_did :: binary()
}).

-opaque t() :: #withdraw_profile_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> withdraw_profile_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(Params) -> from_map(Params).

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{citizen_did := Did}) when is_binary(Did) ->
    {ok, #withdraw_profile_v1{citizen_did = Did}};
from_map(_) ->
    {error, missing_citizen_did}.

-spec validate(t()) -> ok | {error, term()}.
validate(#withdraw_profile_v1{citizen_did = Did}) when byte_size(Did) > 0 -> ok;
validate(_) -> {error, missing_citizen_did}.

-spec to_map(t()) -> map().
to_map(#withdraw_profile_v1{citizen_did = Did}) ->
    #{command_type => withdraw_profile_v1, citizen_did => Did}.

-spec stream_id(t()) -> binary().
stream_id(#withdraw_profile_v1{citizen_did = Did}) ->
    profile_aggregate:stream_id(Did).

-spec get_citizen_did(t()) -> binary().
get_citizen_did(#withdraw_profile_v1{citizen_did = V}) -> V.
