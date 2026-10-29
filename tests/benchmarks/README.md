# Shim benchmarks

Loads the BindingShim inside a real Endstone server and reports the managed-to-native cost of representative calls. A small native Endstone plugin hosts the CLR through `nethost`/`hostfxr`, loads the managed benchmark assembly, and invokes its `[UnmanagedCallersOnly]` entry point. The managed side calls the generated Interop through the same BindingShim table used by plugins.

## Run

```shell
powershell -File scripts/run-benchmarks.ps1 `
  -ServerRoot C:\path\to\endstone-server `
  -EndstoneRoot C:\path\to\endstone-v0.11.15 `
  -Python C:\path\to\venv\Scripts\python.exe
```

The script builds the solution, the Windows shim, the managed benchmark assembly, and the native host plugin. It installs the plugin under `plugins/`, copies the managed payload and `nethost.dll` to `plugins/hosihikari-benchmarks/`, starts Endstone with `--no-interactive`, and waits for `data/hosihikari/shim-benchmarks/benchmarks.txt`.

Requirements: Windows x64, Endstone 0.11.15 headers, an Endstone server prepared by `python -m endstone`, the `endstone` Python package in that environment, expected-lite/nlohmann_json under the local xmake cache, clang-cl, and the .NET 10 host pack.

## Measurements

Each line reports nanoseconds per call and managed bytes allocated per call after warmup:

- `method.server.get_port`: scalar field through the table.
- `string.server.get_name`: string return, thread-local shim buffer, and managed copy.
- `vector.string.translatable`: `string[]` parameter encoding into the UTF-8 arena and an owned result.
- `vector.int.arraytag`: `int[]` parameter pinning and an owned result.
- `map.permission.create`: `Dictionary<string, bool>` parameter encoding and an owned result.
- `map.permission.children`: one-entry map result decoding into a managed dictionary.
- `map.permission.children_8`: eight-entry map result decoding, showing the per-entry cost.
- `map.item_meta.enchants`: scalar-key map result without string-key allocation.
- `map.block_data.create`: `Dictionary<string, Variant>` parameter encoding and an owned result.
- `shared.scoreboard`: `shared_ptr` result through a pooled `SharedHandle`; the native scoreboard construction dominates.
- `shared.ban_entry`: shared-handle lookup and release through the pool.
- `shared.array.ban_entries`: `SharedHandle[]` result; only the array is allocated.
- `vector.result.plugins`: borrowed pointer-vector result.
- `vector.result.online_players`: empty vector result, served from `Array.Empty<T>()`.

Expected result:

```text
load=ok
method.server.get_port=...
string.server.get_name=...
vector.string.translatable=...
vector.int.arraytag=...
map.permission.create=...
map.permission.children=...
map.permission.children_8=...
map.item_meta.enchants=...
map.block_data.create=...
shared.scoreboard=...
shared.ban_entry=...
shared.array.ban_entries=...
vector.result.plugins=...
vector.result.online_players=...
result=OK
```

The numbers are environment-dependent and are not a CI gate. They complement the LeviLamina benchmark set: the Endstone surface exercises map parameters, variant-valued maps, shared handles, and record factories that the LLAPI slice does not.

Empty vector results return `Array.Empty<T>()`, and pooled shared handles reach zero steady-state allocation; a shared-handle array therefore costs only the array itself. Map results decode into a managed `Dictionary<K, V>`: the dictionary is the projection's allocation floor, and string-keyed maps add one string per entry. The shim's map buffer is thread-local and invalidated by the next call, so the result is copied rather than exposed as a borrowed view.
