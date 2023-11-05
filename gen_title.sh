#!/bin/bash

# 检查输入参数是否为空
if [ -z "$1" ]; then
    echo "请输入目录路径作为参数"
    exit 1
fi

# 遍历目录中的每个文件
for file in "$1"/*; do
    if [ -f "$file" ]; then
        # 找到第一个包含"#"的行，并将该行的内容作为TITLE
        title=$(grep -m 1 "#" "$file" | sed 's/# *//')
        
        # 在文件头部插入指定内容
        echo "---" > tmpfile
        echo "title: $title" >> tmpfile
        echo "---" >> tmpfile
        
        # 将临时文件的内容和原文件的内容合并，并覆盖原文件
        cat tmpfile "$file" > "$file".new && mv "$file".new "$file"
        
        # 删除临时文件
        rm tmpfile
    fi
done

echo "处理完成"
