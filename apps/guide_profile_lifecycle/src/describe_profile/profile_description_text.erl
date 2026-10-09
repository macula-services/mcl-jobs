%%% @doc What text a profile description may carry.
%%%
%%% A published profile is read by strangers in a public directory, which is
%%% where a reversed or invisibly padded headline impersonates someone. So
%%% text is normalised to NFC first (lengths count the normalised bytes),
%%% and refused when it is not UTF-8 or carries a control character (C0, DEL,
%%% C1) or an invisible format character: bidi embeddings, overrides and
%%% isolates, zero-width spaces and joiners, word joiners and invisible
%%% operators, line and paragraph separators, the BOM, the soft hyphen, the
%%% Arabic letter mark and the Mongolian vowel separator.
%%% @end
-module(profile_description_text).

-export([checked/3]).

%% @doc The NFC form of Text when it is acceptable and Min to Max bytes long.
-spec checked(term(), non_neg_integer(), pos_integer()) -> {ok, binary()} | error.
checked(Text, Min, Max) when is_binary(Text) ->
    sized(normalised(unicode:characters_to_nfc_binary(Text)), Min, Max);
checked(_Other, _Min, _Max) ->
    error.

normalised(Nfc) when is_binary(Nfc) ->
    plain(lists:all(fun allowed/1, unicode:characters_to_list(Nfc)), Nfc);
normalised(_Malformed) ->
    error.

plain(true, Nfc) -> {ok, Nfc};
plain(false, _Nfc) -> error.

sized({ok, Nfc}, Min, Max) when byte_size(Nfc) >= Min, byte_size(Nfc) =< Max -> {ok, Nfc};
sized(_, _Min, _Max) -> error.

allowed(C) when C < 16#20; C >= 16#7F, C =< 16#9F -> false;
allowed(16#AD) -> false;
allowed(16#61C) -> false;
allowed(16#180E) -> false;
allowed(C) when C >= 16#200B, C =< 16#200F -> false;
allowed(C) when C >= 16#2028, C =< 16#202E -> false;
allowed(C) when C >= 16#2060, C =< 16#206F -> false;
allowed(16#FEFF) -> false;
allowed(_) -> true.
