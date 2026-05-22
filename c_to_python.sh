#!/bin/bash
set -e

# ── 参数解析 ──
RESUME_STEP=1
C_FILE=""
MODULE_NAME=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --resume)
      RESUME_STEP="$2"
      shift 2
      ;;
    -*)
      echo "未知参数: $1"
      exit 1
      ;;
    *)
      if [ -z "$C_FILE" ]; then
        C_FILE="$1"
      elif [ -z "$MODULE_NAME" ]; then
        MODULE_NAME="$1"
      else
        echo "多余参数: $1"
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$C_FILE" ]; then
  echo "Usage: $0 <c-file> [module-name] [--resume step2|step3]"
  echo "Example: $0 fib.c fibex --resume step3"
  exit 1
fi

MODULE_NAME="${MODULE_NAME:-cmodule}"
WORKDIR="./output"
CONFIG_FILE="./cloud_config.json"
mkdir -p "$WORKDIR"

if [ ! -f "$C_FILE" ]; then
  echo "Error: $C_FILE not found"
  exit 1
fi

# ── 清理无效 UTF-8 字符 ──
clean_utf8() {
  cd "$WORKDIR"
  python3 -c "
import glob
for f in glob.glob('*.c') + glob.glob('*.py') + glob.glob('*.txt'):
    try:
        with open(f, 'rb') as fh: data = fh.read()
        clean = data.decode('utf-8', errors='ignore').encode('utf-8')
        with open(f, 'wb') as fh: fh.write(clean)
    except:
        pass
" 2>/dev/null || true
  cd - > /dev/null
}

# ── 删除 Python 文件中的非 ASCII 行（保留 shebang/coding） ──
sanitize_python() {
  cd "$WORKDIR"
  for f in *.py; do
    [ ! -f "$f" ] && continue
    python3 -c "
with open('$f', 'r', errors='ignore') as fh:
    lines = fh.readlines()
new_lines = []
for line in lines:
    if line.startswith('#!') or 'coding' in line:
        new_lines.append(line)
        continue
    # 如果包含非 ASCII 字符，整行跳过
    if any(ord(c) > 127 for c in line):
        continue
    new_lines.append(line)
with open('$f', 'w') as fh:
    fh.writelines(new_lines)
"
  done
  cd - > /dev/null
}

# ── 文件拆分（处理有无代码块标记） ──
split_files() {
  local input_file="$1"
  cd "$WORKDIR"
  awk '
  /^===FILE:/ {
      if (outfile) close(outfile)
      filename = substr($0, 9, length($0)-11)
      outfile = filename
      in_file = 1
      code_block = 0
      next
  }
  in_file && outfile {
      if ($0 ~ /^```/) {
          code_block = !code_block
          next
      }
      if (code_block || $0 !~ /^```/) {
          print > outfile
      }
  }
  ' "$input_file"
  cd - > /dev/null
  clean_utf8
  sanitize_python
}

# ── 读取云端配置 ──
if [ -f "$CONFIG_FILE" ]; then
  echo "==> 读取云端配置: $CONFIG_FILE"
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
  echo "Warning: 未找到 $CONFIG_FILE，跳过 Claude 审查"
  SKIP_CLAUDE=1
fi

# ── Step 1 ──
if [ "$RESUME_STEP" -le 1 ]; then
  echo "==> Step 1: CodeLlama 生成 Python 绑定"
  python3 -c "
import sys
template = open('templates/01_generate.md', 'r').read()
c_code = open('$C_FILE', 'r').read()
prompt = template.replace('{{MODULE_NAME}}', '$MODULE_NAME').replace('{{C_CODE}}', c_code)
sys.stdout.write(prompt)
" | ollama run codellama:7b > "$WORKDIR/generated_raw.txt"

  split_files "generated_raw.txt"

  if [ ! -f "$WORKDIR/${MODULE_NAME}.c" ]; then
    FOUND_C=$(cd "$WORKDIR" && ls *.c 2>/dev/null | grep -v test | head -1)
    if [ -n "$FOUND_C" ]; then
      echo "Warning: CodeLlama 生成了 '$FOUND_C' 而非 '${MODULE_NAME}.c'，已自动纠正"
      mv "$WORKDIR/$FOUND_C" "$WORKDIR/${MODULE_NAME}.c"
    else
      echo "Error: 未生成任何 C 扩展文件"
      cat "$WORKDIR/generated_raw.txt"
      exit 1
    fi
  fi

  # 快速编译预检
  echo "==> 快速编译预检..."
  cd "$WORKDIR"
  if python3 -c "
import subprocess, sys
try:
    subprocess.run(['python3', 'setup.py', 'build_ext', '--inplace'],
                   check=True, capture_output=True)
    print('编译预检通过')
except subprocess.CalledProcessError as e:
    sys.exit(1)
" 2>/dev/null; then
    echo "==> 预检通过"
  else
    echo "Warning: 编译预检失败，请检查 ${MODULE_NAME}.c 是否包含完整的函数实现"
    echo "你可以手动修复后从 Step 2 继续: $0 $C_FILE $MODULE_NAME --resume step2"
  fi
  cd - > /dev/null

  echo "==> Step 1 完成"
else
  echo "==> 跳过 Step 1（从 Step $RESUME_STEP 开始）"
  if [ ! -f "$WORKDIR/${MODULE_NAME}.c" ] || [ ! -f "$WORKDIR/setup.py" ] || [ ! -f "$WORKDIR/test.py" ]; then
    echo "Error: 缺少 Step 1 生成的文件，无法从 Step $RESUME_STEP 继续"
    exit 1
  fi
fi

# ── Step 2 ──
if [ "$RESUME_STEP" -le 2 ]; then
  echo "==> Step 2: Qwen 14B 安全审查"
  python3 -c "
import sys
template = open('templates/02_review_qwen.md', 'r').read()
ext_code = open('$WORKDIR/${MODULE_NAME}.c', 'r').read()
setup_code = open('$WORKDIR/setup.py', 'r').read()
test_code = open('$WORKDIR/test.py', 'r').read()
prompt = template.replace('{{MODULE_NAME}}', '$MODULE_NAME') \
                 .replace('{{EXTENSION_CODE}}', ext_code) \
                 .replace('{{SETUP_CODE}}', setup_code) \
                 .replace('{{TEST_CODE}}', test_code)
sys.stdout.write(prompt)
" | ollama run qwen2.5:14b > "$WORKDIR/review_qwen_raw.txt"

  split_files "review_qwen_raw.txt"

  # 补全缺失文件
  if [ ! -f "$WORKDIR/${MODULE_NAME}_final.c" ]; then
    cp "$WORKDIR/${MODULE_NAME}.c" "$WORKDIR/${MODULE_NAME}_final.c"
  fi
  if [ ! -f "$WORKDIR/setup_final.py" ]; then
    cp "$WORKDIR/setup.py" "$WORKDIR/setup_final.py"
  fi
  if [ ! -f "$WORKDIR/test_final.py" ]; then
    cp "$WORKDIR/test.py" "$WORKDIR/test_final.py"
  fi
  echo "==> Step 2 完成"
else
  echo "==> 跳过 Step 2（从 Step $RESUME_STEP 开始）"
  if [ ! -f "$WORKDIR/${MODULE_NAME}_final.c" ]; then
    echo "Error: 缺少 ${MODULE_NAME}_final.c，无法继续"
    exit 1
  fi
fi

# ── Step 3 ──
echo "==> Step 3: Claude 架构审查"
if [ "$SKIP_CLAUDE" -eq 1 ]; then
  echo "==> 跳过 Claude 审查（缺少配置）"
else
  if [ ! -f "$WORKDIR/${MODULE_NAME}_final.c" ]; then
    cp "$WORKDIR/${MODULE_NAME}.c" "$WORKDIR/${MODULE_NAME}_final.c"
    cp "$WORKDIR/setup.py" "$WORKDIR/setup_final.py"
    cp "$WORKDIR/test.py" "$WORKDIR/test_final.py"
  fi

  REVIEW_PROMPT=$(python3 -c "
import sys
template = open('templates/03_review_claude.md', 'r').read()
final_c = open('$WORKDIR/${MODULE_NAME}_final.c', 'r').read()
setup_final = open('$WORKDIR/setup_final.py', 'r').read()
test_final = open('$WORKDIR/test_final.py', 'r').read()
prompt = template.replace('{{MODULE_NAME}}', '$MODULE_NAME') \
                 .replace('{{FINAL_CODE}}', final_c) \
                 .replace('{{SETUP_CODE}}', setup_final) \
                 .replace('{{TEST_CODE}}', test_final)
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
        }')" > "$WORKDIR/review_claude_raw.txt"

  split_files "review_claude_raw.txt"

  if [ ! -f "$WORKDIR/${MODULE_NAME}_reviewed.c" ]; then
    cp "$WORKDIR/${MODULE_NAME}_final.c" "$WORKDIR/${MODULE_NAME}_reviewed.c"
  fi
  if [ ! -f "$WORKDIR/setup_reviewed.py" ]; then
    cp "$WORKDIR/setup_final.py" "$WORKDIR/setup_reviewed.py"
  fi
  if [ ! -f "$WORKDIR/test_reviewed.py" ]; then
    cp "$WORKDIR/test_final.py" "$WORKDIR/test_reviewed.py"
  fi
  echo "==> Claude 审查完成"
fi

echo ""
echo "========================================"
echo "  流水线成功完成！"
ls -la "$WORKDIR"
echo "========================================"
echo "最终推荐使用文件："
echo "  - C 扩展:        $WORKDIR/${MODULE_NAME}_reviewed.c"
echo "  - 安装脚本:      $WORKDIR/setup_reviewed.py"
echo "  - 测试:          $WORKDIR/test_reviewed.py"