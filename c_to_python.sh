#!/bin/bash
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <c-file> [module-name]"
  exit 1
fi

C_FILE="$1"
MODULE_NAME="${2:-cmodule}"
WORKDIR="./output"
CONFIG_FILE="./cloud_config.json"
mkdir -p "$WORKDIR"

if [ ! -f "$C_FILE" ]; then
  echo "Error: $C_FILE not found"
  exit 1
fi

# ── 读取云端配置 ──
if [ -f "$CONFIG_FILE" ]; then
  echo "==> 读取云端配置: $CONFIG_FILE"
  # 用 python 解析 json，安全取出字段
  CLOUD_MODEL=$(python3 -c "import json; cfg=json.load(open('$CONFIG_FILE')); print(cfg.get('model',''))")
  CLOUD_API_KEY=$(python3 -c "import json; cfg=json.load(open('$CONFIG_FILE')); print(cfg.get('apiKey',''))")
  CLOUD_API_BASE=$(python3 -c "import json; cfg=json.load(open('$CONFIG_FILE')); print(cfg.get('apiBase',''))")
  if [ -z "$CLOUD_MODEL" ] || [ -z "$CLOUD_API_KEY" ] || [ -z "$CLOUD_API_BASE" ]; then
    echo "Warning: 云端配置不完整，跳过 Claude 审查"
    SKIP_CLAUDE=1
  else
    SKIP_CLAUDE=0
  fi
else
  echo "Warning: 未找到 $CONFIG_FILE，跳过 Claude 审查（可复制 cloud_config.example.json 并修改）"
  SKIP_CLAUDE=1
fi

echo "==> Step 1: CodeLlama 生成 Python 绑定"
python3 -c "
import sys
template = open('templates/01_generate.md', 'r').read()
c_code = open('$C_FILE', 'r').read()
prompt = template.replace('{{MODULE_NAME}}', '$MODULE_NAME').replace('{{C_CODE}}', c_code)
sys.stdout.write(prompt)
" | ollama run codellama:7b > "$WORKDIR/generated_raw.txt"

cd "$WORKDIR"
awk '/^===FILE:/ {
    filename = substr($0, 9, length($0)-11)
    if (outfile) close(outfile)
    outfile = filename
    next
}
/^```/ { in_code = !in_code; next }
in_code && outfile { print > outfile }' generated_raw.txt

if [ ! -f "${MODULE_NAME}.c" ]; then
  FOUND_C=$(ls *.c 2>/dev/null | grep -v test | head -1)
  if [ -n "$FOUND_C" ]; then
    echo "Warning: CodeLlama 生成了 '$FOUND_C' 而非 '${MODULE_NAME}.c'，已自动纠正"
    mv "$FOUND_C" "${MODULE_NAME}.c"
  else
    echo "Error: 未生成任何 C 扩展文件"
    cat generated_raw.txt
    exit 1
  fi
fi
cd - > /dev/null

echo "==> Step 2: Qwen 14B 安全审查"
python3 -c "
import sys
template = open('templates/02_review_qwen.md', 'r').read()
extension_code = open('$WORKDIR/${MODULE_NAME}.c', 'r').read()
prompt = template.replace('{{MODULE_NAME}}', '$MODULE_NAME').replace('{{EXTENSION_CODE}}', extension_code)
sys.stdout.write(prompt)
" | ollama run qwen2.5:14b > "$WORKDIR/review_qwen_raw.txt"

cd "$WORKDIR"
awk '/^===FILE:/ {
    filename = substr($0, 9, length($0)-11)
    if (outfile) close(outfile)
    outfile = filename
    next
}
/^```/ { in_code = !in_code; next }
in_code && outfile { print > outfile }' review_qwen_raw.txt
cd - > /dev/null

if [ ! -f "$WORKDIR/${MODULE_NAME}_final.c" ]; then
  echo "Warning: Qwen 未生成 ${MODULE_NAME}_final.c，使用原始文件作为最终代码"
  cp "$WORKDIR/${MODULE_NAME}.c" "$WORKDIR/${MODULE_NAME}_final.c"
fi

echo "==> Step 3: Claude 架构审查"
if [ "$SKIP_CLAUDE" -eq 1 ]; then
  echo "==> 跳过 Claude 审查"
else
  REVIEW_PROMPT=$(python3 -c "
import sys
template = open('templates/03_review_claude.md', 'r').read()
final_code = open('$WORKDIR/${MODULE_NAME}_final.c', 'r').read()
prompt = template.replace('{{MODULE_NAME}}', '$MODULE_NAME').replace('{{FINAL_CODE}}', final_code)
print(prompt)
")
  curl -s "${CLOUD_API_BASE}/messages" \
    -H "x-api-key: $CLOUD_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$(jq -n --arg prompt "$REVIEW_PROMPT" \
       --arg model "$CLOUD_MODEL" \
       '{
          model: $model,
          max_tokens: 2000,
          messages: [{role: "user", content: $prompt}]
        }')" > "$WORKDIR/review_claude.json"
  echo "==> Claude 审查完成"
fi

echo ""
echo "========================================"
echo "  流水线成功完成！"
ls -la "$WORKDIR"
echo "========================================"