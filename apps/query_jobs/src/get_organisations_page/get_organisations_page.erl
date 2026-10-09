%% @doc get_organisations_page: active organisations in id order, one page at
%% a time (keyset paging: `after' is the last id of the previous page).
-module(get_organisations_page).

-export([page/2]).

-define(DEFAULT_LIMIT, 20).
-define(MAX_LIMIT, 50).

-spec page(term(), term()) -> {ok, map()} | {error, atom()}.
page(After, Limit) ->
    paged(cursor(After), limit(Limit)).

paged({ok, Cursor}, {ok, Limit}) ->
    rows(jobs_query_store:q(
           "SELECT organisation_id, name, initiated_by, initiated_at, archived"
           " FROM organisations WHERE organisation_id > ? AND initiated_at IS NOT NULL"
           " AND archived = 0 ORDER BY organisation_id LIMIT ?",
           [Cursor, Limit + 1]), Limit);
paged({error, _} = E, _Limit) -> E;
paged(_Cursor, {error, _} = E) -> E.

cursor(undefined) -> {ok, <<>>};
cursor(After) -> after_id(organisation_aggregate:valid_id(After), After).

after_id(true, After) -> {ok, After};
after_id(false, _After) -> {error, invalid_cursor}.

limit(undefined) -> {ok, ?DEFAULT_LIMIT};
limit(N) when is_integer(N), N >= 1, N =< ?MAX_LIMIT -> {ok, N};
limit(_) -> {error, invalid_limit}.

rows({error, _}, _Limit) ->
    {error, store_unavailable};
rows(Rows, Limit) when length(Rows) > Limit ->
    Page = lists:sublist(Rows, Limit),
    [Last | _] = lists:last(Page),
    {ok, #{organisations => [get_organisation_by_id:row(R) || R <- Page], next => Last}};
rows(Rows, _Limit) ->
    {ok, #{organisations => [get_organisation_by_id:row(R) || R <- Rows]}}.
