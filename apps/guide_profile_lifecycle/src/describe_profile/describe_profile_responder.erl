%%% @doc RESPONDER for the `mcl-jobs/describe_profile' procedure.
%%%
%%% Describes the CALLER's own profile: the citizen is the node id that signed
%%% the CALL, so nobody can describe a profile for somebody else. Payload:
%%% `headline' (text), `skills' (list of text, optional), `location' (text,
%%% optional); the limits are describe_profile_v1's.
%%%
%%% Replies `#{}' once the event is stored, or `#{reason => Why}' naming
%%% the rule that refused it (README, "Procedures").
%%% @end
-module(describe_profile_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2, command/1]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    {reply, replied(dispatched(command(Payload))), State}.

%% @doc The command a CALL stands for: the caller's own profile.
-spec command(map()) -> {ok, describe_profile_v1:t()} | {error, atom()}.
command(Payload) ->
    for_caller(mcl_om_wire:caller(Payload), Payload).

for_caller(<<_:256>> = CitizenDid, Payload) ->
    describe_profile_v1:new(#{citizen_did => CitizenDid,
                              headline => mcl_om_wire:field(headline, Payload),
                              skills => mcl_om_wire:field(skills, Payload, []),
                              location => mcl_om_wire:field(location, Payload, <<>>)});
for_caller(_Missing, _Payload) ->
    {error, no_caller}.

dispatched({ok, Cmd}) -> maybe_describe_profile:dispatch(Cmd);
dispatched({error, _} = Refused) -> Refused.

replied({ok, _Version, _Events}) -> #{};
replied({error, Reason}) when is_atom(Reason) -> #{reason => {text, atom_to_binary(Reason)}};
replied({error, _Unexpected}) -> #{reason => {text, <<"internal_error">>}}.
