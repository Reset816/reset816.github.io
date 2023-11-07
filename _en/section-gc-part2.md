---
title: Section GC Analysis - Part 2 Gold Source Code Explanation
part: 2
---

*This article has been translated from Chinese by ChatGPT, and the wording may not be entirely accurate.*

# Section GC Analysis - Part 2 gold Source Code Explanation

## Overview

This article is part of the [Addressing Linux Kernel Section GC Failure Issues][006] series.

- [Section GC Analysis - Part 1 Introduction to the Principle][001]
- [Section GC Analysis - Part 2 Gold Source Code Analysis][002]
- [Section GC Analysis - Part 3 Reference Construction Process][003]
- [Addressing Linux Kernel Section GC Failure Issues - Part 1][004]
- [Addressing Linux Kernel Section GC Failure Issues - Part 2][005]

ld.gold is part of GNU binutils suite, it is an alternative to ld.bfd (often simply referred to as ld), designed with a focus on performance and linking capability for large applications.

In [the previous article][001], we introduced the usage of `--gc-sections`. In this article, we are going to delve deeper into how the linker traverses references and removes unused sections in combination with gold. We'll be analyzing the source code of binutils version 2.40.

## Preparatory Work

### Download the code

```bash
wget https://ftp.gnu.org/gnu/binutils/binutils-2.40.tar.gz
tar xvf binutils-2.40.tar.gz
cd binutils-2.40/
```

### Compilation

```bash
./configure --enable-gold # Generate Makefile
make -j
```

The compiled gold linker is located in `gold/ld-new`.

### Manually linking object files with ld

Write a test program `test.c`:

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

Using the `-c` option allows GCC to perform only the compilation phase, generating the corresponding object file without linking. This allows us to track the linking process with GDB. However, manually linking with ld is very troublesome as it requires specifying various libraries, and the location of those libraries varies across different distributions.

We can use the `-v` parameter to have GCC export the complete compilation process.

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

With the help of ChatGPT, using these outputs, I obtained the manual linking command:

```bash
ld -dynamic-linker /lib64/ld-linux-x86-64.so.2 -pie /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/Scrt1.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crti.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtbeginS.o -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1 -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib -L/lib/../lib -L/usr/lib/../lib -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../.. test.o -lgcc_s -lc -lgcc /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtendS.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crtn.o
```

### Debugging using the command line

We can debug gold in the terminal with the following command:

```bash
gdb --args gold/ld-new --gc-sections -dynamic-linker /lib64/ld-linux-x86-64.so.2 -pie /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/Scrt1.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crti.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtbeginS.o -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1 -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib -L/lib/../lib -L/usr/lib/../lib -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../.. test.o -lgcc_s -lc -lgcc /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtendS.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crtn.o
```

args can also be set after entering gdb with `set args`.

```gdb
file gold/ld-new
set args --gc-sections -dynamic-linker /lib64/ld-linux-x86-64.so.2 -pie /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/Scrt1.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crti.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtbeginS.o -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1 -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib -L/lib/../lib -L/usr/lib/../lib -L/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../.. test.o -lgcc_s -lc -lgcc /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtendS.o /usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crtn.o
```

Find the line number 509 where `if (parameters->options().gc_sections())` is located

```gdb
layout split
break gold.cc:509
run
```

![image-20230526174349868.png](/images/20230526-section-gc-part2/image-20230526174349868.png)

The debugging process can now be successfully initiated.

### Debugging using VSCode

Debugging using a terminal might not be convenient. A configuration file can be written to allow us to debug directly in VSCode.

Create `.vscode/launch.json` file:

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

Use the shortcut `Ctrl+Shift+D` to open `Run and Debug`, and you'll see a configuration option for debugging, which will allow you to use GUI for debugging operations.

![image-20230526175134246.png](/images/20230526-section-gc-part2/image-20230526175134246.png)

## Code Analysis

### Overview

```c++
if (parameters->options().gc_sections())
{
  // Find the start symbol if any.
  Symbol* sym = symtab->lookup(parameters->entry()); // Mark the entry symbol
  if (sym != NULL)
    symtab->gc_mark_symbol(sym);
  sym = symtab->lookup(parameters->options().init()); // Mark init
  if (sym != NULL && sym->is_defined() && !sym->is_from_dynobj())
    symtab->gc_mark_symbol(sym);
  sym = symtab->lookup(parameters->options().fini()); // Mark fini
  if (sym != NULL && sym->is_defined() && !sym->is_from_dynobj())
    symtab->gc_mark_symbol(sym);
  // Symbols named with -u should not be considered garbage.
  symtab->gc_mark_undef_symbols(layout);
  gold_assert(symtab->gc() != NULL);
  // Do a transitive closure on all references to determine the worklist.
  symtab->gc()->do_transitive_closure(); // Traverse references
}
```

This segment of code adds certain sections that must be preserved, such as function entry points, to the worklist (`work list`), then iterates over the `work list` adding sections referenced by each item back into the `work list` for processing, until the `work list` is empty.

Using GDB for trace debugging:

![2023-05-17-15-02-35.png](/images/20230526-section-gc-part2/2023-05-17-15-02-35.png)

As you can see, the `_start` symbol, which is the entry point of the program, is located first, then the `gc_mark_symbol()` function marks this symbol.

### Marking Symbols as Referenced

Let's dive into the `gc_mark_symbol()` function to see what it does exactly.

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

The function is used to mark a symbol as referenced, preventing it from being collected by the garbage collector.

The function starts by calling the `shndx()` method of the `Symbol` class to obtain the section index `shndx` and a boolean value `is_ordinary`, which indicates whether the section is an ordinary one. If the section is ordinary, not an undefined section (index value `elfcpp::SHN_UNDEF`), and not part of a dynamic object, it is added to the `work list` to be processed during transitive closure.

When adding to the `work list`, a `Section_id` object is added, which represents the section where the symbol is located.
`Section_id` is a tuple consisting of the `shndx` index value and the object where the symbol resides.

Finally, the method `target().gc_mark_symbol()` is called to add some special sections to the `work list`. This operation is highly architecture-dependent, required only for powerpc architecture.

![2023-05-17-17-14-49.png](/images/20230526-section-gc-part2/2023-05-17-17-14-49.png)

As you can see, the object `Scrt1.o` containing the `_start` symbol has been pushed into the `work list`, with `shndx` being 3.

The `work list` is not empty, already containing the following elements, including duplicate items:

| index | name                                                              |
|-------|-------------------------------------------------------------------|
| 0     | `/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/Scrt1.o` |
| 1     | `/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crti.o`  |
| 2     | `/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crti.o`  |
| 3     | `/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtbeginS.o`             |
| 4     | `/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/crtbeginS.o`             |
| 5     | `/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crtn.o`  |
| 6     | `/usr/lib/gcc/x86_64-pc-linux-gnu/13.1.1/../../../../lib/crtn.o`  |

Back in `gold.cc`, after processing the entry function `_start`, the symbols for init and fini are obtained through `symtab->lookup(parameters->options().init())` and `symtab->lookup(parameters->options().fini())`, their objects are `crti.o`, which are also added to the `work list`.

### Traversing References

The `do_transitive_closure()` function iterates over all elements in the `work list`, adding sections referenced by each item into the `work list` until the `work list` is empty.

```c++
void
Garbage_collection::do_transitive_closure()
{
  while (!this->worklist().empty()) // Call worklist_ready() until the work list is empty
    {
      // Add elements from the work list to the referenced list
      // one by one.
      Section_id entry = this->worklist().back(); // Retrieve an element (entry) from the end of the work list
      this->worklist().pop_back(); // Remove the element from the work list
      if (!this->referenced_list().insert(entry).second) // Insert the element into the referenced list. If the list already contains the element (i.e., insert().second is false), skip the subsequent steps
        continue;
      Garbage_collection::Section_ref::iterator find_it =
                this->section_reloc_map().find(entry); // Find the iterator corresponding to the entry in the section_reloc_map (find_it)
      if (find_it == this->section_reloc_map().end()) // If there is no iterator found for the entry, skip the subsequent steps
        continue;
      const Garbage_collection::Sections_reachable &v = find_it->second; // Retrieve a vector named v from find_it, representing other sections referenced by entry
      // Scan the vector of references for each work_list entry.
      for (Garbage_collection::Sections_reachable::const_iterator it_v =
               v.begin();
           it_v != v.end();
           ++it_v) // Iterate through each element (it_v) in v
        {
          // Do not add already processed sections to the work_list.
          if (this->referenced_list().find(*it_v)
              == this->referenced_list().end())  // If the element is already in the referenced list, skip the subsequent steps
            {
              this->worklist().push_back(*it_v); // Add the element to the work list
            }
        }
    }
  this->worklist_ready();
}
```

After the function completes, the `work list` is empty, and the `referenced list` contains all referenced sections.

Each item in the `referenced list` is a `Section_id`, where the first element of the `Section_id` tuple is `Relobj*`, representing a regular object file (ET_REL), and the second element is `shndx`.

<p align="center">
<img src="/images/20230526-section-gc-part2/image-20230519131233600.png" alt="image-20230519131233600.png" style="zoom:50%" />
</p>

For the test program `test.c`, it can be seen that `referenced_list_[12].first` and `referenced_list_[13].first` point to the same `Relobj*`, which is `test.o`, but their `shndx` values are different, one is 4 and the other is 6.

By using `readelf` to view the section information for `test.o`, it is found that `.text.fun` has an `Ndx` of 4, `.text.main` has an `Ndx` of 6, and `.text.un_used` is not in the `referenced list`. Here, `.text.un_used` has been removed.

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

We use GDB to track the formation process of the `referenced list`.

Set a conditional breakpoint to stop when the `work list` reaches `test.o`.

```gdb
break gc.cc:47 if entry.first == 0x555555ff25c0
```

![image-20230519132511143.png](/images/20230526-section-gc-part2/image-20230519132511143.png)

At this point, `shndx` is 6, which is the section where `.text.main` is located. Next, it should add the function referenced by `.text.main` to the `work list`.

`section_reloc_map` is of type `std::map<Section_id, Sections_reachable>` and stores key-value pairs. `section_reloc_map().find(entry)` returns an iterator `find_it`, which contains only one element. `find_it->first` contains the key `Section_id`, and `find_it->second` contains the value `Sections_reachable`. The `Sections_reachable` corresponding to the `Section_id` needs to be processed subsequently.

`Sections_reachable` is of type `Unordered_set<Section_id, Section_id_hash>`. `Unordered_set` is a container type to store unique elements in an unordered set, and here `Section_id_hash` is used to define a custom hash operation.

<p align="center">
<img src="/images/20230526-section-gc-part2/image-20230519172618681.png" alt="image-20230519172618681.png" style="zoom:50%" />
</p>

The `Sections_reachable` corresponding to that `Section_id` contains only one element, which is another `Section_id` pointing to `test.o`, with `shndx` as 4, i.e., the section where `.text.fun` is located. Finally, this `Section_id` is added to the `work list`.

From this process, it is apparent that the `Sections_reachable` corresponding to a `Section_id` contains all elements referenced by that `Section_id`.

### Establishing References

By tracking `Sections_reachable`, it is found that `gc_process_relocs()` function established the reference relationship.

`gc_process_relocs()` is a function template, instantiated differently for different architectures.

## Summary

The gold linker's code is relatively clear, making it easy to understand the purpose of every function. This article analyzed the principles behind how the gold linker eliminates unreferenced sections. Subsequent studies will be based on this to research the process of establishing reference tables.

## References

- Tiny Linux Kernel Project: Section Garbage Collection Patchset

[001]: ../section-gc-part1
[002]: ../section-gc-part2
[003]: ../section-gc-part3
[004]: ../section-gc-no-more-keep-part1
[005]: ../section-gc-no-more-keep-part2
[006]: https://summer-ospp.ac.cn/org/prodetail/2341f0584
