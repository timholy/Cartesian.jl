# Cartesian.jl

Fast multidimensional algorithms for the Julia language.

This package provides macros that currently appear to be the most performant way
to implement numerous multidimensional algorithms in Julia.

## NEWS: Cartesian is in Base, and backwards compatibility

If you're using at least a pre-release version of Julia 0.3, I recommend using the version
in base, which you can access with `using Base.Cartesian`.
I also recommend the base [documentation](http://docs.julialang.org/en/latest/devdocs/cartesian/).

At this point, the best purpose for this package is to provide a base-compatible
implementation of Cartesian for Julia 0.2. This was implemented in the
the 0.2 release of this package. Unfortunately, this changed several features,
including the naming convention for variables
(from `i1` to `i_1`). If you directly use these names (most likely, you do not), this will break your code.
Sorry about that. You can either pin the package at the 0.1.5 release, or make changes in your code.

# Legacy documentation

The following documentation applies only for this package's 0.1 series. Use the
[Julia documentation](http://docs.julialang.org/en/latest/devdocs/cartesian/) if you are using
a more recent version of this package.

## Caution

In practice, `Cartesian` effectively introduces a separate "dialect" of
Julia. There is reason to hope that the main language will eventually
support much of this functionality, and if/when that happens some or all of this
should become obsolete. In the meantime, this package appears to be the most
powerful way to write efficient multidimensional algorithms.

## Installation

Install with the package manager, `Pkg.add("Cartesian")`.

## Principles of usage

Most macros in this package work like this:
```
@nloops 3 i A begin
    s += @nref 3 A i
end
```
which generates the following code:
```
for i3 = 1:size(A,3)
    for i2 = 1:size(A,2)
        for i1 = 1:size(A,1)
            s += A[i1,i2,i3]
        end
    end
end
```
The (basic) syntax of `@nloops` is as follows:

- The first argument must be an integer (_not_ a variable) specifying the number
of loops.
- The second argument is the symbol-prefix used for the iterator variable. Here
we used `i`, and variables `i1, i2, i3` were generated.
- The third argument specifies the range for each iterator variable. If you use
a variable (symbol) here, it's taken as `1:size(A,dim)`. More flexibly, you can
use the anonymous-function expression syntax described below.
- The last argument is the body of the loop. Here, that's what appears between
the `begin...end`.

There are some additional features described
[below](https://github.com/timholy/Cartesian.jl#core-macros).

`@nref` follows a similar pattern, generating `A[i1,i2,i3]` from `@nref 3 A i`.
The general practice is to read from left to right, which is why
`@nloops` is `@nloops 3 i A expr` (as in `for i2 = 1:size(A,2)`, where `i2` is
to the left and the range is to the right) whereas `@nref` is `@nref 3 A i` (as
in `A[i1,i2,i3]`, where the array comes first).

If you're developing code with Cartesian, you may find that debugging is made
easier when you can see the generated code. This is possible via the
(unexported) underscore-function variants:

```
julia> Cartesian._nref(3, :A, :i)
:($(Expr(:escape, :(A[i1,i2,i3]))))
```

and similarly for `Cartesian._nloops`.

There are two additional important general points described below.

#### Supplying the dimensionality from functions

The first argument to both of these macros is the dimensionality, which must be
an integer. When you're writing a function that you intend to work in multiple
dimensions, this may not be something you want to hard-code. Fortunately, it's
straightforward to use an `@eval` construct, like this:

```
for N = 1:4
    @eval begin
        function laplacian{T}(A::Array{T,$N})
            B = similar(A)
            @nloops $N i A begin
                ...
            end
        end
    end
end
```

This would generate versions of `laplacian` for dimensions 1 through 4. While
it's somewhat more awkward, you can generate truly arbitrary-dimension functions
using a wrapper that keeps track of whether it has already compiled a version of
the function for different dimensionalities and data types:

```
let _mysum_defined = Dict{Any, Bool}()
global mysum
function mysum{T,N}(A::StridedArray{T,N})
    def = get(_mysum_defined, typeof(A), false)
    if !def
        ex = quote
            function _mysum{T}(A::StridedArray{T,$N})
                s = zero(T)
                @nloops $N i A begin
                    s += @nref $N A i
                end
                s
            end
        end
        eval(current_module(), ex)
        _mysum_defined[typeof(A)] = true
    end
    _mysum(A)
end
end
```

In addition to being longer than the first version, there's a (small)
performance price for checking the dictionary.

#### Anonymous-function expressions as macro arguments

Perhaps the single most powerful feature in `Cartesian` is the ability to supply
anonymous-function expressions to many macros. Let's consider implementing the
`laplacian` function mentioned above. The (discrete) laplacian of a two
dimensional array would be calculated as

```
lap[i,j] = A[i+1,j] + A[i-1,j] + A[i,j+1] + A[i,j-1] - 4A[i,j]
```

One obvious issue with this formula is how to handle the edges, where `A[i-1,j]`
might not exist. As a first illustration of anonymous-function expressions,
for now let's take the easy way out and avoid dealing with them (later you'll
see how you can handle them properly). In 2d we might write
such code as

```
for i2 = 2:size(A,2)-1
    for i1 = 2:size(A,1)-1
        lap[i1,i2] = ...
    end
end
```

where one should note that the range `2:size(A,2)-1` omits the first and last
index.

In `Cartesian` this can be written in the following way:

```
@nloops 2 i d->(2:size(A,d)-1) begin
    (@nref 2 lap i) = ...
end
```

Note here that the range argument is being supplied as an anonymous function. A
key point is that this anonymous function is _evaluated when the macro runs_.
(Whatever symbol appears as the variable of the anonymous function, here `d`, is
looped over the dimensionality.) Effectively, this expression gets _inlined_,
and hence generates exactly the code above with no extra runtime overhead.

There is an important bit of extra syntax associated with these expressions: the
expression `i_d`, for `d=3`, is translated into `i3`. Suppose we have two sets
of variables, a "main" group of indices `i1`, `i2`, and `i3`, and an "offset" group
of indices `j1`, `j2`, and `j3`. Then the expression

```
@nref 3 A d->(i_d+j_d)
```

gets translated into

```
A[i1+j1, i2+j2, i3+j3]
```

The `_` notation mimics the subscript notation of LaTeX; also like LaTeX, you
can use curly-braces to group sub-expressions. For example,
`d->p_{d-1}=p_d-1` generates `p2 = p3 - 1`.

## A complete example: implementing `imfilter`

With this, we have enough machinery to implement a simple multidimensional
function `imfilter`, which computes the correlation (similar to a convolution)
between an array `A` and a filtering kernel `kern`. We're going to require that
`kernel` has odd-valued sizes along each dimension, say of size `2*w[d]+1`, and
suppose that there is a function `padarray` that pads `A` with width `w[d]`
along each edge in dimension `d`, using whatever boundary conditions the user
desires.

A complete implementation of `imfilter` is:

```
for N = 1:5
    @eval begin
        function imfilter{T}(A::Array{T,$N}, kern::Array{T,$N}, boundaryargs...)
            w = [div(size(kern, d), 2) for d = 1:$N]
            for d = 1:$N
                if size(kern, d) != 2*w[d]+1
                    error("kernel must have odd size in each dimension")
                end
            end
            Apad = padarray(A, w, boundaryargs...)
            B = similar(A)
            @nloops $N i A begin
                # Compute the filtered value
                tmp = zero(T)
                @nloops $N j kern begin
                    tmp += (@nref $N Apad d->(i_d+j_d-1))*(@nref $N kern j)
                end
                # Store the result
                (@nref $N B i) = tmp     # note the ()
            end
            B
        end
    end
end
```

The line

```
tmp += (@nref $N Apad d->(i_d+j_d-1))*(@nref $N kern j)
```

gets translated into

```
tmp += Apad[i1+j1-1, i2+j2-1, ...] * kern[j1, j2, ...]
```

We also note that the assignment to `B` requires parenthesis around the `@nref`,
because otherwise the expression `i = tmp` would be passed as the final argument
of the `@nref` macro.


## A complete example: implementing `laplacian`

We could implement the laplacian with `imfilter`, but that would be quite
wasteful: we don't need the "corners" of the 3x3x... grid, just its edges and
center. Consequently, we can write a considerably faster algorithm, where the
advantage over `imfilter` would grow rapidly with dimensionality. Implementing
this algorithm will further illustrate the flexibility of anonymous-function
range expressions as well as another key macro, `@nexprs`.

In two dimensions, we'll generate the following code, which uses "replicating
boundary conditions" to handle the edges gracefully:

```
function laplacian{T}(A::Array{T,2})
    B = similar(A)
    for i2 = 1:size(A,2), i1 = 1:size(A,1)
        tmp = zero(T)
        tmp += i1 < size(A,1) ? A[i1+1,i2] : A[i1,i2]
        tmp += i2 < size(A,2) ? A[i1,i2+1] : A[i1,i2]
        tmp += i1 > 1 ? A[i1-1,i2] : A[i1,i2]
        tmp += i2 > 1 ? A[i1,i2-1] : A[i1,i2]
        B[i1,i2] = tmp - 4*A[i1,i2]
    end
    B
end
```

To generate those terms with all but one of the indices unaltered, we'll use
an anonymous function like this:

```
d2->(d2 == d1) ? i_d2+1 : i_d2
```

which shifts by 1 only when `d2 == d1`. We'll use the macro `@nexprs`
(documented below) to generate the `N` expressions we need. Here is the complete
implementation for dimensions 1 through 5:

```
for N = 1:5
    @eval begin
        function laplacian{T}(A::Array{T,$N})
            B = similar(A)
            @nloops $N i A begin
                tmp = zero(T)
                # Do the shift by +1.
                @nexprs $N d1->begin
                    tmp += (i_d1 < size(A,d1)) ? (@nref $N A d2->(d2==d1)?i_d2+1:i_d2) : (@nref $N A i)
                end
                # Do the shift by -1.
                @nexprs $N d1->begin
                    tmp += (i_d1 > 1) ? (@nref $N A d2->(d2==d1)?i_d2-1:i_d2) : (@nref $N A i)
                end
                # Subtract the center and store the result
                (@nref $N B i) = tmp - 2*$N*(@nref $N A i)
            end
            B
        end
    end
end
```

## Reductions and broadcasting

Cartesian makes it easy to implement reductions and broadcasting,
using the "pre" and "post" expression syntax described
[below](https://github.com/timholy/Cartesian.jl#core-macros).
Suppose we want to implement a function that can compute the maximum
along user-supplied dimensions of an array:

```
B = maxoverdims(A, (1,2))  # computes the max of A along dimensions 1&2
```
but allow the user to choose these dimensions arbitrarily. For two-dimensional arrays,
we might hand-write such code in the following way:
```
function maxoverdims{T}(A::AbstractMatrix{T}, region)
    szout = [size(A,1), size(A,2)]
    szout[[region...]] = 1   # output has unit-size in chosen dimensions
    B = fill(typemin(T), szout...)::Array{T,2}  # julia can't infer dimensionality here
    szout1 = szout[1]
    szout2 = szout[2]
    for i2 = 1:size(A, 2)
        j2 = szout2 == 1 ? 1 : i2
        for i1 = 1:size(A, 1)
            j1 = szout1 == 1 ? 1 : i1
            @inbounds B[j1,j2] = max(B[j1,j2], A[i1,i2])
        end
    end
    B
end
```
This code can be generated for arbitrary dimensions in the following way:
```
for N = 1:4
    @eval begin
        function maxoverdims{T}(A::AbstractArray{T,$N}, region)
            szout = [size(A,d) for d = 1:$N]
            szout[[region...]] = 1
            B = fill(typemin(T), szout...)::Array{T,$N}
            Cartesian.@nextract $N szout szout
            Cartesian.@nloops $N i A d->(j_d = szout_d==1 ? 1 : i_d) begin
                @inbounds (Cartesian.@nref $N B j) = max((Cartesian.@nref $N B j), (Cartesian.@nref $N A i))
            end
            B
        end
    end
end
```

You might be slightly concerned about the conditional expression
inside the inner-most loop, and what influence that might have on performance.
Fortunately, in most cases the impact seems to be very modest (in the
author's tests, a few percent). The reason is that on any given execution of
this function, each one of these branches always resolves the same way.
Consequently, the CPU can learn to predict, with 100% accuracy, which branch
will be taken. The computation time is therefore dominated by the cache-misses
generated by traversing the array.

## Macro reference

### Core macros

```
@nloops N itersym rangeexpr bodyexpr
@nloops N itersym rangeexpr preexpr bodyexpr
@nloops N itersym rangeexpr preexpr postexpr bodyexpr
```
Generate `N` nested loops, using `itersym` as the prefix for the iteration
variables. `rangeexpr` may be an anonymous-function expression, or a simple
symbol `var` in which case the range is `1:size(var,d)` for dimension `d`.

Optionally, you can provide "pre" and "post" expressions. These get executed
first and last, respectively, in the body of each loop. For example,
```
@nloops 2 i A d->j_d=min(i_d,5) begin
    s += @nref 2 A j
end
```
would generate
```
for i2 = 1:size(A, 2)
    j2 = min(i2, 5)
    for i1 = 1:size(A, 1)
        j1 = min(i1, 5)
        s += A[j1, j2]
    end
end
```
If you want just a post-expression, supply `nothing` for the pre-expression.
Using parenthesis and semicolons, you can supply multi-statement expressions.

<br />
```
@nref N A indexexpr
```
Generate expressions like `A[i1,i2,...]`. `indexexpr` can either be an
iteration-symbol prefix, or an anonymous-function expression.

<br />
```
@nexpr N expr
```
Generate `N` expressions. `expr` should be an anonymous-function expression. See
the `laplacian` example above.

<br />
```
@nextract N esym isym
```
Given a tuple or vector `I` of length `N`, `@nextract 3 I I` would generate the
expression `I1, I2, I3 = I`, thereby extracting each element of `I` into a
separate variable.

<br />
```
@nall N expr
```
`@nall 3 d->(i_d > 1)` would generate the expression
`(i1 > 1 && i2 > 1 && i3 > 1)`. This can be convenient for bounds-checking.

<br />
```
P, k = @nlinear N A indexexpr
```
Given an `Array` or `SubArray` `A`, `P, k = @nlinear N A indexexpr` generates an
array `P` and a linear index `k` for which `P[k]` is equivalent to
`@nref N A indexexpr`. Use this when it would be most convenient to implement an
algorithm
using linear-indexing.

This is particularly useful when an anonymous-function
expression cannot be evaluated at compile-time. For example, using an
example from `Images`, suppose you wanted to iterate over each pixel and perform
a calculation base on the color dimension of an array. In particular, we have a
function `rgb` which generates an RGB color from 3 numbers. We can do this for
each pixel of the array in the following way:

```
sz = [size(img,d) for d = 1:ndims(img)]
cd = colordim(img)  # determine which dimension of img represents color
sz[cd] = 1          # we'll "iterate" over color separately
strd = stride(img, cd)
@nextract $N sz sz
A = data(img)
@nloops $N i d->1:sz_d begin
    P, k = @nlinear $N A i
    rgbval = rgb(P[k], P[k+strd], P[k+2strd])
end
```

It appears to be difficult to generate code like this just using `@nref`,
because the expression `d->(d==cd)` could not be evaluated at compile-time.


### Additional macros

```
@ntuple N itersym
@ntuple N expr
```
Generates an `N`-tuple from a symbol prefix (e.g., `(i1,i2,...)`) or an
anonymous-function expression.

```
@nrefshift N A i j
```
Generates `A[i1+j1,i2+j2,...]`. This is legacy from before `@nref` accepted
anonymous-function expressions.

```
@nlookup N A I i
```
Generates `A[I1[i1], I2[i2], ...]`. This can also be easily achieved with
`@nref`.

```
@indexedvariable N i
```
Generates the expression `iN`, e.g., `@indexedvariable 2 i` would generate `i2`.

```
@forcartesian itersym sz bodyexpr
```
This is the oldest macro in the collection, and quite an outlier in terms of
functionality:
```
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

From the simple example above, `@forcartesian` generates a block of code like
this:

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

This has more overhead than the direct for-loop approach of `@nloops`, but for
many algorithms this shouldn't matter. Its advantage is that the dimensionality
does not need to be known at compile-time.


## Performance improvements for SubArrays

Julia currently lacks efficient linear-indexing for generic `SubArrays`.
Consequently, cartesian indexing is the only high-performance way to
address elements of `SubArray`s. Many simple algorithms, like `sum`, can have
their performance boosted immensely by implementing them for `SubArray`s using
`Cartesian`. For example, in 3d it's easy to get a boost on the scale of
100-fold.
