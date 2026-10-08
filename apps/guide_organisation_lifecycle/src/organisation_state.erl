%%% @doc State of an organisation aggregate.
%%%
%%% status is a bit-flag integer (organisation_status.hrl), never an atom.
%%% @end
-module(organisation_state).
-behaviour(evoq_state).

-include("organisation_status.hrl").

-export([new/1, apply_event/2, to_map/1]).
-export([status/1, organisation_id/1, name/1]).

-record(state, {
    organisation_id :: binary() | undefined,
    name :: binary() | undefined,
    status = 0 :: non_neg_integer()
}).

-type state() :: #state{}.
-export_type([state/0]).

-spec new(binary()) -> state().
new(OrganisationId) ->
    #state{organisation_id = OrganisationId}.

-spec status(state()) -> non_neg_integer().
status(#state{status = S}) -> S.

-spec organisation_id(state()) -> binary() | undefined.
organisation_id(#state{organisation_id = D}) -> D.

-spec name(state()) -> binary() | undefined.
name(#state{name = N}) -> N.

%% @doc Folds one event into state, matched on its event_type, which is
%% how the event also comes back on replay from the store.
-spec apply_event(state(), map()) -> state().
apply_event(S, #{event_type := <<"organisation_initiated_v1">>} = Ev) ->
    S#state{organisation_id = maps:get(organisation_id, Ev),
            name = maps:get(name, Ev),
            status = evoq_bit_flags:set(S#state.status, ?ORGANISATION_INITIATED)};
apply_event(S, #{event_type := <<"organisation_archived_v1">>}) ->
    S#state{status = evoq_bit_flags:set(S#state.status, ?ORGANISATION_ARCHIVED)};
apply_event(S, _Unknown) ->
    S.

-spec to_map(state()) -> map().
to_map(#state{organisation_id = D, name = N, status = St}) ->
    #{organisation_id => D, name => N, status => St}.
