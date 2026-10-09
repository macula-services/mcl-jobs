%% @doc get_profile_by_id: one profile, as visible_profiles allows the
%% caller to see it.
-module(get_profile_by_id).

-export([find/2]).

%% @doc The profile of Citizen (64 hex), seen by Caller (a node id, or
%% anything else for nobody in particular).
-spec find(term(), term()) -> {ok, map()} | {error, atom()}.
find(Citizen, Caller) ->
    named(visible_profiles:citizen(Citizen), Caller).

named({ok, CitizenHex}, Caller) ->
    found(jobs_query_store:q(
            "SELECT citizen, headline, skills, location, published FROM profiles"
            " WHERE citizen = ? AND " ++ visible_profiles:where(),
            [CitizenHex, visible_profiles:owner(Caller)]));
named({error, _} = E, _Caller) ->
    E.

found([Row | _]) -> {ok, visible_profiles:row(Row)};
found([]) -> {error, not_found};
found({error, _}) -> {error, store_unavailable}.
