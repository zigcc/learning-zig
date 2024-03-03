> 原文地址：<https://www.openmymind.net/learning_zig/language_overview_2>

# 语言概述 - 第二部分

本部分继续上一部分的内容：熟悉 Zig 语言。我们将探索 Zig 的控制流和结构以外的类型。通过这两部分的学习，我们将掌握 Zig 语言的大部分语法，这让我们可以继续深入 Zig 语言，同时也为如何使用 std 标准库打下了基础。

## 控制流

Zig 的控制流很可能是我们所熟悉的，但它与 Zig 语言的其他特性协同工作是我们还没有探索过。我们先简单概述控制流的基本使用，之后在讨论依赖控制流的相关特性时，再来重新回顾。

你会注意到，我们使用 `and` 和 `or` 来代替逻辑运算符 `&&` 和 `||`。与大多数语言一样，`and` 和 `or` 会短路执行，即如果左侧为假，`and` 的右侧运算符就不会执行；如果左侧为真，`or` 的右侧就不会执行。在 Zig 中，控制流是通过关键字完成的，因此要使用 `and` 和 `or`。

此外，比较运算符 `==` 在切片（如 `[]const u8`，即字符串）间不起作用。在大多数情况下，需要使用 `std.mem.eql(u8,str1,str2)`，它将比较两个片段的长度和字节数。

Zig 中，`if`、`else if` 和 `else` 也很常见：

```zig
// std.mem.eql 将逐字节进行比较，对于字符串来说它是大小写敏感的。
if (std.mem.eql(u8, method, "GET") or std.mem.eql(u8, method, "HEAD")) {
	// 处理 GET 请求
} else if (std.mem.eql(u8, method, "POST")) {
	// 处理 POST 请求
} else {
	// ...
}
```

> `std.mem.eql` 的第一个参数是一个类型，这里是 `u8`。这是我们看到的第一个泛型函数。我们将在后面的部分进一步探讨。

上述示例比较的是 ASCII 字符串，不区分大小写可能更合适，这时 `std.ascii.eqlIgnoreCase(str1, str2)` 可能是更好的选择。

虽然没有三元运算符，但可以使用 if/else 来代替：

```zig
const super = if (power > 9000) true else false;
```

`switch` 语句类似于`if/else if/else`，但具有穷举的优点。也就是说，如果没有涵盖所有情况，编译时就会出错。下面这段代码将无法编译：

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

编译时会报错：`switch` 必须处理所有的可能性。由于我们的 `years_married` 是一个 16 位整数，这是否意味着我们需要处理所有 64K 中情况？是的，不过我们可以使用 `else` 来代替：

```zig
// ...
6 => return "sugar",
else => return "no more gifts for you",
```

在进行匹配时，我们可以合并多个 `case` 或使用范围；在进行处理时，可以使用代码块来处理复杂的情况：

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

虽然 `switch` 在很多情况下都很有用，但在处理枚举时，它穷举的性质才真正发挥了作用，我们很快就会谈到枚举。

Zig 的 `for` 循环用于遍历数组、切片和范围。例如，我们可以这样写：

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

`for` 循环也可以同时处理多个序列，只要这些序列的长度相同。上面我们使用了 `std.mem.eql` 函数，下面是其大致实现：

```zig
pub fn eql(comptime T: type, a: []const T, b: []const T) bool {
	// if they aren't the same length, they can't be equal
	if (a.len != b.len) return false;

	for (a, b) |a_elem, b_elem| {
		if (a_elem != b_elem) return false;
	}

	return true;
}
```

一开始的 `if` 检查不仅是一个很好的性能优化，还是一个必要的防护措施。如果我们去掉它，并传递不同长度的参数，就会出现运行时 `panic`。`for` 在作用于多个序列上时，要求其长度相等。

`for` 循环也可以遍历范围，例如：

```zig
for (0..10) |i| {
	std.debug.print("{d}\n", .{i});
}
```

> 在 `switch` 中，范围使用了三个点，即 `3...6`，而这个示例中，范围使用了两个点，即 `0..10`。这是因为在 switch 中，范围的两端都是闭区间，而 for 则是左闭右开。

与一个（或多个）序列组合使用时，它的作用就真正体现出来了：

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

范围的末端由 `haystack` 的长度推断，不过我们也可以写出 `0..haystack.len`，但这没有必要。`for` 循环不支持常见的 `init; compare; step` 风格，对于这种情况，可以使用 `while`。

因为 `while` 比较简单，形式如下：`while (condition) { }`，这有利于更好地控制迭代。例如，在计算字符串中转义序列的数量时，我们需要将迭代器递增 2 以避免重复计算 `\\`：

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

`while` 可以包含 `else` 子句，当条件为假时执行 `else` 子句。它还可以接受在每次迭代后要执行的语句。在 `for` 支持遍历多个序列之前，这一功能很常用。上述语句可写成

```zig
var i: usize = 0;
var escape_count: usize = 0;

// 改写后的
while (i < src.len) : (i += 1) {
	if (src[i] == '\\') {
		// +1 here, and +1 above == +2
		// 这里 +1，上面也 +1，相当于 +2
		i += 1;
		escape_count += 1;
	}
}

```

Zig 也支持 `break` 和 `continue` 关键字，用于跳出最内层循环或跳转到下一次迭代。

代码块可以附带标签（label），`break` 和 `continue` 可以作用在特定标签上。举例说明：

```zig
outer: for (1..10) |i| {
	for (i..10) |j| {
		if (i * j > (i+i + j+j)) continue :outer;
		std.debug.print("{d} + {d} >= {d} * {d}\n", .{i+i, j+j, i, j});
	}
}
```

`break` 还有另一个有趣的行为，即从代码块中返回值：

```zig
const personality_analysis = blk: {
	if (tea_vote > coffee_vote) break :blk "sane";
	if (tea_vote == coffee_vote) break :blk "whatever";
	if (tea_vote < coffee_vote) break :blk "dangerous";
};
```

像这样有返回值的的块，必须以分号结束。

稍后，当我们讨论带标签的联合（tagged union）、错误联合（error unions）和可选类型（Optional）时，我们将看到控制流如何与它们联合使用。

## 枚举

枚举是带有标签的整数常量。它们的定义很像结构体：

```zig
// 可以是 "pub" 的
const Status = enum {
	ok,
	bad,
	unknown,
};
```

与结构体一样，枚举可以包含其他定义，包括函数，这些函数可以选择性地将枚举作为第一个参数：

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

> 如果需要枚举的字符串表示，可以使用内置的 `@tagName(enum)` 函数。

回想一下，结构类型可以使用 `.{...}` 符号根据其赋值或返回类型来推断。在上面，我们看到枚举类型是根据与 `self` 的比较推导出来的，而 `self` 的类型是 `Stage`。我们本可以明确地写成：`return self == Stage.confirmed` 或 `self == Stage.err`。但是，在处理枚举时，你经常会看到通过 `.$value` 这种省略具体类型的情况。

`switch` 的穷举性质使它能与枚举很好地搭配，因为它能确保你处理了所有可能的情况。不过在使用 `switch` 的 `else` 子句时要小心，因为它会匹配任何新添加的枚举值，而这可能不是我们想要的行为。

## 带标签的联合 Tagged Union

联合定义了一个值可以具有的一系列类型。例如，这个 `Number` 可以是整数、浮点数或 nan（非数字）：

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

一个联合一次只能设置一个字段；试图访问一个未设置的字段是错误的。既然我们已经设置了 `int` 字段，如果我们试图访问 `n.float`，就会出错。我们的一个字段 `nan` 是 `void` 类型。我们该如何设置它的值呢？使用 `{}`：

```zig
const n = Number{.nan = {}};
```

使用联合的一个难题是要知道设置的是哪个字段。这就是带标签的联合发挥作用的地方。带标签的联合将枚举与联合定义在一起，可用于 `switch` 语句中。请看下面这个例子：

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

请注意， `switch` 中的每个分支捕获了字段的类型值。也就是说，`dt` 是 `Timestamp.DateTime` 类型，而 `ts` 是 `i32` 类型。这也是我们第一次看到嵌套在其他类型中的结构。`DateTime` 本可以在联合之外定义。我们还看到了两个新的内置函数：`@rem` 用于获取余数，`@intCast` 用于将结果转换为 `u16`（`@intCast` 从返回值类型中推断出我们需要 `u16`）。

从上面的示例中我们可以看出，带标签的联合的使用有点像接口，只要我们提前知道所有可能的实现，我们就能够将其转化带标签的联合这种形式。

最后，带标签的联合中的枚举类型可以自动推导出来。我们可以直接这样做：

```zig
const Timestamp = union(enum) {
	unix: i32,
	datetime: DateTime,

	...
```

这里 Zig 会根据带标签的联合，自动创建一个隐式枚举。

## 可选类型 Optional

在类型前加上问号 `?`，任何值都可以声明为可选类型。可选类型既可以是 `null`，也可以是已定义类型的值：

```zig
var home: ?[]const u8 = null;
var name: ?[]const u8 = "Leto";
```

明确类型的必要性应该很清楚：如果我们只使用 const name = `"Leto"`，那么推导出的类型将是非可选的 `[]const u8`。

`.?`用于访问可选类型后面的值：

```zig
std.debug.print("{s}\n", .{name.?});

```

但如果在 `null` 上使用 `.?`，运行时就会 `panic`。`if` 语句可以安全地取出可选类型背后的值：

```zig
if (home) |h| {
	// h is a []const u8
	// we have a home value
} else {
	// we don't have a home value
}
```

`orelse` 可用于提取可选类型的值或执行代码。这通常用于指定默认值或从函数中返回：

```zig
const h = home orelse "unknown"

// 或直接返回函数
const h = home orelse return;
```

不过，orelse 也可以带一个代码块，用于执行更复杂的逻辑。可选类型还可以与 `while` 整合，经常用于创建迭代器。我们这里忽略迭代器的细节，但希望这段伪代码能说明问题：

```zig
while (rows.next()) |row| {
	// do something with our row
}
```

## 未定义的值 Undefined

到目前为止，我们看到的每一个变量都被初始化为一个合理的值。但有时我们在声明变量时并不知道它的值。可选类型是一种选择，但并不总是合理的。在这种情况下，我们可以将变量设置为未定义，让其保持未初始化状态。

通常这样做的一个地方是创建数组，其值将由某个函数来填充：

```zig
var pseudo_uuid: [16]u8 = undefined;
std.crypto.random.bytes(&pseudo_uuid);
```

上述代码仍然创建了一个 16 字节的数组，但它的每个元素都没有被赋值。

## 错误 Errors

Zig 中错误处理功能十分简单、实用。这一切都从错误集（error sets）开始，错误集的使用方式类似于枚举：

```zig
// 与第 1 部分中的结构一样，OpenError 也可以标记为 "pub"。
// 使其可以在其定义的文件之外访问
const OpenError = error {
	AccessDenied,
	NotFound,
};
```

任意函数（包括 `main`）都可以返回这个错误：

```zig
pub fn main() void {
	return OpenError.AccessDenied;
}

const OpenError = error {
	AccessDenied,
	NotFound,
};
```

如果你尝试运行这个程序，你会得到一个错误：`expected type 'void', found 'error{AccessDenied,NotFound}'`。这是有道理的：我们定义了返回类型为 `void` 的 `main` 函数，但我们却返回了另一种东西（很明显，它是一个错误，而不是 `void`）。要解决这个问题，我们需要更改函数的返回类型。

```zig
pub fn main() OpenError!void {
	return OpenError.AccessDenied;
}
```

这就是所谓的错误联合类型，它表示我们的函数既可以返回 `OpenError` 错误，也可以返回 `void`（也就是什么都没有）。到目前为止，我们已经非常明确：我们为函数可能返回的错误创建了一个错误集，并在函数的错误联合类型中使用了该错误集。但是，说到错误，Zig 有一些巧妙的技巧。首先，我们可以让 Zig 通过使用 `!return_type` 来推导错误集，而不是将 `error union` 指定为 `error_set!return_type`。因此，我们可以（也推荐）将我们 `main` 函数定义为：

```zig
pub fn main() !void

```

其次，Zig 能够为我们隐式创建错误集。我们可以这样做，而不需要提前声明：

```zig
pub fn main() !void {
	return error.AccessDenied;
}
```

完全显式和隐式方法并不完全等同。例如，引用具有隐式错误集的函数时，需要使用特殊的 `anyerror` 类型。类库开发人员可能会发现显式的好处，比如可以达到代码即文档的效果。不过，我认为隐式错误集和推导错误联合类型都很实用；我在平时编程中，大量使用了这两种方法。

错误联合类型的真正价值在于 Zig 语言提供了 `catch` 和 `try` 来处理它们。返回错误联合类型的函数调用时，可以包含一个 `catch` 子句。例如，一个 http 服务器库的代码可能如下所示：

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

`switch` 的版本更符合惯用法：

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

这看起来花哨，但老实说，你在 `catch` 中最有可能做的事情就是把错误信息给调用者：

```zig
action(req, res) catch |err| return err;
```

这种模式非常常见，因此 Zig 提供了 `try` 关键字用于处理这种情况。上述代码的另一种写法如下：

```zig
try action(req, res);
```

鉴于必须处理错误，这一点尤其有用。多数情况下的做法就是使用 `try` 或 `catch`。

> Go 开发人员会注意到，`try` 比 `if err != nil { return err }` 的按键次数更少。

大多数情况下，你都会使用 `try` 和 `catch`，但 `if` 和 `while` 也支持错误联合类型，这与可选类型很相似。在 `while` 的情况下，如果条件返回错误，则执行 `else` 子句。

有一种特殊的 `anyerror` 类型可以容纳任何错误。虽然我们可以将函数定义为返回 `anyerror!TYPE` 而不是 `!TYPE`，但两者并不等同。`anyerror` 是全局错误集，是程序中所有错误集的超集。因此，在函数签名中使用 `anyerror` 很可能表示这个函数虽然可以返回错误，而实际上它大概率不会返回错误。 `anyerror` 主要用在可以是任意错误类型的函数参数或结构体字段中（想象一下日志库）。

函数同时返回可选类型与错误联合类型的情况并不少见。在推导错误集的情况下，形式如下：

```zig
// 载入上次保存的游戏
pub fn loadLast() !?Save {
	// TODO
	return null;
}
```

使用此类函数有多种方法，但最简洁的方法是使用 `try` 来解除错误，然后使用 `orelse` 来解除可选类型。下面是一个大致的模式：

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

---

虽然我们还未涉及 Zig 语言中更高级的功能，但我们在前两部分中看到的是 Zig 语言重要组成部分。它们将作为一个基础，让我们能够探索更复杂的话题，而不用被语法所困扰。
