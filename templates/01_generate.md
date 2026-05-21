你是一个 Python C 扩展专家。请将以下 C 函数包装成 Python 可调用的模块。

模块名：`{{MODULE_NAME}}`
C 函数代码：
```c
{{C_CODE}}
```

要求：
- 使用 Python C API 创建扩展模块，不要用 ctypes。
- 需要生成以下 3 个文件，**文件名必须使用指定的模块名**：
  1.  C 扩展源文件（必须是 `{{MODULE_NAME}}.c`）
  2.  `setup.py`（内部也要引用正确的模块名）
  3.  `test.py`
- **重要**：生成的代码中绝对不能出现 `{{MODULE_NAME}}` 这样的占位符，必须直接使用指定的模块名。
- 严格按照下面的格式输出，分隔行包含完整文件名：
===FILE:{{MODULE_NAME}}.c===
```c
// C 扩展代码
```

===FILE:setup.py===
```python
# setup 代码
```

===FILE:test.py===
```python
# test 代码
```
- 确保 GIL 管理正确，在注释中说明线程安全措施。
- 直接输出，不要添加额外解释。