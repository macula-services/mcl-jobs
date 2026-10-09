%%% @doc State of a profile aggregate.
%%%
%%% status is a bit-flag integer (profile_status.hrl), never an atom.
%%% @end
-module(profile_state).
-behaviour(evoq_state).

-include("profile_status.hrl").

-export([new/1, apply_event/2, to_map/1]).
-export([status/1, citizen_did/1]).

-record(state, {
    citizen_did :: binary() | undefined,
    status = 0 :: non_neg_integer()
}).

-type state() :: #state{}.
-export_type([state/0]).

-spec new(binary()) -> state().
new(CitizenDid) ->
    #state{citizen_did = CitizenDid}.

-spec status(state()) -> non_neg_integer().
status(#state{status = S}) -> S.

-spec citizen_did(state()) -> binary() | undefined.
citizen_did(#state{citizen_did = D}) -> D.

%% @doc Folds one event into state, matched on its event_type, which is
%% how the event also comes back on replay from the store.
-spec apply_event(state(), map()) -> state().
apply_event(S, #{event_type := <<"profile_initiated_v1">>} = Ev) ->
    S#state{citizen_did = maps:get(citizen_did, Ev),
            status = evoq_bit_flags:set(S#state.status, ?PROFILE_INITIATED)};
apply_event(S, #{event_type := <<"profile_archived_v1">>}) ->
    S#state{status = evoq_bit_flags:set(S#state.status, ?PROFILE_ARCHIVED)};
apply_event(S, #{event_type := <<"profile_described_v1">>}) ->
    S#state{status = evoq_bit_flags:set(S#state.status, ?PROFILE_DESCRIBED)};
apply_event(S, #{event_type := <<"profile_published_v1">>}) ->
    S#state{status = evoq_bit_flags:set(S#state.status, ?PROFILE_PUBLISHED)};
apply_event(S, #{event_type := <<"profile_withdrawn_v1">>}) ->
    S#state{status = evoq_bit_flags:unset(S#state.status, ?PROFILE_PUBLISHED)};
apply_event(S, _Unknown) ->
    S.

-spec to_map(state()) -> map().
to_map(#state{citizen_did = D, status = St}) ->
    #{citizen_did => D, status => St}.
