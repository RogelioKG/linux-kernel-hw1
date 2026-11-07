# 作業引導：`my_get_physical_addresses`

這份文件只提供方向、提示和該查的函式，不附解答程式碼。

- 作業說明：<https://hackmd.io/@AvrilChen/ByKKII5jMg> (內容有出入時，以作業說明和助教公告為準)
- 環境建置：[`README.md`](../README.md)
- 文中的 kernel source 路徑都從 repo 根目錄算起，例如 `build/linux-5.15.135/mm/memory.c`；行號請用 `grep -n` 自己找

## 0. 時程與配分

| 項目 | 內容 |
|---|---|
| 繳交期限 | 2026-11-10 |
| Demo 時段登記 | 2026-11-02 13:00 至 **2026-11-12 17:00**，填寫助教公告的登記檔案 |
| 推甄撞期 | 當天上、下午都無法配合時，組長要在 **2026-11-12 20:00 前**來信附上證明，改到當天晚上 |
| Demo | 2026-11-13，**必須到場**，自備筆電 |

| 作業說明 | Demo 流程 (2026-11-04 助教公告) |
|---|---|
| Q1 30 分 + Q2 30 分 | step 1：當場執行並解說，60% |
| 問答 40% | step 2：8 題 Q&A，40% |

- **待確認**：HackMD 報告是否另外計分
- 建議順序：syscall (第 2 節) → Q1 全部通過 (第 3 節) → Q2 (第 4 節) → 報告與 demo (第 5、6 節)。Q1、Q2 用的是同一個 syscall，Q2 不需要另外寫 kernel 程式碼

## 1. 起點：repo 現況

- `src/linux_kernel_hw1.c` 已經是完整實作 (走訪 page table，支援 4 KiB、2 MiB、1 GiB page)；第 2 節是實作時的思路，可以對照原始碼看
- `scripts/3-wire.sh` 已經把它登記成 x86_64 syscall 449
- `tests/q1.c`、`tests/q2.c` 和作業說明裡的驗證程式相同，只差在排版
- 目前的結果 (`build/qemu.log`)：`q1` 全部 PASS，`q2` 是 `Summary: 0 FAIL, 0 INCONCLUSIVE, 0 SKIP`
- 每次修改後執行 `scripts/5-compile.sh && scripts/6-run.sh`，QEMU 開機後會自動執行 `q1`、`q2`；`scripts/6-run.sh shell` 則會進入 VM 的 root shell (見 4.3)
- 想讓 clangd 能跳到 kernel 的定義、看到正確的 include 路徑與 config 巨集：在 `scripts/5-compile.sh` 之後執行 `scripts/compdb.sh`，它會在 repo 根目錄產生 `compile_commands.json`。kernel 是透過 `build/linux-5.15.135/kernel/linux_kernel_hw1` 這個 symlink 編譯 `src/` 的，所以腳本會把這些 entry 複製一份，改成 `src/` 底下的路徑；`tests/q1.c`、`tests/q2.c`、`tests/poweroff.c` 另外補上 user space 的編譯參數，否則 clangd 會套用 kernel 的 `-nostdinc`

## 2. 實作 syscall (Q1、Q2 共用)

### 2.1 介面規格

原型是 `void * my_get_physical_addresses(void *);`，回傳值：

- `0`：沒有 present 的 physical mapping、位址在 kernel space，或是取鎖時被中斷
- 非 0：**精確到 byte 的** physical address (frame 起點加上 page 內的 offset)

其他要求：

- `vaddr` 只是一個數字，要走的是 `current->mm` 的 page table，**不需要** `access_ok()` 或 `copy_from_user()`
- 查詢時**不能觸發 page fault**，否則 Q1 State 1 的「還沒存取 → 0」就不成立
- 5.15 用 449；從 5.16 起 449 是 `futex_waitv`，換成新版 kernel 時要改號碼 (作業建議 548)

### 2.2 要先懂的概念

| 概念 | 要回答的問題 | 去哪裡查 |
|---|---|---|
| x86_64 多層 page table | virtual address 的哪些 bit 分別用來索引 PGD、P4D、PUD、PMD、PTE？最後 12 bit 是什麼？ | `build/linux-5.15.135/Documentation/x86/x86_64/mm.rst`、`build/linux-5.15.135/arch/x86/include/asm/pgtable_64_types.h` (`PMD_SHIFT`、`PUD_SHIFT`) |
| 5 層 page table 與 folding | 在 4 層的機器上，`p4d` 這層怎麼「折疊」掉？為什麼程式碼還是要走過 `p4d`？ | `build/linux-5.15.135/Documentation/vm/arch_pgtable_helpers.rst`；這個 repo 的 `build/out/.config` 有 `CONFIG_X86_5LEVEL=y` |
| process 的 address space | page table 的根放在哪裡？kernel thread 為什麼沒有 `mm`？ | `build/linux-5.15.135/include/linux/mm_types.h` 的 `struct mm_struct` (`pgd` 欄位) |
| 各層的 offset 與檢查巨集 | `*_offset()`、`*_none()`、`*_bad()`、`*_present()` 各代表什麼？ | `build/linux-5.15.135/include/linux/pgtable.h` (`pgd_offset`、`pud_offset`、`pmd_offset`)、`build/linux-5.15.135/arch/x86/include/asm/pgtable.h` (`p4d_offset`、`pte_present`、`pte_pfn`、`pmd_pfn`、`pud_pfn`) |
| Huge page (PMD 2MB、PUD 1GB) | 為什麼 huge page 的 entry 在 `pmd_bad()` 看來是「壞的」？huge page 內的 offset 有幾 bit？ | `build/linux-5.15.135/Documentation/vm/transhuge.rst`；x86 上 `pmd_leaf`/`pud_leaf` 定義成 `pmd_large`/`pud_large` (`build/linux-5.15.135/arch/x86/include/asm/pgtable.h`) |
| mmap lock | 走 page table 時為什麼要持有 `mm` 的 read lock？`_killable` 版本失敗代表什麼？ | `build/linux-5.15.135/include/linux/mmap_lock.h` (`mmap_read_lock_killable`、`mmap_read_unlock`) |
| page table lock (split PTL) | PTE 這層和 huge PMD 各用什麼鎖？ | `build/linux-5.15.135/include/linux/mm.h` (`pte_offset_map_lock`、`pte_unmap_unlock`、`pmd_lock`)、`build/linux-5.15.135/Documentation/vm/split_page_table_lock.rst` |
| PFN 與 DRAM | 什麼是 PFN？`pfn_valid()` 濾掉的是什麼？ | `build/linux-5.15.135/include/linux/mmzone.h`、`build/linux-5.15.135/Documentation/vm/memory-model.rst` |
| 位址界線 | user space 的上界是多少？ | `build/linux-5.15.135/arch/x86/include/asm/page_64_types.h` (`TASK_SIZE`) |

參考實作是 `build/linux-5.15.135/mm/gup.c` 的 `follow_p4d_mask` → `follow_pud_mask` → `follow_pmd_mask` → `follow_page_pte`。可以參考它的結構和取鎖方式，但不要直接呼叫 (原因見 2.4)。

### 2.3 建議實作步驟

1. **確認接線**：用 `pr_info()` 印出 `vaddr`，確認它有出現在 `build/qemu.log`
2. **邊界檢查**：`current->mm` 是 NULL，或 `vaddr >= TASK_SIZE` 時回傳 0
3. **取 mmap read lock**：呼叫 `mmap_read_lock_killable()`，失敗就回傳 0；用單一出口 (`goto out`) 確保每條路徑都會解鎖
4. **逐層往下走**：`pgd_offset` → `p4d_offset` → `pud_offset` → `pmd_offset`，遇到 `*_none()` 就結束
5. **PUD 層**：先判斷是不是 leaf (1GB)。是的話用 `pud_pfn` 加上 1GB 範圍內的 offset 算出 physical address；判斷完 leaf 才檢查 `pud_bad()`
6. **PMD 層**：先判斷是不是 leaf (2MB)。是的話取 `pmd_lock()`，用 `READ_ONCE()` 重新讀一次，確認仍然是 present 且是 leaf 才算 physical address；如果已經被拆開，就放鎖改走 PTE 路徑。最後才檢查 `pmd_bad()`
7. **PTE 層**：`pte_offset_map_lock()` → `pte_present()` → 取 PFN → `pfn_valid()` → 算 physical address → `pte_unmap_unlock()`
8. **計算 physical address**：把 `pte_pfn()` 先轉成 `phys_addr_t` 再左移 `PAGE_SHIFT`，加上 `vaddr & ~PAGE_MASK`；huge page 要換成對應大小的 mask
9. **放鎖並回傳**：呼叫 `mmap_read_unlock()`，回傳型別是 `long`

可能會用到的 header：`linux/mm.h`、`linux/sched.h`、`linux/pgtable.h`、`linux/mmap_lock.h`。

### 2.4 常見陷阱

- **不要用 `get_user_pages()`、`follow_page()`**：它們可能觸發 fault。而且 zero page 是 special mapping (`do_anonymous_page` 用 `pte_mkspecial` 設定)，`vm_normal_page()` 會回傳 NULL，導致 Q1 State 2 失敗
- **leaf 的檢查順序**：要先檢查 `*_leaf`，再檢查 `*_bad`，否則 huge page 會被當成錯誤
- **漏解鎖**：任何一條路徑漏掉 `mmap_read_unlock` 或 `pte_unmap_unlock`，都會讓系統卡死。QEMU 沒有回應時，按 `Ctrl-A` 再按 `X` 離開
- **持有 spinlock 時睡眠**：持有 PTE／PMD lock 的期間，不要呼叫可能睡眠的函式
- **溢位**：PFN 沒有先轉成 64-bit 就左移
- **offset 遺失**：只回傳 frame 起點的話，`Page Offset Preservation` 會失敗
- **q1、q2 測不到 THP 路徑**：kernel config 有開 `CONFIG_TRANSPARENT_HUGEPAGE` (`madvise` 模式)，但 q1、q2 的區域都小於 2MB，不會用到 huge PMD。想驗證的話，另外寫測試：準備 2MB 對齊的區域，呼叫 `madvise(MADV_HUGEPAGE)` 並寫入，再查詢不同的 offset
- **抓出鎖的錯誤**：開啟 `CONFIG_PROVE_LOCKING`、`CONFIG_DEBUG_ATOMIC_SLEEP` 後重新編譯 (kernel 會變慢)

## 3. Question 1 (30 分)：anonymous memory 的狀態機與 paging 粒度

### 3.1 題目要求

用 `mmap()` 配置 anonymous memory，觀察以下現象：

- **Part A (狀態機)**
  1. State 1 (Reserved)：還沒存取時，physical address 為 0
  2. State 2 (Read-Only Shared)：讀取之後，不同的 virtual page 都 map 到同一個 **Global Zero Page**
  3. State 3 (Committed)：寫入時觸發 page fault，kernel 配置一個私有的 physical page
- **Part B (硬體粒度與 paging 抽象)**
  1. Page-Level Internal Fragmentation：`mmap` 120 bytes，仍然會 map 整個 4KB page
  2. Paging Abstraction over Physical Discontinuity：連續的 virtual address 可能對應到不連續的 physical address

各項的 PASS 條件，請看 `tests/q1.c` 中每個 `print_res` 前面的判斷式。

### 3.2 要理解的 kernel 行為

| 現象 | 對應程式碼 |
|---|---|
| 讀取還沒配置的 anonymous page → zero page (唯讀) | `build/linux-5.15.135/mm/memory.c` 的 `do_anonymous_page` (搜尋 "Use the zero-page for reads")、`build/linux-5.15.135/include/linux/pgtable.h` 的 `my_zero_pfn`、`is_zero_pfn` |
| zero page 本身 | `build/linux-5.15.135/arch/x86/include/asm/pgtable.h` 的 `ZERO_PAGE`、`empty_zero_page` |
| 寫入 zero page → write-protect fault → 配置新的 page | `build/linux-5.15.135/mm/memory.c` 的 `do_wp_page` → `wp_page_copy` (看它怎麼處理 `is_zero_pfn`) |
| fault 的分派流程 | `build/linux-5.15.135/mm/memory.c` 的 `__handle_mm_fault` → `handle_pte_fault`；x86 的入口在 `build/linux-5.15.135/arch/x86/mm/fault.c` |
| `mmap` 的長度會對齊到 page | `build/linux-5.15.135/mm/mmap.c` 的 `do_mmap` 中的 `len = PAGE_ALIGN(len)` |

### 3.3 驗證

執行 `scripts/5-compile.sh && scripts/6-run.sh`：

- 目標：`q1` 全部 `[PASS]`，並且出現 `[init] q1 exited with status 0`
- `Physical Discontinuity` 是 `[INFO]`，結果取決於 buddy allocator，不算錯誤
- 出現 FAIL 時，用 `pr_info()` 印出各層的 entry 和 physical address，對照該項的判斷式找原因

### 3.4 常見陷阱

- State 2 三個位址的 physical address (扣掉 offset 後) 必須相同；如果把 zero page 濾掉，這項就會失敗
- State 3 要求 Byte 4096 的 physical address 不變；查詢時觸發 fault 會破壞這一項
- Part B Section 1 要求 `p[4096]` 回傳 0，因為那裡是 `PROT_NONE` 的 guard mapping

### 3.5 報告要回答的問題

- 附上執行結果的截圖
- 根據 Part A 解釋：Byte 0 寫入後拿到私有 page，為什麼 Byte 4096 仍然 map 到 Global Zero Page？重點放在 **Page Granularity**
  - 一個 PTE 負責多大的範圍？Byte 0、100、4096 各落在哪個 PTE？write fault 改的是哪一個？
- 根據 Part B 解釋：virtual address 和 physical address 低 12 bit 的關係 (**In-page Offset Invariance**)，以及 page table 如何對使用者隱藏 physical memory 的不連續
  - page table 翻譯的是 virtual address 的哪幾個 bit？低 12 bit 有經過 page table 嗎？每個 virtual page 的 PTE 能不能指向任意的 frame？

## 4. Question 2 (30 分)：anonymous 與 file-backed、CoW、Page Cache

### 4.1 題目要求

- **Part 1 (Backing Types)**：anonymous page 讀取後 map 到 zero page；file-backed page 讀入檔案資料，map 到 Page Cache 的 frame
- **Part 2 (Copy-on-Write)**：`fork()` 之後，parent 和 child process 共用 physical page；child 寫入時會配置私有的 page，parent 的 frame 不變
- **Part 3 (Cache Persistence & Invalidation)**
  - Process A 結束後，Process B 即使用不同的 virtual address (VA Shifting)，仍然會命中同一批 frame
  - `drop_caches` 之後：仍被 map 的 `libm.so` (`mapcount > 0`) 不會被回收；沒有被 map 的 `dummy.bin` (`mapcount == 0`) 會被回收，`mincore()` 的結果依序是 1 → 0 → 1

作業說明的執行方式是 `gcc -Wall -Wextra -O2 q2.c -o q2 -ldl`，再 `sudo ./q2`。最後會印出 `Summary: N FAIL, N INCONCLUSIVE, N SKIP`。

### 4.2 要理解的 kernel 行為

| 現象 | 對應程式碼／文件 |
|---|---|
| file-backed page 的 read fault | `build/linux-5.15.135/mm/memory.c` 的 `do_fault` → `do_read_fault`、`build/linux-5.15.135/mm/filemap.c` 的 `filemap_fault` |
| `fork()` 複製 page table，並把雙方都設成唯讀 | `build/linux-5.15.135/mm/memory.c` 的 `copy_page_range` → `copy_present_pte` |
| child 寫入時各自分開 | `build/linux-5.15.135/mm/memory.c` 的 `do_wp_page`、`wp_page_copy` |
| `drop_caches` 做了什麼 | `build/linux-5.15.135/fs/drop_caches.c` 的 `drop_pagecache_sb` → `build/linux-5.15.135/mm/truncate.c` 的 `invalidate_mapping_pages` → `invalidate_inode_page` (看它遇到 `page_mapped()` 時怎麼處理)；說明文件在 `build/linux-5.15.135/Documentation/admin-guide/sysctl/vm.rst` 的 `drop_caches` 段落 |
| mapcount | `build/linux-5.15.135/include/linux/mm.h` 的 `page_mapcount`、`build/linux-5.15.135/mm/util.c` 的 `page_mapped`、`build/linux-5.15.135/include/linux/mm_types.h` 的 `_mapcount` |
| `mincore()` 怎麼判斷 resident | `build/linux-5.15.135/mm/mincore.c` (`mincore_page` 查的是 page cache，不是 PTE) |
| `/proc/kpagecount` | `build/linux-5.15.135/fs/proc/page.c` 的 `kpagecount_read`、`build/linux-5.15.135/Documentation/admin-guide/mm/pagemap.rst` |

### 4.3 執行環境

`scripts/6-run.sh` 開機時用的 root filesystem，是把編譯用的 Docker image 做成的 Ubuntu 22.04 ext4 disk image (`build/rootfs.img`，由 `scripts/rootfs.sh` 建立)，init 也以 root 身分執行，所以 Q2 需要的條件都已經具備：

1. **`/proc`**：init (`tests/init.sh`) 會掛載 proc、sysfs、devtmpfs，`/proc/sys/vm/drop_caches` 可以寫入，`/proc/kpagecount` 可以讀取 (kernel config 開了 `CONFIG_PROC_PAGE_MONITOR`)
2. **`/var/tmp`**：Ubuntu 的 root filesystem 本來就有這個目錄
3. **`libm.so.6`**：image 裡有完整的 glibc，`q1`、`q2` 照作業說明的指令動態連結
4. **不是 tmpfs**：`/var/tmp` 在 ext4 (IDE 磁碟 `/dev/sda`) 上，`dummy.bin` 的 page cache 可以被 `drop_caches` 回收，不會出現 `[WARN] /var/tmp is tmpfs`

另外，kernel config 已經開啟 THP (`madvise` 模式，和 Ubuntu 22.04 相同)，可以自己寫測試來驗證 huge PMD 路徑。

有兩種執行方式：

- **自動**：`scripts/5-compile.sh && scripts/6-run.sh`，依序執行 `q1`、`q2` 後關機，輸出在 `build/qemu.log`
- **互動 (Demo 用)**：`scripts/6-run.sh shell` 會進入 root 的 bash，`/root` 底下有 `q1.c`、`q2.c` 和編好的 `q1`、`q2`。你可以照作業說明用 `gcc -Wall -Wextra -O2 q2.c -o q2 -ldl` 重新編譯，也能當場編譯助教給的其他程式；因為已經是 root，不需要 `sudo`。用 `poweroff -f` 或 `exit` 關機

目前的實作跑 `q2` 是 `Summary: 0 FAIL, 0 INCONCLUSIVE, 0 SKIP`。如果 syscall 直接 `return 0`，結果會是 `Summary: 2 FAIL, 3 INCONCLUSIVE, 0 SKIP`：兩個 FAIL (`Zero page + file frame`、`CoW`) 和三個 INCONCLUSIVE (`Same PA as A baseline`、`PA changed after reload`、`libm PA stable while mapped`) 都是因為 syscall 回傳 0；`VA shifted` 和 `dummy.bin reclaim` (只靠 `mincore()` 和 `drop_caches`) 仍然會 PASS，可以用來確認環境沒有問題。

照作業說明的做法 (在 Ubuntu 22.04 虛擬機裡編譯、安裝 kernel 後開機執行) 也可以；這個 repo 的 QEMU 流程則不需要安裝 kernel。

### 4.4 常見陷阱

- Part 3 必須以 root 執行，否則整段都會 SKIP
- INCONCLUSIVE 不等於 FAIL，它代表環境沒有讓現象發生 (virtual address 沒有錯開、cache 沒有被回收)。報告裡要能解釋原因，或是調整環境
- Part 1 的 file page 拿到的 physical address 是 0，或是 CoW 對不上，通常是 syscall 本身的問題 (回到第 2 節檢查)

### 4.5 報告要回答的問題

- 附上執行結果的截圖
- 為什麼 kernel 不能在讀取時把 file-backed page map 到 Global Zero Page？
  - zero page 和 file-backed page 各自應該呈現什麼內容？`MAP_SHARED` mapping 和 page cache、其他 process 之間要保持什麼樣的一致性？
- 為什麼 `dummy.bin` 會被清出記憶體 (`mincore()` 1 → 0 → 1)，重新存取時載入到新的 frame，而 `libm.so` 在 `drop_caches` 之後仍然回傳原本的 physical address？請用 **`mapcount`** 說明
  - `drop_caches` 之前，`q2` 對這兩個檔案各做了什麼 (有沒有 unmap)？`invalidate_inode_page` 遇到仍被 map 的 page 時怎麼處理？`kpagecount` 的數字代表什麼？

## 5. 報告與繳交

- 用 **HackMD** 撰寫，寫上**所有組員的姓名與學號**
- 內容包含：原始碼 (`src/linux_kernel_hw1.c` 和接上 syscall 的修改)、執行結果截圖、3.5 與 4.5 的答案
- 在 2026-11-10 前把 HackMD 網址交到 **eeclass**
- **一定要開啟讀取權限**，沒開視同未繳交；**不接受遲交**
- demo 現場只能看已繳交的 report 或紙本，所以報告要寫到能當小抄用：syscall 每一步的理由、每項 PASS 的意義、四題的完整答案

## 6. Demo 準備

### 6.1 流程與規定 (2026-11-04 助教公告)

| 項目 | 內容 |
|---|---|
| step 1 (60%) | 當場開啟 kernel 環境執行一次並解說；可以由一人完整講解，也可以組員分工 |
| step 2 (40%) | 每組 8 題 Q&A，當場抽題；**每位組員至少回答兩題**；可以小組討論，但不能替別人回答 |
| 時間 | 每組 15 + 5 分鐘，**超過 20 分鐘後的回答不計分** |
| 遲到 | 從預約時段開始算，最多有 5 分鐘緩衝，**包含在 20 分鐘內**，超過就不等 |
| 缺席 | 組員無故缺席，該組員 0 分 |
| 設備 | 自備筆電當場執行，**kernel 環境要先開好** |
| 資料 | **禁止使用手機、禁止上網查資料**；可以用筆電看已繳交的 report，或帶紙本資料 |

### 6.2 準備清單

> **現場一定要能跑 Q2**：在自備的筆電上照 `README.md` 建好環境，確認 `scripts/6-run.sh shell` 開機後，Q1、Q2 都能完整跑完。

1. **環境**：到場前先執行 `scripts/6-run.sh shell` 把 VM 開好，不要在 20 分鐘內才開機或編譯；需要的檔案事先離線存在筆電上 (`build/` 裡已經有 kernel 和 `rootfs.img`，現場不需要網路)
2. **時間分配** (建議)：提早到場，不要用掉遲到緩衝；step 1 約 6 分鐘 (Q1、Q2 各約 3 分鐘，講重點，不要逐行念程式碼)；8 題 Q&A 留 8 到 10 分鐘；到第 15 分鐘後要留意時間
3. **分工**：step 1 事先排好誰講哪一段 (例如 syscall 實作、Q1 結果、Q2 結果)；step 2 不能代答，**每位組員都要能回答 6.3 的所有題目**
4. **資料**：報告要寫到能當小抄用 (見第 5 節)；也可以另外準備紙本，例如 page table 各層的 bit 分配、syscall 流程圖、各項 PASS 的意義
5. **演練**：在那台筆電上完整演練一次並計時：開環境、跑 Q1 和 Q2、解說、模擬抽題

### 6.3 可能的問答方向 (自行整理，非助教提供)

- 你的 syscall 從 `current->mm` 一路走到 physical address 的每一步是什麼？每一層遇到什麼情況會回傳 0？
- 為什麼要 `mmap_read_lock`？為什麼用 `_killable`？PTE 層為什麼還要另外上鎖？
- 為什麼 leaf 檢查要放在 `pmd_bad()` 之前？huge PMD 為什麼要上鎖後重新檢查？
- 為什麼不用 `copy_from_user()`？為什麼要檢查 `TASK_SIZE`？`pfn_valid()` 的用途是什麼？
- Demand paging、zero page、CoW 各自省下了什麼？read fault 和 write fault 的處理差在哪裡？
- 為什麼 virtual address 和 physical address 的低 12 bit 相同？連續的 virtual address 為什麼不需要連續的 physical address？
- anonymous page 和 file-backed page 在記憶體不足時各自怎麼處理 (丟棄、寫回、swap)？
- `drop_caches` 會回收哪些 page、不回收哪些 page？`mapcount` 和 `refcount` 有什麼不同？

