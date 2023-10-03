> 原文地址：https://www.openmymind.net/learning_zig/coding_in_zig/

# 在 Zig 中编程

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

我保证，关于悬挂指针和内存管理的讨论已经结束了。我们所讨论的内容可能还不够清晰或过于抽象。当你有更实际的问题需要解决时，再重新讨论这个问题也不迟。不过，如果你打算编写任何稍具规模（non-trivial）的程序，这几乎肯定是你需要掌握的内容。当你觉得可以的时候，我建议你参考上面这个示例，并自己动手实践一下。引入一个 `UserLookup` 类型来封装我们必须做的所有内存管理。尝试使用 `*User` 代替 `User`，在堆上创建用户，然后像处理键那样释放它们。编写涵盖新结构的测试，使用 `std.testing.allocator` 确保不会泄漏任何内存。
