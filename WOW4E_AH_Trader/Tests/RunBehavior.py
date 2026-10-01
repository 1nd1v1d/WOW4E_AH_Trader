"""Execute the addon with Lua 5.1 and deterministic WoW API/frame doubles.

pip install -r Tests/requirements.txt (prefer an isolated venv).
This proves Lua behavior, not real-client rendering or protected API permission.
"""
from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parent.parent
lua = LuaRuntime(unpack_returned_tuples=True)
compile_lua = lua.eval("function(s, name) local f, e = loadstring(s, name); assert(f, e); return f end")
entries = [line.strip() for line in (root / "WOW4E_AH_Trader.toc").read_text(encoding="utf-8-sig").splitlines() if line.strip() and not line.startswith("#")]
for entry in entries:
    compile_lua((root / entry).read_text(encoding="utf-8-sig"), "@" + entry)
print(f"Lua 5.1 compiler: {len(entries)} addon files passed")
lua.execute((root / "Tests" / "WoWMock.lua").read_text(encoding="utf-8-sig"))
for entry in entries:
    compile_lua((root / entry).read_text(encoding="utf-8-sig"), "@" + entry)()
lua.execute((root / "Tests" / "Behavior.lua").read_text(encoding="utf-8-sig"))

# WoW does not preserve table aliases across serialization: mimic its emitted
# Lua literals and initialize a completely fresh interpreter, not the old table.
lua.execute("""
function TEST.Serialize(value, stack)
    local kind = type(value)
    if kind == 'string' then return string.format('%q', value) end
    if kind == 'number' or kind == 'boolean' then return tostring(value) end
    if kind ~= 'table' then error('Nonserializable SavedVariable: ' .. kind) end
    stack = stack or {}; assert(not stack[value], 'SavedVariables cycle'); stack[value] = true
    local fields = {}
    for key, child in pairs(value) do table.insert(fields, '[' .. TEST.Serialize(key, stack) .. ']=' .. TEST.Serialize(child, stack)) end
    stack[value] = nil
    return '{' .. table.concat(fields, ',') .. '}'
end
assert(WOW4E_AHT.Store:Save())
""")
snapshot = lua.eval("TEST.Serialize(WOW4E_AHT_DB)")
fresh = LuaRuntime(unpack_returned_tuples=True)
fresh.execute((root / "Tests" / "WoWMock.lua").read_text(encoding="utf-8-sig"))
fresh.execute("WOW4E_AHT_DB = " + snapshot)
for entry in entries:
    fresh.execute((root / entry).read_text(encoding="utf-8-sig"))
fresh.execute("""
assert(WOW4E_AHT:Initialize())
assert(WOW4E_AHT.Store:GetPrice(800) == 50)
assert(#WOW4E_AHT.Recipes:GetList() == 1)
assert(WOW4E_AHT.DB.shoppingLists.Test)
assert(#WOW4E_AHT.DB.postingHistory == 1)
assert(WOW4E_AHT.DB.production.orders)
TEST.Flush()
print('PASS fresh-interpreter SavedVariables serialization and restart')
""")
