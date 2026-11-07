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
