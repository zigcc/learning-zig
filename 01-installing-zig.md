> 原文地址：<https://www.openmymind.net/learning_zig/#install>

# 安装 Zig

Zig 官网的[下载页面](https://ziglang.org/download/)中包含常见平台的预编译二进制文件。在这个页面上，你可以找到最新开发版本和主要版本的二进制文件。本指南所跟踪的最新版本可在页面顶部找到。

对于我的电脑，我会下载 `zig-macos-aarch64-0.12.0-dev.161+6a5463951.tar.xz`。你使用的可能是不同的平台或更新的版本。展开压缩包，这里面会有一个名为 `zig` 的二进制文件，你可以按照自己喜欢的方式，为其设置别名（alias）或添加到你的路径（PATH）中。

现在，你可以运行 `zig zen` 和 `zig version` 来测试是否安装正确。

> 译者注：建议读者使用版本管理工具来安装 Zig，社区内目前主要有以下几个：

- [asdf-community/asdf-zig](https://github.com/asdf-community/asdf-zig)
- [marler8997/zigup](https://github.com/marler8997/zigup)
- [tristanisham/zvm](https://github.com/tristanisham/zvm)
- [hendriknielaender/zvm](https://github.com/hendriknielaender/zvm)
