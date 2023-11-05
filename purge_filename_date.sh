#!/bin/bash

# 检查输入参数是否为空
if [ -z "$1" ]; then
    echo "请输入要处理的文件夹路径作为参数"
    exit 1
fi

# 遍历文件夹中的每个文件
for file in "$1"/*; do
    if [ -f "$file" ]; then
        # 获取文件名中第一个"-"之后的部分
        new_name=$(echo "$(basename "$file")" | cut -d'-' -f2-)
        
        # 构建新的文件路径
        new_path="$1/$new_name"
        
        # 重命名文件
        mv "$file" "$new_path"
        echo "已重命名文件: $file 为 $new_path"
    fi
done

echo "处理完成"
