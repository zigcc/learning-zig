> 原文地址：<https://www.openmymind.net/learning_zig/language_overview_1>

# 语言概述 - 第 1 部分

Zig 是一种强类型编译语言。它支持泛型，具有强大的编译时元编程功能，并且不包含垃圾收集器。许多人认为 Zig 是 C 的现代替代品。因此，该语言的语法与 C 类似，比较明显的就是以分号结尾的语句和以花括号分隔的块。

Zig 代码如下所示：

```zig
const std = @import("std");

// This code won't compile if `main` isn't `pub` (public)
pub fn main() void {
	const user = User{
		.power = 9001,
		.name = "Goku",
	};

	std.debug.print("{s}'s power is {d}\n", .{user.name, user.power});
}

pub const User = struct {
	power: u64,
	name: []const u8,
};
```

如果将上述内容保存到 `learning.zig` 文件，并运行 `zig run learning.zig`，会得到以下输出：`Goku's power is 9001`。

这是一个简单的示例，即使你是第一次看到 Zig，大概率能够看懂这段代码。尽管如此，下面的内容我们还是来逐行分析它。

> 请参阅[安装 Zig 部分](01-installing-zig.md)，以便快速启动并运行它。

## 模块引用

很少有程序是在没有标准库或外部库的情况下以单个文件编写的。我们的第一个程序也不例外，它使用 Zig 的标准库来进行打印输出。 Zig 的模块系统非常简单，只依赖于 `@import` 函数和 `pub` 关键字（使代码可以在当前文件外部访问）。

> 以 `@` 开头的函数是内置函数。它们是由编译器提供的，而不是标准库提供的。

我们通过指定模块名称来引用它。 Zig 的标准库以 `std` 作为模块名。要引用特定文件，需要使用相对路径。例如，将 `User` 结构移动到它自己的文件中，比如 `models/user.zig`：

```zig
// models/user.zig
pub const User = struct {
	power: u64,
	name: []const u8,
};
```

在这种情况下，可以用如下方式引用它：

```zig
// main.zig
const User = @import("models/user.zig").User;
```

> 如果我们的 `User` 结构未标记为 `pub` 我们会收到以下错误：`'User' is not marked 'pub'`。

`models/user.zig` 可以导出不止一项内容。例如，再导出一个常量：

```zig
// models/user.zig
pub const MAX_POWER = 100_000;

pub const User = struct {
	power: u64,
	name: []const u8,
};
```

这时，可以这样导入两者：

```zig
const user = @import("models/user.zig");
const User = user.User;
const MAX_POWER = user.MAX_POWER
```

此时，你可能会有更多的困惑。在上面的代码片段中，`user` 是什么？我们还没有看到它，如果使用 `var` 来代替 `const` 会有什么不同呢？或者你可能想知道如何使用第三方库。这些都是好问题，但要回答这些问题，需要掌握更多 Zig 的知识点。因此，我们现在只需要掌握以下内容：

- 如何导入 Zig 标准库
- 如何导入其他文件
- 如何导出变量、函数定义

## 代码注释

下面这行 Zig 代码是一个注释：

```zig
// This code won't compile if `main` isn't `pub` (public)
```

Zig 没有像 C 语言中类似 `/* ... */` 的多行注释。

基于注释的文档自动生成功能正在试验中。如果你看过 Zig 的标准库文档，你就会看到它的实际应用。`//!` 被称为顶级文档注释，可以放在文件的顶部。三斜线注释 (`///`) 被称为文档注释，可以放在特定位置，如声明之前。如果在错误的地方使用这两种文档注释，编译器都会出错。

## 函数

下面这行 Zig 代码是程序的入口函数 `main`：

```zig
pub fn main() void
```

每个可执行文件都需要一个名为 `main` 的函数：它是程序的入口点。如果我们将 `main` 重命名为其他名字，例如 `doIt` ，并尝试运行 `zig run learning.zig` ，我们会得到下面的错误：`'learning' has no member named 'main'`。

忽略 `main` 作为程序入口的特殊作用，它只是一个非常基本的函数：不带参数，不返回任何东西（void）。下面的函数会稍微有趣一些：

```zig
const std = @import("std");

pub fn main() void {
	const sum = add(8999, 2);
	std.debug.print("8999 + 2 = {d}\n", .{sum});
}

fn add(a: i64, b: i64) i64 {
	return a + b;
}
```

C 和 C++ 程序员会注意到 Zig 不需要提前声明，即 `add` 在定义之前就被调用了。

接下来要注意的是 `i64` 类型：64 位有符号整数。其他一些数字类型有： `u8` 、 `i8` 、 `u16` 、 `i16` 、 `u32` 、 `i32` 、 `u47` 、 `i47` 、 `u64` 、 `i64` 、 `f32` 和 `f64`。

包含 `u47` 和 `i47` 并不是一个确保您仍然清醒的测试; Zig 支持任意位宽度的整数。虽然你可能不会经常使用这些，但它们可以派上用场。经常使用的一种类型是 `usize`，它是一个无符号指针大小的整数，通常是表示某事物长度、大小的类型。

> 除了 `f32` 和 `f64` 之外，Zig 还支持 `f16` 、 `f80` 和 `f128` 浮点类型。

虽然没有充分的理由这样做，但如果我们将 `add` 的实现更改为：

```zig
fn add(a: i64, b: i64) i64 {
	a += b;
	return a;
}
```

`a += b` 这一行会报下面的错误：`不能给常量赋值`。这是一个重要的教训，我们稍后将更详细地回顾：函数参数是常量。

为了提高可读性，Zig 中不支持函数重载（用不同的参数类型或参数个数定义的同名函数）。暂时来说，以上就是我们需要了解的有关函数的全部内容。

## 结构体

下面这行代码创建了一个 `User` 结构体：

```zig
pub const User = struct {
	power: u64,
	name: []const u8,
};
```

> 由于我们的程序是单个文件，因此 `User` 仅在定义它的文件中使用，因此我们不需要将其设为 `pub` 。

结构字段以逗号终止，并且可以指定默认值：

```zig
pub const User = struct {
	power: u64 = 0,
	name: []const u8,
};
```

当我们创建一个结构体时，必须对每个字段赋值。例如，在一开始的定义中 `power` 没有默认值，因此下面这行代码将报错：`missing struct field: power`。

```zig
const user = User{.name = "Goku"};
```

但是，使用默认值定义后，上面的代码可以正常编译。

结构体可以有方法，也可以包含声明（包括其他结构），甚至可能包含零个字段，此时的作用更像是命名空间。

```zig
pub const User = struct {
	power: u64 = 0,
	name: []const u8,

	pub const SUPER_POWER = 9000;

	fn diagnose(user: User) void {
		if (user.power >= SUPER_POWER) {
			std.debug.print("it's over {d}!!!", .{SUPER_POWER});
		}
	}
};
```

方法只是普通函数，只是说可以用 `struct.method()` 方式调用。以下两种方法等价：

```zig
// call diagnose on user
user.diagnose();

// The above is syntactical sugar for:
User.diagnose(user);
```

大多数时候你将使用`struct.method()`语法，但方法作为普通函数的语法糖在某些场景下可以派上用场。

> `if` 语句是我们看到的第一个控制流。这很简单，对吧？我们将在下一部分中更详细地探讨这一点。

`diagnose` 在定义 `User` 类型中，接受 `User` 作为其第一个参数。因此，我们可以使用`struct.method()` 的语法来调用它。但结构内的函数不必遵循这种模式。一个常见的例子是用于结构体初始化的 `init` 函数：

```zig
pub const User = struct {
	power: u64 = 0,
	name: []const u8,

	pub fn init(name: []const u8, power: u64) User {
		return User{
			.name = name,
			.power = power,
		};
	}
}
```

`init` 的命名方式仅仅是一种约定，在某些情况下，`open` 或其他名称可能更有意义。如果你和我一样，不是 C++ 程序员，可能对 `.$field = $value,` 这种初始化字段的语法感到奇怪，但你很快就会习惯它。

当我们创建 `"Goku"` 时，我们将 `user` 变量声明为 `const` ：

```zig
const user = User{
	.power = 9001,
	.name = "Goku",
};
```

这意味着我们无法修改 `user` 的值。如果要修改变量，应使用 `var` 声明它。另外，你可能已经注意到 `user` 的类型是根据赋值对象推导出来的。我们也可以这样明确地声明：

```zig
const user: User = User{
	.power = 9001,
	.name = "Goku",
};
```

在有些情况下我们必须显式声明变量类型，但大多数时候，去掉显式的类型会让代码可读性更好。类型推导也可以这么使用。下面这段代码和上面的两个片段是等价的：

```zig
const user: User = .{
	.power = 9001,
	.name = "Goku",
};
```

不过这种用法并不常见。比较常见的一种情况是从函数返回结构体时会用到。这里的类型可以从函数的返回类型中推断出来。我们的 `init` 函数可能会这样写：

```zig
pub fn init(name: []const u8, power: u64) User {
	// instead of return User{...}
	return .{
		.name = name,
		.power = power,
	};
}
```

就像我们迄今为止已经探索过的大多数东西一样，今后在讨论 Zig 语言的其他部分时，我们会再次讨论结构体。不过，在大多数情况下，它们都是简单明了的。

## 数组和切片

我们可以略过代码的最后一行，但鉴于我们的代码片段包含两个字符串 `"Goku"` 和 `{s}'s power is {d}\n`，你可能会对 Zig 中的字符串感到好奇。为了更好地理解字符串，我们先来了解一下数组和切片。

数组的大小是固定的，其长度在编译时已知。长度是类型的一部分，因此 4 个有符号整数的数组 `[4]i32` 与 5 个有符号整数的数组 `[5]i32` 是不同的类型。

数组长度可以从初始化中推断出来。在以下代码中，所有三个变量的类型均为 `[5]i32` ：

```zig
const a = [5]i32{1, 2, 3, 4, 5};

// we already saw this .{...} syntax with structs
// it works with arrays too
const b: [5]i32 = .{1, 2, 3, 4, 5};

// use _ to let the compiler infer the length
const c = [_]i32{1, 2, 3, 4, 5};
```

另一方面，切片是指向数组的指针，外加一个在运行时确定的长度。我们将在后面的部分中讨论指针，但你可以将切片视为数组的视图。

> 如果你熟悉 Go，你可能已经注意到 Zig 中的切片有点不同：没有容量，只有指针和长度。

```zig
const a = [_]i32{1, 2, 3, 4, 5};
const b = a[1..4];
```

在上述代码中， `b` 是一个长度为 3 的切片，并且是一个指向 `a` 的指针。但是因为我们使用编译时已知的值来对数组进行切片（即 `1` 和 `4`）所以长度 `3` 在编译时也是已知。 Zig 编译器能够分析出来这些信息，因此 `b` 不是一个切片，而是一个指向长度为 3 的整数数组的指针。具体来说，它的类型是 `*const [3]i32`。所以这个切片的示例被 Zig 编译器的强大推导能力挫败了。

在实际代码中，切片的使用可能会多于数组。无论好坏，程序的运行时信息往往多于编译时信息。不过，在下面这个例子中，我们必须欺骗 Zig 编译器才能得到我们想要的示例：

```zig
const a = [_]i32{1, 2, 3, 4, 5};
var end: usize = 4;
const b = a[1..end];
```

`b` 现在是一个切片了。具体来说，它的类型是 `[]const i32`。你可以看到，切片的长度并不是类型的一部分，因为长度是运行时属性，而类型总是在编译时就完全已知。在创建切片时，我们可以省略上界，创建一个到要切分的对象（数组或切片）末尾的切片，例如 `const c = b[2..]`。

> 如果我们将 `end` 声明为 `const` 那么它将成为编译时已知值，这将导致 `b` 是一个指向数组的指针，而不是切片。我觉得这有点令人困惑，但它并不是经常出现的东西，而且也不太难掌握。我很想在这一点上跳过它，但无法找到一种诚实的方法来避免这个细节。

学习 Zig 让我了解到，类型具有很强的描述性。它不仅仅是一个整数或布尔值，甚至是一个有符号的 32 位整数数组。类型还包含其他重要信息。我们已经讨论过长度是数组类型的一部分，许多示例也说明了可变性（const-ness）也是数组类型的一部分。例如，在上一个示例中，b 的类型是 `[]const i32`。你可以通过下面的代码来验证这一点：

```zig
const std = @import("std");

pub fn main() void {
	const a = [_]i32{1, 2, 3, 4, 5};
	var end: usize = 4;
	const b = a[1..end];
	std.debug.print("{any}", .{@TypeOf(b)});
}
```

如果我们尝试写入 `b` ，例如 `b[2] = 5` ，我们会收到编译时错误：`cannot assign to constant.`。这就是因为 `b` 类型是 `const` 导致。

为了解决这个问题，你可能会想要进行以下更改：

```zig
// replace const with var
var b = a[1..end];
```

但你会得到同样的错误，为什么？作为提示，`b` 的类型是什么，或者更通俗地说，`b` 是什么？切片是指向数组（部分）的长度和指针。切片的类型总是从底层数组派生出来的。无论 `b` 是否声明为 `const`，底层数组都是 `[5]const i32` 类型，因此 b 必须是 `[]const i32` 类型。如果我们想写入 `b`，就需要将 `a` 从 `const` 变为 `var`。

```zig
const std = @import("std");

pub fn main() void {
	var a = [_]i32{1, 2, 3, 4, 5};
	var end: usize = 4;
	const b = a[1..end];
	b[2] = 99;
}
```

这是有效的，因为我们的切片不再是 `[]const i32` 而是 `[]i32` 。你可能想知道为什么当 `b` 仍然是 `const` 时，这段代码可以执行。这时因为 `b` 的可变性是指 `b` 本身，而不是 `b` 指向的数据。好吧，我不确定这是一个很好的解释，但对我来说，这段代码突出了差异：

```zig
const std = @import("std");

pub fn main() void {
	var a = [_]i32{1, 2, 3, 4, 5};
	var end: usize = 4;
	const b = a[1..end];
	b = b[1..];
}
```

上述代码不会编译；正如编译器告诉我们的，我们不能给常量赋值。但如果将代码改成 `var b = a[1..end]` ，那么代码就是正确的了，因为 `b` 本身不再是常量。

在了解 Zig 语言的其他方面（尤其是字符串）的同时，我们还将发现更多有关数组和切片的知识。

## 字符串

我希望我能说，Zig 里有字符串类型，而且非常棒。遗憾的是，它没有。最简单来说，字符串是字节（u8）的序列（即数组或切片）。实际上，我们可以从 `name` 字段的定义中看到这一点：`name: []const u8`.

按照惯例，这类字符串大多数都是用 UTF-8 编码，因为 Zig 源代码本身就是 UTF-8 编码的。但这并不是强制的，而且代表 ASCII 或 UTF-8 字符串的 `[]const u8` 与代表任意二进制数据的 `[]const u8` 实际上并没有什么区别。怎么可能有区别呢，它们是相同的类型。

根据我们所学的数组和切片知识，你可以正确地猜测 `[]const u8` 是对常量字节数组的切片（其中字节是一个无符号 8 位整数）。但我们的代码中没有任何地方对数组进行切分，甚至没有数组，对吧？我们所做的只是将 `"Goku"` 赋值给 `user.name`。这是怎么做到的呢？

你在源代码中看到的字符串字面量有一个编译时已知的长度。编译器知道 `"Goku"` 的长度是 4，所以你会认为 `"Goku"` 最好用数组来表示，比如 `[4]const u8`。但是字符串字面形式有几个特殊的属性。它们被存储在二进制文件的一个特殊位置，并且会去重。因此，指向字符串字面量的变量将是指向这个特殊位置的指针。也就是说，`"Goku"` 的类型更接近于 `*const [4]u8`，是一个指向 4 常量字节数组的指针。

还有更多。字符串字面量以空值结束。也就是说，它们的末尾总是有一个 `\0`。在内存中，`"Goku"` 实际上是这样的：`{'G', 'o', 'k', 'u', 0}`，所以你可能会认为它的类型是 `*const [5]u8`。但这样做充其量只是模棱两可，更糟糕的是会带来危险（你可能会覆盖空结束符）。相反，Zig 有一种独特的语法来表示以空结尾的数组。`"Goku"`的类型是 `*const[4:0]u8`，即 4 字节以空结尾的数组指针。当我们讨论字符串时，我们关注的是以空结尾的字节数组（因为在 C 语言中字符串通常就是这样表示的），语法更通用：`[LENGTH:SENTINEL]`，其中 `SENTINEL` 是数组末尾的特殊值。因此，虽然我想不出为什么需要它，但下面的语法是完全正确的：

```zig
const std = @import("std");

pub fn main() void {
	// an array of 3 booleans with false as the sentinel value
	const a = [3:false]bool{false, true, false};

	// This line is more advanced, and is not going to get explained!
	std.debug.print("{any}\n", .{std.mem.asBytes(&a).*});
}
```

上面代码会输出：`{ 0, 1, 0, 0}` 。

> 我一直在犹豫是否要加入这个示例，因为最后一行非常高级，我不打算解释它。从另一个角度看，如果你愿意的话，这也是一个可以运行的示例，你可以用它来更好地研究我们到目前为止讨论过的一些问题。

如果我的解释还可以接受，那么你可能还有一点不清楚。如果 `"Goku"` 是一个 `*const [4:0]u8` ，那么我们为什么能将它赋值给一个 `[]const u8` 值呢？答案很简单：Zig 会自动进行类型转化。它会在几种不同的类型之间进行类型转化，但最明显的是字符串。这意味着，如果函数有一个 `[]const u8` 参数，或者结构体有一个 `[]const u8` 字段，就可以使用字符串字面形式。由于以空结尾的字符串是数组，而且数组的长度是已知的，因此这种转化代价比较低，即不需要遍历字符串来查找空结束符。

因此，在谈论字符串时，我们通常指的是 `[]const u8`。必要时，我们会明确说明一个以空结尾的字符串，它可以被自动转化为一个 `[]const u8`。但请记住，`[]const u8` 也用于表示任意二进制数据，因此，Zig 并不像高级编程语言那样有字符串的概念。此外，Zig 的标准库只有一个非常基本的 unicode 模块。

当然，在实际程序中，大多数字符串（以及更通用的数组）在编译时都是未知的。最典型的例子就是用户输入，程序编译时并不知道用户输入。这一点我们将在讨论内存时再次讨论。但简而言之，对于这种在编译时不能确定值的数据（长度当然也就无从得知），我们将在运行时动态分配内存。我们的字符串变量（仍然是 `[]const u8` 类型）将是指向动态分配的内存的切片。

## comptime 和 anytype

在我们未解释的最后一行代码中，涉及的知识远比表面看到的多：

```zig
std.debug.print("{s}'s power is {d}\n", .{user.name, user.power});
```

我们只是略微浏览了一下，但它确实提供了一个机会来强调 Zig 的一些更强大的功能。即使你还没有掌握，至少也应该了解这些功能。

首先是 Zig 的编译时执行（compile-time execution）概念。编译时执行是 Zig 元编程功能的核心，顾名思义，就是在编译时而不是运行时运行代码。在本指南中，我们将对编译时可能实现的功能进行浅显介绍，更多高级功能读者可以参考其他资料。

你可能想知道上面这行代码中需要编译时执行的是什么。`print` 函数的定义要求我们的第一个参数（字符串格式）是编译时已知的：

```zig
// notice the "comptime" before the "fmt" variable
pub fn print(comptime fmt: []const u8, args: anytype) void {
```

原因是 `print` 会进行额外的编译时检查，而这在大多数其他语言中是不会出现的。什么样的检查呢？假设你把格式改为 `it's over {d}/n`，但保留了两个参数。你会得到一个编译时错误：`unused argument in 'it's over {d}'`。它还会进行类型检查：将格式字符串改为`{s}'s power is {s}\n`，你会这个错误`invalid format string 's' for type 'u64'`。如果在编译时不知道字符串的格式，就不可能在编译时进行这些检查。因此，需要一个编译时已知的值。

`comptime` 会对编码产生直接影响的地方是整数和浮点字面的默认类型，即特殊的 `comptime_int` 和 `comptime_float`。这行代码是无效的：`var i = 0`。`comptime`代码只能使用编译时已知的数据，对于整数和浮点数，这类数据由特殊的 `comptime_int` 和 `comptime_float` 类型标识。这种类型的值可以在编译时执行。但你可能不会把大部分时间花在编写用于编译时执行的代码上，因此它并不是一个特别有用的默认值。你需要做的是给变量一个显式类型：

```zig
var i: usize = 0;
var j: f64 = 0;
```

> 注意，如果我们使用`const`，就不会出现这个错误，因为错误的关键在于 `comptime_int` 必须是常量。

在以后的章节中，我们将在探索泛型时进一步研究 `comptime`。

我们这行代码的另一个特别之处在于奇怪的 `.{user.name, user.power}`，根据上述 `print` 的定义，我们知道它映射到 `anytype` 类型的变量。这种类型不应与 Java 的 Object 或 Go 的 any（又名 interface{}）混淆。相反，在编译时，Zig 会为传递给它的所有类型专门创建一个单独的 `print` 函数。

这就引出了一个问题：我们传递给它的是什么？我们以前在让编译器推断结构类型时见过 `.{...}` 符号。这与此类似：它创建了一个匿名结构字面。请看这段代码

```zig
pub fn main() void {
	std.debug.print("{any}\n", .{@TypeOf(.{.year = 2023, .month = 8})});
}
```

会输出：

```
struct{comptime year: comptime_int = 2023, comptime month: comptime_int = 8}
```

在这里，我们给匿名结构的字段取名为 `year` 和 `month`。在原始代码中，我们没有这样做。在这种情况下，字段名会自动生成 0、1、2 等。`print` 函数希望结构中包含此类字段，并使用字符串格式中的序号位置来获取适当的参数。

Zig 没有函数重载，也没有可变函数（vardiadic，具有任意数量参数的函数）。但它的编译器能根据传入的类型创建专门的函数，包括编译器自己推导和创建的类型。
