%%% @doc RESPONDER for the `mcl-jobs/withdraw_profile' procedure.
%%%
%%% Acts on the CALLER's own profile: the citizen is the node id that signed
%%% the CALL (macula puts it on the payload as `caller' and overwrites any
%%% the payload sent), so nobody can withdraw a profile for somebody else. The
%%% payload carries nothing else.
%%%
%%% Replies `#{}' once the event is stored, or `#{reason => Why}' naming
%%% the rule that refused it.
%%% @end
-module(withdraw_profile_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2, command/1]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    {reply, replied(dispatched(command(Payload))), State}.

%% @doc The command a CALL stands for: the caller's own profile.
-spec command(map()) -> {ok, withdraw_profile_v1:t()} | {error, no_caller}.
command(Payload) ->
    for_caller(mcl_om_wire:caller(Payload)).

for_caller(<<_:256>> = CitizenDid) -> withdraw_profile_v1:new(#{citizen_did => CitizenDid});
for_caller(_Missing) -> {error, no_caller}.

dispatched({ok, Cmd}) -> maybe_withdraw_profile:dispatch(Cmd);
dispatched({error, _} = Refused) -> Refused.

replied({ok, _Version, _Events}) -> #{};
replied({error, Reason}) when is_atom(Reason) -> #{reason => {text, atom_to_binary(Reason)}};
replied({error, _Unexpected}) -> #{reason => {text, <<"internal_error">>}}.
