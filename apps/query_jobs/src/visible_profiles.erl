%% @doc THE rule for who sees a profile, in one place: both profile queries
%% filter with where/0 and bind owner/1, so they cannot drift apart.
%%
%% A profile is seen when it was initiated, is not archived, and is either
%% published or the caller's own. Anything else answers exactly as a profile
%% that never existed: not_found, or absent from the page.
-module(visible_profiles).

-export([where/0, owner/1, citizen/1, row/1]).

%% @doc The SQL condition; its one parameter is owner/1 of the caller.
-spec where() -> string().
where() ->
    "initiated_at IS NOT NULL AND archived = 0 AND (published = 1 OR citizen = ?)".

%% @doc The caller as the read model spells citizens: lowercase hex of the
%% 32-byte node id. A caller that is not one matches no profile as owner.
-spec owner(term()) -> binary().
owner(<<_:256>> = NodeId) -> binary:encode_hex(NodeId, lowercase);
owner(_NotANodeId) -> <<"-">>.

%% @doc A citizen named by a caller: 64 hex characters, either case, as the
%% read model spells it; anything else is refused.
-spec citizen(term()) -> {ok, binary()} | {error, invalid_citizen}.
citizen(Hex) when is_binary(Hex), byte_size(Hex) =:= 64 ->
    decoded(try binary:decode_hex(Hex) catch error:badarg -> invalid end);
citizen(_) ->
    {error, invalid_citizen}.

decoded(<<_:256>> = NodeId) -> {ok, binary:encode_hex(NodeId, lowercase)};
decoded(_) -> {error, invalid_citizen}.

%% @doc The columns both queries select, in this order, as a reply map.
-spec row([term()]) -> map().
row([Citizen, Headline, Skills, Location, Published]) ->
    #{citizen => Citizen,
      headline => text(Headline),
      skills => skills(Skills),
      location => text(Location),
      published => Published}.

text(undefined) -> <<>>;
text(Text) -> Text.

skills(undefined) -> [];
skills(<<>>) -> [];
skills(Joined) -> binary:split(Joined, <<"\n">>, [global]).
