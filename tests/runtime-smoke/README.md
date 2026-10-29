# Runtime smoke

Loads the committed BindingShim inside a real Endstone server through a small C++ plugin.

## Requirements

- Windows x64.
- Endstone 0.11.15 headers (a checkout or `git archive` of the tag).
- An Endstone server folder prepared by `python -m endstone` (the plugin folder is created on first run).
- The `endstone` Python package installed in the Python environment passed to the script.
- expected-lite and nlohmann_json headers available under the local xmake package cache.
- A local clang-cl toolchain.

## Run

```shell
powershell -File scripts/run-runtime-smoke.ps1 `
  -ServerRoot C:\path\to\endstone-server `
  -EndstoneRoot C:\path\to\endstone-v0.11.15 `
  -Python C:\path\to\venv\Scripts\python.exe
```

The script builds the solution, the native shim, and the C++ plugin; copies the plugin and shim into the server; starts Endstone with `--no-interactive`; and waits for `shim-smoke-result.txt`.

The plugin verifies:

- the shim DLL loads from the Endstone plugin cache;
- `hosihikari_endstone_get_server()` returns the same `Server&` as the plugin API;
- `Server::getName()` and `Server::getVersion()` through the BindingShim match the native calls;
- string and integer vector parameters reach `Translatable::Create` and `ArrayTag<int>::Create`;
- the free-function table entry for `endstone::hash_value` returns the same value as the native inline call;
- `PluginManager::getPlugins()` returns borrowed `Plugin*` addresses;
- `Server::createScoreboard()` returns a `shared_ptr` handle whose target serves `Scoreboard::clearSlot` and releases cleanly;
- `Scoreboard::getObjectives()` returns an owned `Objective[]` (empty on a fresh scoreboard);
- `PlayerBanList::getEntries()` returns `SharedHandle[]` and `getBanEntry("missing")` returns null;
- `addBan` with a 60-second duration, lookup, `isBanned`, and `removeBan` round-trip through `SharedHandle`;
- `ItemMeta::getEnchants()` returns the added enchantment as a map entry through `HosihikariMapEntry`;
- a `Dropdown` control round-trips through the typed form-control variant into `ModalForm::addControl` and back out of `getControls`;
- a `Dictionary<string, bool>` argument reaches `Permission::Create` and `getChildren()` returns the same entry;
- `Server::createBlockData` accepts a block-state map, and `BlockData::getBlockStates()` returns the boolean entry with its variant value intact;
- `CommandSenderWrapper` is constructed from the server's `CommandSender&` through a mutable-reference parameter; the wrapper delegates `getName()` and `getPermissionLevel()` to the sender;
- the generated inheritance casts round-trip `CommandSenderWrapper` to its `CommandSender` base and back, while a downcast of the console sender to `Actor` returns null;
- transitive casts reach `Permissible` from `CommandSenderWrapper` and round-trip back through `Permissible.TryAsCommandSenderWrapper`;
- a `Permission` constructed through `Permission::Create` is transferred into `PluginManager::addPermission` as a `unique_ptr`, and the returned reference serves `getName()`;
- `Command::Create` receives usages, aliases, and permissions as three independent string vectors; `getAliases()` returns the aliases unchanged;
- an `Identifier<ItemType>` constructed from a managed string keeps its borrowed string alive, exposes `getKey()`, and serves `ItemFactory::getItemMeta`;
- `ItemStack` copy assignment replaces the target stack's amount and data with the source stack's values;
- a string `std::variant` round-trips through `ActionForm::setContent`/`getContent`, including index and string accessors;
- `ActionForm::setOnSubmit`/`getOnSubmit` round-trips a `std::function`: the returned callable invokes the managed handler exactly once and releases its shared state once.

Expected result:

```text
load=ok
server.match=true
expected_name=Endstone
expected_version=0.11.15
name=Endstone
version=0.11.15
function.hash=ok
translatable.string_vector=ok
arraytag.int_vector=ok
plugin_manager.plugin_vector=ok
scoreboard.shared_handle=ok
scoreboard.owned_array=ok
ban_list.shared_array=ok
ban_list.add_remove=ok
item_meta.map=ok
modal_form.controls=ok
permission.map=ok
unique_ptr.param=ok
multi_vector.ctor=ok
borrowed_string.ctor=ok
assignment.operator=ok
block_data.map=ok
mutable_reference.ctor=ok
inheritance.cast=ok
inheritance.transitive=ok
action_form.string_variant=ok
callable.round_trip=ok
result=OK
```

The smoke is not part of CI; it requires a local Endstone runtime.
