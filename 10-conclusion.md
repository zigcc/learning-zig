> 原文总结：<https://www.openmymind.net/learning_zig/conclusion>

# 总结

有些读者可能会认出我是各种『The Little $TECH Book』 的作者（译者注：原作者还写过 [The Little Go Book](https://github.com/karlseguin/the-little-go-book)、[The Little MongoDB Book](https://github.com/karlseguin/the-little-mongodb-book)），并想知道为什么这本书不叫『The Little Zig Book』。事实上，我不确定 Zig 是否适合『小』这个范畴。部分挑战在于，Zig 的复杂性和学习曲线会因个人背景和经验的不同而大相径庭。如果你是一个经验丰富的 C 或 C++ 程序员，那么简明扼要地总结一下这门语言可能就够了，你可能会更需要[Zig 的官方文档](https://ziglang.org/documentation/master/)。

虽然我们在本指南中涉及了很多内容，但仍有大量内容我们尚未触及。我不希望这让你气馁或不知所措。所有语言的学习都是循序渐进的，通过本教程，你有了一个良好基础，也可以把它当作参数资料，可以开始学习 Zig 语言中更高级的功能。坦率地说，我没有涉及的部分我本身就理解有限，因此无法很好的解释。但这并不妨碍我使用 Zig 编写有意义的东西，比如一个流行的 [HTTP 服务器](https://github.com/karlseguin/http.zig)。

我确实想强调一件完全被略过的事情。这可能是你已经知道的事情，即 Zig 与 C 代码配合得特别好。因为 Zig 的生态还很年轻，标准库也很小，所以在某些情况下，使用 C 库可能是最好的选择。例如，Zig 标准库中没有正则表达式模块，使用 C 语言库就是一个合理的选择。我曾为 SQLite 和 DuckDB 编写过 Zig 库，这很简单。如果你基本遵循了本指南中的所有内容，应该不会有任何问题。

希望本资料对你有所帮助，也希望你能在编程过程中获得乐趣。
