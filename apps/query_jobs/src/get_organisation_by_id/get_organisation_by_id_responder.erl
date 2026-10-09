%%% @doc RESPONDER for the `mcl-jobs/get_organisation_by_id' procedure.
%%%
%%% Payload `organisation_id'. Replies `#{organisation_id, name, initiated_by,
%%% initiated_at, archived}' or `#{reason => not_found}'.
%%% @end
-module(get_organisation_by_id_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    {reply, query_jobs_reply:replied(get_organisation_by_id:find(mcl_om_wire:field(organisation_id, Payload))), State}.
