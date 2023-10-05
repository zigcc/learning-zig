> 原文地址：https://www.openmymind.net/learning_zig/language_overview_2/

# 语言概览 - 第 2 部分

本部分继续上一部分遗留的内容：使我们熟悉这门语言。我们将探讨Zig的控制流和类型。和第一部分一样，我们将涵盖语言的大部分语法，从而使我们更深入地了解语言和标准库。

Zig 的控制流可能很熟悉，我们将探讨语言方面新增的功能。快速预览控制流，再回来讨论控制流的特殊行为。

您会注意到，使用`and`和`or`代替逻辑运算符`&&`和`||`。与大多数语言一样，`and`和`or`控制执行流程：它们会短路。如果左侧为`false`，则不会计算`and`的右侧，如果左侧为`true`，则不会计算`or`的右侧。在Zig中，控制流使用关键字`and`和`or`。

此外，比较运算符`==`不能用来比较切片，例如`[]const u8`，即字符串。在大多数情况下，使用`std.mem.eql(u8, str1, str2)`，先比较切片长度，再比较切片内容。

Zig 的`if`，`else if`和`else`很常见：

```zig
    // std.mem.eql does a byte-by-byte comparison
    // for a string it'll be case sensitive
    if (std.mem.eql(u8, method, "GET") or std.mem.eql(u8, method, "HEAD")) {
    	// handle a GET request
    } else if (std.mem.eql(u8, method, "POST")) {
    	// handle a POST request
    } else {
    	// ...
    }
```

上面的例子比较ASCII字符串，不需要区分大小写。使用`std.ascii.eqlIgnoreCase(str1, str2)`更合适。

虽然没有三元运算符，但可以这样使用`if/else`：

```zig
    const super = if (power > 9000) true else false;
```

`switch`类似于if/else if/else，但有更显著的优点。如果没有覆盖所有情况，编译时会报错。下面的代码无法通过编译：

```zig
    fn anniversaryName(years_married: u16) []const u8 {
        switch (years_married) {
            1 => return "paper",
            2 => return "cotton",
            3 => return "leather",
            4 => return "flower",
            5 => return "wood",
            6 => return "sugar",
        }
    }
```

我们被告知：“switch必须处理所有可能的情况”。由于我们的`years_married`是16位整数，这是否意味着我们需要处理所有64K种情况？是的，但幸运的是有一个`else`：

```zig
    // ...
    6 => return "sugar",
    else => return "no more gifts for you",
```

我们可以组合多个情况或使用范围，并对复杂情况使用块：

```zig
    fn arrivalTimeDesc(minutes: u16, is_late: bool) []const u8 {
        switch (minutes) {
            0 => return "arrived",
            1, 2 => return "soon",
            3...5 => return "no more than 5 minutes",
            else => {
                if (!is_late) {
                    return "sorry, it'll be a while";
                }
                // todo, something is very wrong
                return "never";
            },
        }
    }
```

多数情况下`switch`很有用，尤其是处理枚举时，它的详尽性才真正发挥作用，我们将很快讨论它。

Zig的`for`循环用于迭代数组、切片和范围。例如，要检查数组是否包含一个值，可以这样写：

```zig
    fn contains(haystack: []const u32, needle: u32) bool {
        for (haystack) |value| {
            if (needle == value) {
                return true;
            }
        }
        return false;
    }
```

`for`循环可以同时处理多个序列，只要这些序列长度相同。上面我们使用`std.mem.eql`函数。这是它（几乎）的样子：

```zig
    pub fn eql(comptime T: type, a: []const T, b: []const T) bool {
        // if they arent' the same length, the can't be equal
        if (a.len != b.len) return false;

        for (a, b) |a_elem, b_elem| {
            if (a_elem != b_elem) return false;
        }

        return true;
    }
```

最开始的`if`检查不仅仅是一种良好的性能优化，也是一种必要的保护。如果我们删除它并传递不同长度的参数，将会运行时崩溃：“循环对象不等长”。

`for`循环也可以迭代范围，例如：

```zig
    for (0..10) |i| {
        std.debug.print("{d}\n", .{i});
    }
```

一个或多个序列结合使用时非常棒：

```zig
    fn indexOf(haystack: []const u32, needle: u32) ?usize {
        for (haystack, 0..) |value, i| {
            if (needle == value) {
                return i;
            }
        }
        return null;
    }
```

范围的末尾由haystack的长度推断出来，尽管我们可以自己编写：`0..hastack.len`。`for`循环不支持更通用的`init; compare; step`惯用法，我们需要使用`while`。

`while`更简单，采用`while (condition) { }`的形式，我们对迭代有更大的控制。例如，在计算字符串中的转义序列数量时，我们需要将迭代器增加2，以避免重复计算`\\`：

```zig
    var i: usize = 0;
    var escape_count: usize = 0;
    while (i < src.len) {
        if (src[i] == '\\') {
            i += 2;
            escape_count += 1;
        } else {
            i += 1;
        }
    }
```

`while`可以有一个`else`子句，当条件为false时执行。它还接受在每次迭代后执行的语句。在`for`支持多个序列之前，这个特性常常被使用。上面的代码可以写成：

```zig
    var i: usize = 0;
    var escape_count: usize = 0;

    //                  this part
    while (i < src.len) : (i += 1) {
        if (src[i] == '\\') {
            // +1 here, and +1 above == +2
            i += 1;
            escape_count += 1;
        }
    }
```

`break`和`continue`支持跳出最内层循环或跳到下一次迭代。

块可以被标记，`break`和`continue`可以指定一个特定的标记。一个刻意制造的示例：

```zig
    outer: for (1..10) |i| {
        for (i..10) |j| {
            if (i * j > (i+i + j+j)) continue :outer;
            std.debug.print("{d} + {d} >= {d} * {d}\n", .{i+i, j+j, i, j});
        }
    }
```

`break`还有另一个有趣的行为，可以从块中返回一个值：

```zig
    const personality_analysis = blk: {
        if (tea_vote > coffee_vote) break :blk "sane";
        if (tea_vote == coffee_vote) break :blk "whatever";
        if (tea_vote < coffee_vote) break :blk "dangerous";
    };
```

这样的块必须以分号终止。

稍后，当探讨带标签的联合、错误联合和可选类型时，将看到这些控制流还提供了什么。

枚举（Enums）是具有标签的整数常量。它们的定义方式与结构相似：

```zig
    // could be "pub"
    const Status = enum {
        ok,
        bad,
        unknown,
    };
```

和结构（struct）一样，可以包含函数定义：

```zig
    const Stage = enum {
        validate,
        awaiting_confirmation,
        confirmed,
        completed,
        err,

        fn isComplete(self: Stage) bool {
            return self == .confirmed or self == .err;
        }
    };
```

请注意，结构类型可以根据其分配或返回类型使用`.{...}`表示。在上面的示例中，我们看到枚举类型是根据其与self的比较而被推断出来的，而self的类型是`Stage`。我们可以显式写成：`return self == Stage.confirmed or self == Stage.err;`。但是，在处理枚举时，通常会看到省略了枚举类型，使用`.$value`表示法。

`switch`的详尽性使其与枚举非常配合，确保处理了所有可能的情况。但是，使用`switch`的`else`子句时要小心，它将匹配任何新增的枚举值，这可能不是您想要的行为。

联合（union）定义了一个值可以拥有一组类型。例如，`Number`联合可以是一个`整数`、一个`浮点数`或一个`nan`（不是一个数字）：

```zig
    const std = @import("std");

    pub fn main() void {
        const n = Number{.int = 32};
        std.debug.print("{d}\n", .{n.int});
    }

    const Number = union {
        int: i64,
        float: f64,
        nan: void,
    };
```

一个联合一次只能设置一个字段；尝试访问未设置的字段会报错。设置了`int`字段，尝试访问`n.float`，将会出错。`nan`字段是`void`类型。如何进行赋值呢？使用`{}`：

```zig
    const n = Number{.nan = {}};
```

需要知道哪个联合字段被设置了。这时，标记联合就该上场了。标记联合将组合枚举与联合，可以在switch语句中使用。考虑以下示例：

```zig
    pub fn main() void {
        const ts = Timestamp{.unix = 1693278411};
        std.debug.print("{d}\n", .{ts.seconds()});
    }

    const TimestampType = enum {
        unix,
        datetime,
    };

    const Timestamp = union(TimestampType) {
        unix: i32,
        datetime: DateTime,

        const DateTime = struct {
            year: u16,
            month: u8,
            day: u8,
            hour: u8,
            minute: u8,
            second: u8,
        };

        fn seconds(self: Timestamp) u16 {
            switch (self) {
                .datetime => |dt| return dt.second,
                .unix => |ts| {
                    const seconds_since_midnight: i32 = @rem(ts, 86400);
                    return @intCast(@rem(seconds_since_midnight, 60));
                },
            }
        }
    };
```

请注意，我们的`switch`中的每个情况都捕获了字段的类型值。也就是说，`dt`是`Timestamp.DateTime`，而`ts`是`i32`。这也是我们首次看到一个类型嵌套在另一个类型中的情况。`DateTime`可以在联合之外定义。我们还看到了两个新的内置函数：`@rem`用于获取余数，`@intCast`用于将结果转换为`u16`（@intCast会根据返回类型将值转换为u16，因为返回值正在被返回）。

从上面的示例中可以看出，标记联合可以像接口一样使用，只要所有可能的实现在预先知道并可以嵌入到标记联合中。

最后，标记联合的枚举类型可以被推断。与定义一个`TimestampType`不同，我们可以这样做：

```zig
    const Timestamp = union(enum) {
        unix: i32,
        datetime: DateTime,

        ...
```

Zig 将会根据我们的联合类型的字段创建一个隐式枚举。

Zig支持在类型前面加上问号?来声明可选类型。可选类型可以是null，也可以是类型的值：

```zig
    var home: ?[]const u8 = null;
    var name: ?[]const u8 = "Leto";
```

需要明确指定类型的原因应该是清楚的：如果我们只是这样做const name = "Leto";，那么推断的类型将是非可选的[]const u8。

`.?`用于访问可选类型的值：

```zig
    std.debug.print("{s}\n", .{name.?});
```

但是，如果在null上使用`.?`，将会导致运行时错误。一个`if`语句可以安全地解包（unwrap）一个可选值：

```zig
    if (home) |h| {
        // h is a []const u8
        // we have a home value
    } else {
        // we don't have a home value
    }
```

`orelse`可以用来解包可选值或执行代码。这通常用于指定默认值或从函数中返回：

```zig
    const h = home orelse "unknown"
    // or maybe

    // exit our function
    const h = home orelse return;
```

然而，`orelse`也可以接受一个块并执行更复杂的逻辑。可选类型还与`while`集成，经常用于创建迭代器。我们不会实现一个迭代器，但是希望这个虚拟代码有意义：

```zig
    while (rows.next()) |row| {
        // do something with our row
    }
```

到目前为止，我们看到的每一个变量都被初始化为一个合理的值。但有时在声明变量时我们不知道它的值。可选值是一种选择，但并不总是合适。在这种情况下，我们可以将变量设置为`undefined`以保持未初始化状态。

在创建一个由某个函数填充的数组时，通常会这样做：

```zig
    var pseudo_uuid: [16]u8 = undefined;
    std.crypto.random.bytes(&pseudo_uuid);
```

上面的代码仍然创建了一个包含16个字节的数组，但是保留了内存的未初始化状态。

Zig具有简单而实用的错误处理功能。一切都从错误集开始，它看起来和行为都像枚举：

```zig
    // Like our struct in Part 1, OpenError can be marked as "pub"
    // to make it accessible outside of the file it is defined in
    const OpenError = error {
        AccessDenied,
        NotFound,
    };
```

一个函数，包括`main`，现在可以返回这个错误：

```zig
    pub fn main() void {
        return OpenError.AccessDenied;
    }

    const OpenError = error {
        AccessDenied,
        NotFound,
    };
```

如果尝试运行此代码，将会得到一个错误：`expected type 'void', found 'error{AccessDenied,NotFound}'`。这是有道理的：我们使用`void`返回类型定义了`main`函数，然后我们返回了某个值（一个错误，当然，但仍然不是`void`）。为了解决这个问题，我们需要更改函数的返回类型。

```zig
    pub fn main() OpenError!void {
        return OpenError.AccessDenied;
    }
```

这被称为错误联合类型，它表示我们的函数可以返回`OpenError`错误或`void`（即什么都没有）。到目前为止，我们一直相当明确：我们为函数可能返回的错误创建了一个错误集，并在函数的错误联合返回类型中使用了该错误集。但是，当涉及到错误时，Zig 有一些不错的技巧。首先，与其将错误联合指定为`error set!return type`，不如使用`!return type`来让 Zig 自动推断错误集。因此，我们可以定义我们的`main`如下：

```zig
    pub fn main() !void
```

其次，Zig 能够隐式地为我们创建错误集。与创建错误集不同，我们可以这样做：

```zig
    pub fn main() !void {
        return error.AccessDenied;
    }
```

我们完全明确和隐含的方法并不完全等同。例如，对具有隐含错误集的函数的引用需要使用特殊的`anyerror`类型。库开发者可能会看到更加明确的优势，比如自我记录的代码。但是，我认为隐式错误集和推断错误联合都是实用的；我经常同时使用这两种方法。

错误联合的真正价值在于语言层面支持`catch`和`try`。返回错误联合的函数调用可以包含`catch`子句。例如，一个HTTP服务器库可能会有以下代码：

```zig
    action(req, res) catch |err| {
        if (err == error.BrokenPipe or err == error.ConnectionResetByPeer) {
            return;
        } else if (err == error.BodyTooBig) {
            res.status = 431;
            res.body = "Request body is too big";
        } else {
            res.status = 500;
            res.body = "Internal Server Error";
            // todo: log err
        }
    };
```

`switch`版本在处理枚举时更加传统：

```zig
    action(req, res) catch |err| switch (err) {
        error.BrokenPipe, error.ConnectionResetByPeer) => return,
        error.BodyTooBig => {
            res.status = 431;
            res.body = "Request body is too big";
        },
        else => {
            res.status = 500;
            res.body = "Internal Server Error";
        }
    };
```

这非常时尚，但老实说，您在`catch`中最有可能做的事情是将错误传递给调用者：

```zig
    action(req, res) catch |err| return err;
```

`try`所要做的是非常常见。与其上面的方式，我们可以：

```zig
    try action(req, res);
```

这特别有用，因为必须处理错误。最有可能的情况是使用`try`或`catch`来处理错误。

多数情况使用`try`和`catch`，但错误联合类型支持`if`和`while`，与可选类型类似。在`while`中，如果条件返回错误，`else`子句会被执行。

还有一个特殊的`anyerror`类型，它可以包含任何错误。虽然我们可以将函数返回定义为`anyerror!TYPE`而不是`!TYPE`，但这两者不等同。推断错误集是基于函数可以返回的内容而创建的。`anyerror`是全局错误集，是程序中所有错误集的超集。因此，在函数签名中使用`anyerror`可能会表示您的函数可以返回实际上它不能返回的错误。`anyerror`用于可以与任何错误一起使用的函数参数或结构字段（想象一个日志记录库）。

函数可以返回错误联合可选类型。对于推断错误集，它看起来像这样：

```zig
    // load the last saved game
    pub fn loadLast() !?Save {
        // TODO
        return null;
    }
```

有不同的方式来使用这种函数，但最紧凑的方式是使用`try`解包错误，然后使用`orelse`解包可选值。以下是一个有效的示例：

```zig
    const std = @import("std");

    pub fn main() void {
        // This is the line you want to focus on
        const save = (try Save.loadLast()) orelse Save.blank();
        std.debug.print("{any}\n", .{save});
    }

    pub const Save = struct {
        lives: u8,
        level: u16,

        pub fn loadLast() !?Save {
            //todo
            return null;
        }

        pub fn blank() Save {
            return .{
                .lives = 3,
                .level = 1,
            };
        }
    };
```

尽管 Zig 有更深入的语言特性，某些语言特性具有更大的功能，但在这两个部分中所看到的内容已经涵盖了语言的一个重要部分。这将为我们提供一个基础，使我们能够探索更复杂的主题，而不会被语法分散注意力。
