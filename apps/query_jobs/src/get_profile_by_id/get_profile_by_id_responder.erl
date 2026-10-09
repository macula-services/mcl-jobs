%%% @doc RESPONDER for the `mcl-jobs/get_profile_by_id' procedure.
%%%
%%% Payload `citizen' (64 hex). Replies `#{profile => ...}' when visible_profiles lets the
%%% caller see it, else `#{reason => not_found}'.
%%% @end
-module(get_profile_by_id_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    {reply, query_jobs_reply:replied(get_profile_by_id:find(mcl_om_wire:field(citizen, Payload),
                                                       mcl_om_wire:caller(Payload))), State}.
