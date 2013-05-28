# Cartesian.jl

Fast multidimensional iteration for the Julia language.

This package provides a single macro, `@forcartesian`, that currently appears to be the fastest way to get a "multidimensional iterator" in Julia.

## Installation

Install with the package manager, `Pkg.add("Cartesian")`.


## Usage

Here's a simple example:

```julia
using Cartesian

sz = [5,3]
@forcartesian c sz begin
    println(c)
end
```

This generates the following output:
```
[1, 1]
[2, 1]
[3, 1]
[4, 1]
[5, 1]
[1, 2]
[2, 2]
[3, 2]
[4, 2]
[5, 2]
[1, 3]
[2, 3]
[3, 3]
[4, 3]
[5, 3]
```

### How it works

From the simple example above, `@forcartesian` generates a block of code like this:

```julia
if !(isempty(sz) || prod(sz) == 0)
    N = length(sz)
    c = ones(Int, N)
    sz1 = sz[1]
    isdone = false
    while !isdone
        println(c)           # This is whatever code we put inside the "loop"
        if (c[1]+=1) > sz1
            idim = 1
            while c[idim] > sz[idim] && idim < N
                c[idim] = 1
                idim += 1
                c[idim] += 1
            end
            isdone = c[end] > sz[end]
        end
    end
end
```

In tests where `m` and `n` are a few hundred and the loop code is very tight, just `counter += 1`, this is still about 5 times slower than a hand-coded example:
```julia
for j = 1:n
    for i = 1:m
        counter += 1
    end
end
```
However, it's about 4-fold faster than `Grid`'s `Counter`, which until now seemed to be the reigning champion.
Compared to the hand-written loop, the advantage is that you get a vector `c` out of it, which can be used to iterate over any number of dimensions.

Moreover, if you're doing any nontrivial work inside your loop, it's possible that you may not notice much overhead.

Finally, there's a trick that may or may not work for you:
```julia
sz1 = sz[1]
sz[1] = 1
@forcartesian c sz begin
    for i = 1:sz1
        # loop code that uses i anywhere c[1] would have otherwise been used
        # For example,
        println(i, " ", c)
    end
end
```
which generates
```
1 [1, 1]
2 [1, 1]
3 [1, 1]
4 [1, 1]
5 [1, 1]
1 [1, 2]
2 [1, 2]
3 [1, 2]
4 [1, 2]
5 [1, 2]
1 [1, 3]
2 [1, 3]
3 [1, 3]
4 [1, 3]
5 [1, 3]
```
This can be more trouble than it's worth if your loop code really needs to have that first index built in to `c`. However, if `sz1` is not small, and your loop code can _efficiently_ make use of `i` in place of `c[1]`, then in very tight loops this can essentially erase all overhead of multidimensional iteration. However, the following example
```
sz1 = sz[1]
sz[1] = 1
@forcartesian c sz begin
    for i = 1:sz1
        c[1] = i
        counter += 1
    end
end
```
is no more performant than the original. So unless your loop is really trivial, it's very unlikely you'll notice much overhead from `Cartesian`.
