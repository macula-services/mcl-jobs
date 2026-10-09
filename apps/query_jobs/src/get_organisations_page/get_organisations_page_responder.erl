%%% @doc RESPONDER for the `mcl-jobs/get_organisations_page' procedure.
%%%
%%% Payload `after' (an organisation id, optional) and `limit' (1 to 50,
%%% default 20). Replies `#{organisations => [...]}', with `next' when there is more.
%%% @end
-module(get_organisations_page_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    {reply, query_jobs_reply:replied(get_organisations_page:page(mcl_om_wire:field('after', Payload),
                                                            mcl_om_wire:field(limit, Payload))), State}.
