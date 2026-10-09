%% @doc get_organisation_by_id: one organisation. Initiating an organisation
%% is a public act, so anyone sees it, archived ones included (archived = 1).
-module(get_organisation_by_id).

-export([find/1, row/1]).

-spec find(term()) -> {ok, map()} | {error, atom()}.
find(Id) ->
    named(organisation_aggregate:valid_id(Id), Id).

named(true, Id) ->
    found(jobs_query_store:q(
            "SELECT organisation_id, name, initiated_by, initiated_at, archived"
            " FROM organisations WHERE organisation_id = ? AND initiated_at IS NOT NULL",
            [Id]));
named(false, _Id) ->
    {error, invalid_organisation_id}.

found([Row | _]) -> {ok, row(Row)};
found([]) -> {error, not_found};
found({error, _}) -> {error, store_unavailable}.

%% @doc The columns both organisation queries select, as a reply map.
-spec row([term()]) -> map().
row([Id, Name, By, At, Archived]) ->
    #{organisation_id => Id, name => Name, initiated_by => By,
      initiated_at => At, archived => Archived}.
