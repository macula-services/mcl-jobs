%% @doc get_profiles_page: the profiles the caller may see, in citizen
%% order, one page at a time (keyset paging: `after' is the last citizen of
%% the previous page).
-module(get_profiles_page).

-export([page/3]).

-define(DEFAULT_LIMIT, 20).
-define(MAX_LIMIT, 50).

%% @doc Up to Limit profiles after After (64 hex, or undefined for the first
%% page), as visible_profiles allows Caller to see them. `next' is present
%% when there is more.
-spec page(term(), term(), term()) -> {ok, map()} | {error, atom()}.
page(After, Limit, Caller) ->
    paged(cursor(After), limit(Limit), Caller).

paged({ok, Cursor}, {ok, Limit}, Caller) ->
    rows(jobs_query_store:q(
           "SELECT citizen, headline, skills, location, published FROM profiles"
           " WHERE citizen > ? AND " ++ visible_profiles:where() ++
           " ORDER BY citizen LIMIT ?",
           [Cursor, visible_profiles:owner(Caller), Limit + 1]), Limit);
paged({error, _} = E, _Limit, _Caller) -> E;
paged(_Cursor, {error, _} = E, _Caller) -> E.

cursor(undefined) -> {ok, <<>>};
cursor(After) -> after_citizen(visible_profiles:citizen(After)).

after_citizen({ok, Hex}) -> {ok, Hex};
after_citizen({error, _}) -> {error, invalid_cursor}.

limit(undefined) -> {ok, ?DEFAULT_LIMIT};
limit(N) when is_integer(N), N >= 1, N =< ?MAX_LIMIT -> {ok, N};
limit(_) -> {error, invalid_limit}.

rows({error, _}, _Limit) ->
    {error, store_unavailable};
rows(Rows, Limit) when length(Rows) > Limit ->
    Page = lists:sublist(Rows, Limit),
    [Last | _] = lists:last(Page),
    {ok, #{profiles => [visible_profiles:row(R) || R <- Page], next => Last}};
rows(Rows, _Limit) ->
    {ok, #{profiles => [visible_profiles:row(R) || R <- Rows]}}.
