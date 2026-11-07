# Linux Kernel Project 1：`my_get_physical_addresses`

## 組員

| 姓名 | 學號 |
|---|---|
| <!-- TODO --> | <!-- TODO --> |

## 1. 原始碼

環境是 Linux 5.15.135、x86_64，syscall number 為 449。

### `kernel/linux_kernel_hw1/linux_kernel_hw1.c`

```c=
#include <linux/kernel.h>
#include <linux/mm.h>
#include <linux/mmap_lock.h>
#include <linux/pgtable.h>
#include <linux/sched.h>
#include <linux/syscalls.h>
#include <linux/types.h>

SYSCALL_DEFINE1(my_get_physical_addresses, void __user *, vaddr) {
  unsigned long addr = (unsigned long)vaddr;
  struct mm_struct *mm = current->mm;
  phys_addr_t pa = 0;
  unsigned long pfn;
  spinlock_t *ptl;
  pgd_t *pgdp;
  p4d_t *p4dp;
  pud_t *pudp, pud;
  pmd_t *pmdp, pmd;
  pte_t *ptep, pte;

  if (!mm || addr >= TASK_SIZE)
    return 0;

  if (mmap_read_lock_killable(mm))
    return 0;

  pgdp = pgd_offset(mm, addr);
  if (pgd_none(*pgdp) || unlikely(pgd_bad(*pgdp)))
    goto out;

  p4dp = p4d_offset(pgdp, addr);
  if (p4d_none(*p4dp) || unlikely(p4d_bad(*p4dp)))
    goto out;

  pudp = pud_offset(p4dp, addr);
  pud = READ_ONCE(*pudp);
  if (pud_none(pud))
    goto out;
  if (pud_leaf(pud)) {
    if (pud_present(pud)) {
      pfn = pud_pfn(pud);
      if (pfn_valid(pfn))
        pa = ((phys_addr_t)pfn << PAGE_SHIFT) | (addr & ~PUD_MASK);
    }
    goto out;
  }
  if (unlikely(pud_bad(pud)))
    goto out;

  pmdp = pmd_offset(pudp, addr);
  pmd = READ_ONCE(*pmdp);
  if (pmd_none(pmd))
    goto out;
  if (pmd_leaf(pmd)) {
    ptl = pmd_lock(mm, pmdp);
    pmd = READ_ONCE(*pmdp);
    if (pmd_present(pmd) && pmd_leaf(pmd)) {
      pfn = pmd_pfn(pmd);
      if (pfn_valid(pfn))
        pa = ((phys_addr_t)pfn << PAGE_SHIFT) | (addr & ~PMD_MASK);
      spin_unlock(ptl);
      goto out;
    }
    spin_unlock(ptl);
    if (pmd_none(pmd))
      goto out;
  }
  if (unlikely(pmd_bad(pmd)))
    goto out;

  ptep = pte_offset_map_lock(mm, pmdp, addr, &ptl);
  pte = *ptep;
  if (pte_present(pte)) {
    pfn = pte_pfn(pte);
    if (pfn_valid(pfn))
      pa = ((phys_addr_t)pfn << PAGE_SHIFT) | (addr & ~PAGE_MASK);
  }
  pte_unmap_unlock(ptep, ptl);

out:
  mmap_read_unlock(mm);
  return (long)pa;
}
```

### Kernel 修改處

`kernel/linux_kernel_hw1/Makefile`：

```makefile
obj-y := linux_kernel_hw1.o
```

`kernel/Makefile` 結尾新增：

```makefile
obj-y += linux_kernel_hw1/
```

`arch/x86/entry/syscalls/syscall_64.tbl` 在 448 之後新增：

```
449	common	my_get_physical_addresses	sys_my_get_physical_addresses
```

## 2. 執行結果

### Question 1

<!-- TODO: QEMU guest 裡執行 ./q1 的完整輸出截圖 -->
![Q1](TODO-q1.png)

### Question 2

<!-- TODO: QEMU guest 裡以 root 執行 ./q2 的完整輸出截圖 (可分兩張) -->
![Q2](TODO-q2.png)

## 3. 問答題

### Q1-1. 為什麼 Byte 0 拿到私有 frame 之後，Byte 4096 仍然停在 Global Zero Page？

page table、page fault 和 CoW 都以 page (4 KiB，也就是一個 PTE) 為單位。Byte 0 和 Byte 100 在同一個 page，共用一個 PTE；Byte 4096 在下一個 page，有自己的 PTE。

- **State 2**：兩個 page 各自發生 read fault，`do_anonymous_page()` 都為它們裝上指向 zero page 的唯讀 special PTE，所以三個 byte 都對應到 `0xd4c4000` 這個 frame。
- **State 3**：寫入 Byte 0 時觸發 write-protect fault，`do_wp_page()` → `wp_page_copy()` 配置一個新的、已清零的 frame (`0xda19000`)，而且**只替換發生 fault 的那個 PTE**。Byte 100 共用這個 PTE，所以跟著換到新 frame；Byte 4096 的 PTE 沒有被動到，仍然指向 zero page。

### Q1-2. 為什麼 VA 和 PA 的低 12 bits 相同？page table 如何隱藏 physical memory 的不連續？

**Offset 不變**：在 4 KiB page 下，virtual address (VA) 只有 bits 47..12 (virtual page number) 會經過 page table 轉換成 PFN，低 12 bits 是 page 內的 offset，直接沿用：`PA = (PFN << 12) | VA[11:0]`。輸出中 Byte 100 的 VA `...064` 對應到 physical address (PA) `0xd4c4064`、`0xda19064`，Byte 4095 的 `...fff` 對應到 `0xda19fff`，都符合這個關係。

**隱藏不連續**：每個 virtual page 都有自己的 PTE，各自記錄一個 PFN。發生 fault 時，frame 由 buddy allocator 隨意配發，和相鄰 virtual page 的 frame 沒有關係。Part B Section 2 中五個 VA 每次剛好加 4096，PA 卻在 `0xc5f4000`～`0xda30000` 之間跳動。程式的每次存取都由 MMU 逐 page 轉換，只需要 page 內連續，所以察覺不到 physical address 不連續。

### Q2-1. 為什麼 file-backed page 讀取時不能 map 到 Global Zero Page？

- **處理路徑不同**：`handle_pte_fault()` 只有在 anonymous VMA 時才會走 `do_anonymous_page()`，這也是唯一會裝上 zero page 的地方。file VMA 走的是 `do_fault()` → `filemap_fault()`，map 的是 page cache 裡的 page，沒有命中就從磁碟讀入。
- **內容不同**：zero page 只適用於內容本來就定義為零的 anonymous memory；file page 必須呈現檔案的實際資料。
- **一致性**：`read()`、`write()` 和所有 process 的 `mmap` 都要看到同一份資料，所以必須共用同一個 page cache page。寫入時還要把 page 標成 dirty，並靠 `page->mapping` / `page->index` 寫回檔案，而 zero page 沒有這些資訊。

輸出中兩個 anonymous page 都是 `0xd4c4000` (zero page)，file page 則是 `0xc5f8000`；另一個 process B 在不同的 VA map 同一個檔案，拿到的也是 `0xc5f8000`，可見兩者共用同一個 page cache page。

### Q2-2. 為什麼 `drop_caches` 之後 `dummy.bin` 被清掉並換了新 frame，`libm.so` 的 PA 卻沒有變？

`_mapcount` 記錄有多少個 PTE map 到這個 page。`drop_caches` 會對每個 page 呼叫 `invalidate_inode_page()`，遇到 dirty 或 `page_mapped()` (mapcount > 0) 的 page 就跳過，只丟掉**乾淨而且沒有被 map** 的 page。

- **`dummy.bin`**：q2 先呼叫 `sync()` 讓 page 變乾淨，再 `munmap` 讓 mapcount 降到 0，所以這個 page 被移出 page cache，mincore 從 1 變成 0。重新存取時 `filemap_fault()` 沒有命中，於是配置新的 frame 並從磁碟讀回，mincore 變回 1，PA 從 `0xc5f8000` 變成 `0xcbfa000`。
- **`libm.so`**：process B 仍然透過 `dlopen` map 著這個 page (`kpagecount=1`)，mapcount > 0，所以被跳過，PA 維持在 `0xc54c1c0`。
