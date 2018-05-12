/* The following copyright notice is included because this implementation
 * copies concepts and algorithms from the `dict` implementation of Redis.
 *
 * Retaining the copyright here may or may not be overkill, but it's better
 * to be safe than sorry, and the original developers deserve recognition.
 *
 * The specific revision of the implementation that was referenced is:
 * https://raw.githubusercontent.com/antirez/redis/b85aae78dfad8cf49b1056ee598c1846252a2ef3/src/dict.h
 * https://raw.githubusercontent.com/antirez/redis/b85aae78dfad8cf49b1056ee598c1846252a2ef3/src/dict.c
 *
 * Copyright (c) 2018, Joe Eli McIlvain
 * Copyright (c) 2006-2012, Salvatore Sanfilippo <antirez at gmail dot com>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *   * Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *   * Neither the name of Redis nor the names of its contributors may be used
 *     to endorse or promote products derived from this software without
 *     specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

use "collections"

type Dict[K: (Hashable #read & Equatable[K] #read), V]
  is HashDict[K, V, HashEq[K]]

type DictIs[K, V] is HashDict[K, V, HashIs[K]]

class HashDict[K, V, H: HashFunction[K] val]
  var _table_a: _Table[K, V] = _table_a.create()
  var _table_b: (_Table[K, V] | None) = None
  var _rehash_idx: USize = 0
  
  fun needs_maintenance(): Bool =>
    """
    Return true when the data structure is in need of maintenance,
    meaning it is in need of one or more calls to `run_maintenance`.
    
    A Dict in need of maintenance operates correctly, but performance suffers.
    """
    _table_b isnt None
  
  fun ref run_maintenance(steps: USize = -1): Bool =>
    """
    Perform at most the given number of steps of rehashing maintenance.
    
    The number of steps is controlled by parameter to allow the caller to limit
    the time spent doing maintenance. By choosing a finite number of steps,
    the latency due to maintenance can be limited to a constant time and spread
    over many calls to reduce latency variance of the overall system.
    If the argument is not supplied, the number of steps isn't limited,
    and any maintenance left to do should complete in this single call
    (no matter how long it takes).
    
    Maintenance consists of iterating over the old table and moving entries
    into the new table, assuming that we are in a rehashing mode already.
    If we're not in the middle of rehashing (_table_b is None), nothing happens.
    
    The number of steps indicates the number of entry migrations to do, though
    to handle the case of limiting time even for sparse tables, the number of
    empty slots that can be traversed is also limited to steps * 10.
    
    If maintenance was completed or was already complete, returns true.
    Otherwise, there is more maintenance to be done and false is returned.
    """
    // Grab the table to rehash from, returning early if there is none there.
    let table_b = try _table_b as _Table[K, V] else return true end
    
    // Set a limit of the maximum number of empty slots to visit.
    (var empty_visits, let overflow) = steps.mulc(10)
    if overflow then empty_visits = -1 end
    
    var i = steps
    while ((i = i - 1) > 0) and (_table_a.total() > 0) do
      
      match _table_a(_rehash_idx = _rehash_idx + 1)
      | let entry': _Entry[K, V] =>
        var entry = entry'
        
        // For each entry chained to this one, copy it to table_b.
        var chain_finished = false
        while not chain_finished do
          // Capture the current value of entry.next - we'll need it later.
          let next = entry.next
          
          // Get the slot index to use in the new table.
          let b_idx = H.hash(entry.key) and table_b.mask()
          
          // Insert this entry into its place in the chain at that slot index.
          entry.next = table_b(b_idx)
          table_b(b_idx) = entry
          
          // Update used counts on both tables to reflect the move.
          // Note that we don't actually have to remove it from the old table.
          _table_a.dec_total()
          table_b.inc_total()
          
          // Continue the loop with the next entry, or break if None.
          match next
          | let e: _Entry[K, V] => entry = e
          else chain_finished = true
          end
        end
        
        // Now that we've copied the chain from the old slot, we remove it.
        _table_a(_rehash_idx - 1) = None
      else
        
        // This is an empty slot - if we've seen too many of these we bail out
        // to avoid doing too much work - we can always continue later.
        if (empty_visits = empty_visits - 1) <= 1 then return false end
        i = i + 1 // refill the steps counter for what we wasted here
      end
    end
    
    // If we haven't rehashed everything yet, bail out so we can continue later.
    if _table_a.total() > 0 then return false end
    
    // We've finished migrating everything out of the old table, so we can
    // get rid of it and shift the new table into its place and kill it.
    (_table_a = table_b).kill()
    _table_b = None
    
    true
  
  fun size(): USize =>
    """
    Return the total number of entries.
    """
    match _table_b | let table_b: this->_Table[K, V] =>
      _table_a.total() + table_b.total()
    else
      _table_a.total()
    end
  
  fun apply(key: box->K!): this->V? =>
    """
    Return the value of the entry at the given key.
    Raises an error if no such entry could be found.
    """
    match _find_entry(key)
    | let entry: this->_Entry[K, V] => entry.value
    else error
    end
  
  fun ref update(key: K, value: V): (V^ | None) =>
    """
    Update the value of the entry with the given key, and return the old value.
    If no such entry was existed, create the new entry and return None.
    """
    match _find_entry(key)
    | let entry: _Entry[K, V] =>
      // There is an existing entry for this key. We need to update its value
      // with the given new value, returning the old value from the expression.
      entry.value = consume value
    | let idx: USize =>
      // Otherwise, we need to create a new entry with this key and value
      // and add it as the head of the entry chain sitting at this slot index.
      let table = _latest_table()
      let entry = _Entry[K, V](consume key, consume value)
      entry.next = table(idx)
      table(idx) = entry
      table.inc_total()
      
      
      _auto_resize()
      
      None
    end
  
  fun ref remove(key: box->K!): (K, V)? => // TODO: return (K^, V^)
    """
    Remove the entry with the given key and return the key and value.
    If no such entry was found, an error will be raised.
    """
    let entry = _find_and_unlink_entry(key)?
    (entry.key, entry.value)
  
  fun ref clear() =>
    """
    Kill and replace internal tables, removing all entries.
    The new table is empty and can be filled with more values.
    """
    (_table_a = _Table[K, V]).kill()
    try ((_table_b = None) as _Table[K, V]).kill() end
    _rehash_idx = 0
  
  fun _latest_table(): this->_Table[K, V] =>
    """
    Return the newest table - the one to use for inserting new entries into.
    Note that the table isn't complete yet, so it shouldn't be used for reading,
    at least not by itself (both tables will be incomplete during rehashing).
    """
    match _table_b
    | let table_b: this->_Table[K, V] => table_b
    else _table_a
    end
  
  fun ref _auto_resize() =>
    """
    Check the number of total hash table entries against the number of slots.
    
    The ideal ratio is 1:1 or just below, so that we have roughly one entry
    per slot in the hash table. See the docstrings for _Table for more details.
    
    If we have more entries than slots, try to initiate a resize to a more
    appropriate table size. If we're already in the middle of rehashing, we
    can't start a new rehashing process until that one finishes.
    """
    if needs_maintenance() then return end
    
    if _table_a.total() >= _table_a.size() then
      try _initiate_rehashing(_table_a.total() * 2)? end
    end
  
  fun ref _initiate_rehashing(n: USize)? =>
    """
    Resize to hold at least n hash slots.
    
    Enters the Dict into a state where it is holding two _Table objects,
    with rehashing into the new _Table as a work in progress to be continued
    incrementally, every time the `run_maintenance` method is called.
    
    If already in a state of rehashing, this method will raise an error
    unless the size of the current target table matches the new desired size.
    
    If already at or above the desired size, nothing will happen.
    
    This operation will never create a new table smaller than the current one,
    so table sizes for as given Dict will only ever grow. This limitation might
    be revisited and removed later if we can audit soundness of doing that. 
    """
    // Enforce the minimum size, and round to nearest power of 2.
    let size' = n.max(_Constants.minimum_table_size()).next_pow2()
    
    // Nothing to do if we're already at the desired size - return successfully.
    if _table_a.size() >= size' then return end
    
    // Raise an error if we're already rehashing to a different size.
    // If we're already rehashing to the desired size, return successfully.
    match _table_b | let table_b: _Table[K, V] =>
      if table_b.size() >= size' then return else error end
    end
    
    // If there's no data in the main table yet, replace it directly.
    // Otherwise, place our new table in the second position for rehashing.
    if _table_a.is_empty() then
      _table_a = _Table[K, V](size')
    else
      _table_b = _Table[K, V](size')
      _rehash_idx = 0
    end
  
  fun _find_entry(key: box->K!): (this->_Entry[K, V] | USize) =>
    """
    Find an existing entry with the given key in the hash tables, returning it.
    If no such entry exists, the index at which it should be will be returned.
    
    Thus, the caller can use this method as the basis for getting an entry,
    inserting a new entry, or modifying the value of an entry.
    
    To remove an entry, use `_find_and_unlink_entry` instead, because extra
    context must be tracked to unlink an entry from an arbitrary position.
    
    If we're in the process of rehashing from `_table_a` into `_table_b`, then
    both tables will be searched, in that order, before returning emptyhanded.
    If emptyhanded, the index returned will be the index to use for inserting
    into `_table_b`, because we should never insert entries into the old table -
    such entries would not be guaranteed to make it into the new table if the
    `_rehash_idx` had already passed by that index.
    """
    let key_hash = H.hash(key)
    
    // Search in _table_a for an existing entry.
    var idx = key_hash and _table_a.mask()
    var entry_or_none = _table_a(idx)
    while true do
      match entry_or_none | let entry: this->_Entry[K, V] =>
        if H.eq(key, entry.key) then return entry end
        entry_or_none = entry.next
      else
        break
      end
    end
    
    // Search in table_b (if it exists) for an existing entry.
    match _table_b | let table_b: this->_Table[K, V] =>
      idx = key_hash and table_b.mask()
      entry_or_none = table_b(idx)
      while true do
        match entry_or_none | let entry: this->_Entry[K, V] =>
          if H.eq(key, entry.key) then return entry end
          entry_or_none = entry.next
        else
          break
        end
      end
    end
    
    // If we found no existing entry, return the index into the latest table.
    idx
  
  fun ref _find_and_unlink_entry(key: box->K!): _Entry[K, V]? =>
    """
    This method does the same work as `_find_entry`, but adds another step:
    if/when an entry is found, it is unlinked from its position in the table,
    removing it on the spot. Because we have to track some extra context to
    sever the link (and properly link the next entry in the chain, if any),
    the code for this method ends up being far more verbose than _find_entry.
    """
    let key_hash = H.hash(key)
    
    // Search in _table_a for an existing entry.
    var table = _table_a
    
    // Find the slot matching our key hash.
    var idx = key_hash and table.mask()
    match table(idx) | let entry': _Entry[K, V] =>
      var entry = entry'
      
      // If the first entry in the chain matches our key, stop here.
      if H.eq(key, entry.key) then
        // Unlink the entry
        table(idx) = entry.next = None
        table.dec_total()
        
        return entry
      end
      
      // Otherwise, check each subsequent entry in the chain.
      while true do
        match entry.next | let next_entry: _Entry[K, V] =>
          let prev_entry = entry = next_entry
          
          if H.eq(key, entry.key) then
            // Unlink the entry
            prev_entry.next = entry.next = None
            table.dec_total()
            
            return entry
          end
        else break
        end
      end
    end
    
    // Search in table_b (if it exists) for an existing entry.
    // This has the same logic as the last code with table_b instead of table_a.
    match _table_b | let table_b: _Table[K, V] =>
      table = table_b
      
      // Find the slot matching our key hash.
      idx = key_hash and table.mask()
      match table(idx) | let entry': _Entry[K, V] =>
        var entry = entry'
        
        // If the first entry in the chain matches our key, stop here.
        if H.eq(key, entry.key) then
          // Unlink the entry
          table(idx) = entry.next = None
          table.dec_total()
          
          return entry
        end
        
        // Otherwise, check each subsequent entry in the chain.
        while true do
          match entry.next | let next_entry: _Entry[K, V] =>
            let prev_entry = entry = next_entry
            
            if H.eq(key, entry.key) then
              // Unlink the entry
              prev_entry.next = entry.next = None
              table.dec_total()
              
              return entry
            end
          else break
          end
        end
      end
    end
    
    error
