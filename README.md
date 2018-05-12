# pony-dict [![CircleCI](https://circleci.com/gh/jemc/pony-dict.svg?style=shield)](https://circleci.com/gh/jemc/pony-dict)

A data type for the Pony language based on [the `dict` data type from the internal implementation of Redis](https://github.com/antirez/redis/blob/b85aae78dfad8cf49b1056ee598c1846252a2ef3/src/dict.c).

`Dict` is an alternative to `Map` from the Pony standard library. It is a chaining hash table featuring incremental rehashing when the table is resized.

During a resize, instead of rehashing the data all at once, the two tables are held in memory and the caller can limit how much time is spent rehashing by calling a method to "run maintenance" on the data structure with a limit on the number of slots to rehash. This allows for creating a hash-table-intensive application (like a key/value store) with less variance in the latency for hash table operations.
