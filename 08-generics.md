> 原文地址：<https://www.openmymind.net/learning_zig/generics>

# 泛型 Generics

在上一小节中，我们创建了一个名为 `IntList` 的动态数组。该数据结构的目标是保存数目不定的数值。虽然我们使用的算法适用于任何类型的数据，但我们的实现与 i64 值绑定。这就需要使用泛型，其目的是从特定类型中抽象出算法和数据结构。

许多语言使用特殊的语法和特定的泛型规则来实现泛型。而在 Zig 中，泛型并不是一种特定的功能，而更多地体现了语言的能力。具体来说，泛型利用了 Zig 强大的编译时元编程功能。

我们先来看一个简单的例子，以了解我们的想法：

```zig
const std = @import("std");

pub fn main() !void {
	var arr: IntArray(3) = undefined;
	arr[0] = 1;
	arr[1] = 10;
	arr[2] = 100;
	std.debug.print("{any}\n", .{arr});
}

fn IntArray(comptime length: usize) type {
	return [length]i64;
}
```

上述代码会打印了 `{ 1, 10, 100 }`。有趣的是，我们有一个返回类型的函数（因此函数是 PascalCase）。这也不是普通的类型，而是由函数参数动态确定的类型。这段代码之所以能运行，是因为我们将 `length` 声明为 `comptime`。也就是说，我们要求任何调用 `IntArray` 的人传递一个编译时已知的长度参数。这是必要的，因为我们的函数返回一个类型，而类型必须始终是编译时已知的。

函数可以返回任何类型，而不仅仅是基本类型和数组。例如，只需稍作改动，我们就可以让函数返回一个结构体：

```zig
const std = @import("std");

pub fn main() !void {
	var arr: IntArray(3) = undefined;
	arr.items[0] = 1;
	arr.items[1] = 10;
	arr.items[2] = 100;
	std.debug.print("{any}\n", .{arr.items});
}

fn IntArray(comptime length: usize) type {
	return struct {
		items: [length]i64,
	};
}
```

也许看起来很奇怪，但 `arr` 的类型确实是 `IntArray(3)`。它和其他类型一样，是一个类型，而 `arr` 和其他值一样，是一个值。如果我们调用 `IntArray(7)`，那就是另一种类型了。也许我们可以让事情变得更简洁：

```zig
const std = @import("std");

pub fn main() !void {
	var arr = IntArray(3).init();
	arr.items[0] = 1;
	arr.items[1] = 10;
	arr.items[2] = 100;
	std.debug.print("{any}\n", .{arr.items});
}

fn IntArray(comptime length: usize) type {
	return struct {
		items: [length]i64,

		fn init() IntArray(length) {
			return .{
				.items = undefined,
			};
		}
	};
}
```

乍一看，这可能并不整齐。但除了匿名和嵌套在一个函数中之外，我们的结构看起来就像我们目前看到的其他结构一样。它有字段，有函数。你知道人们常说『如果它看起来像一只鸭子，那么就就是一只鸭子』。那么，这个结构看起来、游起来和叫起来都像一个正常的结构，因为它本身就是一个结构体。

希望上面这个示例能让你熟悉返回类型的函数和相应的语法。为了得到一个更典型的通用结构，我们需要做最后一个改动：我们的函数必须接受一个类型。实际上，这只是一个很小的改动，但 `type` 会比 `usize` 更抽象，所以我们慢慢来。让我们做一个大改动，修改之前的 `IntList`，使其能与任何类型一起工作。我们先从基本结构开始：

```zig
fn List(comptime T: type) type {
	return struct {
		pos: usize,
		items: []T,
		allocator: Allocator,

		fn init(allocator: Allocator) !List(T) {
			return .{
				.pos = 0,
				.allocator = allocator,
				.items = try allocator.alloc(T, 4),
			};
		}
	}
};
```

上面的结构与 `IntList` 几乎完全相同，只是 `i64` 被替换成了 `T`。我们本可以叫它 `item_type`。不过，按照 Zig 的命名约定，`type` 类型的变量使用 `PascalCase` 风格。

> 无论好坏，使用单个字母表示类型参数的历史都比 Zig 要悠久得多。在大多数语言中，T 是常用的默认值，但你也会看到根据具体语境而变化的情况，例如哈希映射使用 K 和 V 来表示键和值参数类型。

如果你对上述代码还有疑问，可以着重看使用 T 的两个地方：`items：[]T` 和 `allocator.alloc(T, 4)`。当我们要使用这个通用类型时，我们将使用

```zig
var list = try List(u32).init(allocator);
```

编译代码时，编译器会通过查找每个 `T` 并将其替换为 `u32` 来创建一个新类型。如果我们再次使用 `List(u32)`，编译器将重新使用之前创建的类型。如果我们为 `T` 指定一个新值，例如 `List(bool)` 或 `List(User)`，就会创建与之对应的新类型。

为了完成通用的 List，我们可以复制并粘贴 `IntList` 代码的其余部分，然后用 `T` 替换 `i64`：

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main() !void {
	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	const allocator = gpa.allocator();

	var list = try List(u32).init(allocator);
	defer list.deinit();

	for (0..10) |i| {
		try list.add(@intCast(i));
	}

	std.debug.print("{any}\n", .{list.items[0..list.pos]});
}

fn List(comptime T: type) type {
	return struct {
		pos: usize,
		items: []T,
		allocator: Allocator,

		fn init(allocator: Allocator) !List(T) {
			return .{
				.pos = 0,
				.allocator = allocator,
				.items = try allocator.alloc(T, 4),
			};
		}

		fn deinit(self: List(T)) void {
			self.allocator.free(self.items);
		}

		fn add(self: *List(T), value: T) !void {
			const pos = self.pos;
			const len = self.items.len;

			if (pos == len) {
				// we've run out of space
				// create a new slice that's twice as large
				var larger = try self.allocator.alloc(T, len * 2);

				// copy the items we previously added to our new space
				@memcpy(larger[0..len], self.items);

				self.allocator.free(self.items);

				self.items = larger;
			}

			self.items[pos] = value;
			self.pos = pos + 1;
		}
	};
}
```

我们的 `init` 函数返回一个 `List(T)`，我们的 `deinit` 和 `add` 函数使用 `List(T)` 和 `*List(T)` 作为参数。在我们的这个简单的示例中，这样做没有问题，但对于大型数据结构，编写完整的通用名称可能会变得有点繁琐，尤其是当我们有多个类型参数时（例如，散列映射的键和值需要使用不同的类型）。`@This()` 内置函数会返回它被调用时的最内层类型。一般来说，我们会这样定义 `List(T)`：

```zig
fn List(comptime T: type) type {
	return struct {
		pos: usize,
		items: []T,
		allocator: Allocator,

		// Added
		const Self = @This();

		fn init(allocator: Allocator) !Self {
			// ... same code
		}

		fn deinit(self: Self) void {
			// .. same code
		}

		fn add(self: *Self, value: T) !void {
			// .. same code
		}
	};
}
```

`Self` 并不是一个特殊的名称，它只是一个变量，而且是 `PascalCase` 风格，因为它的值是一种类型。我们可以在之前使用 `List(T)` 的地方用 `Self` 来替代。

---

我们可以创建更复杂的示例，使用多种类型参数和更先进的算法。但归根结底，泛型代码的关键点与上述简单示例相差无几。在下一部分，我们将在研究标准库中的 `ArrayList(T)` 和 `StringHashMap(V)` 时再次讨论泛型。
