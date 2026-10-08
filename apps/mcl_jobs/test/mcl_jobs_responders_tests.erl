%%% @doc The four responders act as the CALL's caller, and only as it.
%%%
%%% command/1 is the whole of what a responder decides before dispatch: which
%%% command a CALL stands for. A profile is always the caller's own, whatever
%%% the payload names; an organisation's initiator or archiver is always the
%%% caller. A caller that is not a 32-byte node id is no caller. The dispatch
%%% itself runs against the live store in scripts/smoke.sh.
-module(mcl_jobs_responders_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ALICE, <<16#a1:256>>).
-define(MALLORY, <<16#ee:256>>).
-define(ORG, {text, <<"org-example-0001">>}).

profile_responders_act_on_the_callers_own_profile_test() ->
    Payload = #{caller => ?ALICE, citizen_did => ?MALLORY},
    {ok, I} = initiate_profile_responder:command(Payload),
    ?assertEqual(?ALICE, initiate_profile_v1:get_citizen_did(I)),
    {ok, A} = archive_profile_responder:command(Payload),
    ?assertEqual(?ALICE, archive_profile_v1:get_citizen_did(A)).

organisation_responders_record_the_caller_test() ->
    {ok, I} = initiate_organisation_responder:command(
                #{caller => ?ALICE, organisation_id => ?ORG, name => {text, <<"Example">>},
                  initiated_by => ?MALLORY}),
    ?assertEqual(?ALICE, initiate_organisation_v1:get_initiated_by(I)),
    ?assertEqual(<<"org-example-0001">>, initiate_organisation_v1:get_organisation_id(I)),
    {ok, A} = archive_organisation_responder:command(
                #{caller => ?ALICE, organisation_id => ?ORG, archived_by => ?MALLORY}),
    ?assertEqual(?ALICE, archive_organisation_v1:get_archived_by(A)).

every_responder_refuses_a_call_without_a_node_id_caller_test_() ->
    Payloads = [#{organisation_id => ?ORG, name => {text, <<"Example">>}},
                #{caller => {text, binary:encode_hex(?ALICE)}, organisation_id => ?ORG,
                  name => {text, <<"Example">>}},
                #{caller => <<16#a1:248>>, organisation_id => ?ORG, name => {text, <<"Example">>}}],
    [?_assertEqual({error, no_caller}, R:command(P))
     || R <- [initiate_profile_responder, archive_profile_responder,
              initiate_organisation_responder, archive_organisation_responder],
        P <- Payloads].

a_refusal_is_reported_as_text_without_touching_the_store_test() ->
    ?assertEqual({reply, #{reason => {text, <<"no_caller">>}}, []},
                 initiate_profile_responder:handle_request(#{}, [])),
    ?assertEqual({reply, #{reason => {text, <<"invalid_organisation_id">>}}, []},
                 initiate_organisation_responder:handle_request(
                   #{caller => ?ALICE, organisation_id => {text, <<"Not Valid">>},
                     name => {text, <<"Example">>}}, [])).
