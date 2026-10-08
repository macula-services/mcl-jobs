%%% Bit flags for organisation_state's status field. Powers of 2, set and read
%%% with evoq_bit_flags (reckon-db-org/evoq, guides/bit_flags.md).
-define(ORGANISATION_INITIATED, 1). %% 2^0 -- the organisation exists
-define(ORGANISATION_ARCHIVED,  2). %% 2^1 -- terminal
