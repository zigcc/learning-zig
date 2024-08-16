> 原文地址：<https://www.openmymind.net/learning_zig/heap_memory>

# 堆和分配器 Heap & Allocator

迄今为止，我们所接触到的一切都有个限制，需要预先知道大小。数组总是有一个编译时已知的长度（事实上，长度是类型的一部分）。我们所有的字符串都是字符串字面量，其长度在编译时是已知的。

此外，我们所见过的两种内存管理策略，即**全局数据**和**调用栈**，虽然简单高效，但都有局限性。这两种策略都无法处理动态大小的数据，而且在数据生命周期方面都很固定。

本部分分为两个主题。第一个主题是第三个内存区域--堆的总体概述。另一个主题是 Zig 直接而独特的堆内存管理方法。即使你熟悉堆内存，比如使用过 C 语言的 `malloc`，你也会希望阅读第一部分，因为它是 Zig 特有的。

## 堆

堆是我们可以使用的第三个也是最后一个内存区域。与全局数据和调用栈相比，堆有点像蛮荒之地：什么都可以使用。具体来说，在堆中，我们可以在运行时创建大小已知的内存，并完全控制其生命周期。

调用堆栈之所以令人惊叹，是因为它管理数据的方式简单且可预测（通过压入和弹出堆栈帧）。这一优点同时也是缺点：数据的生命周期与它在调用堆栈中的位置息息相关。堆则恰恰相反。它没有内置的生命周期，因此我们的数据可长可短。这个优点也是它的缺点：它没有内置的生命周期，所以如果我们不释放数据，就没有人会释放。

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
	try std.posix.getrandom(std.mem.asBytes(&seed));
	var random = std.Random.DefaultPrng.init(seed);
	return random.random().uintAtMost(u8, 5) + 5;
}
```

我们稍后将讨论 Zig 的分配器，目前需要知道的是分配器是 `std.mem.Allocator` 类型。我们使用了它的两种方法：`alloc` 和 `free`。分配内存可能出错，故我们用 `try` 捕获调用 `allocator.alloc` 产生的错误。目前唯一可能的错误是 `OutOfMemory`。其参数主要告诉我们它是如何工作的：它需要一个类型（T）和一个计数，成功时返回一个类型为 `[]T` 的切片。它分配发生在运行时期间，必须如此，因为我们的计数只在运行时才可知。

一般来说，每次 `alloc` 都会有相应的 `free`。`alloc`分配内存，`free`释放内存。不要让这段简单的代码限制了你的想象力。这种 `try alloc` + `defer free` 的模式很常见，这是有原因的：在我们分配内存的地方附近释放相对来说是万无一失的。但同样常见的是在一个地方分配，而在另一个地方释放。正如我们之前所说，堆没有内置的生命周期管理。你可以在 HTTP 处理程序中分配内存，然后在后台线程中释放，这是代码中两个完全独立的部分。

## defer 和 errdefer

说句题外话，上面的代码介绍了一个新的语言特性：`defer`，它在退出作用域时执行给定的代码。『作用域退出』包括到达作用域的结尾或从作用域返回。严格来说， `defer` 与分配器或内存管理并无严格关系；你可以用它来执行任何代码。但上述用法很常见。

Zig 的 `defer` 类似于 Go 的 `defer`，但存在一个主要区别。在 Zig 中，`defer` 将在其包含作用域的末尾运行。在 Go 中，`defer` 是在包含函数的末尾运行。除非你是 Go 开发人员，否则 Zig 的做法可能更不令人惊讶。

与`defer` 相似的是 `errdefer`，它作用与之类似，是在退出作用域时执行给定的代码，但只在返回错误时执行。在进行更复杂的设置时，如果因为出错而不得不撤销之前的分配，这将非常有用。

以下示例在复杂性上有所增加。它展示了 `errdefer` 和一个常见的模式，即在 `init` 函数中分配内存，并在 `deinit` 中释放：

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

这段代码主要突显两件事：

1. `errdefer` 的作用。在正常情况下，`player` 在 `init` 分配，在 `deinit` 释放。但有一种边缘情况，即 `history` 初始化失败。在这种情况下，我们需要撤销 `players` 的分配。
2. 我们动态分配的两个切片（`players` 和 `history`）的生命周期是基于我们的应用程序逻辑的。没有任何规则规定何时必须调用 `deinit` 或由谁调用。这是件好事，因为它为我们提供了任意的生命周期，但也存在缺点，就是如果从未调用 `deinit` 或调用 `deinit` 超过一次，就会出现混乱和错误。

> `init` 和 `deinit` 的名字并不特殊。它们只是 Zig 标准库使用的，也是社区采纳的名称。在某些情况下，包括在标准库中，会使用 `open` 和 `close`，或其他更适当的名称。

## 双重释放和内存泄漏

上面提到过，没有规则规定什么时候必须释放什么东西。但事实并非如此，还是有一些重要规则，只是它们不是强制的，需要你自己格外小心。

第一条规则是不可释放同一内存两次。

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

可以预见到，最后一行代码不会被打印出来。这是因为我们释放了相同的内存两次。这被称为双重释放，是无效的。要避免这种情况似乎很简单，但在具有复杂生命周期的大型项目中，却很难发现。

第二条规则是，无法释放没有引用的内存。这听起来似乎很明显，但谁负责释放内存并不总是很清楚。下面的代码声明了一个转小写的函数：

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

上面的代码没问题。但以下用法不是:

```zig
// 对于这个特定的代码，我们应该使用 std.ascii.eqlIgnoreCase
fn isSpecial(allocator: Allocator, name: [] const u8) !bool {
	const lower = try allocLower(allocator, name);
	return std.mem.eql(u8, lower, "admin");
}
```

这是内存泄漏。`allocLower` 中创建的内存永远不会被释放。不仅如此，一旦 `isSpecial` 返回，这块内存就永远无法释放。在有垃圾收集器的语言中，当数据变得无法访问时，垃圾收集器最终会释放无用的内存。

但在上面的代码中，一旦 `isSpecial` 返回，我们就失去了对已分配内存的唯一引用，即 `lower` 变量。而直到我们的进程退出后，这块内存块才会释放。我们的函数可能只会泄漏几个字节，但如果它是一个长时间运行的进程，并且重复调用该函数，未被释放的内存块就会逐渐累积起来，最终会耗尽所有内存。

至少在双重释放的情况下，我们的程序会遭遇严重崩溃。内存泄漏可能很隐蔽。不仅仅是根本原因难以确定。真正的小泄漏或不常执行的代码中的泄漏甚至很难被发现。这是一个很常见的问题，Zig 提供了帮助，我们将在讨论分配器时看到。

## 创建与销毁

`std.mem.Allocator`的`alloc`方法会返回一个切片，其长度为传递的第二个参数。如果想要单个值，可以使用 `create` 和 `destroy` 而不是 `alloc` 和 `free`。

前面几部分在学习指针时，我们创建了 `User` 并尝试增强它的功能。下面是基于堆的版本：

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

`create` 方法接受一个参数，类型（T）。它返回指向该类型的指针或一个错误，即 `!*T`。也许你想知道，如果我们创建了`User`, 但没有设置 `id`, `power`时会发生什么。这就像将这些字段设置为未定义（undefined），其行为也是未定义的。意即，属性没有初始化时，在访问未初始化的变量，行为也是未定义，这意味着程序可能会出现不可预测的行为，比如返回错误的值、崩溃等问题。

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

在这种情况下，返回一个 `User`可能更有意义。但有时你会希望函数返回一个指向它所创建的东西的指针。当你想让生命周期不受调用栈的限制时，你就会这样做。为了解决上面的悬空指针问题，我们可以使用`create` 方法：

```zig
// 我们的返回类型改变了，因为 init 现在可以失败了
// *User -> !*User
fn init(allocator: std.mem.Allocator, id: u64, power: i32) !*User{
	const user = try allocator.create(User);
	user.* = .{
		.id = id,
		.power = power,
	};
	return user;
}
```

我引入了新的语法，`user.* = .{...}`。这有点奇怪，我不是很喜欢它，但你会看到它。右侧是你已经见过的内容：它是一个带有类型推导的结构体初始化器。我们可以明确地使用 `user.* = User{...}`。左侧的 `user.*` 是我们如何去引用该指针所指向的变量。`&` 接受一个 T 类型并给我们一个 `*T` 类型。`.*` 是相反的操作，应用于一个 `*T` 类型的值时，它给我们一个 T 类型。即，`&`获取地址，`.*`获取值。

请记住，`create` 返回一个 `!*User`，所以我们的 `user` 是 `*User` 类型。

## 分配器 Allocator

Zig 的核心原则之一是无隐藏内存分配。根据你的背景，这听起来可能并不特别。但这与 C 语言中使用标准库的 malloc 函数分配内存的做法形成了鲜明的对比。在 C 语言中，如果你想知道一个函数是否分配内存，你需要阅读源代码并查找对 malloc 的调用。

Zig 没有默认的分配器。在上述所有示例中，分配内存的函数都使用了一个 `std.mem.Allocator` 参数。按照惯例，这通常是第一个参数。所有 Zig 标准库和大多数第三方库都要求调用者在分配内存时提供一个分配器。

这种显式性有两种形式。在简单的情况下，每次函数调用都会提供分配器。这样的例子很多，但 `std.fmt.allocPrint` 是你迟早会用到的一个。它类似于我们一直在使用的 std.debug.print，只是分配并返回一个字符串，而不是将其写入 `stderr`：

```zig
const say = std.fmt.allocPrint(allocator, "It's over {d}!!!", .{user.power});
defer allocator.free(say);
```

另一种形式是将 `Allocator` 传递给 `init` ，然后由对象**内部使用**。这种方法不那么明确，因为你已经给了对象一个分配器来使用，但你不知道哪些方法调用将实际分配。对于长寿命对象来说，这种方法更实用。

注入分配器的优势不仅在于显式，还在于灵活性。`std.mem.Allocator` 是一个接口，提供了 `alloc`、`free`、`create` 和 `destroy` 函数以及其他一些函数。到目前为止，我们只看到了 `std.heap.GeneralPurposeAllocator`，但标准库或第三方库中还有其他实现。

> Zig 没有用于创建接口的语法糖。一种类似于接口的模式是带标签的联合（tagged unions），不过与真正的接口相比，这种模式相对受限。整个标准库中也探索了一些其他模式，例如 `std.mem.Allocator`。本指南不探讨这些接口模式。

如果你正在构建一个库，那么最好接受一个 `std.mem.Allocator`，然后让库的用户决定使用哪种分配器实现。否则，你就需要选择正确的分配器，正如我们将看到的，这些分配器并不相互排斥。在你的程序中创建不同的分配器可能有很好的理由。

## 通用分配器 GeneralPurposeAllocator

顾名思义，`std.heap.GeneralPurposeAllocator` 是一种通用的、线程安全的分配器，可以作为应用程序的主分配器。对于许多程序来说，这是唯一需要的分配器。程序启动时，会创建一个分配器并传递给需要它的函数。我的 HTTP 服务器库中的示例代码就是一个很好的例子：

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

我们创建了 `GeneralPurposeAllocator`，从中获取一个 `std.mem.Allocator` 并将其传递给 HTTP 服务器的 `init` 函数。在一个更复杂的项目中，声明的变量`allocator` 可能会被传递给代码的多个部分，每个部分可能都会将其传递给自己的函数、对象和依赖。

你可能会注意到，创建 `gpa` 的语法有点奇怪。什么是`GeneralPurposeAllocator(.{}){}`？

我们之前见过这些东西，只是现在都混合了起来。`std.heap.GeneralPurposeAllocator` 是一个函数，由于它使用的是 `PascalCase`（帕斯卡命名法），我们知道它返回一个类型。（下一部分会更多讨论泛型）。也许这个更明确的版本会更容易解读：

```zig
const T = std.heap.GeneralPurposeAllocator(.{});
var gpa = T{};

// 等同于:

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
```

也许你仍然不太确信 `.{}` 的含义。我们之前也见过它：`.{}` 是一个具有隐式类型的结构体初始化器。

类型是什么，字段在哪里？类型其实是 `std.heap.general_purpose_allocator.Config`，但它并没有直接暴露出来，这也是我们没有显式给出类型的原因之一。没有设置字段是因为 Config 结构定义了默认值，我们将使用默认值。这是配置、选项的中常见的模式。事实上，我们在下面几行向 `init` 传递 `.{.port = 5882}` 时又看到了这种情况。在本例中，除了端口这一个字段外，我们都使用了默认值。

## std.testing.allocator

希望当我们谈到内存泄漏时，你已经足够烦恼，而当我提到 Zig 可以提供帮助时，你肯定渴望了解更多这方面内容。这种帮助来自 `std.testing.allocator`，它是一个 `std.mem.Allocator` 实现。目前，它基于通用分配器（GeneralPurposeAllocator）实现，并与 Zig 的测试运行器进行了集成，但这只是实现细节。重要的是，如果我们在测试中使用 `std.testing.allocator`，就能捕捉到大部分内存泄漏。

你可能已经熟悉了动态数组（通常称为 ArrayLists）。在许多动态编程语言中，所有数组都是动态的。动态数组支持可变数量的元素。Zig 有一个通用 ArrayList，但我们将创建一个专门用于保存整数的 ArrayList，并演示泄漏检测：

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

有趣的部分发生在 `add` 函数里，当 `pos == len`时，表明我们已经填满了当前数组，并且需要创建一个更大的数组。我们可以像这样使用`IntList`：

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

代码运行并打印出正确的结果。不过，尽管我们在 `list` 上调用了 `deinit`，还是出现了内存泄漏。如果你没有发现也没关系，因为我们要写一个测试，并使用 `std.testing.allocator`：

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

> `@as` 是一个执行类型强制的内置函数。如果你好奇什么我们的测试要用到这么多，那么你不是唯一一个。从技术上讲，这是因为第二个参数，即 `actual`，被强制为第一个参数，即 `expected`。在上面的例子中，我们的期望值都是 `comptime_int`，这就造成了问题。包括我在内的许多人都认为这是一种奇怪而不幸的行为。

如果你按照步骤操作，把测试放在 `IntList` 和 `main` 的同一个文件中。Zig 的测试通常写在同一个文件中，经常在它们测试的代码附近。当使用 `zig test learning.zig` 运行测试时，我们会得到了一个令人惊喜的失败：

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

此处有多个内存泄漏。幸运的是，测试分配器准确地告诉我们泄漏的内存是在哪里分配的。你现在能发现泄漏了吗？如果没有，请记住，通常情况下，每个 `alloc` 都应该有一个相应的 `free`。我们的代码在 `deinit` 中调用 `free` 一次。然而在 `init` 中 `alloc` 被调用一次，每次调用 `add` 并需要更多空间时也会调用 `alloc`。每次我们 `alloc` 更多空间时，都需要 `free` 之前的 `self.items`。

```zig
// 现有的代码
var larger = try self.allocator.alloc(i64, len * 2);
@memcpy(larger[0..len], self.items);

// 添加的代码
// 释放先前分配的内存
self.allocator.free(self.items);
```

将`items`复制到我们的 `larger` 切片中后, 添加最后一行`free`可以解决泄漏的问题。如果运行 `zig test learning.zig`，便不会再有错误。

## ArenaAllocator

通用分配器（GeneralPurposeAllocator）是一个合理的默认设置，因为它在所有可能的情况下都能很好地工作。但在程序中，你可能会遇到一些固定场景，使用更专业的分配器可能会更合适。其中一个例子就是需要在处理完成后丢弃的短期状态。解析器（Parser）通常就有这样的需求。一个 `parse` 函数的基本轮廓可能是这样的

```zig
fn parse(allocator: Allocator, input: []const u8) !Something {
	const state = State{
		.buf = try allocator.alloc(u8, 512),
		.nesting = try allocator.alloc(NestType, 10),
	};
	defer allocator.free(state.buf);
	defer allocator.free(state.nesting);

	return parseInternal(allocator, state, input);
}
```

虽然这并不难管理，但 `parseInternal` 内可能还会申请临时内存，当然这些内存也需要释放。作为替代方案，我们可以创建一个 `ArenaAllocator`，一次性释放所有分配：

```zig
fn parse(allocator: Allocator, input: []const u8) !Something {
	// create an ArenaAllocator from the supplied allocator
	var arena = std.heap.ArenaAllocator.init(allocator);

	// this will free anything created from this arena
	defer arena.deinit();

	// create an std.mem.Allocator from the arena, this will be
	// the allocator we'll use internally
	const aa = arena.allocator();

	const state = State{
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

`ArenaAllocator` 接收一个子分配器（在本例中是传入 `init` 的分配器），然后创建一个新的 `std.mem.Allocator`。当使用这个新的分配器分配或创建内存时，我们不需要调用 free 或 destroy。当我们调用 `arena.deinit` 时，会一次性释放所有该分配器申请的内存。事实上，`ArenaAllocator` 的 `free` 和 `destroy` 什么也不做。

必须谨慎使用 `ArenaAllocator`。由于无法释放单个分配，因此需要确保 `ArenaAllocator` 的 `deinit` 会在合理的内存增长范围内被调用。有趣的是，这种知识可以是内部的，也可以是外部的。例如，在上述代码中，由于状态生命周期的细节属于内部事务，因此在解析器中利用 `ArenaAllocator` 是合理的。

> 像 `ArenaAllocator`这样的具有一次性释放所有申请内存的分配器，会破坏每一次 `alloc` 都应该有相应 `free` 的规则。不过，如果你收到的是一个 `std.mem.Allocator`，就不应对其底层实现做任何假设。

我们的 `IntList` 却不是这样。它可以用来存储 10 个或 1000 万个值。它的生命周期可以以毫秒为单位，也可以以周为单位。它无法决定使用哪种类型的分配器。使用 IntList 的代码才有这种知识。最初，我们是这样管理 `IntList` 的：

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

// 说实话，我很纠结是否应该调用 list.deinit。
// 从技术上讲，我们不必这样做，因为我们在上面调用了 defer arena.deinit()。

defer list.deinit();

...
```

由于 `IntList` 接受的参数是 `std.mem.Allocator`， 因此我们不需要做什么改变。如果 `IntList`内部创建了自己的 `ArenaAllocator`，那也是可行的。允许在`ArenaAllocator`内部创建`ArenaAllocator`。

最后举个简单的例子，我上面提到的 HTTP 服务器在响应中暴露了一个 `ArenaAllocator`。一旦发送了响应，它就会被清空。由于`ArenaAllocator`的生命周期可以预测（从请求开始到请求结束），因此它是一种高效的选择。就性能和易用性而言，它都是高效的。

## 固定缓冲区分配器 FixedBufferAllocator

我们要讨论的最后一个分配器是 `std.heap.FixedBufferAllocator`，它可以从我们提供的缓冲区（即 `[]u8`）中分配内存。这种分配器有两大好处。首先，由于所有可能使用的内存都是预先创建的，因此速度很快。其次，它自然而然地限制了可分配内存的数量。这一硬性限制也可以看作是一个缺点。另一个缺点是，`free` 和 `destroy` 只对最后分配/创建的项目有效（想想堆栈）。调用释放非最后分配的内存是安全的，但不会有任何作用。

> 译者注：这不是覆盖的问题。`FixedBufferAllocator` 会按照栈的方式进行内存分配和释放。你可以分配新的内存块，但只能按照后进先出（LIFO）的顺序释放它们。

```zig
const std = @import("std");

pub fn main() !void {
	var buf: [150]u8 = undefined;
	var fa = std.heap.FixedBufferAllocator.init(&buf);

	// this will free all memory allocate with this allocator
	defer fa.reset();

	const allocator = fa.allocator();

	const json = try std.json.stringifyAlloc(allocator, .{
		.this_is = "an anonymous struct",
		.above = true,
		.last_param = "are options",
	}, .{.whitespace = .indent_2});

	// We can free this allocation, but since we know that our allocator is
	// a FixedBufferAllocator, we can rely on the above `defer fa.reset()`
	defer allocator.free(json);

	std.debug.print("{s}\n", .{json});
}
```

输出内容：

```zig
{
  "this_is": "an anonymous struct",
  "above": true,
  "last_param": "are options"
}
```

但如果将 `buf` 更改为 `[120]u8`，将得到一个内存不足的错误。

固定缓冲区分配器（FixedBufferAllocators）的常见模式是 `reset` 并重复使用，竞技场分配器（ArenaAllocators）也是如此。这将释放所有先前的分配，并允许重新使用分配器。

---

由于没有默认的分配器，Zig 在分配方面既透明又灵活。`std.mem.Allocator`接口非常强大，它允许专门的分配器封装更通用的分配器，正如我们在`ArenaAllocator`中看到的那样。

更广泛地说，我们希望堆分配的强大功能和相关责任是显而易见的。对于大多数程序来说，分配任意大小、任意生命周期的内存的能力是必不可少的。

然而，由于动态内存带来的复杂性，你应该注意寻找替代方案。例如，上面我们使用了 `std.fmt.allocPrint`，但标准库中还有一个 `std.fmt.bufPrint`。后者使用的是缓冲区而不是分配器：

```zig
const std = @import("std");

pub fn main() !void {
	const name = "Leto";

	var buf: [100]u8 = undefined;
	const greeting = try std.fmt.bufPrint(&buf, "Hello {s}", .{name});

	std.debug.print("{s}\n", .{greeting});
}
```

该 API 将内存管理的负担转移给了调用者。如果名称较长或 `buf` 较小，`bufPrint` 可能会返回 `NoSpaceLeft` 的错误。但在很多情况下，应用程序都有已知的限制，例如名称的最大长度。在这种情况下，`bufPrint` 更安全、更快速。

动态分配的另一个可行替代方案是将数据流传输到 `std.io.Writer`。与我们的 `Allocator` 一样，`Writer` 也是被许多具体类型实现的接口。上面，我们使用 `stringifyAlloc` 将 JSON 序列化为动态分配的字符串。我们本可以使用 `stringify` 将其写入到一个 Writer 中：

```zig
const std = @import("std");

pub fn main() !void {
	const out = std.io.getStdOut();

	try std.json.stringify(.{
		.this_is = "an anonymous struct",
		.above = true,
		.last_param = "are options",
	}, .{.whitespace = .indent_2}, out.writer());
}
```

> `Allocator`通常是函数的第一个参数，而 `Writer`通常是最后一个参数。ಠ_ಠ

在很多情况下，用 `std.io.BufferedWriter` 封装我们的 `Writer` 会大大提高性能。

我们的目标并不是消除所有动态分配。这行不通，因为这些替代方案只有在特定情况下才有意义。但现在你有了很多选择。从堆栈到通用分配器，以及所有介于两者之间的东西，比如静态缓冲区、流式 `Writer` 和专用分配器。
