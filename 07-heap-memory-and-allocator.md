# 堆内存和 Allocator

到目前为止，我们所看到的所有内容都有个限制，需要预先知道大小。数组具备编译时已知的长度（实际上长度是类型的一部分）。我们所有的字符串都是字符串字面量，它们的长度也是编译时已知的。

此外，我们已经见过上一章的两个内存区域，即两种内存的管理策略：**全局数据**和**调用栈**。虽然简单高效，可限制颇多。此两种策略无法处理动态大小的数据，且都在数据生命周期方面都很严格。

本章分为两个主题。第一个是概述第三个内存区域**堆**。而另一个是 Zig 特有的直接管理堆内存的方法: 分配器`allocator`。即便你熟悉通用概念里的堆内存，比如说用过 `C` 的 `malloc`，但你仍会想一睹 zig 特有的`allocator`的风采。

## 堆

**堆**是我们内存中的第三个，也是最后一个内存区域。与前两个的**全局数据**和**调用栈**相比，堆有点像蛮荒之地，高度自由化。具体来说，在堆内存中，我们可以在运行时为存储的数据动态分配内存，而分配的这些内存大小则在运行时内根据需要动态确定，并且我们可以完全控制这些内存的生命周期——何时释放他们。

调用栈之所以令人惊奇，是因为它以简单和可预测的方式——通过推入和弹出栈帧来管理数据。这既是优点也是缺点：数据的生命周期与其在调用栈上的位置有关。堆恰恰相反。它没有内置的生命周期，所以我们的数据可以根据需要存在很长或很短的时间。而这一优点也是它的缺点：它没有内置的生命周期，所以如果我们不释放数据，就没有人会释放，始终留驻在内存中。

让我们来看一个例子：

```zig
const std = @import("std");

pub fn main() !void {
	// we'll be talking about allocators shortly
	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	const allocator = gpa.allocator();

	// ** The next two lines are the important ones **
	var arr = try allocator.alloc(usize, try getRandomCount());
	defer allocator.free(arr);

	for (0..arr.len) |i| {
		arr[i] = i;
	}
	std.debug.print("{any}\n", .{arr});
}

fn getRandomCount() !u8 {
	var seed: u64 = undefined;
	try std.os.getrandom(std.mem.asBytes(&seed));
	var random = std.rand.DefaultPrng.init(seed);
	return random.random().uintAtMost(u8, 5) + 5;
}
```

我们稍后将讨论 Zig 的 Allocator，目前需要知道的是 Allocator 是一个 `std.mem.Allocator`。我们使用了它的两种方法：`alloc` 和 `free`。分配内存可能出错，故我们用 `try` 捕获调用 `allocator.alloc`产生的错误。目前唯一可能的错误是 `OutOfMemory`。其参数主要告诉我们它是如何工作的：它需要一个类型（T）和一个计数值，成功时返回一个类型为 `[]T` 的切片。这种分配发生在运行时(runtime)期间，它必须如此，因为我们的计数只在运行时才可知。

一般规则是，每个 `alloc` 都会有一个相应的 `free`。`alloc` 在哪里分配内存，`free` 就在哪里释放它。不要让这段简单的代码限制了你的想象力。这种 `try alloc` + `defer free` 的模式很常见，并有充分的理由: 在我们分配内存的地方附近释放内存,相对而言不会出错。

但同样常见的是，在一个地方先分配内存，而后再在另一处释放它。如之前所说，堆没有内置的生命周期管理。你可以在一个 HTTP 处理器中分配内存，而后再在后台线程中释放内存。这可以是代码中完全分离的两部分。

## defer 和 errdefer

说句题外话，上面的代码介绍了一种新的语言特性：`defer`，它在退出作用域时执行给定的代码或块。“作用域退出”包括到达作用域的结尾或从作用域返回。严格来说， `defer` 并不与 Allocator 或内存管理有关；你可以用它来执行任何代码。但上面释放的用法是最常见的地方之一。

Zig 的 `defer` 类似于 Go 的 `defer`，但存在一个主要区别。在 Zig 中，`defer` 将在其包含作用域的末尾运行。在 Go 中，`defer` 是在包含函数的末尾运行。除非你是 Go 开发人员，否则 Zig 的做法可能更不令人惊讶。

与`defer` 相似的是 `errdefer`，它作用与之类似，是在作用域退出时执行给定的代码或块，但只在返回错误时执行。在执行更复杂的设置和因错误而必须撤消之前的内存分配时，这非常有用。

以下示例在复杂性上有所增加。它展示了 `errdefer` 和一个常见的模式，即在 `init` 中分配并在 `deinit` 中释放：

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Game = struct {
	players: []Player,
	history: []Move,
	allocator: Allocator,

	fn init(allocator: Allocator, player_count: usize) !Game {
		var players = try allocator.alloc(Player, player_count);
		errdefer allocator.free(players);

		// store 10 most recent moves per player
		var history = try allocator.alloc(Move, player_count * 10);

		return .{
			.players = players,
			.history = history,
			.allocator = allocator,
		};
	}

	fn deinit(game: Game) void {
		const allocator = game.allocator;
		allocator.free(game.players);
		allocator.free(game.history);
	}
};
```

这段代码能突显两件事。

首先，是 `errdefer` 的实用性。在正常情况下，`players` 在 `init` 中被分配并在 `deinit` 中被释放。但是有一个边缘情况，即 `history` 的初始化失败。仅在这种情况下，我们需要撤销 `players` 的分配。

此代码的第二个值得注意的方面是，我们有两个动态分配的切片: `players` 和 `history`。 这两个的生命周期基于我们的应用逻辑。没有规则规定必须何时调用 `deinit` 或者谁必须调用它。这种思路很好，这两个切片拥有了任意的生命周期。但也存在缺点，就是如果从未调用 `deinit` 或调用 `deinit` 超过一次，就会出现混乱和错误。

> `init` 和 `deinit` 的名字并不特殊。它们只是 Zig 标准库使用的，也是社区采纳的名称。在某些情况下，包括在标准库中，会使用 `open` 和 `close`，或其他更适当的名称。

## 双重释放和内存泄漏

就在上面，我提到没有硬性条件规定，什么时候必须释放这些内存。但这并不完全正确，有一些重要的规则，除非您自己小心谨慎，否则它们不会被强制执行。

第一条规则是不能两次释放相同的内存:

```zig
const std = @import("std");

pub fn main() !void {
	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	const allocator = gpa.allocator();

	var arr = try allocator.alloc(usize, 4);
	allocator.free(arr);
	allocator.free(arr);

	std.debug.print("This won't get printed\n", .{});
}
```

可预见代码的最后一行的结果，`print`不会被打印出来。因为我们 `free` 两次相同的内存块。这称为双重释放，而且这个操作无效。这种问题看起来很好避免，可在具有复杂生命周期的大型项目中，这个问题则很难追踪。

第二条规则是，不能释放没有引用的内存。这听起来似乎很明显，但并不总是清楚谁负责释放它。以下创建一个新的小写字符串：

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

fn allocLower(allocator: Allocator, str: []const u8) ![]const u8 {
	var dest = try allocator.alloc(u8, str.len);

	for (str, 0..) |c, i| {
		dest[i] = switch (c) {
			'A'...'Z' => c + 32,
			else => c,
		};
	}

	return dest;
}
```

上面的代码正常，但下面的则会报错:

```zig
// For this specific code, we should have used std.ascii.eqlIgnoreCase
fn isSpecial(allocator: Allocator, name: [] const u8) !bool {
	const lower = try allocLower(allocator, name);
	return std.mem.eql(u8, lower, "admin");
}
```

这是内存泄漏。创建的内存 `allocLower` 永远不会被释放。不仅如此，一旦 `isSpecial` 返回，这块内存就永远无法释放。在有垃圾收集器的语言中，当数据变得无法访问时，垃圾收集器最终会释放无用的内存。

但在上面的代码中，一旦 `isSpecial` 返回，我们就失去了对已分配内存的唯一引用，即 `lower` 变量(这是一个地址)。而直到我们的进程退出后，这块内存块才会释放。我们的函数可能只会泄漏几个字节，但如果它是一个长时间运行的进程，并且重复调用该函数，无法泄漏的内存块就会逐渐累积起来，最终会耗尽所有内存。

在双重释放的情况下，我们至少只会获得程序崩溃。而内存泄漏稍显阴险。不仅是根本原因难以识别，而且轻微的泄漏或偶尔执行的代码中的泄漏甚至很难检测到。针对这个常见的问题，Zig 做了一些优化，我们将在讨论 Allocator 时讲解这块。

## 创建 & 销毁

`std.mem.Allocator`的`alloc`方法会返回一个切片，其长度为传递的第二个参数。如果想要单个值，可以使用 `create` 和 `destroy` 而不是 `alloc` 和 `free`。

前面几部分在学习指针时，我们创建了 `User` 并尝试增强它的功能。这是该代码的基于堆使用`create`:

```zig
const std = @import("std");

pub fn main() !void {
	// again, we'll talk about allocators soon!
	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	const allocator = gpa.allocator();

	// create a User on the heap
	var user = try allocator.create(User);

	// free the memory allocated for the user at the end of this scope
	defer allocator.destroy(user);

	user.id = 1;
	user.power = 100;

	// this line has been added
	levelUp(user);
	std.debug.print("User {d} has power of {d}\n", .{user.id, user.power});
}

fn levelUp(user: *User) void {
	user.power += 1;
}

pub const User = struct {
	id: u64,
	power: i32,
};
```

`create` 方法接受一个参数，类型（T）。它返回指向该类型的指针或一个错误，即 `!*T`。也许你想知道，如果我们创建了`User`, 但没有设置 `id`, `power`时会发生什么。这就像将这些字段设置为未定义，其行为也是未定义的。意即，属性没有初始化时，在访问未初始化的变量，行为也是未定义，这意味着程序可能会出现不可预测的行为，比如返回错误的值、崩溃等问题。

当我们探索悬空指针时，函数错误地返回了本地`user`的地址：

```zig
pub const User = struct {
	fn init(id: u64, power: i32) *User{
		var user = User{
			.id = id,
			.power = power,
		};
		// this is a dangling pointer
		return &user;
	}
};
```

在这种情况下，返回`User`，而不是`&user`可能会更有意义。但有时你会希望函数返回一个指向它创建的东西的指针。当你想要一个生命周期免于调用堆栈的严格限制时，你会这样做。为了解决我们上面的悬挂指针问题，我们可以使用 `create` 方法：

```zig
// our return type changed, since init can now fail
// *User -> !*User
fn init(allocator: std.mem.Allocator, id: u64, power: i32) !*User{
	var user = try allocator.create(User);
	user.* = .{
		.id = id,
		.power = power,
	};
	return user;
}
```

我引入了新的语法，`user.* = .{...}`。这有点奇怪，我不是很喜欢它，但你会看到它。右侧是你已经见过的内容：它是一个带有推断类型的结构体初始化器。我们可以明确地使用 `user.* = User{...}`。左侧的 `user.*` 是我们如何去引用该指针所指向的变量。`&` 接受一个 T 类型并给我们一个 `*T` 类型。`.*` 是相反的操作，应用于一个 `*T` 类型的值时，它给我们一个 T 类型。即，`&`获取地址，`.*`获取值。

请记住，`create` 返回一个 `!*User`，所以我们的 user 是 `*User` 类型。

---

## 分配器 Allocator

Zig 的一个核心原则是**没有隐藏的内存分配**。可能按照你的背景来说，这可能不是太特殊。但这与 C 语言的写法形成了鲜明的对比。比如在 C 语言中，内存是通过标准库的 `malloc` 函数来分配。在 C 中，如果你想知道一个函数是否分配了内存，你需要阅读源码,并查找代码中对 `malloc` 的调用。

Zig 没有默认的 分配器`Allocator`。在上面的所有示例中，需要分配内存的函数通常需要声明为 `std.mem.Allocator` 的参数。按照之前的惯例，此参数通常是函数的第一个参数。这就是分配器`Allocator`Zig 的所有标准库和大多数第三方库，都要求调用者在打算分配内存时提供一个 分配器 `Allocator`。

**明确分配**是常用的两种分配器的形式之一。在简单的情况下，Allocator 在每次函数调用时都提供。这方面的例子有很多，但你可能迟早需要 `std.fmt.allocPrint`。它的作用类似于我们一直在使用的 `std.debug.print`，但是它分配并返回一个字符串，而不是将其写入 `stderr`：

```zig
const say = std.fmt.allocPrint(allocator, "It's over {d}!!!", .{user.power});
defer allocator.free(say);
```

另一种形式是将 Allocator 传递给 `init` ，然后由对象**内部使用**。

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Game = struct {
	players: []Player,
	history: []Move,
	allocator: Allocator,

	fn init(allocator: Allocator, player_count: usize) !Game {
		var players = try allocator.alloc(Player, player_count);
		errdefer allocator.free(players);

		// store 10 most recent moves per player
		var history = try allocator.alloc(Move, player_count * 10);

		return .{
			.players = players,
			.history = history,
			.allocator = allocator,
		};
	}

	fn deinit(game: Game) void {
		const allocator = game.allocator;
		allocator.free(game.players);
		allocator.free(game.history);
	}
};
```

我们在上面看到了这点，使用我们的 `Game` 结构体。由于你已经给对象一个 Allocator 来使用，但你不知道哪个方法在调用时会实际进行分配，因此这种方式并不明确。这种方法更适用于寿命较长的对象。

注入 Allocator 的优势不仅仅是明确性，还有灵活性。`std.mem.Allocator` 是一个接口，提供了 `alloc`、`free`、`create` 和 `destroy` 函数，以及其他一些函数。到目前为止，我们只看到了 `std.heap.GeneralPurposeAllocator`，但标准库或第三方库中还有其他实现。

> Zig 没有为创建接口提供漂亮的语法糖。一种类似接口的行为的模式是带标签的联合，尽管与真正的接口相比，这相对有许多限制。其他模式已经出现并在标准库中被广泛使用，例如 `std.mem.Allocator`。这份指南不会探讨这些接口模式。

如果你正在构建一个库，最好是接受一个 `std.mem.Allocator`参数，并让你的库的用户决定使用哪种 Allocator 的实现。否则你需要自己选择合适的 Allocator。正如我们将看到的，这些 Allocator 并不是互相排斥的。因而有充分的理由在程序中创建不同的 Allocator。

## 全面通用、线程安全的主分配器 GeneralPurposeAllocator

顾名思义，`std.heap.GeneralPurposeAllocator` 是一个全面的“通用”线程安全 Allocator，可以作为应用程序的主 分配器 `allocator`。对于许多程序来说，这将是唯一需要的 Allocator。在程序启动时，会创建一个 `allocator` 并将其传递给需要的函数。

我的 HTTP 服务器库的示例代码就是一个很好的例子：

```zig
const std = @import("std");
const httpz = @import("httpz");

pub fn main() !void {
	// create our general purpose allocator
	var gpa = std.heap.GeneralPurposeAllocator(.{}){};

	// get an std.mem.Allocator from it
	const allocator = gpa.allocator();

	// pass our allocator to functions and libraries that require it
	var server = try httpz.Server().init(allocator, .{.port = 5882});

	var router = server.router();
	router.get("/api/user/:id", getUser);

	// blocks the current thread
	try server.listen();
}
```

我们创建了 `GeneralPurposeAllocator`，从中获取一个 `std.mem.Allocator` 并将其传递给 HTTP 服务器的 `init` 函数。在一个更复杂的项目中，声明的变量`allocator` 可能会被传递给代码的多个部分，每个部分可能都会将其传递给自己的函数、对象和依赖项。

你可能会注意到，创建 `gpa` 的语法有点奇怪。什么是`GeneralPurposeAllocator(.{}){}`？

我们之前见过这些东西，只是现在都混合了起来。`std.heap.GeneralPurposeAllocator` 是一个函数，由于它使用的是 `PascalCase`（帕斯卡命名法），我们知道它返回一个类型。（下一部分会更多讨论泛型）。这个更明确的写法可能更方便理解：

```zig
const T = std.heap.GeneralPurposeAllocator(.{});
var gpa = T{};

// is the same as:

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
```

也许你仍然不太确信 `.{}` 的含义。我们之前也见过它：`.{}` 是一个具有隐式类型的结构体初始化器。

类型是什么，字段在哪里？尽管没有直接对`.{}`写出具体类型, 但它的类型是 `std.heap.general_purpose_allocator.Config`。因为 `Config` 结构体定义了默认值，没有设置的字段将自动使用默认值。这是配置 / 选项的一个常见模式。实际上，在几行下来我们传递 `. {.port = 5882}` 到 `init` 时，我们又看到了它。在这种情况下，除了`port`使用我们提供的值，其他字段都使用默认值。

---

## 测试分配器 std.testing.allocator，探测内存泄漏

当我们谈到困扰已久的内存泄漏，忽然知道 Zig 可以解决这个问题时，你应该会急切地想要了解更多。

这个解决之法来自 `std.testing.allocator`，它是一个 `std.mem.Allocator`。目前它由`GeneralPurposeAllocator` 实现，并集成在 Zig 的测试运行器中，但这只是一个实现细节。重要的是，如果我们在我们的测试中使用 `std.testing.allocator`，可以捕获大多数内存泄漏。

你可能已经对动态数组非常熟悉，它们通常被称为 `ArrayLists`。在许多动态编程语言中，所有数组都是动态数组。动态数组支持可变数量的元素。Zig 有一个合适的通用 `ArrayList`，我们将创建一个专门用于保存整数的`ArrayList`用来演示泄漏检测：

```zig
pub const IntList = struct {
	pos: usize,
	items: []i64,
	allocator: Allocator,

	fn init(allocator: Allocator) !IntList {
		return .{
			.pos = 0,
			.allocator = allocator,
			.items = try allocator.alloc(i64, 4),
		};
	}

	fn deinit(self: IntList) void {
		self.allocator.free(self.items);
	}

	fn add(self: *IntList, value: i64) !void {
		const pos = self.pos;
		const len = self.items.len;

		if (pos == len) {
			// we've run out of space
			// create a new slice that's twice as large
			var larger = try self.allocator.alloc(i64, len * 2);

			// copy the items we previously added to our new space
			@memcpy(larger[0..len], self.items);

			self.items = larger;
		}

		self.items[pos] = value;
		self.pos = pos + 1;
	}
};
```

有趣的部分发生在 `add`这块。 当 `pos == len`时，表明我们已经填充了当前数组，并且需要创建一个更大的数组。我们可以像这样使用`IntList`：

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main() !void {
	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	const allocator = gpa.allocator();

	var list = try IntList.init(allocator);
	defer list.deinit();

	for (0..10) |i| {
		try list.add(@intCast(i));
	}

	std.debug.print("{any}\n", .{list.items[0..list.pos]});
}
```

代码运行并打印正确的结果。可即使我们调用 `deinit` 释放`list`的内存，实际上仍然存在内存泄漏。如果您没有注意到也没关系，因为我们将使用`std.testing.allocator`编写一个测试：

```zig
const testing = std.testing;
test "IntList: add" {
	// We're using testing.allocator here!
	var list = try IntList.init(testing.allocator);
	defer list.deinit();

	for (0..5) |i| {
		try list.add(@intCast(i+10));
	}

	try testing.expectEqual(@as(usize, 5), list.pos);
	try testing.expectEqual(@as(i64, 10), list.items[0]);
	try testing.expectEqual(@as(i64, 11), list.items[1]);
	try testing.expectEqual(@as(i64, 12), list.items[2]);
	try testing.expectEqual(@as(i64, 13), list.items[3]);
	try testing.expectEqual(@as(i64, 14), list.items[4]);
}
```

> `@as` 是执行类型强制转换的内置函数。你并不是唯一一个觉得奇怪的人。从技术上讲，这是因为第二个参数“实际值”，需要被强制转换为第一个参数“预期的类型值”。在上面的代码中，“预期”都是 `comptime_int`，这就导致了问题。许多人，包括我自己，都认为`testing.expectEqual`中用`@as`是一种奇怪的行为。

如果您按照步骤操作，把测试放在 `IntList` 和 `main` 的同一个文件中。Zig 的测试通常写在同一个文件中，经常在它们测试的代码附近。当我们使用 `zig test learning.zig` 运行我们的测试时，我们得到了一个惊人的失败：

```bash
Test [1/1] test.IntList: add... [gpa] (err): memory address 0x101154000 leaked:
/code/zig/learning.zig:26:32: 0x100f707b7 in init (test)
   .items = try allocator.alloc(i64, 2),
                               ^
/code/zig/learning.zig:55:29: 0x100f711df in test.IntList: add (test)
 var list = try IntList.init(testing.allocator);

... MORE STACK INFO ...

[gpa] (err): memory address 0x101184000 leaked:
/code/test/learning.zig:40:41: 0x100f70c73 in add (test)
   var larger = try self.allocator.alloc(i64, len * 2);
                                        ^
/code/test/learning.zig:59:15: 0x100f7130f in test.IntList: add (test)
  try list.add(@intCast(i+10));
```

此处有多个内存泄漏。幸运的是，测试分配器准确地告诉我们泄漏的内存是在哪里分配的。你现在能发现泄漏了吗？如果没有，请记住，通常情况下，每个 `alloc` 都应该有一个相应的 `free`。我们的代码在 `deinit` 中调用 `free` 一次。然而在 `init` 中 `alloc` 被调用一次，每次调用 `add` 并需要更多空间时也会调用 `alloc`。每次我们 `alloc` 更多空间时，最后都需要 `free` 之前的 `self.items`。

```zig
// existing code
var larger = try self.allocator.alloc(i64, len * 2);
@memcpy(larger[0..len], self.items);

// Added code
// free the previous allocation
self.allocator.free(self.items);
```

将`items`复制到我们的 `larger` 切片中后, 添加最后一行`free`可以解决泄漏的问题。如果运行 `zig test learning.zig`，应该不会再有错误。

## 竞技场分配器 ArenaAllocator

`GeneralPurposeAllocator` 是一个合理的默认选项，因为它在所有可能的情况下都表现良好。但在程序内部，你可能会遇到可以从更专业的分配器中获益的分配模式。一个例子是在处理完成时可以丢弃的短生命周期状态的需求。解析器经常有这样的需求。一个基本的解析函数可能看起来像这样：

```zig
fn parse(allocator: Allocator, input: []const u8) !Something {
	var state = State{
		.buf = try allocator.alloc(u8, 512),
		.nesting = try allocator.alloc(NestType, 10),
	};
	defer allocator.free(state.buf);
	defer allocator.free(state.nesting);

	return parseInternal(allocator, state, input);
}
```

虽然这不是太难管理，但 `parseInternal` 可能需要其他短生命周期的分配，而这些分配也需要被释放。作为替代，我们可以创建一个 `ArenaAllocator`，它允许我们一次性释放所有分配：

```zig
fn parse(allocator: Allocator, input: []const u8) !Something {
	// create an ArenaAllocator from the supplied allocator
	var arena = std.heap.ArenaAllocator.init(allocator);

	// this will free anything created from this arena
	defer arena.deinit();

	// create an std.mem.Allocator from the arena, this will be
	// the allocator we'll use internally
	const aa = arena.allocator();

	var state = State{
		// we're using aa here!
		.buf = try aa.alloc(u8, 512),

		// we're using aa here!
		.nesting = try aa.alloc(NestType, 10),
	};

	// we're passing aa here, so any we're guaranteed that
	// any other allocation will be in our arena
	return parseInternal(aa, state, input);
}
```

`ArenaAllocator` 接受一个子 `allocator`，在这种情况下是传递给 `init` 的 `allocator`，并创建一个新的 `std.mem.Allocator`。当使用这个新 `allocator` 分配或创建内存时，我们不需要调用 `free` 或 `destroy`。当我们在竞技场`arena`上调用 `deinit` 时，一切都将被释放。实际上，`ArenaAllocator` 的 `free` 和 `destroy` 什么都不做。

> 必须小心使用 `ArenaAllocator`。由于没有办法释放单个分配，您需要确保在合理的内存增长内调用竞技场`arena`的 `deinit`。有趣的是，这种可以是内部的，也可以是外部的。例如在我们上面的框架中，从 `Parser` 内部利用 `ArenaAllocator` 是有意义的，因为状态的生命周期的细节是一个内部问题。

> 像 `ArenaAllocator` 这样具有释放所有先前分配的机制的`allocator` 可以打破每个 `alloc` 应该有一个相应的 `free` 的规则。但是，如果你收到一个 `std.mem.Allocator`，你不应该对底层实现做任何假设。

我们的 `IntList` 不能这样说。它可以用来存储 10 或 1000 万个值。它的寿命可以用毫秒或周来衡量。它无权决定使用哪种类型的分配器。使用 `IntList` 的代码具备这种知识。最初，我们像这样管理我们的 `IntList`：

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var list = try IntList.init(allocator);
defer list.deinit();
```

我们可以选择 `ArenaAllocator` 替代：

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
const aa = arena.allocator();

var list = try IntList.init(aa);

// I'm honestly torn on whether or not we should call list.deinit.
// Technically, we don't have to since we call defer arena.deinit() above.
defer list.deinit();

...
```

由于`IntList`只处理 `std.mem.Allocator`， 因此我们不需要改变其内容。如果 `IntList`内部创建 了自己的竞技场`arena`，那也是可行的。允许在`arena`内部创建`arena`。

作为最后一个简单的例子，我上面提到的 `HTTP` 服务器在在响应上公开了一个 `arena allocator`。一旦发送响应，`arena`就会清空里面的内存。`arena` 的可预测生命周期（从请求开始到请求结束）使其成为一个有效的选择，尤以性能和易用性方面高效。

## 固定缓冲区分配器 FixedBufferAllocator

我们要学习的的最后一个` allocator`的`std.heap.FixedBufferAllocator ` 是一个固定缓冲区分配器，它从我们提供的缓冲区（例如 `[]u8`）中分配内存。这种分配器的两个主要优点是，由于所有可能使用的内存都是提前创建的，所以它的速度非常快。其次，它自然地限制了可以分配多少内存，这种硬性限制也可以看作是一个缺点。

另一个缺点是，`free` 和 `destroy` 只能作用于最后分配/创建的项目（可以将其想象为栈的行为）。也就是说，该分配器允许你释放最后一个分配的内存块，但如果你试图释放非最后分配的内存块，该操作是安全的（不会导致程序崩溃或其他不安全行为），但实际上这种调用不会执行任何操作。

_Note_: 这不是覆盖的问题。`FixedBufferAllocator` 会按照栈的方式进行内存分配和释放。你可以分配新的内存块，但只能按照后进先出（LIFO）的顺序释放它们。

```zig
const std = @import("std");

pub fn main() !void {
	var buf: [150]u8 = undefined;
	var fa = std.heap.FixedBufferAllocator.init(&buf);
	defer fa.reset();

	const allocator = fa.allocator();

	const json = try std.json.stringifyAlloc(allocator, .{
		.this_is = "an anonymous struct",
		.above = true,
		.last_param = "are options",
	}, .{.whitespace = .indent_2});

	std.debug.print("{s}\n", .{json});
}
```

上面的会打印这些结果:

```zig
{
  "this_is": "an anonymous struct",
  "above": true,
  "last_param": "are options"
}
```

但如果我们将 `buf` 更改为 `[120]u8`，你将得到一个内存不足的错误。

对于 `FixedBufferAllocators`（以及在较小使用程度上的 `ArenaAllocators`）而言，一个常见的模式是重置`reset`和重用`reuse`它们。这将释放所有先前的分配，并允许分配器被重用。

---

由于没有默认的分配器，Zig 在分配方面既透明又灵活。`std.mem.Allocator` 接口非常强大，允许专用分配器`allocator`包装更通用的分配器，正如我们在 `ArenaAllocator` 中看到的。

一般来说，堆分配的权责显而易见。多数程序必不可少的一点是**可以分配任意大小和任意生命周期的内存**。

然而由于动态内存带来的问题过于复杂，应该留意其他的替代方案。例如，上面我们使用了 `std.fmt.allocPrint`，而标准库还有一个 `std.fmt.bufPrint`。

两者比较起来，后者接受一个缓冲区`buffer`而不是分配器`allocator`：

```zig
const std = @import("std");

pub fn main() !void {
	const name = "Leto";

	var buf: [100]u8 = undefined;
	const greeting = try std.fmt.bufPrint(&buf, "Hello {s}", .{name});

	std.debug.print("{s}\n", .{greeting});
}
```

这个 API 将内存管理的负担转移给了调用者。如果我们声明的内容比`name`里的字符串内容更长，或者比 `buf`的 100 更小，那我们调用 `bufPrint` 可能会返回 **无剩余空间(NoSpaceLeft)** 这种错误。而在很多场景下，应用程序早已设置了限制。例如，变量`name`内字符串的最大长度。在这些情况下，`bufPrint` 更安全、更快。

动态分配的另一个可能替代方案是将流式数据传输到 `std.io.Writer`中。与我们的分配器接口 `Allocator`一样，`Writer` 是由许多类型实现的接口，例如文件。前面的例子中我们使用了 `stringifyAlloc` 来将 `JSON` 序列化到动态分配的字符串中。我们本可以使用 `stringify`，并提供一个 `Writer`承载这个结果：

```zig
pub fn main() !void {
	const out = std.io.getStdOut();

	try std.json.stringify(.{
		.this_is = "an anonymous struct",
		.above = true,
		.last_param = "are options",
	}, .{.whitespace = .indent_2}, out.writer());
}
```

> 分配器`Allocator`应该作为函数的第一个参数，而写入器`Writer`通常是最后一个参数。ಠ_ಠ

许多情况下，将我们的写入器`Writer`包装在 `std.io.BufferedWriter` 中会带来很好的性能提升。

这些替代方案(buf, writer)的目的并非为了消除内存的所有动态分配。这不可能。替代方案只能在特定情况下才会具备实际意义。

迄今为止，在内存的分配方面有了许多备选方法。从栈帧到通用分配器`GeneralPurposeAllocator`，以及介于两者之间的所有东西，比如静态缓冲区`buffer`、流写入器`streaming writer`和专用分配器，如`FixedBufferAllocators`, `ArenaAllocator`。
