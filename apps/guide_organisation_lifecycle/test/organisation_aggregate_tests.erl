%%% @doc The organisation lifecycle rules, through the three callbacks evoq
%%% drives (init/1, execute/2, apply/2): no store, no mesh, no process.
-module(organisation_aggregate_tests).

-include_lib("eunit/include/eunit.hrl").

%% Synthetic: this repository is public.
-define(ORG, <<"org-example-0001">>).
-define(NAME, <<"Example Cooperative"/utf8>>).
-define(FOUNDER, <<16#a1:256>>).
-define(STRANGER, <<16#ee:256>>).

initiate() ->
    #{command_type => initiate_organisation_v1, organisation_id => ?ORG, name => ?NAME,
      initiated_by => ?FOUNDER}.
archive(By) ->
    #{command_type => archive_organisation_v1, organisation_id => ?ORG, archived_by => By}.
archive() -> archive(?FOUNDER).

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

initiated() ->
    {ok, S} = step(fresh(), initiate()),
    S.

initiating_an_organisation_records_it_its_name_and_its_founder_test() ->
    {ok, [Ev]} = organisation_aggregate:execute(fresh(), initiate()),
    ?assertMatch(#{event_type := <<"organisation_initiated_v1">>, organisation_id := ?ORG,
                   name := ?NAME, initiated_by := ?FOUNDER, initiated_at := At}
                   when is_integer(At), Ev),
    S = initiated(),
    ?assertEqual(1, organisation_state:status(S)),
    ?assertEqual(?NAME, organisation_state:name(S)),
    ?assertEqual(?FOUNDER, organisation_state:initiated_by(S)).

an_organisation_is_initiated_once_test() ->
    ?assertEqual({error, already_initiated}, step(initiated(), initiate())),
    ?assertEqual({error, already_initiated},
                 step(initiated(), (initiate())#{initiated_by => ?STRANGER})).

cannot_archive_what_was_never_initiated_test() ->
    ?assertEqual({error, not_initiated}, step(fresh(), archive())).

archiving_by_the_founder_records_it_test() ->
    {ok, [Ev]} = organisation_aggregate:execute(initiated(), archive()),
    ?assertMatch(#{event_type := <<"organisation_archived_v1">>, organisation_id := ?ORG,
                   archived_by := ?FOUNDER}, Ev).

only_the_founder_may_archive_test() ->
    ?assertEqual({error, not_initiator}, step(initiated(), archive(?STRANGER))).

a_stranger_learns_nothing_about_an_archived_organisation_test() ->
    {ok, Archived} = step(initiated(), archive()),
    ?assertEqual({error, not_initiator}, step(Archived, archive(?STRANGER))).

cannot_archive_twice_test() ->
    {ok, Archived} = step(initiated(), archive()),
    ?assertEqual({error, already_archived}, step(Archived, archive())).

an_archived_organisation_cannot_be_initiated_again_test() ->
    {ok, Archived} = step(initiated(), archive()),
    ?assertEqual({error, already_initiated}, step(Archived, initiate())).

an_unknown_command_is_refused_test() ->
    ?assertEqual({error, unknown_command}, step(fresh(), #{command_type => rename_organisation_v1})),
    ?assertEqual({error, unknown_command}, step(fresh(), #{})).

%%--------------------------------------------------------------------
%% What a command accepts
%%--------------------------------------------------------------------

new(Fields) -> initiate_organisation_v1:new(maps:merge(maps:remove(command_type, initiate()), Fields)).

a_valid_initiation_is_accepted_test() ->
    ?assertMatch({ok, _}, new(#{})).

the_organisation_id_is_short_lowercase_text_test_() ->
    [?_assertEqual({error, invalid_organisation_id}, new(#{organisation_id => Id}))
     || Id <- [<<>>, <<"Org">>, <<"org one">>, <<"org/1">>, binary:copy(<<"a">>, 65), 42]].

the_name_is_required_test() ->
    ?assertEqual({error, missing_name}, new(#{name => <<>>})),
    ?assertEqual({error, missing_name},
                 initiate_organisation_v1:new(#{organisation_id => ?ORG, initiated_by => ?FOUNDER})).

the_name_is_printable_utf8_of_bounded_size_test_() ->
    [?_assertEqual({error, invalid_name}, new(#{name => N}))
     || N <- [<<"line\nbreak">>, <<"esc", 27, "[2J">>, <<16#c2, 16#85>>, <<255, 254>>,
              binary:copy(<<"a">>, 201),
              <<"Acme", 16#e2, 16#80, 16#ae, "evil">>,     %% U+202E right-to-left override
              <<"Ac", 16#e2, 16#80, 16#8b, "me">>]].       %% U+200B zero-width space

the_name_is_kept_in_nfc_test() ->
    {ok, Cmd} = new(#{name => <<"Cafe", 16#cc, 16#81>>}),
    ?assertEqual(<<"Caf", 16#c3, 16#a9>>, initiate_organisation_v1:get_name(Cmd)).

a_name_in_any_script_is_fine_test() ->
    ?assertMatch({ok, _}, new(#{name => <<"Coöperatie Zuid · 協同組合"/utf8>>})).

a_command_without_a_32_byte_caller_is_refused_test_() ->
    [?_assertEqual({error, no_caller}, new(#{initiated_by => By}))
     || By <- [undefined, <<>>, <<16#a1:248>>, binary:encode_hex(?FOUNDER)]].

archive_validates_the_id_and_the_caller_test() ->
    ?assertEqual({error, invalid_organisation_id},
                 archive_organisation_v1:new(#{organisation_id => <<"Bad Id">>, archived_by => ?FOUNDER})),
    ?assertEqual({error, no_caller},
                 archive_organisation_v1:new(#{organisation_id => ?ORG})).

the_stream_id_is_one_reckon_db_accepts_test() ->
    Id = organisation_aggregate:stream_id(?ORG),
    ?assertMatch({match, _}, re:run(Id, <<"^[a-z]{1,32}-[a-f0-9]{32}$">>)),
    ?assertNotEqual(Id, organisation_aggregate:stream_id(<<"org-example-0002">>)).

events_survive_the_round_trip_through_their_map_test() ->
    Ev = organisation_initiated_v1:new(#{organisation_id => ?ORG, name => ?NAME,
                                         initiated_by => ?FOUNDER, initiated_at => 1}),
    ?assertEqual({ok, Ev}, organisation_initiated_v1:from_map(organisation_initiated_v1:to_map(Ev))),
    Ar = organisation_archived_v1:new(#{organisation_id => ?ORG, archived_by => ?FOUNDER,
                                        archived_at => 2}),
    ?assertEqual({ok, Ar}, organisation_archived_v1:from_map(organisation_archived_v1:to_map(Ar))).
