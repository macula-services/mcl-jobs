%%% @doc The organisation lifecycle rules, through the three callbacks evoq
%%% drives (init/1, execute/2, apply/2): no store, no mesh, no process.
-module(organisation_aggregate_tests).

-include_lib("eunit/include/eunit.hrl").

%% Synthetic: this repository is public.
-define(ORG, <<"org-example-0001">>).
-define(NAME, <<"Example Cooperative">>).

initiate() -> #{command_type => initiate_organisation_v1, organisation_id => ?ORG, name => ?NAME}.
archive() -> #{command_type => archive_organisation_v1, organisation_id => ?ORG}.

fresh() ->
    {ok, S} = organisation_aggregate:init(?ORG),
    S.

%% Executes one command and folds what it produced, as evoq does.
step(State, Cmd) ->
    folded(organisation_aggregate:execute(State, Cmd), State).

folded({ok, Events}, State) ->
    {ok, lists:foldl(fun(E, S) -> organisation_aggregate:apply(S, E) end, State, Events)};
folded({error, _} = E, _State) ->
    E.

initiating_an_organisation_records_it_and_its_name_test() ->
    {ok, [Ev]} = organisation_aggregate:execute(fresh(), initiate()),
    ?assertMatch(#{event_type := <<"organisation_initiated_v1">>, organisation_id := ?ORG,
                   name := ?NAME, initiated_at := At} when is_integer(At), Ev),
    {ok, S} = step(fresh(), initiate()),
    ?assertEqual(1, organisation_state:status(S)),
    ?assertEqual(?NAME, organisation_state:name(S)).

an_organisation_is_initiated_once_test() ->
    {ok, S} = step(fresh(), initiate()),
    ?assertEqual({error, already_initiated}, step(S, initiate())).

an_organisation_needs_a_name_test() ->
    ?assertEqual({error, missing_name},
                 step(fresh(), maps:remove(name, initiate()))),
    ?assertEqual({error, missing_name},
                 step(fresh(), (initiate())#{name => <<>>})).

cannot_archive_what_was_never_initiated_test() ->
    ?assertEqual({error, not_initiated}, step(fresh(), archive())).

archiving_an_initiated_organisation_records_it_test() ->
    {ok, S1} = step(fresh(), initiate()),
    {ok, [Ev]} = organisation_aggregate:execute(S1, archive()),
    ?assertMatch(#{event_type := <<"organisation_archived_v1">>, organisation_id := ?ORG}, Ev).

cannot_archive_twice_test() ->
    {ok, S1} = step(fresh(), initiate()),
    {ok, S2} = step(S1, archive()),
    ?assertEqual({error, already_archived}, step(S2, archive())).

an_archived_organisation_cannot_be_initiated_again_test() ->
    {ok, S1} = step(fresh(), initiate()),
    {ok, S2} = step(S1, archive()),
    ?assertEqual({error, already_initiated}, step(S2, initiate())).

a_command_without_its_organisation_is_refused_test() ->
    ?assertEqual({error, missing_organisation_id},
                 step(fresh(), maps:remove(organisation_id, initiate()))),
    ?assertEqual({error, missing_organisation_id},
                 step(fresh(), (initiate())#{organisation_id => <<>>})).

an_unknown_command_is_refused_test() ->
    ?assertEqual({error, unknown_command}, step(fresh(), #{command_type => rename_organisation_v1})),
    ?assertEqual({error, unknown_command}, step(fresh(), #{})).

the_stream_id_is_one_reckon_db_accepts_test() ->
    Id = organisation_aggregate:stream_id(?ORG),
    ?assertMatch({match, _}, re:run(Id, <<"^[a-z]{1,32}-[a-f0-9]{32}$">>)),
    ?assertNotEqual(Id, organisation_aggregate:stream_id(<<"org-example-0002">>)).

events_survive_the_round_trip_through_their_map_test() ->
    Ev = organisation_initiated_v1:new(#{organisation_id => ?ORG, name => ?NAME, initiated_at => 1}),
    ?assertEqual({ok, Ev}, organisation_initiated_v1:from_map(organisation_initiated_v1:to_map(Ev))),
    Ar = organisation_archived_v1:new(#{organisation_id => ?ORG, archived_at => 2}),
    ?assertEqual({ok, Ar}, organisation_archived_v1:from_map(organisation_archived_v1:to_map(Ar))).
