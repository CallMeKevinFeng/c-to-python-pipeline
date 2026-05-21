// 计算第 n 个斐波那契数，递归版（仅用于演示）
long long fib(int n) {
    if (n <= 1) return n;
    return fib(n-1) + fib(n-2);
}
