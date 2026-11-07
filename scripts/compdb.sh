#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
K=build/linux-5.15.135

python3 -W ignore $K/scripts/clang-tools/gen_compile_commands.py \
  -d build/out -o build/out/compile_commands.json
python3 - "$PWD" "$K" <<'EOF'
import json, sys
root, k = sys.argv[1:3]
link = f"{root}/{k}/kernel/linux_kernel_hw1/"
src = f"{root}/src/"
db = json.load(open(f"{root}/build/out/compile_commands.json"))
db += [{**e, "file": e["file"].replace(link, src), "command": e["command"].replace(link, src)}
       for e in db if e["file"].startswith(link)]
db += [{"directory": root, "file": f"{root}/tests/{name}",
        "command": f"cc -Wall -Wextra -O2 -c tests/{name}"}
       for name in ("q1.c", "q2.c", "poweroff.c")]
json.dump(db, open(f"{root}/compile_commands.json", "w"), indent=1)
EOF
echo "compile_commands.json written"
