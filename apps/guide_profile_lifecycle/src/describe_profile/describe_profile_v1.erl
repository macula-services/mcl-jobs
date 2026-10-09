%%% @doc Command `describe_profile_v1'.
%%%
%%% What a citizen says about themselves: a headline, up to 30 skills and a
%%% location. It replaces the whole previous description. Once published,
%%% the new description is what the realm sees at once; no re-publish is
%%% needed. Text follows profile_description_text: NFC, no control or
%%% invisible format characters. Limits, in NFC bytes: headline 1 to 200,
%%% each skill 1 to 64, location 0 to 100.
%%% @end
-module(describe_profile_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_citizen_did/1, get_headline/1, get_skills/1, get_location/1]).

-define(MAX_SKILLS, 30).

-record(describe_profile_v1, {
    citizen_did :: <<_:256>>,
    headline :: binary(),
    skills :: [binary()],
    location :: binary()
}).

-opaque t() :: #describe_profile_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> describe_profile_v1.

%% @doc A command that exists is a valid one, its text already normalised.
-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{citizen_did := <<_:256>> = Did} = Params) ->
    described(Did,
              profile_description_text:checked(maps:get(headline, Params, undefined), 1, 200),
              skills(maps:get(skills, Params, [])),
              profile_description_text:checked(maps:get(location, Params, <<>>), 0, 100));
new(_) ->
    {error, no_caller}.

%% @doc Rebuilds a command already validated by new/1, as evoq hands it back.
-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{citizen_did := <<_:256>> = Did, headline := H, skills := S, location := L})
  when is_binary(H), is_list(S), is_binary(L) ->
    {ok, #describe_profile_v1{citizen_did = Did, headline = H, skills = S, location = L}};
from_map(_) ->
    {error, invalid_description}.

-spec validate(t()) -> ok | {error, term()}.
validate(#describe_profile_v1{}) -> ok.

-spec to_map(t()) -> map().
to_map(#describe_profile_v1{citizen_did = Did, headline = H, skills = S, location = L}) ->
    #{command_type => describe_profile_v1, citizen_did => Did,
      headline => H, skills => S, location => L}.

-spec stream_id(t()) -> binary().
stream_id(#describe_profile_v1{citizen_did = Did}) ->
    profile_aggregate:stream_id(Did).

-spec get_citizen_did(t()) -> <<_:256>>.
get_citizen_did(#describe_profile_v1{citizen_did = V}) -> V.

-spec get_headline(t()) -> binary().
get_headline(#describe_profile_v1{headline = V}) -> V.

-spec get_skills(t()) -> [binary()].
get_skills(#describe_profile_v1{skills = V}) -> V.

-spec get_location(t()) -> binary().
get_location(#describe_profile_v1{location = V}) -> V.

described(Did, {ok, H}, {ok, S}, {ok, L}) ->
    {ok, #describe_profile_v1{citizen_did = Did, headline = H, skills = S, location = L}};
described(_Did, error, _S, _L) -> {error, invalid_headline};
described(_Did, _H, error, _L) -> {error, invalid_skills};
described(_Did, _H, _S, error) -> {error, invalid_location}.

skills(Skills) when is_list(Skills), length(Skills) =< ?MAX_SKILLS ->
    each_skill([profile_description_text:checked(S, 1, 64) || S <- Skills]);
skills(_) ->
    error.

each_skill(Checked) ->
    all_ok(lists:all(fun({ok, _}) -> true; (error) -> false end, Checked), Checked).

all_ok(true, Checked) -> {ok, [S || {ok, S} <- Checked]};
all_ok(false, _Checked) -> error.
