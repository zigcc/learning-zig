> 原文地址：<https://www.openmymind.net/learning_zig/style_guide>

# 代码风格和规范

本小节的主要内容是介绍 Zig 编译器强制遵守的 2 条规则，以及 Zig 标准库的命名惯例(naming convention)。

## 未使用变量 Unused Variable

Zig 编译器禁止`未使用变量`，例如以下代码会导致两处编译错误：

```zig
const std = @import("std");

pub fn main() void {
	const sum = add(8999, 2);
}

fn add(a: i64, b: i64) i64 {
	// notice this is a + a, not a + b
	return a + a;
}
```

第一个编译错误，源自于`sum`是一个未使用的本地常量。第二个编译错误，在于在函数`add`的所有形参中，`b`是一个未使用的函数参数。对于这段代码来说，它们是比较明显的漏洞。但是在实际编程中，代码中包含未使用变量和函数形参并非完全不合理。在这种情况下，我们可以通过将未使用变量赋值给`_`（下划线）的方法，避免编译器报错:

```zig
const std = @import("std");

pub fn main() void {
	_ = add(8999, 2);

	// or

	sum = add(8999, 2);
	_ = sum;
}

fn add(a: i64, b: i64) i64 {
	_ = b;
	return a + a;
}
```

除了使用`_ = b`之外，我们还可以直接用`_`来命名函数`add`的形参。但是，在我看来，这样做会牺牲代码的可读性，读者会猜测，这个未使用的形参到底是什么：

```zig
fn add(a: i64, _: i64) i64 {
```

值得注意的是，在上述例子中，`std`也是一个未使用的符号，但是当前这种用法并不会导致任何编译错误。可能在未来，Zig 编译器也将此视为错误。

## 变量覆盖 Variable Shadowing

Zig 不允许使用同名的变量。下面是一个读取 `socket` 的例子，这个例子包含了一个变量覆盖的编译错误：

```zig
fn read(stream: std.net.Stream) ![]const u8 {
	var buf: [512]u8 = undefined;
	const read = try stream.read(&buf);
	if (read == 0) {
		return error.Closed;
	}
	return buf[0..read];
}
```

上述例子中，`read`变量覆盖了`read`函数。我并不太认同这个规范，因为它会导致开发者为了避免覆盖而使用短且无意义的变量名。例如，为了让上述代码通过编译，需要将变量名`read`改成`n`。

我认为，这个规范并不能使代码可读性提高。在这个场景下，应该是开发者，而不是编译器，更有资格选择更有可读性的命名方案。

## 命名规范

除了遵守以上这些规则以外，开发者可以自由地选择他们喜欢的命名规范。但是，理解 Zig 自身的命名规范是有益的，因为大部分你需要打交道的代码，如 Zig 标准库，或者其他三方库，都采用了 Zig 的命名规范。

Zig 代码采用 4 个空格进行缩进。我个人会因为客观上更方便，使用`tab`键。

Zig 的函数名采用了驼峰命名法（camelCase)，而变量名会采用小写加下划线（snake case)的命名方式。类型则采用的是 PascalCase 风格。除了这三条规则外，一个有趣的交叉规则是，如果一个变量表示一个类型，或者一个函数返回一个类型，那么这个变量或者函数遵循 PascalCase。在之前的章节中，其实已经见到了这个例子，不过，可能你没有注意到：

```zig
std.debug.print("{any}\n", .{@TypeOf(.{.year = 2023, .month = 8})});
```

我们已经看到过一些内置函数：`@import`，`@rem`和`@intCast`。因为这些都是函数，他们的命名遵循驼峰命名法。`@TypeOf`也是一个内置函数，但是他遵循 PascalCase，为何？因为他返回的是一个类型，因此它的命名采用了类型命名方法。当我们使用一个变量，去接收`@TypeOf`的返回值，这个变量也需要遵循类型命名规则（即 PascalCase）:

```zig
const T = @TypeOf(3);
std.debug.print("{any}\n", .{T});
```

`zig` 命令包含一个 `fmt` 子命令，在给定一个文件或目录时，它会根据 Zig 的编码风格对文件进行格式化。但它并没有包含所有上述的规则，比如它能够调整缩排，以及花括号`{`的位置，但是它不会调整标识符的大小写。
