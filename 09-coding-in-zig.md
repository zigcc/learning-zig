> 原文地址：https://www.openmymind.net/learning_zig/coding_in_zig/

# 使用 Zig 编程

在介绍了 Zig 语言的大部分内容之后，我们将对一些主题进行回顾，并展示几种使用 Zig 编程时一些实用的技巧。在此过程中，我们将介绍更多的标准库，并介绍一些不那么琐碎的代码片段。

## 悬空指针 Dangling Pointers

我们首先来看看更多关于悬空指针的例子。这似乎是一个奇怪的问题，但如果你来自垃圾回收语言，这可能是你将面临的最大挑战。

你能猜到下面的输出是什么吗？

```zig
const std = @import("std");

pub fn main() !void {
	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	const allocator = gpa.allocator();

	var lookup = std.StringHashMap(User).init(allocator);
	defer lookup.deinit();

	const goku = User{.power = 9001};

	try lookup.put("Goku", goku);
	const entry = lookup.getPtr("Goku").?;

	// returns an optional, .? would panic if "Goku"
	// wasn't in our hashmap
	const entry = lookup.getPtr("Goku").?;

	std.debug.print("Goku's power is: {d}\n", .{entry.power});

	// returns true/false depending on if the item was removed
	_ = lookup.remove("Goku");

	std.debug.print("Goku's power is: {d}\n", .{entry.power});
}

const User = struct {
	power: i32,
};
```
当我运行这个程序时，我得到了

```bash
Goku's power is: 9001
Goku's power is: -1431655766
```

这段代码引入了 Zig 的 `std.StringHashMap`，它是 `std.AutoHashMap` 的特定版本，键类型设置为 `[]const u8`。即使你不能百分百确定发生了什么，也可以猜测我的输出与我们从查找中删除条目后的第二次打印有关。注释掉删除的调用，输出就正常了。

理解上述代码的关键在于了解数据在内存的中位置，或者换句话说，了解数据的所有者。请记住，Zig 参数是按值传递的，也就是说，我们传递的是值的浅副本。我们查找的 `User` 与 `goku` 引用的内存不同。我们上面的代码有两个用户，每个用户都有自己的所有者。`goku` 的所有者是 `main`，而它的副本的所有者是 `lookup`。

`getPtr` 方法返回的是指向 `map` 中值的指针，在我们的例子中，它返回的是 `*User`。问题就在这里，删除会使我们的 `entry`指针失效。在这个示例中，`getPtr` 和 `remove` 的位置很近，因此问题也很明显。但不难想象，代码在调用 `remove` 时，并不知道 `entry` 的引用被保存在其他地方了。

> 在编写这个示例时，我并不确定会发生什么。删除有可能是通过设置内部标志来实现的，实际删除是惰性的。如果是这样的话，上面的示例在简单的情况下可能会 "奏效"，但在更复杂的情况下就会失败。这听起来非常难以调试。

除了不调用 `remove` 之外，我们还可以用几种不同的方法来解决这个问题。首先，我们可以使用 `get` 而不是 `getPtr`。这样 `lookup` 将返回一个 `User` 的副本，而不再是 `*User`。这样我们就有了三个用户：
1. 定义在函数内部的 `goku`，`main` 函数是其所有者
2. 调用 `lookup.put` 时，形式参数会得到 `goku` 一个的副本，`lookup` 是其所有者
3. 使用 `get` 函数返回的 `entry`，`main` 函数是其所有者

由于 `entry` 现在是 `User` 的独立副本，因此将其从 `lookup` 中删除不会再使其失效。

另一种方法是将 `lookup` 的类型从 `StringHashMap(User)` 改为 `StringHashMap(*const User)`。这段代码可以工作：
```zig
const std = @import("std");

pub fn main() !void {
	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	const allocator = gpa.allocator();

	// User -> *const User
	var lookup = std.StringHashMap(*const User).init(allocator);
	defer lookup.deinit();

	const goku = User{.power = 9001};

	// goku -> &goku
	try lookup.put("Goku", &goku);

	// getPtr -> get
	const entry = lookup.get("Goku").?;

	std.debug.print("Goku's power is: {d}\n", .{entry.power});
	_ = lookup.remove("Goku");
	std.debug.print("Goku's power is: {d}\n", .{entry.power});
}

const User = struct {
	power: i32,
};
```

上述代码中有许多微妙之处。首先，我们现在只有一个用户 `goku`。`lookup` 和 `entry` 中的值都是对 `goku` 的引用。我们对 `remove` 的调用仍然会删除查找中的值，但该值只是 `user` 的地址，而不是 `user` 本身。如果我们坚持使用 `getPtr`，那么被 `remove` 后，我们就会得到一个无效的 `**User`。在这两种解决方案中，我们都必须使用 `get` 而不是 `getPtr`，但在这种情况下，我们只是复制地址，而不是完整的 `User`。对于占用内存较多的对象来说，这可能是一个很大的区别。

如果把所有东西都放在一个函数中，再加上一个像 `User` 这样的小值，这仍然像是一个人为制造的问题。我们需要一个能让数据所有权成为当务之急的例子。

## 所有权 Ownership

我喜欢哈希表（HashMap），因为这是每个人都知道并且会经常使用的结构。它们有很多不同的用例，其中大部分你可能都用过。虽然哈希表可以用在一个局部查找的地方，但通常是从程序的整个运行期常驻的，因此插入其内的值需要同样长的生命周期。

这段代码将使用终端中输入的名称来填充我们的 `lookup`。如果名字为空，就会停止提示循环。最后，它会检测 `Leto` 是否出现在 `lookup` 中。

```zig
const std = @import("std");

pub fn main() !void {
	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	const allocator = gpa.allocator();

	var lookup = std.StringHashMap(User).init(allocator);
	defer lookup.deinit();

	// stdin is an std.io.Reader
	// the opposite of an std.io.Writer, which we already saw
	const stdin = std.io.getStdIn().reader();

	// stdout is an std.io.Writer
	const stdout = std.io.getStdOut().writer();

	var i: i32 = 0;
	while (true) : (i += 1) {
		var buf: [30]u8 = undefined;
		try stdout.print("Please enter a name: ", .{});
		if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |name| {
			if (name.len == 0) {
				break;
			}
			try lookup.put(name, .{.power = i});
		}
	}

	const has_leto = lookup.contains("Leto");
	std.debug.print("{any}\n", .{has_leto});
}

const User = struct {
	power: i32,
};
```

上述代码虽然区分大小写，但无论我们如何完美地输入 `Leto`，`contains` 总是返回 `false`。让我们通过遍历 `lookup` 打印其值来调试一下：
```zig
// Place this code after the while loop

var it = lookup.iterator();
while (it.next()) |kv| {
	std.debug.print("{s} == {any}\n", .{kv.key_ptr.*, kv.value_ptr.*});
}

```

这种迭代器模式在 Zig 中很常见，它依赖于 while 和可选类型（`Optional`）之间的协同作用。我们的迭代器返回指向键和值的指针，因此我们用 `.*` 对它们进行反引用，以访问实际值而不是地址。输出结果将取决于你输入的内容，但我得到的是
```bash
Please enter a name: Paul
Please enter a name: Teg
Please enter a name: Leto
Please enter a name:

�� == learning.User{ .power = 1 }

��� == learning.User{ .power = 0 }

��� == learning.User{ .power = 2 }
false
```
值看起来没问题，但键不一样。如果你不确定发生了什么，那可能是我的错。之前，我故意误导了你的注意力。我说哈希表通常声明周期会比较长，因此需要同等生命周期的值（value）。事实上，哈希表不仅需要长生命周期的值，还需要长生命周期的键（key）！请注意，`buf` 是在 `while` 循环中定义的。当我们调用 `put` 时，我们给了哈希表插入一个键值对，这个键的生命周期比哈希表本身短得多。将 `buf` 移到 `while` 循环之外可以解决生命周期问题，但每次迭代都会重复使用缓冲区。由于我们正在更改底层的键数据，因此它仍然无法工作。

对于上述代码，实际上只有一种解决方案：我们的 `lookup` 必须拥有键的所有权。我们需要添加一行并修改另一行：

```zig
// replace the existing lookup.put with these two lines
const owned_name = try allocator.dupe(u8, name);

// name -> owned_name
try lookup.put(owned_name, .{.power = i});
```

`dupe` 是 `std.mem.Allocator` 中的一个方法，我们以前从未见过。它会分配给定值的副本。代码现在可以工作了，因为我们的键现在在堆上，比 `lookup`的生命周期更长。事实上，我们在延长这些字符串的生命周期方面做得太好了，以至于引入了内存泄漏。

你可能以为当我们调用 lookup.deinit 时，键和值就会被释放。但 StringHashMap 并没有放之四海而皆准的解决方案。首先，键可能是字符串文字，无法释放。其次，它们可能是用不同的分配器创建的。最后，虽然更先进，但在某些情况下，键可能不属于哈希表。

唯一的解决办法就是自己释放键值。在这一点上，创建我们自己的 `UserLookup` 类型并在 `deinit` 函数中封装这一清理逻辑可能会比较合理。一种简单的改法：
```zig
// replace the existing:
//   defer lookup.deinit();
// with:
defer {
	var it = lookup.keyIterator();
	while (it.next()) |key| {
		allocator.free(key.*);
	}
	lookup.deinit();
}
```

这里的 `defer` 逻辑使用了一个代码快，它释放每个键，最后去释放 `lookup` 本身。我们使用的 `keyIterator` 只会遍历键。迭代器的值是指向哈希映射中键的指针，即 `*[]const u8`。我们希望释放实际的值，因为这是我们通过 `dupe` 分配的，所以我们使用 `key.*`.

我保证，关于悬挂指针和内存管理的讨论已经结束了。我们所讨论的内容可能还不够清晰或过于抽象。当你有更实际的问题需要解决时，再重新讨论这个问题也不迟。不过，如果你打算编写任何稍具规模（non-trivial）的程序，这几乎肯定是你需要掌握的内容。当你觉得可以的时候，我建议你参考上面这个示例，并自己动手实践一下。引入一个 `UserLookup` 类型来封装我们必须做的所有内存管理。尝试使用 `*User` 代替 `User`，在堆上创建用户，然后像处理键那样释放它们。编写覆盖新结构的测试，使用 `std.testing.allocator` 确保不会泄漏任何内存。

## ArrayList

现在你可以忘掉我们的 `IntList` 和我们创建的通用替代方案了。Zig 标准库中有一个动态数组实现：`std.ArrayList(T)`。

它是相当标准的东西，但由于它如此普遍需要和使用的数据结构，值得看看它的实际应用:
```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main() !void {
	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	const allocator = gpa.allocator();

	var arr = std.ArrayList(User).init(allocator);
	defer {
		for (arr.items) |user| {
			user.deinit(allocator);
		}
		arr.deinit();
	}

	// stdin is an std.io.Reader
	// the opposite of an std.io.Writer, which we already saw
	const stdin = std.io.getStdIn().reader();

	// stdout is an std.io.Writer
	const stdout = std.io.getStdOut().writer();

	var i: i32 = 0;
	while (true) : (i += 1) {
		var buf: [30]u8 = undefined;
		try stdout.print("Please enter a name: ", .{});
		if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |name| {
			if (name.len == 0) {
				break;
			}
			const owned_name = try allocator.dupe(u8, name);
			try arr.append(.{.name = owned_name, .power = i});
		}
	}

	var has_leto = false;
	for (arr.items) |user| {
		if (std.mem.eql(u8, "Leto", user.name)) {
			has_leto = true;
			break;
		}
	}

	std.debug.print("{any}\n", .{has_leto});
}

const User = struct {
	name: []const u8,
	power: i32,

	fn deinit(self: User, allocator: Allocator) void {
		allocator.free(self.name);
	}
};
```
以上是哈希表代码的基于 `ArrayList(User)` 的另一种实现。所有相同的生命周期和内存管理规则都适用。请注意，我们仍在创建 `name` 的副本，并且仍在删除 `ArrayList` 之前释放每个 `name`。

现在是指出 Zig 没有属性或私有字段的好时机。当我们访问 `arr.items` 来遍历值时，就可以看到这一点。没有属性的原因是为了消除阅读 Zig 代码中的歧义。在 Zig 中，如果看起来像字段访问，那就是字段访问。我个人认为，没有私有字段是一个错误，但我们可以解决这个问题。我已经习惯在字段前加上下划线，表示『仅供内部使用』。

由于字符串的类型是 `[]u8` 或 `[]const u8`，因此 `ArrayList(u8)` 是字符串构造器的合适类型，比如 .NET 的 `StringBuilder` 或 Go 的 `strings.Builder`。事实上，当一个函数的参数是 `Writer` 而你需要一个字符串时，就会用到 `ArrayList(u8)`。我们之前看过一个使用 `std.json.stringify` 将 JSON 输出到 `stdout` 的示例。下面是将 JSON 输出到 `ArrayList(u8)` 的示例：
```zig
const std = @import("std");

pub fn main() !void {
	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	const allocator = gpa.allocator();

	var out = std.ArrayList(u8).init(allocator);
	defer out.deinit();

	try std.json.stringify(.{
		.this_is = "an anonymous struct",
		.above = true,
		.last_param = "are options",
	}, .{.whitespace = .indent_2}, out.writer());

	std.debug.print("{s}\n", .{out.items});
}
```

## Anytype

在[语言概述的第一部分](02-language-overview-part1.md)中，我们简要介绍了 `anytype`。这是一种非常有用的编译时 duck 类型。下面是一个简单的 logger：
```zig
pub const Logger = struct {
	level: Level,

	// "error" is reserved, names inside an @"..." are always
	// treated as identifiers
	const Level = enum {
		debug,
		info,
		@"error",
		fatal,
	};

	fn info(logger: Logger, msg: []const u8, out: anytype) !void {
		if (@intFromEnum(logger.level) <= @intFromEnum(Level.info)) {
			try out.writeAll(msg);
		}
	}
};
```
`info` 函数的 `out` 参数类型为 `anytype`。这意味着我们的 logger 可以将信息输出到任何具有 writeAll 方法的结构中，该方法接受一个 `[]const u8` 并返回一个 `!void`。这不是运行时特性。类型检查在编译时进行，每使用一种类型，就会创建一个类型正确的函数。如果我们试图调用 `info`，而该类型不具备所有必要的函数（本例中只有 `writeAll`），我们就会在编译时出错：

```zig
var l = Logger{.level = .info};
try l.info("sever started", true);
```
会得到如下错误：
```bash
no field or member function named 'writeAll' in 'bool'
```
使用 `ArrayList(u8)` 的 `writer` 就可以运行：
```zig
pub fn main() !void {
	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	const allocator = gpa.allocator();

	var l = Logger{.level = .info};

	var arr = std.ArrayList(u8).init(allocator);
	defer arr.deinit();

	try l.info("sever started", arr.writer());
	std.debug.print("{s}\n", .{arr.items});
}
```

`anytype` 的一个最大缺点就是文档。下面是我们用过几次的 `std.json.stringify` 函数的签名：

```zig
// I **hate** multi-line function definitions
// But I'll make an exception for a guide which
// you might be reading on a small screen.

fn stringify(
	value: anytype,
	options: StringifyOptions,
	out_stream: anytype
) @TypeOf(out_stream).Error!void
```

第一个参数 `value: anytype` 是显而易见的，它是要序列化的值，可以是任何类型（实际上，Zig 的 JSON 序列化器不能序列化某些类似，比如 HashMap）。我们可以猜测，`out_stream` 是写入 JSON 的地方，但至于它需要实现什么方法，你和我一样猜得到。唯一的办法就是阅读源代码，或者传递一个假值，然后使用编译器错误作为我们的文档。如果有更好的自动文档生成器，这一点可能会得到改善。不过，我希望 Zig 能提供接口，这已经不是第一次了。

## @TypeOf

在前面的部分中，我们使用 `@TypeOf` 来帮助我们检查各种变量的类型。从我们的用法来看，你可能会认为它返回的是字符串类型的名称。然而，鉴于它是一个 PascalCase 风格函数，你应该更清楚：它返回的是一个类型。

我最喜欢用 `anytype` 与 `@TypeOf` 和 `@hasField` 内置函数搭配使用，以编写测试帮助程序。虽然我们看到的每个 `User` 类型都非常简单，但我还是要请大家想象一下一个有很多字段的更复杂的结构。在许多测试中，我们需要一个 `User`，但我们只想指定与测试相关的字段。让我们创建一个 `userFactory`：

```zig
fn userFactory(data: anytype) User {
	const T = @TypeOf(data);
	return .{
		.id = if (@hasField(T, "id")) data.id else 0,
		.power = if (@hasField(T, "power")) data.power else 0,
		.active  = if (@hasField(T, "active")) data.name else true,
		.name  = if (@hasField(T, "name")) data.name else "",
	};
}

pub const User = struct {
	id: u64,
	power: u64,
	active: bool,
	name: [] const u8,
};
```
我们可以通过调用 `userFactory(.{})` 创建默认用户，也可以通过 `userFactory(.{.id = 100, .active = false})` 来覆盖特定字段。这只是一个很小的模式，但我非常喜欢。这也是迈向元编程世界的第一步。

更常见的是 `@TypeOf` 与 `@typeInfo` 配对，后者返回一个 `std.buildin.Type`。这是一个功能强大的带标记的联合（tagged union），可以完整描述一个类型。`std.json.stringify` 函数会递归地调用它，以确定如何将其序列化。

# 构建系统

如果你通读了整本指南，等待着深入了解如何建立更复杂的项目，包括多个依赖关系和各种目标，那你就要失望了。Zig 拥有强大的构建系统，以至于越来越多的非 Zig 项目都在使用它，比如 libsodium。不幸的是，所有这些强大的功能都意味着，对于简单的需求来说，它并不是最容易使用或理解的。

> 事实上，是我不太了解 Zig 的构建系统，所以无法解释清楚。

不过，我们至少可以获得一个简要的概述。为了运行 Zig 代码，我们使用了 `zig run learning.zig`。有一次，我们还用 `zig test learning.zig` 进行了一次测试。运行和测试命令用来玩玩还行，但如果要做更复杂的事情，就需要使用构建命令了。编译命令依赖于带有特殊编译入口的 `build.zig` 文件。下面是一个示例：
```zig
// build.zig

const std = @import("std");

pub fn build(b: *std.Build) !void {
	_ = b;
}
```
每个构建程序都有一个默认的『安装』步骤，可以使用 `zig build install` 运行它，但由于我们的文件大部分是空的，你不会得到任何有意义的工件。我们需要告诉构建程序我们程序的入口是 `learning.zig`：

```zig
const std = @import("std");

pub fn build(b: *std.Build) !void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	// setup executable
	const exe = b.addExecutable(.{
		.name = "learning",
		.target = target,
		.optimize = optimize,
		.root_source_file = .{ .path = "learning.zig" },
	});
	b.installArtifact(exe);
}
```

现在，如果运行 `zig build install`，就会在 `./zig-out/bin/learning` 中得到一个二进制文件。通过使用 `standardTargetOptions` 和 `standardOptimizeOption`，我们就能以命令行参数的形式覆盖默认值。例如，要为 `Windows` 构建一个大小优化的程序版本，我们可以这样做：
```bash
zig build install -Doptimize=ReleaseSmall -Dtarget=x86_64-windows-gnu
```

除了默认的『安装』步骤外，可执行文件通常还会增加两个步骤：『运行』和『测试』。一个库可能只有一个『测试』步骤。对于基本的无参数即可运行的程序来说，只需要在构建文件的最后添加四行：
```zig
// add after: b.installArtifact(exe);

const run_cmd = b.addRunArtifact(exe);
run_cmd.step.dependOn(b.getInstallStep());

const run_step = b.step("run", "Start learning!");
run_step.dependOn(&run_cmd.step);
```
这里通过 `dependOn` 的两次调用创建两个依赖关系。第一个依赖关系将我们的 `run_cmd` 与内置的安装步骤联系起来。第二个是将 `run_step` 与我们新创建的 `run_cmd` 绑定。你可能想知道为什么需要 `run_cmd` 和 `run_step`。我认为这种分离是为了支持更复杂的设置：依赖于多个命令的步骤，或者在多个步骤中使用的命令。如果运行 `zig build --help` 并滚动到顶部，你会看到新增的 `run` 步骤。现在你可以执行 `zig build run` 来运行程序了。

要添加『测试』步骤，你需要重复刚才添加的大部分运行代码，只是不再使用 `b.addExecutable`，而是使用 `b.addTest`：

```zig
const tests = b.addTest(.{
	.target = target,
	.optimize = optimize,
	.root_source_file = .{ .path = "learning.zig" },
});

const test_cmd = b.addRunArtifact(tests);
test_cmd.step.dependOn(b.getInstallStep());
const test_step = b.step("test", "Run the tests");
test_step.dependOn(&test_cmd.step);
```
我们将该步骤命名为 `test`。运行 `zig build --help` 会显示另一个可用步骤 `test`。由于我们没有进行任何测试，因此很难判断这一步是否有效。在 `learning.zig` 中，添加
```zig
test "dummy build test" {
	try std.testing.expectEqual(false, true);
}
```
现在运行 `zig build test`时，应该会出现测试失败。如果你修复了测试，并再次运行 `zig build test`，你将不会得到任何输出。默认情况下，Zig 的测试运行程序只在失败时输出结果。如果你像我一样，无论成功还是失败，都想要一份总结，那就使用 `zig build test --summary all`。

这是启动和运行构建系统所需的最低配置。但是请放心,如果你需要构建你的程序，Zig 内置的功能大概率能覆盖你的需求。最后，你可以（也应该）在你的项目根目录下使用 `zig init-exe` 或 `zig init-lib`，让 Zig 为你创建一个文档齐全的 `build.zig` 文件。

## 第三方依赖

Zig 的内置软件包管理器相对较新，因此存在一些缺陷。虽然还有改进的余地，但它目前还是可用的。我们需要了解两个部分：创建软件包和使用软件包。我们将对其进行全面介绍。

首先，新建一个名为 `calc` 的文件夹并创建三个文件。第一个是 `add.zig`，内容如下：
```zig
// Oh, a hidden lesson, look at the type of b
// and the return type!!

pub fn add(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
	return a + b;
}

const testing = @import("std").testing;
test "add" {
	try testing.expectEqual(@as(i32, 32), add(30, 2));
}
```

这个例子可能看起来有点傻，一整个软件包只是为了加两个数值，但它能让我们专注于打包方面。接下来，我们将添加一个同样愚蠢的：`calc.zig`：
```zig
pub const add = @import("add.zig").add;

test {
	// By default, only tests in the specified file
	// are included. This magic line of code will
	// cause a reference to all nested containers
	// to be tested.
	@import("std").testing.refAllDecls(@This());
}
```
我们将其分割为 `calc.zig` 和 `add.zig`，以证明 `zig build` 可以自动构建和打包所有项目文件。最后，我们可以添加 build.zig：

```zig
const std = @import("std");

pub fn build(b: *std.Build) !void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	const tests = b.addTest(.{
		.target = target,
		.optimize = optimize,
		.root_source_file = .{ .path = "calc.zig" },
	});

	const test_cmd = b.addRunArtifact(tests);
	test_cmd.step.dependOn(b.getInstallStep());
	const test_step = b.step("test", "Run the tests");
	test_step.dependOn(&test_cmd.step);
}
```
这些都是我们在上一节中看到的内容的重复。有了这些，你就可以运行 `zig build test --summary all`。

回到我们的 `learning`项目和之前创建的 `build.zig`。首先，我们将添加本地 `calc` 作为依赖项。我们需要添加三项内容。首先，我们将创建一个指向 `calc.zig`的模块：
```zig
// You can put this near the top of the build
// function, before the call to addExecutable.

const calc_module = b.addModule("calc", .{
	.source_file = .{ .path = "PATH_TO_CALC_PROJECT/calc.zig" },
});
```

您需要调整 `calc.zig` 的路径。现在，我们需要将此模块添加到现有的 `exe` 和 `tests` 中：
```zig
const exe = b.addExecutable(.{
	.name = "learning",
	.target = target,
	.optimize = optimize,
	.root_source_file = .{ .path = "learning.zig" },
});
// add this
exe.addModule("calc", calc_module);
b.installArtifact(exe);

....

const tests = b.addTest(.{
	.target = target,
	.optimize = optimize,
	.root_source_file = .{ .path = "learning.zig" },
});
// add this
tests.addModule("calc", calc_module);
```

现在，可以在项目中 `@import("calc")`：

```zig
const calc = @import("calc");
...
calc.add(1, 2);
```

添加远程依赖关系需要花费更多精力。首先，我们需要回到 `calc` 项目并定义一个模块。你可能认为项目本身就是一个模块，但一个项目（project）可以暴露多个模块（module），所以我们需要明确地创建它。我们使用相同的 `addModule`，但舍弃了返回值。只需调用 `addModule` 就足以定义模块，然后其他项目就可以导入该模块。
```zig
_ = b.addModule("calc", .{
	.source_file = .{ .path = "calc.zig" },
});
```

这是我们需要对库进行的唯一改动。因为这是一个远程依赖的练习，所以我把这个 `calc` 项目推送到了 GitHub，这样我们就可以把它导入到我们的 `learning` 项目中。它可以在 https://github.com/karlseguin/calc.zig 上找到。

回到我们的 `learning`项目，我们需要一个新文件 `build.zig.zon`。ZON 是 Zig Object Notation 的缩写，它允许以人类可读格式表达 Zig 数据，并将人类可读格式转化为 Zig 代码。`build.zig.zon` 的内容包括：
```zig
.{
  .name = "learning",
  .version = "0.0.0",
  .dependencies = .{
    .calc = .{
      .url = "https://github.com/karlseguin/calc.zig/archive/e43c576da88474f6fc6d971876ea27effe5f7572.tar.gz",
      .hash = "12ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    },
  },
}
```
该文件中有两个可疑值，第一个是 url 中的 e43c576da88474f6fc6d971876ea27effe5f7572。这只是 git 提交的哈希值。第二个是哈希值。据我所知，目前还没有很好的方法来告诉我们这个值应该是多少，所以我们暂时使用一个假值。

要使用这一依赖关系，我们需要对 `build.zig` 进行一处修改：
```zig
// replace this:
const calc_module = b.addModule("calc", .{
	.source_file = .{ .path = "calc/calc.zig" },
});

// with this:
const calc_dep = b.dependency("calc", .{.target = target,.optimize = optimize});
const calc_module = calc_dep.module("calc");
```

在 `build.zig.zon` 中，我们将依赖关系命名为 `calc`，这就是我们要加载的依赖关系。在这个依赖关系中，我们将使用其中的 `calc` 模块，也就是我们在 `calc` 的 `build.zig.zon` 中命名的模块。

如果你尝试运行 `zig build test`，应该会看到一个错误：

```bash
error: hash mismatch:
expected:
12ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,

found:
122053da05e0c9348d91218ef015c8307749ef39f8e90c208a186e5f444e818672d4
```

将正确的哈希值复制并粘贴回 `build.zig.zon`，然后再次尝试运行 `zig build test`，现在一切应该都正常了。

听起来很多，我希望能精简一些。但这主要是你可以从其他项目中复制和粘贴的东西，一旦设置完成，你就可以继续了。

需要提醒的是，我发现 Zig 对依赖项的缓存偏激。如果你试图更新依赖项，但 Zig 似乎检测不到变化。这时，我会删除项目的 `zig-cache` 文件夹以及 `~/.cache/zig`。

---

我们已经涉猎了很多领域，探索了一些核心数据结构，并将之前的大块内容整合到了一起。我们的代码变得复杂了一些，不再那么注重特定的语法，看起来更像真正的代码。让我感到兴奋的是，尽管如此复杂，但代码大部分都是有意义的。如果暂时没有看懂，也不要放弃。选取一个示例并将其分解，添加打印语句，为其编写一些测试。亲自动手编写自己的代码，然后再回来阅读那些没有看懂的部分。
