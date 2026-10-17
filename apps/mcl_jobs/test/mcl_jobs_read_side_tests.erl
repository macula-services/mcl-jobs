%%% @doc The whole released pipeline, end to end, with no mesh: commands
%%% dispatched into a real reckon-db store, the store subscription, evoq's
%%% router, the projections, the SQLite read model, and the query desks
%%% answering from it. This is where the visibility rule is proven from
%%% both sides: what an owner sees, and what everyone else does not.
-module(mcl_jobs_read_side_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("reckon_db/include/reckon_db.hrl").

%% Synthetic node ids: this repository is public.
-define(ALICE, <<16#a1:256>>).
-define(BOB, <<16#b0:256>>).
-define(MALLORY, <<16#ee:256>>).

read_side_test_() ->
    {setup, fun start/0, fun stop/1,
     [{timeout, 60, fun an_unpublished_profile_is_seen_only_by_its_owner/0},
      {timeout, 60, fun a_published_profile_is_seen_by_anyone_until_withdrawn/0},
      {timeout, 60, fun an_archived_profile_is_seen_by_nobody/0},
      {timeout, 60, fun profiles_page_in_citizen_order/0},
      {timeout, 60, fun organisations_are_public_and_archive_leaves_the_page/0},
      {timeout, 60, fun malformed_queries_are_refused_by_name/0},
      {timeout, 60, fun a_replayed_older_description_changes_nothing/0}]}.

%%--------------------------------------------------------------------
%% Environment
%%--------------------------------------------------------------------

start() ->
    Dir = filename:join(["/tmp", "mcl_jobs_read_side_tests",
                         integer_to_list(erlang:unique_integer([positive]))]),
    _ = application:load(evoq),
    [ok = application:set_env(evoq, K, V)
     || {K, V} <- [{event_store_adapter, reckon_evoq_adapter},
                   {subscription_adapter, reckon_evoq_adapter},
                   {snapshot_store_adapter, reckon_evoq_adapter},
                   {store_id, mcl_jobs_store}]],
    os:putenv("MCL_DATA_DIR", Dir),
    {ok, Started} = application:ensure_all_started([reckon_db, evoq, reckon_evoq, esqlite,
                                                    project_jobs]),
    {ok, _} = reckon_db_sup:start_store(#store_config{store_id = mcl_jobs_store,
                                                      data_dir = filename:join(Dir, "store"),
                                                      mode = single}),
    {ok, Sub} = evoq_store_subscription:start_link(mcl_jobs_store),
    unlink(Sub),
    {ok, Query} = jobs_query_store:start_link(project_jobs_sup:sqlite_path()),
    unlink(Query),
    {Dir, Started, Sub, Query}.

stop({Dir, Started, Sub, Query}) ->
    exit(Query, shutdown),
    exit(Sub, shutdown),
    [application:stop(App) || App <- lists:reverse(Started)],
    os:unsetenv("MCL_DATA_DIR"),
    file:del_dir_r(Dir).

%% Dispatch as the responder would, through each desk's own dispatch.
profile(Desk, Who, Fields) ->
    {ok, Cmd} = (cmd_module(Desk)):new(Fields#{citizen_did => Who}),
    {ok, _, _} = (handler(Desk)):dispatch(Cmd).

cmd_module(Desk) -> list_to_atom(atom_to_list(Desk) ++ "_profile_v1").
handler(Desk) -> list_to_atom("maybe_" ++ atom_to_list(Desk) ++ "_profile").

described(Who, Headline) ->
    profile(describe, Who, #{headline => Headline, skills => [<<"Erlang">>, <<"SQL">>],
                             location => <<"Leuven">>}).

hex(Id) -> binary:encode_hex(Id, lowercase).

%% Projections are asynchronous: ask until the answer is the expected one.
eventually(Fun, Expected) -> eventually(Fun, Expected, 100).

eventually(Fun, Expected, 0) -> ?assertEqual(Expected, Fun());
eventually(Fun, Expected, Tries) -> again(Fun(), Fun, Expected, Tries).

again(Expected, _Fun, Expected, _Tries) -> ok;
again(_Other, Fun, Expected, Tries) -> timer:sleep(100), eventually(Fun, Expected, Tries - 1).

seen_by(Who, Citizen) ->
    published(get_profile_by_id:find(hex(Citizen), Who)).

published({ok, #{published := P}}) -> {seen, P};
published({error, Reason}) -> Reason.

%% The described fields, or the read's error while the row is not there yet.
%% `initiate' and `describe' are separate commands, so their projections land
%% separately: a test that reads the fields after waiting only for the row to
%% exist is racing the second projection, and reads the empty fields
%% `initiate' wrote.
described_fields(Who, Citizen) ->
    fields(get_profile_by_id:find(hex(Citizen), Who)).

fields({ok, #{headline := H, skills := S, location := L}}) -> {H, S, L};
fields({error, Reason}) -> Reason.

%%--------------------------------------------------------------------
%% Profiles
%%--------------------------------------------------------------------

an_unpublished_profile_is_seen_only_by_its_owner() ->
    profile(initiate, ?ALICE, #{}),
    described(?ALICE, <<"Builds event stores">>),
    %% Wait for the described row, not just for the row: the assertions below
    %% read the fields `describe' writes.
    eventually(fun() -> described_fields(?ALICE, ?ALICE) end,
               {<<"Builds event stores">>, [<<"Erlang">>, <<"SQL">>], <<"Leuven">>}),
    eventually(fun() -> seen_by(?ALICE, ?ALICE) end, {seen, 0}),
    ?assertEqual(not_found, seen_by(?MALLORY, ?ALICE)),
    ?assertEqual(not_found, seen_by(undefined, ?ALICE)),
    {ok, #{headline := H, skills := S, location := L}} = get_profile_by_id:find(hex(?ALICE), ?ALICE),
    ?assertEqual({<<"Builds event stores">>, [<<"Erlang">>, <<"SQL">>], <<"Leuven">>}, {H, S, L}).

a_published_profile_is_seen_by_anyone_until_withdrawn() ->
    profile(publish, ?ALICE, #{}),
    eventually(fun() -> seen_by(?MALLORY, ?ALICE) end, {seen, 1}),
    ?assertEqual({seen, 1}, seen_by(undefined, ?ALICE)),
    %% The owner's hex in upper case names the same profile.
    ?assertMatch({ok, _}, get_profile_by_id:find(binary:encode_hex(?ALICE, uppercase), ?MALLORY)),
    profile(withdraw, ?ALICE, #{}),
    eventually(fun() -> seen_by(?MALLORY, ?ALICE) end, not_found),
    ?assertEqual({seen, 0}, seen_by(?ALICE, ?ALICE)).

an_archived_profile_is_seen_by_nobody() ->
    profile(initiate, ?BOB, #{}),
    described(?BOB, <<"Writes compilers">>),
    profile(publish, ?BOB, #{}),
    eventually(fun() -> seen_by(?MALLORY, ?BOB) end, {seen, 1}),
    profile(archive, ?BOB, #{}),
    eventually(fun() -> seen_by(?BOB, ?BOB) end, not_found),
    ?assertEqual(not_found, seen_by(?MALLORY, ?BOB)),
    ?assertEqual(not_found, seen_by(?MALLORY, <<16#12:256>>)).

profiles_page_in_citizen_order() ->
    Citizens = [<<N:256>> || N <- [16#c1, 16#c2, 16#c3]],
    [begin profile(initiate, C, #{}), described(C, <<"h">>), profile(publish, C, #{}) end
     || C <- Citizens],
    Seen = fun() -> page_citizens(get_profiles_page:page(undefined, 50, ?MALLORY)) end,
    eventually(Seen, [hex(C) || C <- Citizens]),
    {ok, #{profiles := [_, _], next := Next}} = get_profiles_page:page(undefined, 2, ?MALLORY),
    ?assertEqual({ok, [hex(<<16#c3:256>>)]},
                 {ok, page_citizens(get_profiles_page:page(Next, 2, ?MALLORY))}),
    %% Alice's own withdrawn profile appears on her page only.
    ?assert(lists:member(hex(?ALICE), page_citizens(get_profiles_page:page(undefined, 50, ?ALICE)))),
    ?assertNot(lists:member(hex(?ALICE), Seen())).

page_citizens({ok, #{profiles := Ps}}) -> [C || #{citizen := C} <- Ps].

%%--------------------------------------------------------------------
%% Organisations
%%--------------------------------------------------------------------

organisations_are_public_and_archive_leaves_the_page() ->
    Org = fun(Id) ->
        {ok, C} = initiate_organisation_v1:new(#{organisation_id => Id, name => <<"Example Co">>,
                                                 initiated_by => ?ALICE}),
        {ok, _, _} = maybe_initiate_organisation:dispatch(C)
    end,
    Org(<<"org-example-a">>),
    Org(<<"org-example-b">>),
    eventually(fun() -> org_ids(get_organisations_page:page(undefined, 50)) end,
               [<<"org-example-a">>, <<"org-example-b">>]),
    {ok, #{name := <<"Example Co">>, initiated_by := By, archived := 0}} =
        get_organisation_by_id:find(<<"org-example-a">>),
    ?assertEqual(hex(?ALICE), By),
    {ok, A} = archive_organisation_v1:new(#{organisation_id => <<"org-example-a">>,
                                            archived_by => ?ALICE}),
    {ok, _, _} = maybe_archive_organisation:dispatch(A),
    eventually(fun() -> org_ids(get_organisations_page:page(undefined, 50)) end,
               [<<"org-example-b">>]),
    ?assertMatch({ok, #{archived := 1}}, get_organisation_by_id:find(<<"org-example-a">>)),
    ?assertEqual({error, not_found}, get_organisation_by_id:find(<<"org-example-z">>)).

org_ids({ok, #{organisations := Os}}) -> [I || #{organisation_id := I} <- Os].

%%--------------------------------------------------------------------
%% Refusals and replays
%%--------------------------------------------------------------------

malformed_queries_are_refused_by_name() ->
    ?assertEqual({error, invalid_citizen}, get_profile_by_id:find(<<"zz">>, ?ALICE)),
    ?assertEqual({error, invalid_citizen}, get_profile_by_id:find(binary:copy(<<"g">>, 64), ?ALICE)),
    ?assertEqual({error, invalid_cursor}, get_profiles_page:page(<<"nope">>, 10, ?ALICE)),
    ?assertEqual({error, invalid_limit}, get_profiles_page:page(undefined, 51, ?ALICE)),
    ?assertEqual({error, invalid_limit}, get_organisations_page:page(undefined, 0)),
    ?assertEqual({error, invalid_cursor}, get_organisations_page:page(<<"Bad Id">>, 10)),
    ?assertEqual({error, invalid_organisation_id}, get_organisation_by_id:find(<<"Bad Id">>)).

%% An older description delivered after a newer one (a replay, or delivery
%% out of order) does not bring the old text back.
a_replayed_older_description_changes_nothing() ->
    described(?ALICE, <<"Newer headline">>),
    eventually(fun() -> headline(?ALICE) end, <<"Newer headline">>),
    Old = #{data => #{citizen_did => ?ALICE, headline => <<"Stale">>, skills => [],
                      location => <<>>}, version => 0},
    {ok, _} = profile_described_v1_to_sqlite_profiles:handle_event(
                <<"profile_described_v1">>, Old, #{}, #{}),
    ?assertEqual(<<"Newer headline">>, headline(?ALICE)).

headline(Who) ->
    {ok, #{headline := H}} = get_profile_by_id:find(hex(Who), Who),
    H.
