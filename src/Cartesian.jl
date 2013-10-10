module Cartesian

import Base: replace

export cartesian_linear, linear, @forcartesian, @indexedvariable, @nall, @nexprs, @nextract, @nlinear, @nlookup, @nloops, @nref, @nrefshift, @ntuple

macro forcartesian(sym, sz, ex)
    idim = gensym()
    N = gensym()
    sz1 = gensym()
    isdone = gensym()
    quote
        if !(isempty($(esc(sz))) || prod($(esc(sz))) == 0)
            $N = length($(esc(sz)))
            $sz1 = $(esc(sz))[1]
            $isdone = false
            $(esc(sym)) = ones(Int, $N)
            while !$isdone
                $(esc(ex))
                if ($(esc(sym))[1] += 1) > $sz1
                    $idim = 1
                    while $(esc(sym))[$idim] > $(esc(sz))[$idim] && $idim < $N
                        $(esc(sym))[$idim] = 1
                        $idim += 1
                        $(esc(sym))[$idim] += 1
                    end
                    $isdone = $(esc(sym))[$N] > $(esc(sz))[$N]
                end
            end
        end
    end
end

function cartesian_linear(A::AbstractArray, I::Vector{Int})
    k = 0
    for j = length(I):-1:1
        k = size(A, j)*k + I[j]-1
    end
    k += 1
end

# Generate nested loops
macro nloops(N, itersym, rangeexpr, args...)
    _nloops(N, itersym, rangeexpr, args...)
end

# Range of each loop is determined by an array's size,
#   for i2 = 1:size(A,2)
#     for i1 = 1:size(A,1)
#       ...
function _nloops(N::Int, itersym::Symbol, arrayforsize::Symbol, args::Expr...)
    if !(1 <= length(args) <= 3)
        error("Too many arguments")
    end
    body = args[end]
    ex = Expr(:escape, body)
    for dim = 1:N
        itervar = namedvar(itersym, dim)
        preexpr = length(args) > 1 ? inlineanonymous(args[1], dim) : (:(nothing))
        postexpr = length(args) > 2 ? inlineanonymous(args[2], dim) : (:(nothing))
        ex = quote
            for $(esc(itervar)) = 1:size($(esc(arrayforsize)),$dim)
                $(esc(preexpr))
                $ex
                $(esc(postexpr))
            end
        end
    end
    ex
end

# An alternative where the range of each loop is determined by an expression,
#    for i2 = r,  where r is the result of evaluating d->f(d) for d=2
# Note that the "anonymous function" is inlined because we pass it as an
# anonymous function expression.
# It's possible to make the range depend on a set of indexed variables, using the
# notation i_d which gets translated into i3 for d=3.
function _nloops(N::Int, itersym::Symbol, rangeexpr::Expr, args::Expr...)
    if rangeexpr.head != :->
        error("Second argument must be an anonymous function expression to compute the range")
    end
    if !(1 <= length(args) <= 3)
        error("Too many arguments")
    end
    body = args[end]
    ex = Expr(:escape, body)
    for dim = 1:N
        itervar = namedvar(itersym, dim)
        rng = inlineanonymous(rangeexpr, dim)
        preexpr = length(args) > 1 ? inlineanonymous(args[1], dim) : (:(nothing))
        postexpr = length(args) > 2 ? inlineanonymous(args[2], dim) : (:(nothing))
        ex = quote
            for $(esc(itervar)) = $(esc(rng))
                $(esc(preexpr))
                $ex
                $(esc(postexpr))
            end
        end
    end
    ex
end

# Generate expression A[i1, i2, ...]
macro nref(N, A, sym)
    _nref(N, A, sym)
end

function _nref(N::Int, A::Symbol, sym::Symbol)
    vars = [ namedvar(sym, i) for i = 1:N ]
    Expr(:escape, Expr(:ref, A, vars...))
end

function _nref(N::Int, A::Symbol, ex::Expr)
    vars = [ inlineanonymous(ex,i) for i = 1:N ]
    Expr(:escape, Expr(:ref, A, vars...))
end

# Generate expression A[i1+j1, i2+j2, ...]
macro nrefshift(N, A, sym, shiftexpr)
    _nrefshift(N, A, sym, shiftexpr)
end

# ... using an offset symbol. This is useful with nested @nloops
function _nrefshift(N::Int, A::Symbol, iter1::Symbol, iter2::Symbol)
    vars = [ :($(namedvar(iter1, i))+$(namedvar(iter2, i))) for i = 1:N ]
    Expr(:escape, Expr(:ref, A, vars...))
end

# ... using a shiftexpr, e.g., A[i1, i2+1, ...] with d->(d==2)?1:0
function _nrefshift(N::Int, A::Symbol, sym::Symbol, shiftexpr::Expr)
    vars = [ poparithmetic(:($(namedvar(sym, i))+$(inlineanonymous(shiftexpr, i)))) for i = 1:N ]
    Expr(:escape, Expr(:ref, A, vars...))
end

# Generate expression A[ I1[i1], I2[i2], ... ]
macro nlookup(N, A, indexes, itersym)
    _nlookup(N, A, indexes, itersym)
end

function _nlookup(N::Int, A::Symbol, indexes::Symbol, itersym::Symbol)
    vars = [ :($(namedvar(indexes, i))[$(namedvar(itersym, i))]) for i = 1:N ]
    Expr(:escape, Expr(:ref, A, vars...))
end

macro ntuple(N, ex)
    _ntuple(N, ex)
end

function _ntuple(N::Int, sym::Symbol)
    vars = [ namedvar(sym, i) for i = 1:N ]
    Expr(:escape, Expr(:tuple, vars...))
end

function _ntuple(N::Int, ex::Expr)
    vars = [ inlineanonymous(ex,i) for i = 1:N ]
    Expr(:escape, Expr(:tuple, vars...))
end

# Generate N expressions
macro nexprs(N, ex)
    _nexprs(N, ex)
end

function _nexprs(N::Int, ex::Expr)
    exs = [ inlineanonymous(ex,i) for i = 1:N ]
    Expr(:escape, Expr(:block, exs...))
end

# Make variables esym1, esym2, ... = isym
macro nextract(N, esym, isym)
    _nextract(N, esym, isym)
end

function _nextract(N::Int, esym::Symbol, isym::Symbol)
    aexprs = [Expr(:escape, Expr(:(=), namedvar(esym, i), :(($isym)[$i]))) for i = 1:N]
    Expr(:block, aexprs...)
end

function _nextract(N::Int, esym::Symbol, ex::Expr)
    aexprs = [Expr(:escape, Expr(:(=), namedvar(esym, i), inlineanonymous(ex,i))) for i = 1:N]
    Expr(:block, aexprs...)
end

# Check whether variables i1, i2, ... all satisfy criterion
macro nall(N, criterion)
    _nall(N, criterion)
end

function _nall(N::Int, criterion::Expr)
    if criterion.head != :->
        error("Second argument must be an anonymous function expression yielding the criterion")
    end
    conds = [Expr(:escape, inlineanonymous(criterion, i)) for i = 1:N]
    Expr(:&&, conds...)
end

# Convert to a linear index
macro nlinear(N, A, itersym)
    _nlinear(N, A, itersym)
end

function _nlinear(N::Int, A::Symbol, itersym::Symbol)
    Expr(:call, :linear, :($(esc(A))), [Expr(:escape, namedvar(itersym, i)) for i = 1:N]...)
end

function _nlinear(N::Int, A::Symbol, ex::Expr)
    Expr(:call, :linear, :($(esc(A))), [Expr(:escape, inlineanonymous(ex, i)) for i = 1:N]...)
end

namedvar(base::Symbol, ext) = symbol(string(base)*string(ext))

macro indexedvariable(N, sym)
    _indexedvariable(N, sym)
end

# _indexedvariable(ex::Expr, sym::Symbol) = _indexedvariable(eval(ex), sym)

function _indexedvariable(i::Integer, sym::Symbol)
    nv = namedvar(sym, i)
    :($(esc(nv)))
end

linear(A::Array, i1::Integer) = A, i1
linear(A::Array, i1::Integer, i2::Integer) = A, i1+size(A,1)*(i2-1)
linear(A::Array, i1::Integer, i2::Integer, i3::Integer) = A, i1+size(A,1)*(i2-1+size(A,2)*(i3-1))
linear(A::Array, i1::Integer, i2::Integer, i3::Integer, i4::Integer) = A, i1+size(A,1)*(i2-1+size(A,2)*(i3-1+size(A,3)*(i4-1)))
linear(A::Array, i1::Integer, i2::Integer, i3::Integer, i4::Integer, i5::Integer) = A, i1+size(A,1)*(i2-1+size(A,2)*(i3-1+size(A,3)*(i4-1+size(A,4)*(i5-1))))

linear{T}(s::SubArray{T,1}, i::Integer) =
    s.parent, s.first_index + (i-1)*s.strides[1]
linear{T}(s::SubArray{T,2}, i::Integer, j::Integer) =
    s.parent, s.first_index + (i-1)*s.strides[1] + (j-1)*s.strides[2]
linear{T}(s::SubArray{T,3}, i::Integer, j::Integer, k::Integer) =
    s.parent, s.first_index + (i-1)*s.strides[1] + (j-1)*s.strides[2] + (k-1)*s.strides[3]
linear{T}(s::SubArray{T,4}, i::Integer, j::Integer, k::Integer, l::Integer) =
    s.parent, s.first_index + (i-1)*s.strides[1] + (j-1)*s.strides[2] + (k-1)*s.strides[3] + (l-1)*s.strides[4]
linear{T}(s::SubArray{T,5}, i::Integer, j::Integer, k::Integer, l::Integer, m::Integer) =
    s.parent, s.first_index + (i-1)*s.strides[1] + (j-1)*s.strides[2] + (k-1)*s.strides[3] + (l-1)*s.strides[4] + (m-1)*s.strides[5]

function inlineanonymous(ex::Expr, val)
    # Inline the anonymous-function part
    if ex.head != :->
        error("Not an anonymous function")
    end
    if !isa(ex.args[1], Symbol)
        error("Not a single-argument anonymous function")
    end
    sym = ex.args[1]
    ex = ex.args[2]
    exout = replace(copy(ex), sym, val)
    exout = poplinenum(exout)
    # Inline ternary expressions
    if exout.head == :if
        try
            tf = eval(exout.args[1])
            exout = tf?exout.args[2]:exout.args[3]
        catch
        end
    end
    exout
end

# Replace a symbol by a value or a "coded" symbol
# E.g., for d = 3,
#    replace(:d, :d, 3) -> 3
#    replace(:i_d, :d, 3) -> :i3
replace(n::Number, sym::Symbol, val) = n
function replace(s::Symbol, sym::Symbol, val)
    if (s == sym)
        return val
    else
        tail = "_"*string(sym)
        sstr = string(s)
        if endswith(sstr, tail)
            return symbol(sstr[1:end-length(tail)]*string(val))
        end
    end
    s
end
function replace(ex::Expr, sym::Symbol, val)
    # Curly-brace notation
    if ex.head == :curly && length(ex.args) == 2 && isa(ex.args[1], Symbol) && endswith(string(ex.args[1]), "_")
        excurly = replace(ex.args[2], sym, val)
        return symbol(string(ex.args[1])[1:end-1]*string(poparithmetic(excurly)))
    end
    for i in 1:length(ex.args)
        ex.args[i] = replace(ex.args[i], sym, val)
    end
    ex
end

function poplinenum(ex::Expr)
    if ex.head == :block
        if length(ex.args) == 1
            return ex.args[1]
        elseif length(ex.args) == 2 && ex.args[1].head == :line
            return ex.args[2]
        end
    end
    ex
end

# This only handles simple stuff
function poparithmetic(ex::Expr)
    if ex.head == :call && in(ex.args[1], (:+, :-, :*, :/)) && all([isa(ex.args[i], Number) for i = 2:length(ex.args)])
        return eval(ex)
    elseif ex.head == :call && (ex.args[1] == :+ || ex.args[1] == :-) && length(ex.args) == 3 && ex.args[3] == 0
        # simplify x+0 and x-0
        return ex.args[2]
    end
    ex
end

end
