class _Table[K, V]
  """
  This class holds the actual memory layout of the hash table.
  However, most of the algorithm lives in the methods of the Dict class.
  
  Holds an array of slots, where each slot holds zero or more entries.
  When initially created, all slots will hold a value of None - no entries.
  
  Entries in the same slot are chained together as a singly-linked list,
  so this array only points to the head _Entry of each chain.
  
  To maximize performance, we want to minimize the number of empty slots
  and minimize the number of entries in each slot. In other words, we
  prefer to have a roughly one-to-one ratio of entries to slots.
  
  The total number of entries is tracked separately from the array itself.
  """
  embed _array: Array[(_Entry[K, V] | None)]
  var _total: USize = 0
  
  new ref create(n: USize = _Constants.minimum_table_size()) =>
    """
    Create a new table of size n, rounded up to the next power of 2.
    
    Once created, the table size cannot change, except by calling `kill`,
    which sets the size to zero and makes the table permanently unusable.
    """
    _array = _array.init(None, n.next_pow2())
  
  fun size(): USize =>
    """
    The number of slots in the hash table.
    For correct operation this must always be a power of 2,
    due to how the `mask` function works and is used.
    """
    _array.size()
  
  fun mask(): USize =>
    """
    A bitmask representing how many bits of the key hash value to use when
    translating to an slot index in the table.
    
    For example, a table of size 16 would have a bitmask with a binary value
    `1111`, meaning that only the lowest four bits of the hash will be used. 
    """
    size() - 1
  
  fun total(): USize =>
    """
    The total number of entries in the hash table.
    
    Because this is a chaining hash table, it is possible to have a greater
    `used` count than the `size`, because slots may hold more than one entry.
    
    This number is not modified internally by any methods of _Table, so it must
    be explicitly maintained by the caller using `inc_total` and `dec_total`.
    """
    _total
  
  fun is_empty(): Bool => _total == 0
  fun ref inc_total(n: USize = 1): USize => _total = _total + n
  fun ref dec_total(n: USize = 1): USize => _total = _total - n
  
  fun apply(i: USize): this->(_Entry[K, V] | None) =>
    """
    Get the data at the given slot index in the table.
    
    The return value will either be an _Entry (which should be treated as the
    head of a linked-list chain of entries in the slot) or None.
    
    If the index is out of bounds, None will be returned, same as an empty slot.
    It is the job of the caller to make sure the hash value is converted to
    a valid index by using the binary `and` of the hash value and the `mask`.
    """
    try _array(i)? else None end
  
  fun ref update(i: USize, value: (_Entry[K, V] | None)) =>
    """
    Set the data at the given slot index in the table.
    
    If an _Entry is given, any entries linked to it will also be in that slot.
    
    If an out-of-bounds slot index is given, this will silently do nothing.
    It is the job of the caller to make sure the hash value is converted to
    a valid index by using the binary `and` of the hash value and the `mask`.
    """
    try _array(i)? = value end
  
  fun ref kill() =>
    """
    Set this to a table of size zero, such that all reads and writes will fail.
    This table will not hold data ever again; it cannot be resized up again.
    This is used for quickly killing tables that may still be held by iterators.
    """
    _array.clear()
    _total = 0
