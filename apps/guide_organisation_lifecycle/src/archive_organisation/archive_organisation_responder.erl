%%% @doc RESPONDER for the `mcl-jobs/archive_organisation' procedure.
%%%
%%% Archives the organisation named by `organisation_id', on behalf of the
%%% caller, the node id that signed the CALL. Only the node that initiated it
%%% may: anyone else is refused `not_initiator'.
%%%
%%% Replies `#{}' once the event is stored, or `#{reason => Why}' naming
%%% the rule that refused it (README, "Procedures").
%%% @end
-module(archive_organisation_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2, command/1]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    {reply, replied(dispatched(command(Payload))), State}.

%% @doc The command a CALL stands for, acting as its caller.
-spec command(map()) -> {ok, archive_organisation_v1:t()} | {error, atom()}.
command(Payload) ->
    for_caller(mcl_om_wire:caller(Payload), #{organisation_id => mcl_om_wire:field(organisation_id, Payload)}).

for_caller(<<_:256>> = By, Fields) -> archive_organisation_v1:new(Fields#{archived_by => By});
for_caller(_Missing, _Fields) -> {error, no_caller}.

dispatched({ok, Cmd}) -> maybe_archive_organisation:dispatch(Cmd);
dispatched({error, _} = Refused) -> Refused.

replied({ok, _Version, _Events}) -> #{};
replied({error, Reason}) when is_atom(Reason) -> #{reason => {text, atom_to_binary(Reason)}};
replied({error, _Unexpected}) -> #{reason => {text, <<"internal_error">>}}.
