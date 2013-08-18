# Cartesian.jl

Fast multidimensional iteration for the Julia language.

This package provides macros that currently appear to be the fastest way to implement several multidimensional algorithms in Julia.

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

And here's a demonstration of the performance improvements one can get with another macro, `@forarrays`:
```
A = rand(1000,1001,50);
X = zeros(900,840,53);
sA = sub(A, 7:800, 50:513, 2:49);
sX = sub(X, 12+(1:size(sA,1)), 3+(1:size(sA,2)), 4+(1:size(sA,3)));

julia> copy!(sX, sA);

julia> X1 = copy(X);

julia> @time copy!(sX, sA);
elapsed time: 15.947416695 seconds (3738479504 bytes allocated)

julia> fill!(X, 0);

julia> using Cartesian

julia> import Base.copy!

julia> for N = 1:5
           @eval begin
               function copy!{R,S}(dest::AbstractArray{R,$N}, src::AbstractArray{S,$N})
                   @forarrays $N o i dest src begin
                       parent(dest)[odest] = parent(src)[osrc]
                   end
                   return dest
               end
           end
       end

julia> copy!(sX, sA);

julia> X == X1
true

julia> @time copy!(sX, sA);
elapsed time: 0.175267421 seconds (2512 bytes allocated)
```
In this case, it's 100 times faster and far more memory efficient.


With `@forarrays`, the arguments appear in the following order:
- `N`, the dimensionality. This must be an *integer*, not a symbol, which is why
we put this in an `@eval` loop. See `test/tests.jl` for an example of how to
create a wrapper for arbitrary dimensionality.
- `o`, the prefix for the linear-indexing (offset) variable. Each array
(mentioned later) will have its own offset variable defined (see `odest` and
`osrc` in the code snippet above). Note that for `SubArray`s, these are relative
to the *parent* array, which is why the indexing operations inside the loop are
written as `parent(A)[o]`.
- `i`, the prefix for the coordinate variables. In three dimensions there will
be 3 such variables created, `i1`, `i2`, and `i3`.
- A list of the arrays for which you'd like to create offset variables
- Last, the expression you want in the inner loop (inside the `begin..end`).

There's also a variant, `@forrangearrays`, that lets you supply a subset of the coordinate range:
```
@forrangearrays 3 o i d->2:size(A,d)-1 A begin
    ...
end
```
would skip the edges of `A`.

These macros also create some additional variables, e.g., `strideA3`, which can be useful for addressing neighboring points. See below for details.

The most flexible of these related macros is `@forindexes`, which can be used like this:
```
indexes = Vector{Int}[[3,4,5,1,2],[5,3,1,6,4,2]]
A = zeros(5,6)
k = 1
@forindexes 2 o i indexes A begin
    A[oA] = k
    k += 1
end

julia> A
5x6 Float64 Array:
 14.0  29.0   9.0  24.0  4.0  19.0
 15.0  30.0  10.0  25.0  5.0  20.0
 11.0  26.0   6.0  21.0  1.0  16.0
 12.0  27.0   7.0  22.0  2.0  17.0
 13.0  28.0   8.0  23.0  3.0  18.0
```
Note that this example is the equivalent of `A[indexes[1],indexes[2]] = 1:30`, but in general you can use `@forindexes` in situations in which you'd rather not have to allocate the right-hand side (or any other temporaries).

The general syntax is the following:
```
@forindexes N o i indexesA A indexesB B ... begin
    expr
end
```
If you want this to be safe for `SubArray`s, you should do something like this:
```
ind = parentsubindexes(A)
@forindexes $N o i ind A begin
    parent(A)[oA] = val
end
```
This properly handles `slice`s, whereas
```
ind = parentindexes(A)
P = parent(A)
@forindexes $N o i ind P begin
    P[oP] = val   # WRONG!
end
```
does not. Also, if you're passing indexes into a function as an argument, make sure you [force specialization on each indexes argument](https://github.com/JuliaLang/julia/issues/4090).

Note that you only need to supply as many index/array pairs as is required to set strides and offsets; if `A`, `B`, and `C` are identical in terms of their indexing, size, and strides, then the following suffices:
```
@forindexes N o i indexesA A begin
    C[oA] = A[oA] + B[oA]
end
```
This will be more efficient because only one set of offset variables needs to be constructed (see below).  For functions with a tight inner loop, `@forindexes` is slower than `@forarrays` because an additional lookup needs to be performed.


### How `@forarrays` works

From the simple code snippet above, `@forarrays` creates a block of code that
looks like this (implementation for 3d shown):

```
    stridedest1 = stride(dest, 1)
    stridedest2 = stride(dest, 2)
    stridedest3 = stride(dest, 3)
    stridesrc1  = stride(src, 1)
    stridesrc2  = stride(src, 2)
    stridesrc3  = stride(src, 3)
    pindexesdest = parsedindexes(dest)
    pindexessrc = parsedindexes(src)
    for i3 = 1:size(dest, 3)
        odest3 = sliceoffset(dest) + (index(dest, pindexesdest, 3, i3)-1)*stridedest3
        osrc3  = sliceoffset(src) + (index(src, pindexessrc, 3, i3)-1)*stridesrc3
        for i2 = 1:size(dest, 2)
            odest2 = odest3 + (index(dest, pindexesdest, 2, i2)-1)*stridedest2
            osrc2  = osrc3 + (index(src, pindexessrc, 2, i2)-1)*stridesrc2
            for i1 = 1:size(dest, 1)
                odest = odest2 + (index(dest, pindexesdest, 1, i1)-1)*stridedest1
                osrc  = osrc2 + (index(src, pindexessrc, 1, i1)-1)*stridesrc1
                dest.parent[odest] = src.parent[osrc]
            end
        end
    end
```

The key to its speed is the tightness of this inner loop. Note also that no
memory is allocated.

The internal functions `parsedindexes`, `sliceoffset`, and `index` all work
together to handle plain arrays, subarrays, and sliced arrays.


### How `@forcartesian` works

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
