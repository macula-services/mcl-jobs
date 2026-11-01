%%% @doc Every procedure's reply, as a client reads it off the wire.
%%%
%%% The first 0.2.0 smoke run found the README and smoke.sh expecting
%%% get_profile_by_id as `{profile: {...}}' while the service answered the
%%% fields flat. The end-to-end suite asserted on the Erlang map and missed it
%%% (mcl-jobs#4). So this suite pins each procedure's reply keys in ONE table,
%%% `replies/0', and holds three things to it:
%%%
%%%   - each responder's own handle_request/2, called with a payload shaped as
%%%     macula delivers it and run against a real store and read model, gives
%%%     those keys once its reply has been through macula's own CBOR encoding
%%%     and the strict decoder a caller uses;
%%%   - a refusal is `{reason}' and nothing else, for every procedure;
%%%   - the README's procedure table names the same keys, and lists the same
%%%     procedures as capabilities/0.
-module(mcl_jobs_wire_replies_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("reckon_db/include/reckon_db.hrl").

%% Synthetic node ids: this repository is public.
-define(ALICE, <<16#a1:256>>).
-define(BOB, <<16#b0:256>>).
-define(MALLORY, <<16#ee:256>>).

-define(PROFILE, [<<"citizen">>, <<"headline">>, <<"location">>, <<"published">>, <<"skills">>]).
-define(ORGANISATION, [<<"archived">>, <<"initiated_at">>, <<"initiated_by">>, <<"name">>,
                       <<"organisation_id">>]).

%% THE TABLE. Per procedure: the keys every success reply carries, the keys
%% it may carry, and, for a page, the keys of each item on it.
replies() ->
    [{<<"initiate_profile">>,       {[], [], none}},
     {<<"describe_profile">>,       {[], [], none}},
     {<<"publish_profile">>,        {[], [], none}},
     {<<"withdraw_profile">>,       {[], [], none}},
     {<<"archive_profile">>,        {[], [], none}},
     {<<"initiate_organisation">>,  {[], [], none}},
     {<<"archive_organisation">>,   {[], [], none}},
     {<<"get_profile_by_id">>,      {?PROFILE, [], none}},
     {<<"get_profiles_page">>,      {[<<"profiles">>], [<<"next">>], {<<"profiles">>, ?PROFILE}}},
     {<<"get_organisation_by_id">>, {?ORGANISATION, [], none}},
     {<<"get_organisations_page">>, {[<<"organisations">>], [<<"next">>],
                                     {<<"organisations">>, ?ORGANISATION}}}].

%%--------------------------------------------------------------------
%% The table covers what the service announces, and the README says it
%%--------------------------------------------------------------------

the_table_names_every_announced_procedure_test() ->
    Announced = [maps:get(name, C) || C <- mcl_jobs_service:capabilities()],
    ?assertEqual(lists:sort(Announced), lists:sort(proplists:get_keys(replies()))).

the_readme_names_the_same_reply_keys_test() ->
    Expected = lists:sort([{Name, lists:sort(Required ++ [<<K/binary, "?">> || K <- Optional])}
                           || {Name, {Required, Optional, _}} <- replies()]),
    ?assertEqual(Expected, lists:sort(readme_replies())).

%%--------------------------------------------------------------------
%% The replies themselves, end to end with no mesh
%%--------------------------------------------------------------------

wire_replies_test_() ->
    {setup, fun start/0, fun stop/1,
     [{timeout, 60, fun every_success_reply_carries_the_table_keys/0},
      {timeout, 60, fun every_refusal_is_a_reason_and_nothing_else/0}]}.

every_success_reply_carries_the_table_keys() ->
    Seen = lists:append(
             [[call(initiate_profile, Who, #{}),
               call(describe_profile, Who, #{headline => {text, <<"Builds things">>},
                                             skills => [{text, <<"Erlang">>}],
                                             location => {text, <<"Leuven">>}}),
               call(publish_profile, Who, #{})] || Who <- [?ALICE, ?BOB]]
             ++ [[call(initiate_organisation, ?ALICE, #{organisation_id => {text, Id},
                                                        name => {text, <<"Example Co">>}})]
                 || Id <- [<<"org-wire-a">>, <<"org-wire-b">>]]),
    %% Projections land asynchronously; read once both pages are full.
    eventually(fun() -> length(items(call(get_profiles_page, ?MALLORY, #{}), <<"profiles">>)) end, 2),
    eventually(fun() -> length(items(call(get_organisations_page, ?MALLORY, #{}),
                                     <<"organisations">>)) end, 2),
    Reads = [call(get_profile_by_id, ?MALLORY, #{citizen => {text, hex(?ALICE)}}),
             %% A limit below the count, so `next' is on the wire.
             call(get_profiles_page, ?MALLORY, #{limit => 1}),
             call(get_profiles_page, ?MALLORY, #{}),
             call(get_organisation_by_id, ?MALLORY, #{organisation_id => {text, <<"org-wire-a">>}}),
             call(get_organisations_page, ?MALLORY, #{limit => 1}),
             call(get_organisations_page, ?MALLORY, #{})],
    Ends = [call(withdraw_profile, ?ALICE, #{}),
            call(archive_profile, ?BOB, #{}),
            call(archive_organisation, ?ALICE, #{organisation_id => {text, <<"org-wire-b">>}})],
    Calls = Seen ++ Reads ++ Ends,
    [?assertEqual({Name, conforms}, {Name, conforms(Name, Reply)}) || {Name, Reply} <- Calls],
    %% Both shapes of a page were seen, with and without `next'.
    Pages = [lists:member(<<"next">>, maps:keys(R)) || {N, R} <- Calls, N =:= <<"get_profiles_page">>],
    ?assertEqual([true, false], Pages),
    ?assertEqual(lists:sort(proplists:get_keys(replies())),
                 lists:usort([Name || {Name, _} <- Calls])).

every_refusal_is_a_reason_and_nothing_else() ->
    Refusals = [call_as(Name, #{}, undefined) || Name <- refused_without_a_caller()]
               ++ [call(get_profile_by_id, ?MALLORY, #{citizen => {text, <<"zz">>}}),
                   call(get_profiles_page, ?MALLORY, #{limit => 51}),
                   call(get_organisation_by_id, ?MALLORY, #{organisation_id => {text, <<"Bad Id">>}}),
                   call(get_organisations_page, ?MALLORY, #{limit => 0})],
    [?assertMatch({_, [<<"reason">>], {text, _}},
                  {Name, maps:keys(Reply), maps:get(<<"reason">>, Reply)})
     || {Name, Reply} <- Refusals],
    ?assertEqual(lists:sort(proplists:get_keys(replies())),
                 lists:usort([Name || {Name, _} <- Refusals])).

%% Every command acts as its caller, so with none it refuses.
refused_without_a_caller() ->
    [Name || {Name, {[], [], none}} <- replies()].

%%--------------------------------------------------------------------
%% Calling a responder as macula does
%%--------------------------------------------------------------------

call(Procedure, Caller, Args) -> call_as(atom_to_binary(Procedure), Args, Caller).

%% The args go through the wire the way a caller's do: encoded, strictly
%% decoded (every key and string arrives as `{text, _}'), with the signer
%% merged in as `caller'. The reply comes back the same way.
call_as(Name, Args, Caller) ->
    Responder = binary_to_atom(<<Name/binary, "_responder">>),
    {ok, Payload} = macula_record_cbor:decode_strict(macula_record_cbor:encode(Args)),
    {ok, St} = Responder:init([]),
    {reply, Reply, _} = Responder:handle_request(with_caller(Payload, Caller), St),
    {ok, Decoded} = macula_record_cbor:decode_strict(macula_record_cbor:encode(Reply)),
    {Name, plain_keys(Decoded)}.

with_caller(Payload, undefined) -> Payload;
with_caller(Payload, Caller) -> Payload#{caller => Caller}.

%% Text keys as the binaries a client names them by, all the way down.
plain_keys(Map) when is_map(Map) ->
    maps:from_list([{key(K), plain_keys(V)} || K := V <- Map]);
plain_keys(List) when is_list(List) -> [plain_keys(V) || V <- List];
plain_keys(Other) -> Other.

key({text, K}) -> K.

conforms(Name, Reply) ->
    {Required, Optional, Items} = proplists:get_value(Name, replies()),
    Keys = lists:sort(maps:keys(Reply)),
    conforms(Keys -- Optional =:= lists:sort(Required), Keys, item_keys(Reply, Items)).

conforms(true, _Keys, ok) -> conforms;
conforms(false, Keys, _) -> {wrong_keys, Keys};
conforms(true, _Keys, Wrong) -> Wrong.

item_keys(_Reply, none) -> ok;
item_keys(Reply, {List, Expected}) ->
    Wrong = [lists:sort(maps:keys(I)) || I <- maps:get(List, Reply),
                                          lists:sort(maps:keys(I)) =/= lists:sort(Expected)],
    item_keys(Wrong).

item_keys([]) -> ok;
item_keys(Wrong) -> {wrong_item_keys, Wrong}.

items({_Name, Reply}, List) -> maps:get(List, Reply, []).

hex(Id) -> binary:encode_hex(Id, lowercase).

eventually(Fun, Expected) -> eventually(Fun, Expected, 100).

eventually(Fun, Expected, 0) -> ?assertEqual(Expected, Fun());
eventually(Fun, Expected, Tries) -> again(Fun(), Fun, Expected, Tries).

again(Expected, _Fun, Expected, _Tries) -> ok;
again(_Other, Fun, Expected, Tries) -> timer:sleep(100), eventually(Fun, Expected, Tries - 1).

%%--------------------------------------------------------------------
%% The README's procedure table
%%--------------------------------------------------------------------

%% Each `| `mcl-jobs/<name>` | payload | `{...}`...' row, as {Name, Keys}:
%% the first code span of the answer column, its keys with any `"' dropped
%% and a trailing `?' kept for an optional one.
readme_replies() ->
    {ok, Text} = file:read_file(alongside("README.md")),
    {match, Rows} = re:run(Text, "^\\| `mcl-jobs/([a-z_]+)` \\|[^|]*\\| `(\\{[^`]*\\})`",
                           [multiline, global, {capture, all_but_first, binary}]),
    [{Name, lists:sort(answer_keys(Answer))} || [Name, Answer] <- Rows].

answer_keys(Answer) ->
    Inner = binary:part(Answer, 1, byte_size(Answer) - 2),
    Flat = re:replace(Inner, "\\[[^]]*\\]", "", [global, {return, binary}]),
    [K || Part <- binary:split(Flat, <<",">>, [global]),
          K <- [answer_key(Part)], K =/= <<>>].

answer_key(Part) ->
    [Key | _] = binary:split(Part, <<":">>),
    binary:replace(string:trim(Key), <<"\"">>, <<>>, [global]).

%%--------------------------------------------------------------------
%% Environment, as in mcl_jobs_read_side_tests
%%--------------------------------------------------------------------

start() ->
    Dir = filename:join(["/tmp", "mcl_jobs_wire_replies_tests",
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

alongside(Name) -> climb(filename:dirname(code:which(?MODULE)), Name, 8).

climb(_Dir, Name, 0) -> Name;
climb(Dir, Name, Left) ->
    Candidate = filename:join(Dir, Name),
    found(filelib:is_regular(Candidate), Candidate, Dir, Name, Left).

found(true, Candidate, _Dir, _Name, _Left) -> Candidate;
found(false, _Candidate, Dir, Name, Left) ->
    climb(filename:dirname(Dir), Name, Left - 1).
