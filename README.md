# linux-kernel-hw1

Linux Kernel 作業：在 Linux 5.15.135 (x86_64) 新增 syscall `my_get_physical_addresses` (number 449)，傳入 virtual address，回傳對應的 physical address。

Kernel 在 Ubuntu 22.04 的 Docker container 裡 build，再用 QEMU + KVM 開機測試。不會安裝到主機上，也不需要 `sudo`，刪掉 `build/` 就能回到原狀。

作業的完整步驟見 [`docs/GUIDE.md`](docs/GUIDE.md)，整體架構見 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

## Prerequisites (Arch Linux)

```bash
sudo pacman -S --needed git docker qemu-system-x86
sudo systemctl enable --now docker
sudo usermod -aG docker,kvm "$USER"   # 完成後重新登入
docker info >/dev/null && [ -w /dev/kvm ] && echo ready
```

最後一行印出 `ready` 就表示環境沒問題。

## Build & Run

第一次照順序執行：

```bash
scripts/1-image.sh    # 建立 build 用的 container image，並用它產生 build/rootfs.img
scripts/2-fetch.sh    # 下載 kernel source 到 build/linux-5.15.135
scripts/3-wire.sh     # 把 src/ 接進 kernel，並在 syscall table 登記 449
scripts/4-config.sh   # 產生 kernel config 到 build/out
scripts/5-compile.sh  # 編譯 kernel 與 q1、q2，放進 build/rootfs.img
scripts/6-run.sh      # 用 QEMU 開機，自動執行 q1、q2 後關機
```

之後修改 `src/linux_kernel_hw1.c`，只需要重跑最後兩步：

```bash
scripts/5-compile.sh && scripts/6-run.sh
```

## Results

- 輸出都在 `build/qemu.log`
- `q1` 全部 `[PASS]` 就是通過；`q2` 看最後一行 `Summary: N FAIL, N INCONCLUSIVE, N SKIP`
- Demo 時用 `scripts/6-run.sh shell` 進入 VM 的 root shell，`q1`、`q2` 在 `/root`，結束時輸入 `poweroff -f`
- QEMU 沒有回應時，按 `Ctrl-A` 再按 `X` 離開

## Troubleshooting

| 狀況 | 處理方式 |
|---|---|
| Docker 出現 `permission denied`，或 QEMU 無法使用 KVM | 確認已加入 `docker`、`kvm` group，並且重新登入過 |
| 開機停在 `VFS: Unable to mount root fs` | 重跑 `scripts/rootfs.sh` 重建 `build/rootfs.img`，再跑一次 `scripts/5-compile.sh` |
