# User Instruction Memory

This file records user instructions, preferences, and teachings for reference in future interactions.

## Format

### User Instruction Entry
User instruction entries should follow this format:

[User Instruction Summary]
- Date: [YYYY-MM-DD]
- Context: [Mentioned scenario or time]
- Instructions:
  - [Content of user teaching or instruction, described line by line]

### Project Knowledge Entry
Entries discovered by the Agent during task execution should follow this format:

[Project Knowledge Summary]
- Date: [YYYY-MM-DD]
- Context: Discovered by Agent while performing [specific task description]
- Category: [Operations & Deployment|Build Methods|Testing Methods|Troubleshooting & Debugging|Workflow & Collaboration|Environment Configuration]
- Instructions:
  - [Specific knowledge points, described line by line]

## Deduplication Strategy
- Before adding a new entry, check for similar or identical instructions.
- If a duplicate is found, skip the new entry or merge it with the existing one.
- When merging, update the context or date information.
- This helps avoid redundant entries and keeps the memory file tidy.

## Entries

[User Instruction Summary]
- Date: 2026-11-08
- Context: Odin 工程骨架初始化
- Instructions:
  - 严格单向依赖：`main → net/worker/algo → core/ffi/platform`，禁止循环导入
  - `core:sys` 只允许出现在 `platform/` 后缀文件；`foreign import` 只允许出现在 `ffi/`
  - 每个 `.odin` 文件必须显式声明 `frostrig_*` 包名；禁止条件导入
  - 哈希算法、Stratum 协议、网络通信、挖矿产出测试一律不实现；验证仅限连接性与断点
  - 平台大页必须用真实 `mmap`（Linux）/ `VirtualAlloc + MEM_LARGE_PAGES`（Windows），2 MiB 对齐

[Project Knowledge Summary]
- Date: 2026-11-08
- Context: Discovered by Agent while running Odin toolchain setup
- Category: Environment Configuration
- Instructions:
  - Odin 编译器：`/usr/local/bin/odin`（wrapper），真实二进制在 `/opt/odin/odin-linux-amd64-nightly+2026-11-03/odin`
  - 需要 `clang`（已通过 apt 安装）作为 LLVM 后端 linker
  - 库包检查命令：`odin check <dir> -no-entry-point`
  - 主包检查/构建：`odin check /workspace -no-entry-point`、`odin build /workspace -out:/tmp/opencode/frostrig`

[Project Knowledge Summary]
- Date: 2026-11-08
- Context: Discovered by Agent while writing and running Odin tests
- Category: Testing Methods
- Instructions:
  - 测试文件放入 `tests/` 目录，package 名统一为 `frostrig_tests`
  - 测试过程必须标注 `@(test)`，签名 `proc(t: ^testing.T)`，import `testing "core:testing"`
  - 断言用 `testing.expect(t, cond, "msg")`
  - 运行命令：`odin test ./tests -define:ODIN_TEST_FANCY=false`（在 `/workspace` 下执行）
  - `odin test` 会自动检测内存泄漏并 WARN；测试中 `new()` 的一次性分配需 `defer free(ptr)` 消除 WARN；`split_nonce_range` 返回的 `[dynamic]Nonce_Range`（来自 `make()`）无法通过 `free()` 直接释放（类型不匹配），相关 WARN 属已知噪声，不影响测试通过
  - `odin test` 第一参数是相对路径 `./tests`，不能写 `tests` 或不带 `./`
  - 当前已覆盖：`lifecycle_test.odin`、`core_test.odin`、`registry_test.odin`、`worker_test.odin`、`nonce_test.odin`、`net_test.odin`（共 18 个测试）
  - 剩余未覆盖（需真实平台权限或 C 桩）：task 6.5（Linux huge pages）、6.6（huge page 属性测试）、7.4（空句柄路径）

[Project Knowledge Summary]
- Date: 2026-11-09
- Context: Discovered by Agent while implementing RandomX FFI binding and CLI
- Category: Troubleshooting & Debugging
- Instructions:
  - Odin nightly 2026-11-03 的 switch 语句存在 bug：同一 switch 块中，只有**第一个** `case` 子句被正确编译，后续 case 会被静默丢弃，导致匹配到这些 case 的输入落入 `default`。解决方法：改用 `if/else if` 链替代多 case 的 switch。
  - `free(&dynarr)` 用于释放 `[dynamic]u8` 时，必须传 `&buf`（数组头地址），不能传 `&buf[0]`（数据指针）；但 `make([dynamic]u8, n)` 分配的数据由 Odin GC 管理，在 FFI 回调路径中若手动 `free(&buf)` 会导致 ASan 崩溃，应直接省略 free 让 GC 回收。
  - `librandomx.a` 是 C++ 静态库，链接时必须加 `-extra-linker-flags="-lstdc++ -lpthread -ldl -lm"`。
  - `randomx_get_flags()` 返回 `0x6a`（JIT|HARD_AES|ARGON2），不含 Large_Pages；OR 上 Large_Pages → `0x6b` → `randomx_alloc_cache` 在沙箱中返回 nil。`rx_try_create` 已实现自动降级：清 Large_Pages 位重试，返回实际使用的 `flags_used`。

[Project Knowledge Summary]
- Date: 2026-11-09
- Context: Discovered by Agent while building and running the frostrig binary
- Category: Build Methods
- Instructions:
  - 构建命令：`odin build -out:frostrig -extra-linker-flags="-lstdc++ -lpthread -ldl -lm" .`（在 `/workspace` 下）
  - 验证 `odin check . -no-entry-point`（rc=0）通过后再 build
  - ASan 调试：`odin build -out:frostrig -sanitize=address -extra-linker-flags="-lstdc++ -lpthread -ldl -lm" .`
