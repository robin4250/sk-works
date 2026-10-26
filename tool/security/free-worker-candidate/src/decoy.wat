(module
 (memory (export "memory") 1 1)
 (func (export "status") (result i32) i32.const 200)
 (func (export "response_ptr") (result i32) i32.const 0)
 (func (export "response_len") (result i32) i32.const 45)
 (data (i32.const 0) "{\22environment\22:\22synthetic-only\22,\22records\22:[]}")
)
