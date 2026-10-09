%%% @doc What a description may say: NFC text, no control or invisible
%%% format characters, bounded sizes. A public directory is where a reversed
%%% or invisibly padded headline would impersonate someone.
-module(describe_profile_v1_tests).

-include_lib("eunit/include/eunit.hrl").

-define(CITIZEN, <<16#c1:256>>).

new(Fields) ->
    describe_profile_v1:new(maps:merge(#{citizen_did => ?CITIZEN, headline => <<"Builds event stores">>},
                                       Fields)).

a_headline_alone_is_a_description_test() ->
    {ok, Cmd} = new(#{}),
    ?assertEqual([], describe_profile_v1:get_skills(Cmd)),
    ?assertEqual(<<>>, describe_profile_v1:get_location(Cmd)).

any_script_is_fine_test() ->
    ?assertMatch({ok, _}, new(#{headline => <<"Ingénieur · エンジニア · مهندس"/utf8>>,
                                skills => [<<"Erlang/OTP">>, <<"C++">>], location => <<"Tienen">>})).

text_is_stored_in_nfc_test() ->
    Decomposed = <<"Cafe", 16#cc, 16#81>>,
    {ok, Cmd} = new(#{headline => Decomposed}),
    ?assertEqual(<<"Caf", 16#c3, 16#a9>>, describe_profile_v1:get_headline(Cmd)).

invisible_and_control_characters_are_refused_test_() ->
    Bad = [<<"evil", 16#e2, 16#80, 16#ae, "txet">>,      %% U+202E right-to-left override
           <<"pad", 16#e2, 16#80, 16#8b>>,               %% U+200B zero-width space
           <<"iso", 16#e2, 16#81, 16#a6, "x">>,          %% U+2066 left-to-right isolate
           <<16#ef, 16#bb, 16#bf, "bom">>,               %% U+FEFF
           <<"line", 16#e2, 16#80, 16#a8, "sep">>,       %% U+2028
           <<"soft", 16#c2, 16#ad, "hyphen">>,           %% U+00AD
           <<"tab\there">>, <<"nl\n">>, <<16#c2, 16#85>>, <<255>>],
    [?_assertEqual({error, invalid_headline}, new(#{headline => B})) || B <- Bad] ++
    [?_assertEqual({error, invalid_skills}, new(#{skills => [B]})) || B <- Bad] ++
    [?_assertEqual({error, invalid_location}, new(#{location => B})) || B <- Bad].

sizes_are_bounded_test() ->
    ?assertEqual({error, invalid_headline}, new(#{headline => <<>>})),
    ?assertEqual({error, invalid_headline}, new(#{headline => binary:copy(<<"a">>, 201)})),
    ?assertMatch({ok, _}, new(#{headline => binary:copy(<<"a">>, 200)})),
    ?assertEqual({error, invalid_skills}, new(#{skills => [<<>>]})),
    ?assertEqual({error, invalid_skills}, new(#{skills => [binary:copy(<<"a">>, 65)]})),
    ?assertEqual({error, invalid_skills}, new(#{skills => lists:duplicate(31, <<"x">>)})),
    ?assertMatch({ok, _}, new(#{skills => lists:duplicate(30, <<"x">>)})),
    ?assertEqual({error, invalid_skills}, new(#{skills => <<"not a list">>})),
    ?assertEqual({error, invalid_location}, new(#{location => binary:copy(<<"a">>, 101)})).

the_headline_is_required_test() ->
    ?assertEqual({error, invalid_headline},
                 describe_profile_v1:new(#{citizen_did => ?CITIZEN})).

a_command_without_a_32_byte_caller_is_refused_test() ->
    ?assertEqual({error, no_caller}, describe_profile_v1:new(#{headline => <<"x">>})),
    ?assertEqual({error, no_caller},
                 describe_profile_v1:new(#{citizen_did => <<1:248>>, headline => <<"x">>})).

the_command_and_event_survive_their_maps_test() ->
    {ok, Cmd} = new(#{skills => [<<"Erlang">>], location => <<"Leuven">>}),
    ?assertEqual({ok, Cmd}, describe_profile_v1:from_map(describe_profile_v1:to_map(Cmd))),
    Ev = profile_described_v1:new(#{citizen_did => ?CITIZEN, headline => <<"h">>, skills => [],
                                    location => <<>>, described_at => 3}),
    ?assertEqual({ok, Ev}, profile_described_v1:from_map(profile_described_v1:to_map(Ev))).
