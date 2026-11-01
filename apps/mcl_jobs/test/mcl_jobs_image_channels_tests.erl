%% @doc Which registry tags each push publishes, asserted locally.
%%
%% `:latest' is what anyone outside the fleet pulls, and what
%% deploy/docker-compose.yml runs. It must name a signed release and never an
%% unreviewed tip of main (mcl-jobs#9). The tag list comes from
%% scripts/image_tags.sh, so this suite runs that script for each kind of ref
%% build-push.yml can see; and it reads the workflow, so the one job that does
%% move `:latest' stays behind the v* tag and the signature.
-module(mcl_jobs_image_channels_tests).

-include_lib("eunit/include/eunit.hrl").

-define(IMAGE, "ghcr.io/macula-services/mcl-jobs").
-define(SHA, "e33a0f2c0ffee0000000000000000000000000ab").

%% A push to main publishes the tip for trying, under :main and :<sha>, and
%% nothing anybody follows.
main_publishes_main_and_its_sha_and_never_latest_test() ->
    ?assertEqual({0, "tags=" ?IMAGE ":main " ?IMAGE ":" ?SHA},
                 tags("refs/heads/main")).

%% A v* tag publishes its version ONLY. :latest moves later, in
%% promote-latest, once attest has signed this digest.
a_release_tag_publishes_its_version_only_test() ->
    ?assertEqual({0, "tags=" ?IMAGE ":0.4.1"}, tags("refs/tags/v0.4.1")).

%% workflow_dispatch can run from any branch; a branch build must publish
%% nothing at all, and say why.
any_other_ref_is_refused_naming_it_test() ->
    {Status, Out} = tags("refs/heads/some-branch"),
    ?assertNotEqual(0, Status),
    ?assertNotEqual(nomatch, string:find(Out, "refs/heads/some-branch")),
    ?assertEqual(nomatch, string:find(Out, "tags=")).

%% The workflow takes its tags from the script, so the cases above are the
%% ones that ship.
the_workflow_sets_its_tags_from_the_script_test() ->
    ?assertMatch({match, _}, re:run(workflow(), "scripts/image_tags\\.sh")).

%% :latest appears in exactly one job, promote-latest. That job runs only for
%% a v* tag, and only after attest.
only_promote_latest_moves_latest_and_only_after_a_signed_release_test() ->
    Jobs = jobs(workflow()),
    ?assertEqual(["promote-latest"],
                 [Name || {Name, Body} <- Jobs, mentions_latest(Body)]),
    Promote = proplists:get_value("promote-latest", Jobs),
    ?assertMatch({match, _}, re:run(Promote, "^    needs: \\[build-and-push, attest\\]$", [multiline])),
    ?assertMatch({match, _}, re:run(Promote, "^    if: startsWith\\(github\\.ref, 'refs/tags/v'\\)", [multiline])).

%% No image while the service's own tests are red: the build waits on them.
the_build_waits_on_the_tests_test() ->
    Build = proplists:get_value("build-and-push", jobs(workflow())),
    ?assertMatch({match, _}, re:run(Build, "^    needs: \\[guard, test\\]$", [multiline])).

%%------------------------------------------------------------------------------

tags(Ref) ->
    Cmd = "GITHUB_REF=" ++ Ref ++ " GITHUB_SHA=" ++ ?SHA ++ " sh "
          ++ alongside("scripts/image_tags.sh") ++ " 2>&1; echo \"exit=$?\"",
    Lines = string:split(string:trim(os:cmd(Cmd)), "\n", all),
    {Body, ["exit=" ++ Status]} = lists:split(length(Lines) - 1, Lines),
    {list_to_integer(Status), lists:flatten(lists:join("\n", Body))}.

workflow() ->
    {ok, Text} = file:read_file(alongside(".github/workflows/build-push.yml")),
    binary_to_list(Text).

%% The top-level jobs, each with its own text up to the next job. Comments go,
%% so a job explaining :latest is not taken for one moving it.
jobs(Text) ->
    [_, After] = string:split(Text, "\njobs:\n"),
    Code = [L || L <- string:split(After, "\n", all), not is_comment(L)],
    split_jobs(Code, []).

split_jobs([], Acc) -> lists:reverse(Acc);
split_jobs(["  " ++ [C | _] = Line | Rest], Acc) when C =/= $\s ->
    Name = string:trim(Line, trailing, ":"),
    {Body, Next} = lists:splitwith(fun(L) -> not is_job_line(L) end, Rest),
    split_jobs(Next, [{string:trim(Name), lists:flatten(lists:join("\n", Body))} | Acc]);
split_jobs([_ | Rest], Acc) -> split_jobs(Rest, Acc).

is_job_line("  " ++ [C | _]) -> C =/= $\s;
is_job_line(_) -> false.

is_comment(Line) -> lists:prefix("#", string:trim(Line, leading)).

mentions_latest(Body) -> string:find(Body, ":latest") =/= nomatch.

%% Relative to the beam rather than the working directory, as in
%% mcl_jobs_service_tests.
alongside(Name) -> climb(filename:dirname(code:which(?MODULE)), Name, 8).

climb(_Dir, Name, 0) -> Name;
climb(Dir, Name, Left) ->
    Candidate = filename:join(Dir, Name),
    found(filelib:is_regular(Candidate), Candidate, Dir, Name, Left).

found(true, Candidate, _Dir, _Name, _Left) -> Candidate;
found(false, _Candidate, Dir, Name, Left) ->
    climb(filename:dirname(Dir), Name, Left - 1).
