%%% @doc Handler for `archive_organisation_v1'.
%%%
%%% Validates the payload and builds the event. The lifecycle rules (what
%%% may happen to an organisation in which state) live in organisation_aggregate.
%%% @end
-module(maybe_archive_organisation).

-export([handle_from_map/1, handle/1, dispatch/1]).

-include_lib("evoq/include/evoq.hrl").

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    handled(archive_organisation_v1:from_map(Payload)).

-spec handle(archive_organisation_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    built(archive_organisation_v1:validate(Cmd), Cmd).

%% @doc Dispatches through evoq, which runs the aggregate and persists the
%% event in mcl_jobs_store.
-spec dispatch(archive_organisation_v1:t()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    EvoqCmd = #evoq_command{
        command_type = archive_organisation_v1,
        aggregate_type = organisation_aggregate,
        aggregate_id = archive_organisation_v1:stream_id(Cmd),
        payload = archive_organisation_v1:to_map(Cmd),
        metadata = #{timestamp => erlang:system_time(millisecond)}
    },
    evoq_command_router:dispatch(EvoqCmd, #{
        store_id => organisation_aggregate:store_id(),
        adapter => reckon_evoq_adapter,
        consistency => eventual
    }).

handled({ok, Cmd}) -> handle(Cmd);
handled({error, _} = E) -> E.

built(ok, Cmd) ->
    Event = organisation_archived_v1:new(#{
        organisation_id => archive_organisation_v1:get_organisation_id(Cmd),
        archived_by => archive_organisation_v1:get_archived_by(Cmd)}),
    {ok, [organisation_archived_v1:to_map(Event)]};
built({error, _} = E, _Cmd) ->
    E.
