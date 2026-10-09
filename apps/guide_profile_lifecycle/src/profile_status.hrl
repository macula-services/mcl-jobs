%%% Bit flags for profile_state's status field. Powers of 2, set and read
%%% with evoq_bit_flags (reckon-db-org/evoq, guides/bit_flags.md).
-define(PROFILE_INITIATED, 1). %% 2^0 -- the profile exists
-define(PROFILE_ARCHIVED,  2). %% 2^1 -- terminal
-define(PROFILE_DESCRIBED, 4). %% 2^2 -- it carries a description
-define(PROFILE_PUBLISHED, 8). %% 2^3 -- the realm can see it
