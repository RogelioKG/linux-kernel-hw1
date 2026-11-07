# Architecture

這個專案在 Linux 5.15.135 新增 syscall `my_get_physical_addresses` (x86_64 number 449)。整個流程分在三個環境裡執行：

- **主機**：依序執行 `scripts/` 的各個步驟，下載並修改 kernel source，最後用 QEMU 開機
- **Docker builder container** (`linux-kernel-hw1-builder`，Ubuntu 22.04 / GCC 11)：`scripts/in-docker.sh` 把 `docker run` 包起來，所有編譯和 image 處理都在這裡做
- **QEMU guest**：用 `build/rootfs.img` 當 root filesystem 開機，PID 1 是 `/usr/sbin/hw1-init` (也就是 `tests/init.sh`)，由它執行測試

環境建置的細節見 [`README.md`](../README.md)，作業引導見 [`GUIDE.md`](./GUIDE.md)。

## 1. 建置流程

```mermaid
flowchart TD
    subgraph HOST["主機"]
        S1["1-image.sh<br/>docker build"]
        S2["2-fetch.sh<br/>curl | tar (已解開就跳過)"]
        S3["3-wire.sh<br/>symlink src/、改 kernel/Makefile 與 syscall_64.tbl"]
        S4h["4-config.sh<br/>scripts/config 開 THP、PROC_PAGE_MONITOR"]
        S5["5-compile.sh"]
        S6["6-run.sh<br/>qemu-system-x86_64 -enable-kvm"]
    end

    subgraph DOCKER["Docker builder container (scripts/in-docker.sh)"]
        D4["make defconfig / olddefconfig"]
        D5k["make bzImage"]
        D5t["gcc q1.c、q2.c"]
        DR["rootfs.sh (由 1-image.sh 呼叫)<br/>docker export image → 解開<br/>gcc poweroff.c → mkfs.ext4"]
        D5f["e2fsck -p<br/>debugfs -f tests/rootfs.debugfs"]
    end

    subgraph GUEST["QEMU guest"]
        G1["/usr/sbin/hw1-init (PID 1)<br/>掛載 proc / sysfs / devtmpfs"]
        GA["hw1=auto<br/>執行 /root/q1、/root/q2 後關機"]
        GS["hw1=shell<br/>root bash，poweroff -f 離開"]
    end

    S1 -- "docker build 之後" --> DR
    S1 --> S2 --> S3 --> S4h
    S4h -. 前後各呼叫 .-> D4
    S4h --> S5
    S5 --> D5k --> D5t --> D5f
    S5 --> S6
    S6 -- "開機 bzImage + rootfs.img" --> G1
    G1 --> GA
    G1 --> GS
    GA -- "serial console 輸出 tee" --> LOG["build/qemu.log"]
```

- 第一次要依序執行 1 到 6；之後修改 `src/linux_kernel_hw1.c`，只需要重跑 `5-compile.sh && 6-run.sh`
- `4-config.sh` 裡的 `defconfig`、`olddefconfig` 在 container 裡執行，夾在中間的 `scripts/config` 則在主機上執行
- `1-image.sh` 在 `docker build` 之後呼叫 `rootfs.sh`，每次都重建 `build/rootfs.img`。其中 `docker create`、`docker export` 在主機上執行，解開 image、編譯 `poweroff`、`mkfs.ext4` 則在 container 裡
- `2-fetch.sh` 發現 `build/linux-5.15.135` 已存在就直接結束，避免重新解壓蓋掉 `3-wire.sh` 改過的 `kernel/Makefile` 與 `syscall_64.tbl`

## 2. 檔案與產物對應

```mermaid
flowchart LR
    subgraph REPO["repo"]
        DF["Dockerfile"]
        SRC["src/<br/>linux_kernel_hw1.c、Makefile"]
        Q1C["tests/q1.c"]
        Q2C["tests/q2.c"]
        INIT["tests/init.sh"]
        POFF["tests/poweroff.c"]
        DBG["tests/rootfs.debugfs"]
    end

    subgraph BUILD["build/ (gitignore)"]
        IMG[("builder image<br/>linux-kernel-hw1-builder")]
        KSRC["linux-5.15.135/<br/>kernel/linux_kernel_hw1 → src/"]
        OUT["out/.config"]
        BZ["out/arch/x86/boot/bzImage"]
        Q1["q1"]
        Q2["q2"]
        ROOTFS["rootfs.img (ext4, 2G)"]
        LOG["qemu.log"]
    end

    subgraph GFS["guest root filesystem (rootfs.img 內)"]
        GINIT["/usr/sbin/hw1-init"]
        GPOFF["/usr/sbin/poweroff"]
        GROOT["/root/q1、q2<br/>/root/q1.c、q2.c"]
    end

    DF -- "1-image.sh" --> IMG
    SRC -- "3-wire.sh symlink" --> KSRC
    KSRC -- "4-config.sh" --> OUT
    KSRC --> BZ
    OUT -- "5-compile.sh make bzImage" --> BZ
    Q1C -- "5-compile.sh gcc" --> Q1
    Q2C -- "5-compile.sh gcc -ldl" --> Q2
    IMG -- "rootfs.sh docker export" --> ROOTFS
    POFF -- "rootfs.sh gcc" --> GPOFF
    DBG -. "debugfs 依此清單寫入" .-> ROOTFS
    INIT --> GINIT
    Q1 --> GROOT
    Q2 --> GROOT
    Q1C --> GROOT
    Q2C --> GROOT
    GINIT --- ROOTFS
    GPOFF --- ROOTFS
    GROOT --- ROOTFS
    BZ -- "6-run.sh -kernel" --> LOG
    ROOTFS -- "6-run.sh -drive" --> LOG
```

- `rootfs.img` 是把整個 builder image 匯出後做成的 Ubuntu 22.04 root filesystem，所以 guest 裡有 bash、gcc、glibc。它由 `rootfs.sh` 建立，`1-image.sh` 每次都會呼叫它；修改 `Dockerfile` 之後重跑 `1-image.sh`，只改 `tests/poweroff.c` 時重跑 `rootfs.sh` 即可，兩者之後都要再跑 `5-compile.sh`
- 每次執行 `5-compile.sh`，都會用 `debugfs` 照 `tests/rootfs.debugfs` 的清單，把 `init.sh`、`q1`、`q2` 和它們的原始碼覆寫進 `rootfs.img`，不需要 mount，也不需要 root
- `qemu.log` 只在自動模式 (`6-run.sh` 不加參數) 產生，`shell` 模式不會寫檔
