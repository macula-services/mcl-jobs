%%% @doc The profile lifecycle rules, through the three callbacks evoq
%%% drives (init/1, execute/2, apply/2): no store, no mesh, no process.
-module(profile_aggregate_tests).

-include_lib("eunit/include/eunit.hrl").

%% Synthetic: this repository is public.
-define(CITIZEN, <<"did:example:citizen-0001">>).

initiate() -> #{command_type => initiate_profile_v1, citizen_did => ?CITIZEN}.
archive() -> #{command_type => archive_profile_v1, citizen_did => ?CITIZEN}.

fresh() ->
    {ok, S} = profile_aggregate:init(?CITIZEN),
    S.

%% Executes one command and folds what it produced, as evoq does.
step(State, Cmd) ->
    folded(profile_aggregate:execute(State, Cmd), State).

folded({ok, Events}, State) ->
    {ok, lists:foldl(fun(E, S) -> profile_aggregate:apply(S, E) end, State, Events)};
folded({error, _} = E, _State) ->
    E.

initiating_a_profile_records_it_test() ->
    {ok, [Ev]} = profile_aggregate:execute(fresh(), initiate()),
    ?assertMatch(#{event_type := <<"profile_initiated_v1">>, citizen_did := ?CITIZEN,
                   initiated_at := At} when is_integer(At), Ev),
    {ok, S} = step(fresh(), initiate()),
    ?assertEqual(1, profile_state:status(S)).

a_profile_is_initiated_once_test() ->
    {ok, S} = step(fresh(), initiate()),
    ?assertEqual({error, already_initiated}, step(S, initiate())).

cannot_archive_what_was_never_initiated_test() ->
    ?assertEqual({error, not_initiated}, step(fresh(), archive())).

archiving_an_initiated_profile_records_it_test() ->
    {ok, S1} = step(fresh(), initiate()),
    {ok, [Ev]} = profile_aggregate:execute(S1, archive()),
    ?assertMatch(#{event_type := <<"profile_archived_v1">>, citizen_did := ?CITIZEN}, Ev).

cannot_archive_twice_test() ->
    {ok, S1} = step(fresh(), initiate()),
    {ok, S2} = step(S1, archive()),
    ?assertEqual({error, already_archived}, step(S2, archive())).

an_archived_profile_cannot_be_initiated_again_test() ->
    {ok, S1} = step(fresh(), initiate()),
    {ok, S2} = step(S1, archive()),
    ?assertEqual({error, already_initiated}, step(S2, initiate())).

a_command_without_its_citizen_is_refused_test() ->
    ?assertEqual({error, missing_citizen_did},
                 step(fresh(), #{command_type => initiate_profile_v1})),
    ?assertEqual({error, missing_citizen_did},
                 step(fresh(), #{command_type => initiate_profile_v1, citizen_did => <<>>})).

an_unknown_command_is_refused_test() ->
    ?assertEqual({error, unknown_command}, step(fresh(), #{command_type => promote_profile_v1})),
    ?assertEqual({error, unknown_command}, step(fresh(), #{})).

the_stream_id_is_one_reckon_db_accepts_test() ->
    Id = profile_aggregate:stream_id(?CITIZEN),
    ?assertMatch({match, _}, re:run(Id, <<"^[a-z]{1,32}-[a-f0-9]{32}$">>)),
    ?assertEqual(Id, profile_aggregate:stream_id(?CITIZEN)),
    ?assertNotEqual(Id, profile_aggregate:stream_id(<<"did:example:citizen-0002">>)).

events_survive_the_round_trip_through_their_map_test() ->
    Ev = profile_initiated_v1:new(#{citizen_did => ?CITIZEN, initiated_at => 1}),
    ?assertEqual({ok, Ev}, profile_initiated_v1:from_map(profile_initiated_v1:to_map(Ev))),
    Ar = profile_archived_v1:new(#{citizen_did => ?CITIZEN, archived_at => 2}),
    ?assertEqual({ok, Ar}, profile_archived_v1:from_map(profile_archived_v1:to_map(Ar))).
