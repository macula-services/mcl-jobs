%% @doc How query_jobs answers on the wire: an answer map with every binary
%% as CBOR text, or #{reason => Why}. Integers stay integers; there are no
%% booleans (0 or 1).
-module(query_jobs_reply).

-export([replied/1]).

-spec replied({ok, map()} | {error, atom()}) -> map().
replied({ok, Answer}) -> out(Answer);
replied({error, Reason}) -> #{reason => {text, atom_to_binary(Reason)}}.

out(Map) when is_map(Map) -> maps:map(fun(_K, V) -> out(V) end, Map);
out(List) when is_list(List) -> [out(V) || V <- List];
out(Bin) when is_binary(Bin) -> {text, Bin};
out(undefined) -> {text, <<>>};
out(Other) -> Other.
