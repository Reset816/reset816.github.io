---
title: Section GC 分析 - Part 2 gold 源码解析
part: 2
---

# Section GC 分析 - Part 2 gold 源码解析

## 概述

本文为 [解决 Linux 内核 Section GC 失败问题][006] 系列文章的一部分。

- [Section GC 分析 - Part 1 原理简介][001]
- [Section GC 分析 - Part 2 gold 源码解析][002]
- [Section GC 分析 - Part 3 引用建立过程][003]
- [解决 Linux 内核 Section GC 失败问题 - Part 1][004]
- [解决 Linux 内核 Section GC 失败问题 - Part 2][005]

ld.gold 是 GNU binutils 套件的一个组成部分，是 ld.bfd（通常简称为 ld）的一个替代品，设计上更关注性能和链接大型应用的能力。

[上一篇文章][001]我们介绍了 `--gc-sections` 的用法，这篇文章将结合 gold，进一步介绍链接器遍历引用并删除未使用 section 的过程。我们将分析 binutils 的 2.40 版本源代码。

## 准备工作

### 下载代码

```bash
wget https://ftp.gnu.org/gnu/binutils/binutils-2.40.tar.gz
tar xvf binutils-2.40.tar.gz
cd binutils-2.40/
```

### 编译

```bash
./configure --enable-gold # 生成 Makefile 文件
make -j
```

编译生成的 gold 链接器位于 `gold/ld-new`。

### 使用 ld 手动链接目标文件

编写一个用来测试的程序 `test.c`：

```c
int fun()
{
    return 0;
}

int un_used(){
    return 0;
}

int main(){
    fun();
    return 0;
```

```bash
gcc -c -ffunction-sections test.c
```

使用 `-c` 选项可以让 GCC 只进行编译阶段，生成对应的目标文件，而不进行链接阶段。这样我们可以用 GDB 来追踪链接过程。但是手动使用 ld 来链接非常麻烦，需要指定各种库，而且在不同的发行版中，库的位置不一样。

我们可以使用 `-v` 参数让 GCC 导出编译的完整过程。

```bash
$ gcc -v test.c
Using built-in specs.
COLLECT_GCC=gcc
COLLECT_LTO_WRAPPER=/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/lto-wrapper
Target: x86_64-pc-linux-gnu
Configured with: /build/gcc/src/gcc/configure --enable-languages=ada,c,c++,d,fortran,go,lto,objc,obj-c++ --enable-bootstrap --prefix=/usr --libdir=/usr/lib --libexecdir=/usr/lib --mandir=/usr/share/man --infodir=/usr/share/info --with-bugurl=https://bugs.archlinux.org/ --with-build-config=bootstrap-lto --with-linker-hash-style=gnu --with-system-zlib --enable-__cxa_atexit --enable-cet=auto --enable-checking=release --enable-clocale=gnu --enable-default-pie --enable-default-ssp --enable-gnu-indirect-function --enable-gnu-unique-object --enable-libstdcxx-backtrace --enable-link-serialization=1 --enable-linker-build-id --enable-lto --enable-multilib --enable-plugin --enable-shared --enable-threads=posix --disable-libssp --disable-libstdcxx-pch --disable-werror
Thread model: posix
Supported LTO compression algorithms: zlib zstd
gcc version 13.1.1 20230429 (GCC)
COLLECT_GCC_OPTIONS='-v' '-mtune=generic' '-march=x86-64' '-dumpdir' 'a-'
 /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/cc1 -quiet -v test.c -quiet -dumpdir a- -dumpbase test.c -dumpbase-ext .c -mtune=generic -march=x86-64 -version -o /tmp/cc02XNs2.s
GNU C17 (GCC) version 13.1.1 20230429 (x86_64-pc-linux-gnu)
	compiled by GNU C version 13.1.1 20230429, GMP version 6.2.1, MPFR version 4.2.0, MPC version 1.3.1, isl version isl-0.26-GMP

warning: MPFR header version 4.2.0 differs from library version 4.2.0-p9.
GGC heuristics: --param ggc-min-expand=100 --param ggc-min-heapsize=131072
ignoring nonexistent directory "/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../x86_64-pc-linux-gnu/include"
#include "..." search starts here:
#include <...> search starts here:
 /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/include
 /usr/local/include
 /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/include-fixed
 /usr/include
End of search list.
Compiler executable checksum: f7ab8f6abad0db9962575524ae915978
COLLECT_GCC_OPTIONS='-v' '-mtune=generic' '-march=x86-64' '-dumpdir' 'a-'
 as -v --64 -o /tmp/ccJpcjZ4.o /tmp/cc02XNs2.s
GNU assembler version 2.40.0 (x86_64-pc-linux-gnu) using BFD version (GNU Binutils) 2.40.0
COMPILER_PATH=/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/:/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/:/usr/lib/gcc/x86_64-pc-linux-gnu/:/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/:/usr/lib/gcc/x86_64-pc-linux-gnu/
LIBRARY_PATH=/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/:/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/:/lib/../lib/:/usr/lib/../lib/:/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../:/lib/:/usr/lib/
COLLECT_GCC_OPTIONS='-v' '-mtune=generic' '-march=x86-64' '-dumpdir' 'a.'
 /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/collect2 -plugin /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/liblto_plugin.so -plugin-opt=/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/lto-wrapper -plugin-opt=-fresolution=/tmp/cckiS0x9.res -plugin-opt=-pass-through=-lgcc -plugin-opt=-pass-through=-lgcc_s -plugin-opt=-pass-through=-lc -plugin-opt=-pass-through=-lgcc -plugin-opt=-pass-through=-lgcc_s --build-id --eh-frame-hdr --hash-style=gnu -m elf_x86_64 -dynamic-linker /lib64/ld-linux-x86-64.so.2 -pie /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/Scrt1.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crti.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtbeginS.o -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1 -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib -L/lib/../lib -L/usr/lib/../lib -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../.. /tmp/ccJpcjZ4.o -lgcc --push-state --as-needed -lgcc_s --pop-state -lc -lgcc --push-state --as-needed -lgcc_s --pop-state /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtendS.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crtn.o
COLLECT_GCC_OPTIONS='-v' '-mtune=generic' '-march=x86-64' '-dumpdir' 'a.'
```

在 ChatGPT 的帮助下，基于这些输出，我得到了手动链接的命令：

```bash
ld -dynamic-linker /lib64/ld-linux-x86-64.so.2 -pie /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/Scrt1.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crti.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtbeginS.o -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1 -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib -L/lib/../lib -L/usr/lib/../lib -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../.. test.o -lgcc_s -lc -lgcc /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtendS.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crtn.o
```

### 使用命令行进行调试

我们可以在终端中使用以下命令来调试 gold：

```bash
gdb --args gold/ld-new --gc-sections -dynamic-linker /lib64/ld-linux-x86-64.so.2 -pie /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/Scrt1.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crti.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtbeginS.o -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1 -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib -L/lib/../lib -L/usr/lib/../lib -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../.. test.o -lgcc_s -lc -lgcc /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtendS.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crtn.o
```

args 也可以在进入 gdb 以后通过 `set args` 来设定。

```gdb
file gold/ld-new
set args --gc-sections -dynamic-linker /lib64/ld-linux-x86-64.so.2 -pie /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/Scrt1.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crti.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtbeginS.o -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1 -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib -L/lib/../lib -L/usr/lib/../lib -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../.. test.o -lgcc_s -lc -lgcc /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtendS.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crtn.o
```

找到 `if (parameters->options().gc_sections())` 所在行号 509

```gdb
layout split
break gold.cc:509
run
```

![image-20230526174349868.png](/images/20230526-section-gc-part2/image-20230526174349868.png)

可以成功进行调试。

### 使用 VSCode 进行调试

使用终端来调试可能不太方便。可以写一份配置文件，让我们能直接在 VSCode 中进行调试。

创建 `.vscode/launch.json` 文件：

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "GDB GOLD",
            "type": "cppdbg",
            "request": "launch",
            "program": "${workspaceFolder}/gold/ld-new",
            "args": [
              "--gc-sections",
              "-dynamic-linker",
              "/lib64/ld-linux-x86-64.so.2",
              "-pie",
              "/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/Scrt1.o",
              "/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crti.o",
              "/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtbeginS.o",
              "-L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1",
              "-L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib",
              "-L/lib/../lib",
              "-L/usr/lib/../lib",
              "-L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../..",
              "test.o",
              "-lgcc_s",
              "-lc",
              "-lgcc",
              "/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtendS.o",
              "/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crtn.o"
          ],
            "cwd": "${workspaceFolder}",
            "setupCommands": [
              {
                  "description": "Enable pretty-printing for gdb",
                  "text": "-enable-pretty-printing"
              }
            ],
            "stopAtEntry": false
        },
    ]
}
```

使用快捷键 `Ctrl+Shift+D` 打开 `Run and Debug`, 如下图，现在有了 debug 的配置选项，可以使用 GUI 进行调试操作。

![image-20230526175134246.png](/images/20230526-section-gc-part2/image-20230526175134246.png)

## 代码分析

### 概览

```c++
if (parameters->options().gc_sections())
{
  // Find the start symbol if any.
  Symbol* sym = symtab->lookup(parameters->entry()); // 标记入口符号
  if (sym != NULL)
symtab->gc_mark_symbol(sym);
  sym = symtab->lookup(parameters->options().init()); // 标记 init
  if (sym != NULL && sym->is_defined() && !sym->is_from_dynobj())
symtab->gc_mark_symbol(sym);
  sym = symtab->lookup(parameters->options().fini()); // 标记 fini
  if (sym != NULL && sym->is_defined() && !sym->is_from_dynobj())
symtab->gc_mark_symbol(sym);
  // Symbols named with -u should not be considered garbage.
  symtab->gc_mark_undef_symbols(layout);
  gold_assert(symtab->gc() != NULL);
  // Do a transitive closure on all references to determine the worklist.
  symtab->gc()->do_transitive_closure(); // 遍历 references
}
```

这段代码会把一些固定的需要保留的 section，例如函数入口等，加入到工作列表（`work list`）中，然后遍历 `work list`，将每个元素引用到的 section 再次加入 `work list` 中处理，直到 `work list` 为空。

使用 GDB 进行跟踪调试：

![2023-05-17-15-02-35.png](/images/20230526-section-gc-part2/2023-05-17-15-02-35.png)

可以看到，先找到了 `_start` 符号，即程序的入口点，然后调用 `gc_mark_symbol()` 函数标记了这个符号。

### 标记符号为被引用

我们进入 `gc_mark_symbol()` 函数看看它具体是怎么做的。

```C++
void
Symbol_table::gc_mark_symbol(Symbol* sym)
{
  // Add the object and section to the work list.
  bool is_ordinary;
  unsigned int shndx = sym->shndx(&is_ordinary);
  if (is_ordinary && shndx != elfcpp::SHN_UNDEF && !sym->object()->is_dynamic())
    {
      gold_assert(this->gc_!= NULL);
      Relobj* relobj = static_cast<Relobj*>(sym->object());
      this->gc_->worklist().push_back(Section_id(relobj, shndx));
    }
  parameters->target().gc_mark_symbol(this, sym);
}
```

该函数的作用是将一个符号标记为被引用，从而避免被垃圾回收器回收。

该函数首先通过调用 `Symbol` 类的 `shndx()` 获取符号所在的节（section）的索引值 `shndx` 和一个布尔值 `is_ordinary`，`is_ordinary` 表示该节是否为常规节。如果该节是常规节且不是未定义节（索引值为 `elfcpp::SHN_UNDEF`），同时该节所在的对象不是动态链接库，则将该节添加到 `work list` 中，以便在传递闭包算法中处理。

添加到 `work list` 时候是添加了一个 `Section_id` 对象，表示该符号所在的节。
`Section_id` 是一个二元组，由 `shndx` 索引值和该符号所在的对象构成。

最后调用 `target().gc_mark_symbol()`，将一些特殊的节加入 `work list`。这个操作是和架构强相关的，只有 powerpc 才需要进行这个操作。

![2023-05-17-17-14-49.png](/images/20230526-section-gc-part2/2023-05-17-17-14-49.png)

可以看到，`_start` 符号所在的对象 `Scrt1.o` 已经被 push 进 `work list`，`shndx` 为 3。

`work list` 不为空，已经有以下元素，包含了重复项目：

| index | name                                                              |
|-------|-------------------------------------------------------------------|
| 0     | `/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/Scrt1.o` |
| 1     | `/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crti.o`  |
| 2     | `/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crti.o`  |
| 3     | `/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtbeginS.o`             |
| 4     | `/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtbeginS.o`             |
| 5     | `/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crtn.o`  |
| 6     | `/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crtn.o`  |

回到 `gold.cc`，处理完入口函数 `_start` 后，通过 `symtab->lookup(parameters->options().init())` 和 `symtab->lookup(parameters->options().fini())` 获取到 init 和 fini 符号，他们所在的对象是 `crti.o`，也加入到了 `work list` 中。

### 遍历引用

`do_transitive_closure()` 函数会遍历 `work list` 中所有元素，将每个元素引用到的 section 加入 `work list`，直到 `work list` 为空。

```c++
void
Garbage_collection::do_transitive_closure()
{
  while (!this->worklist().empty()) // 调用 worklist_ready() 函数直到工作列表为空
    {
      // Add elements from the work list to the referenced list
      // one by one.
      Section_id entry = this->worklist().back(); // 从工作列表的末尾取出一个元素（entry）
      this->worklist().pop_back(); // 从工作列表中移除该元素
      if (!this->referenced_list().insert(entry).second) // 将该元素插入到引用列表中。如果列表中存在该元素（即 insert().second 为 false），则跳过后续步骤
        continue;
      Garbage_collection::Section_ref::iterator find_it =
                this->section_reloc_map().find(entry); // 在 section_reloc_map 中查找 entry 对应的迭代器（find_it）
      if (find_it == this->section_reloc_map().end()) // 如果没有找到 entry 对应的迭代器，则跳过后续步骤
          continue;
      const Garbage_collection::Sections_reachable &v = find_it->second; // 从 find_it 中获取一个 vector，命名为 v，表示 entry 引用的其他 section
      // Scan the vector of references for each work_list entry.
      for (Garbage_collection::Sections_reachable::const_iterator it_v =
               v.begin();
           it_v != v.end();
           ++it_v) // 遍历 v 中的每个元素（it_v）
        {
          // Do not add already processed sections to the work_list.
          if (this->referenced_list().find(*it_v)
              == this->referenced_list().end())  // 如果该元素已经在被引用列表中，则跳过后续步骤
            {
              this->worklist().push_back(*it_v); // 将该元素添加到工作列表中
            }
        }
    }
  this->worklist_ready();
}
```

函数完成后，`work list` 为空，`referenced list` 存放了所有被引用的节。

`referenced list` 的每一项都是一个 `Section_id`，`Section_id` 这个二元组第一项是 `Relobj*`，表示一个目标文件 regular object (ET_REL)，第二项是 `shndx`。

<p align="center">
<img src="/images/20230526-section-gc-part2/image-20230519131233600.png" alt="image-20230519131233600.png" style="zoom:50%" />
</p>

针对测试程序 `test.c`，可以看到 `referenced_list_[12].first` 和 `referenced_list_[13].first` 指向了同一个 `Relobj*`，即 `test.o`，但他们的 `shndx` 值不同，一个是 4 一个为 6。

使用 `readelf` 查看 `test.o` 的 section 信息，可以发现 `.text.fun` 的 `Ndx` 是 4，`.text.main` 的 `Ndx` 是 6，`.text.un_used` 并不存在于 `referenced list` 中。在这里，`.text.un_used` 被删除。

```bash
$ readelf -s test.o

Symbol table '.symtab' contains 8 entries:
   Num:    Value          Size Type    Bind   Vis      Ndx Name
     0: 0000000000000000     0 NOTYPE  LOCAL  DEFAULT  UND
     1: 0000000000000000     0 FILE    LOCAL  DEFAULT  ABS test.c
     2: 0000000000000000     0 SECTION LOCAL  DEFAULT    4 .text.fun
     3: 0000000000000000     0 SECTION LOCAL  DEFAULT    5 .text.un_used
     4: 0000000000000000     0 SECTION LOCAL  DEFAULT    6 .text.main
     5: 0000000000000000    11 FUNC    GLOBAL DEFAULT    4 fun
     6: 0000000000000000    11 FUNC    GLOBAL DEFAULT    5 un_used
     7: 0000000000000000    21 FUNC    GLOBAL DEFAULT    6 main
```

我们使用 GDB 来追踪 `referenced list` 的建立流程。

设置一个条件断点，当 `work list` 遍历到 test.o 的时候停止。

```gdb
break gc.cc:47 if entry.first == 0x555555ff25c0
```

![image-20230519132511143.png](/images/20230526-section-gc-part2/image-20230519132511143.png)

这时候 `shndx` 为 6，即遍历到了 `.text.main` 所在的 section。接下来，他应该会把 `.text.main` 引用到的函数加入到 `work list` 中。

`section_reloc_map` 的类型是 `std::map<Section_id, Sections_reachable>`，存放了键值对数据。`section_reloc_map().find(entry)` 会返回一个迭代器 `find_it`，这个迭代器中只有一个元素。`find_it->first` 存放了键 `Section_id`，`find_it-second` 存放了值 `Sections_reachable`。后续需要对该 `Section_id` 对应的 `Sections_reachable` 进行操作。

`Sections_reachable` 是 `Unordered_set<Section_id, Section_id_hash>` 类型。`Unordered_set` 是个用于存储唯一的元素集合的无序容器类型，这里使用 `Section_id_hash` 自定义了哈希操作。

<p align="center">
<img src="/images/20230526-section-gc-part2/image-20230519172618681.png" alt="image-20230519172618681.png" style="zoom:50%" />
</p>

该 `Section_id` 对应的 `Sections_reachable` 容器中只有一个元素，这个元素是一个 `Section_id` 指向了 `test.o`，`shndx` 为 4，即 `.text.fun` 所在 section。最后把该 `Section_id` 添加到了 `work list` 中。

从这个过程中我们可以看到，`Section_id` 对应的 `Sections_reachable` 存放了该 `Section_id` 引用到的所有元素。

### 建立引用关系

通过对 `Sections_reachable` 的追踪，可以发现是 `gc_process_relocs()` 函数建立了引用关系。

`gc_process_relocs()` 是一个函数模板，不同的架构有各自的实例化方式。

## 总结

gold 链接器的代码比较清晰，可以很快的明白每个函数的作用。这篇文章分析了 gold 删除未引用到的 section 的实现原理。之后将在此基础上研究引用表的建立过程。

## 参考资料

- Tiny Linux Kernel Project: Section Garbage Collection Patchset

[001]: ../section-gc-part1
[002]: ../section-gc-part2
[003]: ../section-gc-part3
[004]: ../section-gc-no-more-keep-part1
[005]: ../section-gc-no-more-keep-part2
[006]: https://summer-ospp.ac.cn/org/prodetail/2341f0584
