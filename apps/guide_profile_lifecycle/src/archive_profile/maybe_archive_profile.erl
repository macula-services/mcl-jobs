%%% @doc Handler for `archive_profile_v1'.
%%%
%%% Validates the payload and builds the event. The lifecycle rules (what
%%% may happen to a profile in which state) live in profile_aggregate.
%%% @end
-module(maybe_archive_profile).

-export([handle_from_map/1, handle/1, dispatch/1]).

-include_lib("evoq/include/evoq.hrl").

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    handled(archive_profile_v1:from_map(Payload)).

-spec handle(archive_profile_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    built(archive_profile_v1:validate(Cmd), Cmd).

%% @doc Dispatches through evoq, which runs the aggregate and persists the
%% event in mcl_jobs_store.
-spec dispatch(archive_profile_v1:t()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    EvoqCmd = #evoq_command{
        command_type = archive_profile_v1,
        aggregate_type = profile_aggregate,
        aggregate_id = archive_profile_v1:stream_id(Cmd),
        payload = archive_profile_v1:to_map(Cmd),
        metadata = #{timestamp => erlang:system_time(millisecond)}
    },
    evoq_command_router:dispatch(EvoqCmd, #{
        store_id => profile_aggregate:store_id(),
        adapter => reckon_evoq_adapter,
        consistency => eventual
    }).

handled({ok, Cmd}) -> handle(Cmd);
handled({error, _} = E) -> E.

built(ok, Cmd) ->
    Event = profile_archived_v1:new(#{citizen_did => archive_profile_v1:get_citizen_did(Cmd)}),
    {ok, [profile_archived_v1:to_map(Event)]};
built({error, _} = E, _Cmd) ->
    E.
