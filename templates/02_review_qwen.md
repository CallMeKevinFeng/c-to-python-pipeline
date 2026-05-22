你是一个资深 C/Python 安全审查专家。请对以下 Python C 扩展项目的所有代码进行严格安全检查，并直接输出修复后的最终版本。

模块名：`{{MODULE_NAME}}`

项目文件：
=== 文件：{{MODULE_NAME}}.c ===
```c
{{EXTENSION_CODE}}
```

=== 文件：setup.py ===
```python
{{SETUP_CODE}}
```

=== 文件：test.py ===
```python
{{TEST_CODE}}
```

审查要求：
- 对 C 扩展：检查引用计数、内存泄漏、缓冲区溢出、GIL 安全、错误处理等。
- 对 setup.py：检查编译选项、平台兼容性、python_requires 等。
- 对 test.py：检查测试覆盖率、边界条件、异常处理。
- 输出修复后的**所有三个文件**，每个文件用以下格式（文件名加 `_final` 后缀）：
===FILE:{{MODULE_NAME}}_final.c===
```c
// 修复后的代码
```
===FILE:setup_final.py===
```python
# 修复后的代码
```
===FILE:test_final.py===
```python
# 修复后的代码
```
如果有严重问题，在代码注释中说明修改原因。如果某文件完全没问题，输出原始的完整代码，但仍使用 `_final` 文件名。