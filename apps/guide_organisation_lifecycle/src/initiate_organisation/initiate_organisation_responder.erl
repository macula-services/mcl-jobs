%%% @doc RESPONDER for the `mcl-jobs/initiate_organisation' procedure.
%%%
%%% Initiates the organisation named by `organisation_id' (1 to 64 of
%%% [a-z0-9-]) with its `name' (UTF-8 text, at most 200 bytes, no control
%%% characters). The caller, the node id that signed the CALL, is recorded as
%%% the organisation's initiator: the only node that may archive it.
%%%
%%% Replies `#{}' once the event is stored, or `#{reason => Why}' naming
%%% the rule that refused it (README, "Procedures").
%%% @end
-module(initiate_organisation_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2, command/1]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    {reply, replied(dispatched(command(Payload))), State}.

%% @doc The command a CALL stands for, acting as its caller.
-spec command(map()) -> {ok, initiate_organisation_v1:t()} | {error, atom()}.
command(Payload) ->
    for_caller(mcl_om_wire:caller(Payload), #{organisation_id => mcl_om_wire:field(organisation_id, Payload),
                                              name => mcl_om_wire:field(name, Payload)}).

for_caller(<<_:256>> = By, Fields) -> initiate_organisation_v1:new(Fields#{initiated_by => By});
for_caller(_Missing, _Fields) -> {error, no_caller}.

dispatched({ok, Cmd}) -> maybe_initiate_organisation:dispatch(Cmd);
dispatched({error, _} = Refused) -> Refused.

replied({ok, _Version, _Events}) -> #{};
replied({error, Reason}) when is_atom(Reason) -> #{reason => {text, atom_to_binary(Reason)}};
replied({error, _Unexpected}) -> #{reason => {text, <<"internal_error">>}}.
