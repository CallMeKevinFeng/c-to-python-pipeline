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
- 严格按照下面的格式输出，每个文件的代码必须用三个反引号围起来，反引号单独占一行（不能省略）：
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
- **关键约束（必须遵守，否则代码无法编译）**：
  - **【强制】** 如果用户提供的 C 代码中包含需要包装的函数（如 `fib`），你必须将该函数的**完整、未经修改的实现**原样复制到生成的 .c 文件中，放在所有 Python 包装函数之前。绝不允许只写声明或用注释代替，也不能假设该函数已存在。
  - **【强制】** 只能使用 Python 3 的 `PyModule_Create` 和 `PyInit_` 初始化，严禁出现 Python 2 的 `Py_InitModule`。
  - 生成的 setup.py 必须基于 setuptools（`from setuptools import setup`），不用 distutils，不引用外部文件（如 README.txt），long_description 请直接用简单字符串。
  - 所有代码注释和标识符只使用 ASCII 字符（禁止中文、全角符号）。
- 确保 GIL 管理正确，在注释中说明线程安全措施。
- 直接输出，不要添加额外解释。