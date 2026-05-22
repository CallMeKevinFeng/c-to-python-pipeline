作为 Python C 扩展架构师，请审查以下项目文件的整体设计，并直接输出优化后的最终版本。

模块名：`{{MODULE_NAME}}`

项目文件：
=== 文件：{{MODULE_NAME}}_final.c ===
```c
{{FINAL_CODE}}
```

=== 文件：setup.py ===
```python
{{SETUP_CODE}}
```

=== 文件：test.py ===
```python
{{TEST_CODE}}
```

审查维度：
- C 扩展：PEP 7、性能、跨平台、错误处理
- setup.py：现代打包（pyproject.toml 替代建议）、依赖声明、平台标签
- test.py：覆盖率、CI 友好、pytest 风格
输出要求：
1. 先以文字简要说明优化点（如无则说“代码已符合生产标准”）。
2. 然后输出优化后的所有文件，格式：
===FILE:{{MODULE_NAME}}_reviewed.c===
```c
// 优化后代码
```
===FILE:setup_reviewed.py===
```python
# 优化后代码
```
===FILE:test_reviewed.py===
```python
# 优化后代码
```
注意：文件名必须严格使用上述命名，直接输出，不要添加额外解释。