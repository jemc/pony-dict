primitive _Constants
  fun minimum_table_size(): USize =>
    """
    This is the minimum heap size that an allocated _Table array will have.
    
    Because Array itself uses a minimum of 8, there's no compelling reason to
    use a number smaller than 8 - it won't change how much memory is allocated.
    """
    8
