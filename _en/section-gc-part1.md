---
title: Section GC Analysis - Part 1 An Introduction to the Principles
part: 1
---

*This article has been translated from Chinese by ChatGPT, and the wording may not be entirely accurate.*

# Section GC Analysis - Part 1: An Introduction to the Principles

## Overview

This article is part of the [Addressing Linux Kernel Section GC Failure Issues][006] series.

- [Section GC Analysis - Part 1 Introduction to the Principle][001]
- [Section GC Analysis - Part 2 Gold Source Code Analysis][002]
- [Section GC Analysis - Part 3 Reference Construction Process][003]
- [Addressing Linux Kernel Section GC Failure Issues - Part 1][004]
- [Addressing Linux Kernel Section GC Failure Issues - Part 2][005]

This article will provide a brief introduction to the `--gc-sections` feature.

The `--gc-sections` option in GCC can trim unused functions and variables during linking.

During compilation and linking, the compiler and linker create a symbol table. When the `--gc-sections` option is enabled, the linker will analyze the symbol table to determine which code and data are not used, and then remove them from the final output. This pruning has several benefits:

- Reduces the size of the executable file
- Optimizes loading time
- More cache-friendly for instructions and data
- Reduces attack surface

The prerequisite for performing GC on sections is that every function and data segment should have its own section before linking. However, by default, GCC places all functions in the `.text` section. We can use the `-ffunction-sections` parameter to give each function its own section.

## Introduction to -ffunction-sections

By default, compilers place data into different sections according to the following rules:

| Section   | Data Type         | Description                                                  |
|-----------|-------------------|--------------------------------------------------------------|
| `.text`   | Executable code   | Contains the program's machine instructions                  |
| `.rodata` | Read-only data    | Contains immutable constant data, such as string literals and global constants |
| `.data`   | Initialized read-write data | Contains initialized global and static variables that can be read and written during program execution |
| `.bss`    | Uninitialized data | Contains uninitialized global and static variables           |

With all the code placed in the code section, the linker does not know which functions and variables are used and cannot perform trimming. To enable garbage collection, each function needs to have its own section.

The `-ffunction-sections` and `-fdata-sections` options in GCC make each function or variable have its own section. Here we will only discuss `-ffunction-sections` in detail; `-fdata-sections` works similarly.

Here is an example code that includes a used function `fun()` and an unused function `unused()`:

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

Enable the `-ffunction-sections` option, compile the file without linking.

```
gcc -c test.c
```

Examine the symbol table of the object file.

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

We can see the functions `fun()` and `unused()` do not have individual sections.

Enable the `-ffunction-sections` option again and compile, but do not link.

```
gcc -c -ffunction-sections test.c
```

Examine the symbol table of the object file.

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

Now we can observe that both `fun()` and `unused()` functions have their own sections.

## --gc-sections in Practice

Compile the example program without enabling the `--gc-sections` option and check the object file size:

```bash
$ gcc test.c
$ size a.out
   text    data     bss     dec     hex filename
   1340     544       8    1892     764 a.out
```

The `--print-gc-sections` option can print the sections that are trimmed. These arguments have to be passed to the linker with `-Wl`.

Compile the example program with the `--gc-sections` option enabled, print the trimmed sections, and check the object file size:

```bash
$ gcc -ffunction-sections -Wl,--gc-sections,--print-gc-sections test.c
/usr/bin/ld: removing unused section '.rodata.cst4' in file '/usr/lib/gcc/x86_64-linux-gnu/11/../../../x86_64-linux-gnu/Scrt1.o'
/usr/bin/ld: removing unused section '.data' in file '/usr/lib/gcc/x86_64-linux-gnu/11/../../../x86_64-linux-gnu/Scrt1.o'
/usr/bin/ld: removing unused section '.text.unused' in file '/tmp/cc9O4Y8L.o'
$ size a.out
   text    data     bss     dec     hex filename
   1285     536       8    1829     725 a.out
```

As we can see, the code section is reduced.

Read the symbol table:

```bash
$ readelf -s a.out | grep FUNC
     1: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND _[...]@GLIBC_2.34 (2)
     5: 0000000000000000     0 FUNC    WEAK   DEFAULT  UND [...]@GLIBC_2.2.5 (3)
     4: 0000000000001070     0 FUNC    LOCAL  DEFAULT   14 deregister_tm_clones
     5: 00000000000010a0     0 FUNC    LOCAL  DEFAULT   14 register_tm_clones
     6: 00000000000010e0     0 FUNC    LOCAL  DEFAULT   14 __do_global_dtors_aux
     9: 0000000000001120     0 FUNC    LOCAL  DEFAULT   14 frame_dummy
    18: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND __libc_start_main[...]
    21: 0000000000001150     0 FUNC    GLOBAL HIDDEN    15 _fini
    22: 0000000000001129    11 FUNC    GLOBAL DEFAULT   14 fun
    26: 0000000000001040    38 FUNC    GLOBAL DEFAULT   14 _start
    28: 0000000000001134    25 FUNC    GLOBAL DEFAULT   14 main
    31: 0000000000000000     0 FUNC    WEAK   DEFAULT  UND __cxa_finalize@GL[...]
    32: 0000000000001000     0 FUNC    GLOBAL HIDDEN    11 _init
```

It is evident that `unused()` is no longer in the symbol table, while the used function `fun()` remains.

## Conclusion

Section GC is a method of trimming during the compilation and linking of binary files. It works by creating independent Sections for each function and variable during the compilation phase through the `-ffunction-sections` and `-fdata-sections` options. During linking, the `--gc-sections` option then traverses all Sections, linking those functions and variables that are used into the target binary file, and removing the unused portions, thereby achieving the goal of reducing the program size.

## References

- Tiny Linux Kernel Project: Section Garbage Collection Patchset

[001]: ../section-gc-part1
[002]: ../section-gc-part2
[003]: ../section-gc-part3
[004]: ../section-gc-no-more-keep-part1
[005]: ../section-gc-no-more-keep-part2
[006]: https://summer-ospp.ac.cn/org/prodetail/2341f0584
