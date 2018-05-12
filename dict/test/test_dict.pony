use "ponytest"
use ".."
use "collections"

class TestDict is UnitTest
  fun name(): String => "dict.Dict"
  
  fun apply(h: TestHelper) =>
    let dict = Dict[String, U64]
    
    ///
    // Write and read a few entries.
    
    dict("apple") = 4
    dict("banana") = 5
    dict("currant") = 6
    
    h.assert_eq[U64](try dict("apple")? else 0xDEAD end, 4)
    h.assert_eq[U64](try dict("banana")? else 0xDEAD end, 5)
    h.assert_eq[U64](try dict("currant")? else 0xDEAD end, 6)
    
    ///
    // At only 3 entries, we don't need maintenance yet.
    
    h.assert_eq[USize](dict.size(), 3)
    h.assert_false(dict.needs_maintenance())
    h.assert_true(dict.run_maintenance())
    
    ///
    // Add 5 more entries and expect to need maintenance.
    // With this arbitrary hash distribution, it happens to need 4 steps.
    
    for i in Range(0, 5) do
      (let key, let value) = ("key" + i.string(), i.u64())
      
      dict(key) = value
      
      h.assert_eq[U64](try dict(key)? else 0xDEAD end, value)
    end
    
    h.assert_eq[USize](dict.size(), 8)
    h.assert_true(dict.needs_maintenance())
    h.assert_false(dict.run_maintenance(1))
    h.assert_false(dict.run_maintenance(1))
    h.assert_false(dict.run_maintenance(1))
    h.assert_true(dict.run_maintenance(1))
    
    ///
    // Now remove those entries; we won't need maintenance again.
    
    for i in Range(0, 5) do
      (let key, let value) = ("key" + i.string(), i.u64())
      
      h.assert_eq[U64](try dict.remove(key)?._2 else 0xDEAD end, value)
    end
    
    h.assert_eq[USize](dict.size(), 3)
    h.assert_false(dict.needs_maintenance())
    h.assert_true(dict.run_maintenance())
    
    h.assert_eq[U64](try dict("apple")? else 0xDEAD end, 4)
    h.assert_eq[U64](try dict("banana")? else 0xDEAD end, 5)
    h.assert_eq[U64](try dict("currant")? else 0xDEAD end, 6)
    
    ///
    // Finally, clear out all remaining entries.
    
    dict.clear()
    
    h.assert_eq[USize](dict.size(), 0)
    h.assert_false(dict.needs_maintenance())
    h.assert_true(dict.run_maintenance())
    
    h.assert_eq[U64](try dict("apple")? else 0xDEAD end, 0xDEAD)
    h.assert_eq[U64](try dict("banana")? else 0xDEAD end, 0xDEAD)
    h.assert_eq[U64](try dict("currant")? else 0xDEAD end, 0xDEAD)
