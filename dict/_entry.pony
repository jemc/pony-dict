class _Entry[K, V]
  """
  An _Entry is a small data structure containing a key, value,
  and an optional next pointer, in the manner of a singly linked list.
  
  See docstrings for _Table for more information.
  """
  var key: K
  var value: V
  var next: (_Entry[K, V] | None) = None
  
  new ref create(k: K, v: V) =>
    (key, value) = (consume k, consume v)
  
  fun string(): String iso^ =>
    """
    Print a representation of the key and value, including next entries, if any.
    This output is meant for debugging purposes only, and is subject to change.
    """
    let buf = recover String end
    
    iftype K <: Stringable #read
    then buf.append(key.string())
    else buf.push('?')
    end
    
    buf.append(" => ")
    
    iftype V <: Stringable #read
    then buf.append(value.string())
    else buf.push('?')
    end
    
    match next | let next': this->_Entry[K, V] =>
      buf.append("; ")
      buf.append(next'.string())
    end
    
    consume buf
