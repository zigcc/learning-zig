> 原文地址：<https://www.openmymind.net/learning_zig/pointers>

# 指针

Zig 不包含垃圾回收器。管理内存的重任由开发者负责。这是一项重大责任，因为它直接影响到应用程序的性能、稳定性和安全性。

我们将从指针开始讨论，这本身就是一个重要的话题，同时也是训练我们从面向内存的角度来看待程序数据的开始。如果你已经对指针、堆分配和悬挂指针了如指掌，那么可以跳过本小节和下一小节，直接阅读[堆内存和分配器](07-heap-memory-and-allocator.md)，这部分内容与 Zig 更为相关。

---

下面的代码创建了一个 `power` 为 100 的用户，然后调用 `levelUp` 函数将用户的 `power` 加一。你能猜到它的输出结果吗？

```zig
const std = @import("std");

pub fn main() void {
	var user = User{
		.id = 1,
		.power = 100,
	};

	// this line has been added
	levelUp(user);
	std.debug.print("User {d} has power of {d}\n", .{user.id, user.power});
}

fn levelUp(user: User) void {
	user.power += 1;
}

pub const User = struct {
	id: u64,
	power: i32,
};
```

那是个不太友善的把戏；代码无法编译：_局部变量从未被修改_。这是指 `main` 函数中的 `user` 变量。一个从未被修改的变量必须声明为 const。你可能会想：但在 `levelUp` 函数中我们确实修改了 `user`，这怎么回事？让我们假设 Zig 编译器弄错了，并试着糊弄它。我们将强制让编译器看到 `user` 确实被修改了：

```zig
const std = @import("std");

pub fn main() void {
	var user = User{
		.id = 1,
		.power = 100,
	};
	user.power += 0;

	// 代码的其余部分保持不变。
```

现在我们在 `levelUp` 中遇到了一个错误：**不能赋值给常量**。我们在第一部分中看到函数参数是常量，因此 `user.power += 1` 是无效的。为了解决这个错误，我们可以将 `levelUp` 函数改为

```zig
fn levelUp(user: User) void {
	var u = user;
	u.power += 1;
}
```

虽然编译成功了，但输出结果却是`User 1 has power of 100`，而我们代码的目的显然是让 `levelUp` 将用户的 `power` 提升到 101。这是怎么回事？

要理解这一点，我们可以将数据与内存联系起来，而变量只是将类型与特定内存位置关联起来的标签。例如，在 `main` 中，我们创建了一个`User`。内存中数据的简单可视化表示如下

```text
user -> ------------ (id)
        |    1     |
        ------------ (power)
        |   100    |
        ------------
```

有两点需要注意：

1. 我们的`user`变量指向结构的起点
2. 字段是按顺序排列的

请记住，我们的`user`也有一个类型。该类型告诉我们 `id` 是一个 64 位整数，`power` 是一个 32 位整数。有了对数据起始位置的引用和类型，编译器就可以将 `user.power` 转换为：访问位置在结构体第 64 位上的一个 32 位整数。这就是变量的威力，它们可以引用内存，并包含以有意义的方式理解和操作内存所需的类型信息。

> 默认情况下，Zig 不保证结构的内存布局。它可以按字母顺序、大小升序或插入填充（padding）某些字段。只要它能正确翻译我们的代码，它就可以为所欲为。这种自由度可以实现某些优化。只有在声明 `packed struct`时，我们才能获得内存布局的有力保证。我们还可以创建一个 `extern struct`，这样可以保证内存布局与 C 应用程序二进制接口 (ABI) 匹配。尽管如此，我们对`user`的可视化还是合理而有用的。

下面是一个稍有不同的可视化效果，其中包括内存地址。这些数据的起始内存地址是我想出来的一个随机地址。这是`user`变量引用的内存地址，也是第一个字段 `id` 的值所在的位置。由于 `id` 是一个 64 位整数，需要 8 字节内存。因此，`power` 必须位于 `$start_address + 8` 上：

```text
user ->   ------------  (id: 1043368d0)
          |    1     |
          ------------  (power: 1043368d8)
          |   100    |
          ------------
```

为了验证这一点，我想介绍一下取地址符运算符：`&`。顾名思义，取地址运算符返回一个变量的地址（它也可以返回一个函数的地址，是不是很神奇？）保留现有的 `User` 定义，试试下面的代码：

```zig
pub fn main() void {
	const user = User{
		.id = 1,
		.power = 100,
	};
	std.debug.print("{*}\n{*}\n{*}\n", .{&user, &user.id, &user.power});
}
```

这段代码输出了`user`、`user.id`、和`user.power`的地址。根据平台等差异，可能会得到不同的输出结果，但都会看到`user`和`user.id`的地址相同，而`user.power`的地址偏移量了 8 个字节。输出的结果如下：

```text
learning.User@1043368d0
u64@1043368d0
i32@1043368d8
```

取地址运算符返回一个指向值的指针。指向值的指针是一种特殊的类型。类型`T`的值的地址是`*T`。因此，如果我们获取 `user` 的地址，就会得到一个 `*User`，即一个指向 `User` 的指针：

```zig
pub fn main() void {
	var user = User{
		.id = 1,
		.power = 100,
	};
	user.power += 0;

	const user_p = &user;
	std.debug.print("{any}\n", .{@TypeOf(user_p)});
}
```

我们最初的目标是通过`levelUp`函数将用户的`power`值增加 1 。我们已经让代码编译通过，但当我们打印`power`时，它仍然是原始值。虽然有点跳跃，但让我们修改代码，在 `main` 和 `levelUp` 中打印 `user`的地址：

```zig
pub fn main() void {
	var user = User{
		.id = 1,
		.power = 100,
	};
	user.power += 0;

	// added this
	std.debug.print("main: {*}\n", .{&user});

	levelUp(user);
	std.debug.print("User {d} has power of {d}\n", .{user.id, user.power});
}

fn levelUp(user: User) void {
	// add this
	std.debug.print("levelUp: {*}\n", .{&user});
	var u = user;
	u.power += 1;
}
```

如果运行这个程序，会得到两个不同的地址。这意味着在 `levelUp` 中被修改的 `user`与 `main` 中的`user`是不同的。这是因为 Zig 传递了一个值的副本。这似乎是一个奇怪的默认行为，但它的好处之一是，函数的调用者可以确保函数不会修改参数（因为它不能）。在很多情况下，有这样的保证是件好事。当然，有时我们希望函数能修改参数，比如 `levelUp`。为此，我们需要 `levelUp` 作用于 `main` 中 `user`，而不是其副本。我们可以通过向函数传递 `user`的地址来实现这一点：

```zig
const std = @import("std");

pub fn main() void {
	var user = User{
		.id = 1,
		.power = 100,
	};

	// no longer needed
	// user.power += 1;

	// user -> &user
	levelUp(&user);
	std.debug.print("User {d} has power of {d}\n", .{user.id, user.power});
}

// User -> *User
fn levelUp(user: *User) void {
	user.power += 1;
}

pub const User = struct {
	id: u64,
	power: i32,
};
```

我们必须做两处改动。首先是用 `user` 的地址（即 `&user` ）来调用 `levelUp`，而不是 `user`。这意味着我们的函数参数不再是 `User`，取而代之的是一个 `*User`，这是我们的第二处改动。

我们不再需要通过 `user.power += 0;` 来强制修改 user 的那个丑陋的技巧了。最初，我们因为 user 是 var 类型而无法让代码编译，编译器告诉我们它从未被修改。我们以为编译器错了，于是通过强制修改来“糊弄”它。但正如我们现在所知道的，在 levelUp 中被修改的 user 是不同的；编译器是正确的。

现在，代码已按预期运行。虽然在函数参数和内存模型方面仍有许多微妙之处，但我们正在取得进展。现在也许是一个好时机来说明一下，除了特定的语法之外，这些都不是 Zig 所独有的。我们在这里探索的模型是最常见的，有些语言可能只是向开发者隐藏了很多细节，因此也就隐藏了灵活性。

## 方法

一般来说，我们会把 `levelUp` 写成 `User`结构的一个方法：

```zig
pub const User = struct {
	id: u64,
	power: i32,

	fn levelUp(user: *User) void {
		user.power += 1;
	}
};
```

这就引出了一个问题：我们如何调用带有指针参数的方法？也许我们必须这样做：`&user.levelUp()`？实际上，只需正常调用即可，即 user.levelUp()。Zig 知道该方法需要一个指针，因此会正确地传递值（通过引用传递）。

我最初选择函数是因为它很明确，因此更容易学习。

## 常量函数参数

我不止一次暗示过，在默认情况下，Zig 会传递一个值的副本（称为 "按值传递"）。很快我们就会发现，实际情况要更微妙一些（提示：嵌套对象的复杂值怎么办？）

即使坚持使用简单类型，事实也是 Zig 可以随心所欲地传递参数，只要它能保证代码的意图不受影响。在我们最初的 `levelUp` 中，参数是一个`User`，Zig 可以传递用户的副本或对 `main.user` 的引用，只要它能保证函数不会对其进行更改即可。(我知道我们最终确实希望它被改变，但通过采用 `User` 类型，我们告诉编译器我们不希望它被改变）。

这种自由度允许 Zig 根据参数类型使用最优策略。像 User 这样的小类型可以通过值传递（即复制），成本较低。较大的类型通过引用传递可能更便宜。只要代码的意图得以保留，Zig 可以使用任何方法。在某种程度上，使用常量函数参数可以做到这一点。

现在你知道函数参数是常量的原因之一了吧。

> 也许你会想，即使与复制一个非常小的结构相比，通过引用传递怎么会更慢呢？我们接下来会更清楚地看到这一点，但要点是，当 `user` 是指针时，执行 `user.power` 会增加一点点开销。编译器必须权衡复制的代价和通过指针间接访问字段的代价。

## 指向指针的指针

我们之前查看了`main`函数中 `user` 的内存结构。现在我们改变了 `levelUp`，那么它的内存会是什么样的呢？

```text
main:
user -> ------------  (id: 1043368d0)  <---
        |    1     |                      |
        ------------  (power: 1043368d8)  |
        |   100    |                      |
        ------------                      |
                                          |
        .............  empty space        |
        .............  or other data      |
                                          |
levelUp:                                  |
user -> -------------  (*User)            |
        | 1043368d0 |----------------------
        -------------
```

在 `levelUp` 中，`user` 是指向 `User` 的指针。它的值是一个地址。当然不是任何地址，而是 `main.user` 的地址。值得明确的是，`levelUp` 中的 `user` 变量代表一个具体的值。这个值恰好是一个地址。而且，它不仅仅是一个地址，还是一个类型，即 `*User`。这一切都非常一致，不管我们讨论的是不是指针：变量将类型信息与地址联系在一起。指针的唯一特殊之处在于，当我们使用点语法时，例如 `user.power`，Zig 知道 `user` 是一个指针，就会自动跟随地址。

> 通过指针访问字段时，有些语言可能会使用不同的运算符。

重要的是要理解，`levelUp`函数中的`user`变量本身存在于内存中的某个地址。就像之前所做的一样，我们可以亲自验证这一点：

```zig
fn levelUp(user: *User) void {
	std.debug.print("{*}\n{*}\n", .{&user, user});
	user.power += 1;
}
```

上面打印了`user`变量引用的地址及其值，这个值就是`main`函数中的`user`的地址。

如果`user`的类型是`*User`，那么`&user`呢？它的类型是`**User`, 或者说是一个指向`User`指针的指针。我可以一直这样做，直到内存溢出！

我们可以使用多级间接指针，但这并不是我们现在所需要的。本节的目的是说明指针并不特殊，它只是一个值，即一个地址和一种类型。

## 嵌套指针

到目前为止，`User` 一直很简单，只包含两个整数。很容易就能想象出它的内存，而且当我们谈论『复制』 时，也不会有任何歧义。但是，如果 User 变得更加复杂并包含一个指针，会发生什么情况呢？

```zig
pub const User = struct {
	id: u64,
	power: i32,
	name: []const u8,
};
```

我们已经添加了`name`，它是一个切片。回想一下，切片由长度和指针组成。如果我们使用名字`Goku`初始化`user`，它在内存中会是什么样子？

```text
user -> -------------  (id: 1043368d0)
        |     1     |
        -------------  (power: 1043368d8)
        |    100    |
        -------------  (name.len: 1043368dc)
        |     4     |
        -------------  (name.ptr: 1043368e4)
  ------| 1182145c0 |
  |     -------------
  |
  |     .............  empty space
  |     .............  or other data
  |
  --->  -------------  (1182145c0)
        |    'G'    |
        -------------
        |    'o'    |
        -------------
        |    'k'    |
        -------------
        |    'u'    |
        -------------
```

新的`name`字段是一个切片，由`len`和`ptr`字段组成。它们与所有其他字段一起按顺序排放。在 64 位平台上，`len`和`ptr`都将是 64 位，即 8 字节。有趣的是`name.ptr`的值：它是指向内存中其他位置的地址。

> 由于我们使用了字符串字面形式，`user.name.ptr` 将指向二进制文件中存储所有常量的区域内的一个特定位置。

通过多层嵌套，类型可以变得比这复杂得多。但无论简单还是复杂，它们的行为都是一样的。具体来说，如果我们回到原来的代码，`levelUp` 接收一个普通的 `User`，Zig 提供一个副本，那么现在有了嵌套指针后，情况会怎样呢？

答案是只会进行浅拷贝。或者像有些人说的那样，只拷贝了变量可立即寻址的内存。这样看来，`levelUp` 可能只会得到一个 `user` 残缺副本，`name` 字段可能是无效的。但请记住，像 `user.name.ptr` 这样的指针是一个值，而这个值是一个地址。它的副本仍然是相同的地址：

```text
main: user ->    -------------  (id: 1043368d0)
                 |     1     |
                 -------------  (power: 1043368d8)
                 |    100    |
                 -------------  (name.len: 1043368dc)
                 |     4     |
                 -------------  (name.ptr: 1043368e4)
                 | 1182145c0 |-------------------------
levelUp: user -> -------------  (id: 1043368ec)       |
                 |     1     |                        |
                 -------------  (power: 1043368f4)    |
                 |    100    |                        |
                 -------------  (name.len: 1043368f8) |
                 |     4     |                        |
                 -------------  (name.ptr: 104336900) |
                 | 1182145c0 |-------------------------
                 -------------                        |
                                                      |
                 .............  empty space           |
                 .............  or other data         |
                                                      |
                 -------------  (1182145c0)        <---
                 |    'G'    |
                 -------------
                 |    'o'    |
                 -------------
                 |    'k'    |
                 -------------
                 |    'u'    |
                 -------------
```

从上面可以看出，浅拷贝是可行的。由于指针的值是一个地址，复制该值意味着我们得到的是相同的地址。这对可变性有重要影响。我们的函数不能更改 `main.user` 中的字段，因为它得到了一个副本，但它可以访问同一个`name`，那么它能更改 `name` 吗？在这种特殊情况下，不行，因为 `name` 是常量。另外，`Goku`是一个字符串字面量，它总是不可变的。不过，只要花点功夫，我们就能明白浅拷贝的含义：

```zig
const std = @import("std");

pub fn main() void {
	var name = [4]u8{'G', 'o', 'k', 'u'};
	const user = User{
		.id = 1,
		.power = 100,
		// slice it, [4]u8 -> []u8
		.name = name[0..],
	};
	levelUp(user);
	std.debug.print("{s}\n", .{user.name});
}

fn levelUp(user: User) void {
	user.name[2] = '!';
}

pub const User = struct {
	id: u64,
	power: i32,
	// []const u8 -> []u8
	name: []u8
};
```

上面的代码会打印出`Go!u`。我们不得不将`name`的类型从`[]const u8`更改为`[]u8`，并且不再使用字符串字面量（它们总是不可变的），而是创建一个数组并对其进行切片。有些人可能会认为这前后不一致。通过值传递可以防止函数改变直接字段，但不能改变指针后面有值的字段。如果我们确实希望 `name` 不可变，就应该将其声明为 `[]const u8` 而不是 `[]u8`。

不同编程语言有不同的实现方式，但许多语言的工作方式与此完全相同（或非常接近）。虽然所有这些看似深奥，但却是日常编程的基础。好消息是，你可以通过简单的示例和片段来掌握这一点；它不会随着系统其他部分复杂性的增加而变得更加复杂。

## 递归结构

有时你需要一个递归结构。在保留现有代码的基础上，我们为 `User` 添加一个可选的 `manager` 字段，类型为 `?User`。同时，我们将创建两个`User`，并将其中一个指定为另一个的管理者：

```zig
const std = @import("std");

pub fn main() void {
	const leto = User{
		.id = 1,
		.power = 9001,
		.manager = null,
	};

	const duncan = User{
		.id = 1,
		.power = 9001,
		.manager = leto,
	};

	std.debug.print("{any}\n{any}", .{leto, duncan});
}

pub const User = struct {
	id: u64,
	power: i32,
	manager: ?User,
};
```

这段代码无法编译：`struct 'learning.User' depends on itself`。这个问题的根本原因是每种类型都必须在编译时确定大小，而这里的递归结构体大小是无法确定的。

我们在添加 `name` 时没有遇到这个问题，尽管 `name`可以有不同的长度。问题不在于值的大小，而在于类型本身的大小。name 是一个切片，即 `[]const u8`，它有一个已知的大小：16 字节，其中 `len` 8 字节，`ptr` 8 字节。

你可能会认为这对任何 `Optional`或 `union` 来说都是个问题。但对于它们来说，最大字段的大小是已知的，这样 Zig 就可以使用它。递归结构没有这样的上限，该结构可以递归一次、两次或数百万次。这个次数会因`User`而异，在编译时是不知道的。

我们通过 `name` 看到了答案：使用指针。指针总是占用 `usize` 字节。在 64 位平台上，指针占用 8 个字节。就像`Goku`并没有与 `user`一起存储一样，使用指针意味着我们的`manager`不再与`user`的内存布局绑定。

```zig
const std = @import("std");

pub fn main() void {
	const leto = User{
		.id = 1,
		.power = 9001,
		.manager = null,
	};

	const duncan = User{
		.id = 1,
		.power = 9001,
		// changed from leto -> &leto
		.manager = &leto,
	};

	std.debug.print("{any}\n{any}", .{leto, duncan});
}

pub const User = struct {
	id: u64,
	power: i32,
	// changed from ?const User -> ?*const User
	manager: ?*const User,
};
```

你可能永远不需要递归结构，但这里并不是介绍数据建模的教程，因此不过多进行介绍。这里主要是想讨论指针和内存模型，以及更好地理解编译器的意图。

---

很多开发人员都在为指针而苦恼，因为指针总是难以捉摸。它们给人的感觉不像整数、字符串或`User`那样具体。虽然你现在不必完全理解这些概念，但掌握它们是值得的，而且不仅仅是为了 Zig。这些细节可能隐藏在 Ruby、Python 和 JavaScript 等语言中，其次是 C#、Java 和 Go。它影响着你如何编写代码以及代码如何运行。因此，请慢慢来，多看示例，添加调试打印语句来查看变量及其地址。你探索得越多，就会越清楚。
