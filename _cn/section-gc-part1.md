---
title: Section GC 分析 - Part 1 原理简介
part: 1
toc: true
---

# Section GC 分析 - Part 1 原理简介

## 概述

本文为 [解决 Linux 内核 Section GC 失败问题][006] 系列文章的一部分。

- [Section GC 分析 - Part 1 原理简介][001]
- [Section GC 分析 - Part 2 gold 源码解析][002]
- [Section GC 分析 - Part 3 引用建立过程][003]
- [解决 Linux 内核 Section GC 失败问题 - Part 1][004]
- [解决 Linux 内核 Section GC 失败问题 - Part 2][005]

这篇文章将简单介绍 `--gc-sections`。

GCC 的 `--gc-sections` 选项可以在链接时对未使用到的函数和变量进行裁剪。

在编译和链接过程中，编译器和链接器会生成符号表。开启 `--gc-sections` 选项后，链接器会分析符号表，确定哪些代码和数据是未被使用的，然后将其从最终输出中移除。这种裁剪操作有以下好处：

- 减小可执行文件的大小
- 优化加载时间
- 对指令和数据缓存更友好
- 减小攻击面

对 section 执行 GC 操作的前提，链接前每个函数和数据都有自己的 section。但默认情况下，GCC 把函数统一放在了 `.text` section 中。我们可以使用 `-ffunction-sections` 参数来让每个函数都有自己的 section。

## -ffunction-sections 介绍

默认情况下，编译器按照以下规则将数据放入各个段中：

| 段        | 数据类型           | 说明                                                          |
|-----------|----------------|-------------------------------------------------------------|
| `.text`   | 可执行代码         | 存放程序的机器指令                                            |
| `.rodata` | 只读数据           | 存放不可修改的常量数据，例如字符串常量、全局常量等              |
| `.data`   | 初始化的可读写数据 | 存放已初始化的全局变量和静态变量，可以在程序运行时进行读写操作 |
| `.bss`    | 未初始化数据       | 存放未初始化的全局和静态变量                                  |

像这样所有代码都放在了代码段中，链接器不知道哪些函数和变量被使用了，无法进行裁剪。要想进行垃圾回收，需要让每个函数都有自己的节。

GCC 的 `-ffunction-sections` 和 `-fdata-sections` 选项会让每个函数或者变量拥有自己的节。我们在这里只详细介绍 `-ffunction-sections`，`-fdata-sections` 同理。

以下是示例代码，包括了使用到的函数 `fun()` 和未使用到的函数 `unused()`

```C
void fun(){
    return;
}

void unused(){
    return;
}

int main(){
    fun();
}
```

启用 `-ffunction-sections` 选项，编译该文件，但不进行链接。

```
gcc -c test.c
```

查看目标文件符号表。

```bash
$ readelf -s test.o

Symbol table '.symtab' contains 8 entries:
   Num:    Value          Size Type    Bind   Vis      Ndx Name
     0: 0000000000000000     0 NOTYPE  LOCAL  DEFAULT  UND
     1: 0000000000000000     0 FILE    LOCAL  DEFAULT  ABS test.c
     2: 0000000000000000     0 SECTION LOCAL  DEFAULT    1 .text
     5: 0000000000000000    11 FUNC    GLOBAL DEFAULT    1 fun
     6: 0000000000000000    11 FUNC    GLOBAL DEFAULT    1 unused
     7: 0000000000000000    25 FUNC    GLOBAL DEFAULT    1 main
```

可以看到 `fun()` 和 `unused()` 函数没有单独的 section。

启用 `-ffunction-sections` 选项，编译该文件，但不进行链接。

```
gcc -c --function-sections test.c
```

查看目标文件符号表。

```bash
$ readelf -s test.o

Symbol table '.symtab' contains 8 entries:
   Num:    Value          Size Type    Bind   Vis      Ndx Name
     0: 0000000000000000     0 NOTYPE  LOCAL  DEFAULT  UND
     1: 0000000000000000     0 FILE    LOCAL  DEFAULT  ABS test.c
     2: 0000000000000000     0 SECTION LOCAL  DEFAULT    4 .text.fun
     3: 0000000000000000     0 SECTION LOCAL  DEFAULT    5 .text.unused
     4: 0000000000000000     0 SECTION LOCAL  DEFAULT    6 .text.main
     5: 0000000000000000    11 FUNC    GLOBAL DEFAULT    4 fun
     6: 0000000000000000    11 FUNC    GLOBAL DEFAULT    5 unused
     7: 0000000000000000    25 FUNC    GLOBAL DEFAULT    6 main
```

可以看到 `fun()` 和 `unused())` 函数都有了各自的 section。

## --gc-sections 实践

不启用 `--gc-sections` 选项编译实例程序，并查看目标文件大小：

```bash
$ gcc test.c
$ size a.out
   text    data     bss     dec     hex filename
   1340     544       8    1892     764 a.out
```

`--print-gc-sections` 选项可以打印出被裁剪的 sections。这些参数需要通过 `-Wl` 传递给链接器。

启用 `--gc-sections` 选项编译实例程序，打印被裁剪的 sections，并查看目标文件大小：

```bash
$ gcc --function-sections -Wl,--gc-sections,--print-gc-sections test.c
/usr/bin/ld: removing unused section '.rodata.cst4' in file '/usr/lib/gcc/x86_64-linux-gnu/11/../../../x86_64-linux-gnu/Scrt1.o'
/usr/bin/ld: removing unused section '.data' in file '/usr/lib/gcc/x86_64-linux-gnu/11/../../../x86_64-linux-gnu/Scrt1.o'
/usr/bin/ld: removing unused section '.text.unused' in file '/tmp/cc9O4Y8L.o'
$ size a.out
   text    data     bss     dec     hex filename
   1285     536       8    1829     725 a.out
```

可以看到，代码段缩小了。

读取符号表：

```bash
$ readelf -s a.out | grep FUNC
     1: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND _[...]@GLIBC_2.34 (2)
     5: 0000000000000000     0 FUNC    WEAK   DEFAULT  UND [...]@GLIBC_2.2.5 (3)
     4: 0000000000001070     0 FUNC    LOCAL  DEFAULT   14 deregister_tm_clones
     5: 00000000000010a0     0 FUNC    LOCAL  DEFAULT   14 register_tm_clones
     6: 00000000000010e0     0 FUNC    LOCAL  DEFAULT   14 __do_global_dtors_aux
     9: 0000000000001120     0 FUNC    LOCAL  DEFAULT   14 frame_dummy
    18: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND __libc_start_mai[...]
    21: 0000000000001150     0 FUNC    GLOBAL HIDDEN    15 _fini
    22: 0000000000001129    11 FUNC    GLOBAL DEFAULT   14 fun
    26: 0000000000001040    38 FUNC    GLOBAL DEFAULT   14 _start
    28: 0000000000001134    25 FUNC    GLOBAL DEFAULT   14 main
    31: 0000000000000000     0 FUNC    WEAK   DEFAULT  UND __cxa_finalize@G[...]
    32: 0000000000001000     0 FUNC    GLOBAL HIDDEN    11 _init
```

可见 `unused()` 也不存在于符号表中，被使用到的 `fun()` 函数存在于符号表中。

## 总结

Section GC 是一种二进制文件的编译和链接时裁剪方式，它在编译阶段通过 `-ffunction-sections` 和 `-fdata-sections` 为每个函数和变量创建独立的 Section，然后在链接阶段通过 `--gc-sections` 遍历所有的 Section，把使用到的函数和变量链接进目标二进制文件，并剔除其他未被使用到的部分，从而达成减少程序大小的目标。

## 参考资料

- Tiny Linux Kernel Project: Section Garbage Collection Patchset

[001]: ../section-gc-part1
[002]: ../section-gc-part2
[003]: ../section-gc-part3
[004]: ../section-gc-no-more-keep-part1
[005]: ../section-gc-no-more-keep-part2
[006]: https://summer-ospp.ac.cn/org/prodetail/2341f0584
