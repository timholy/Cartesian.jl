module Cartesian

import Base: replace

export @forcartesian, @forarrays, @forrangearrays, @forindexes, parent, parentsubindexes

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

### Fast SubArray (and Array) operations ###

parent(A::Array) = A
parent(S::SubArray) = S.parent
index(A::Array, dim::Integer, i::Integer) = i
index(S::SubArray, dim::Integer, i::Integer) = S.indexes[dim][i]
parentsubindexes(A::Array) = ntuple(ndims(A), i -> 1:size(A,i))
parentsubindexes(A::SubArray) = A.indexes[Base.parentdims(A)]

# Calculate the offset due to trailing/sliced singleton dimensions
sliceoffset(A::Array) = 0
function sliceoffset(S::SubArray)
    missingdims = setdiff(1:ndims(parent(S)), Base.parentdims(S))
    off = 0
    for i in missingdims
        off += (S.indexes[i][1]-1)*stride(parent(S), i)
    end
    off
end

namedvar(base::Symbol, ext) = symbol(string(base)*string(ext))
namedvar(base::Symbol, ext1, ext2) = symbol(string(base)*string(ext1)*string(ext2))

function inlineanonymous(ex::Expr, val)
    if ex.head != :->
        error("Not an anonymous function")
    end
    if !isa(ex.args[1], Symbol)
        error("Not a single-argument anonymous function")
    end
    sym = ex.args[1]
    ex = ex.args[2]
    replace(copy(ex), sym, val)
end

replace(s::Symbol, sym::Symbol, val) = (s == sym) ? val : s
replace(n::Number, sym::Symbol, val) = n
function replace(ex::Expr, sym::Symbol, val)
    for i in 1:length(ex.args)
        ex.args[i] = replace(ex.args[i], sym, val)
    end
    ex
end

# Generate expressions like :( sliceA = sliceoffset(A) )
function sliceoffsetexpr(array::Symbol)
    slice = namedvar(:slice, array)
    return :($(esc(slice)) = sliceoffset($(esc(array))))
end

# Generate expressions like :( oA3 = 1 + :sliceA3 + (i3-1)*strideA3 ), using strides appropriate for a particular array A
function offsetexpr(offset::Symbol, iter::Symbol, array::Symbol, dim::Integer)
    ocur = dim == 1 ? namedvar(offset, array) : namedvar(offset, array, dim)
    icur = namedvar(iter, dim)
    scur = namedvar(:stride, array, dim)
    slice = namedvar(:slice, array)
    return :($(esc(ocur)) = 1 + $(esc(slice)) + (index($(esc(array)), $dim, $(esc(icur)))-1)*$(esc(scur)))
end

# Generate expressions like :( oA3 = 1 + :sliceA3 + (index3[i3]-1)*strideA3 )
function offsetexpr(offset::Symbol, iter::Symbol, index::Symbol, array::Symbol, dim::Integer)
    ocur = dim == 1 ? namedvar(offset, array) : namedvar(offset, array, dim)
    icur = namedvar(iter, dim)
    scur = namedvar(:stride, array, dim)
    slice = namedvar(:slice, array)
    indexcur = namedvar(index, dim)
    return :($(esc(ocur)) = 1 + $(esc(slice)) + ($(esc(indexcur))[$(esc(icur))]-1)*$(esc(scur)))
end

# Generate expressions like :( oA2 = oA3 + (i2-1)*strideA2 )
function nestedoffsetexpr(offset::Symbol, iter::Symbol, array::Symbol, dim::Integer)
    ocur = dim == 1 ? namedvar(offset, array) : namedvar(offset, array, dim)
    oprev = namedvar(offset, array, dim+1)
    icur = namedvar(iter, dim)
    scur = namedvar(:stride, array, dim)
    return :($(esc(ocur)) = $(esc(oprev)) + (index($(esc(array)), $dim, $(esc(icur)))-1)*$(esc(scur)))
end

# Generate expressions like :( oA2 = oA3 + (index2[i2]-1)*strideA2 )
function nestedoffsetexpr(offset::Symbol, iter::Symbol, index::Symbol, array::Symbol, dim::Integer)
    ocur = dim == 1 ? namedvar(offset, array) : namedvar(offset, array, dim)
    oprev = namedvar(offset, array, dim+1)
    icur = namedvar(iter, dim)
    scur = namedvar(:stride, array, dim)
    indexcur = namedvar(index, dim)
    return :($(esc(ocur)) = $(esc(oprev)) + ($(esc(indexcur))[$(esc(icur))]-1)*$(esc(scur)))
end

# Generate expressions like :( strideA3 = strideA2 * size(parent(A), 3) )
# function stride1expr(array::Symbol)
#     s = namedvar(:stride, array, 1)
#     return :($(esc(s)) = stride($(esc(array)), 1))
# end

function strideexpr(array::Symbol, dim::Integer)
    s = namedvar(:stride, array, dim)
    return :($(esc(s)) = stride($(esc(array)), $dim))
#     sprev = namedvar(:stride, array, dim-1)
#     return :($(esc(scur)) = $(esc(sprev))*size(parent($(esc(array))), $(dim-1)))
end

excat(exlist) = length(exlist) == 1 ? exlist[1] : Expr(:block, exlist...)

# In args, the first n-1 are array symbols, the last is the expression
function _forrangearrays(N, offsetsym, itersym, rangeexpr, args...)
    if !isa(N, Integer)
        error("First argument must be the number of dimensions (as an integer)")
    end
    if !isa(offsetsym, Symbol)
        error("Second argument must be the base-name of the offset variable")
    end
    if !isa(itersym, Symbol)
        error("Third argument must be the base-name of the coordinate (iteration) variable")
    end
    if !(isa(rangeexpr, Expr) && rangeexpr.head == :->)
        error("Fourth argument must be an anonymous-function expression to compute the range")
    end
    if length(args) < 2
        error("Supply at least one array and the inner-loop expression")
    end
    for i = 1:length(args)-1
        if !isa(args[i], Symbol)
            error("All of the arrays must be symbols")
        end
    end
    if !isa(args[end], Expr)
        error("The final argument must be the inner-loop expression")
    end
    asyms = args[1:end-1]
    ex = Expr(:escape, args[end])
    # Generate N-1 loops, starting with the inner one
    for idim = 1:N-1
        offsetvars = [nestedoffsetexpr(offsetsym, itersym, asym, idim) for asym in asyms]
        itervar = namedvar(itersym, idim)
        rng = inlineanonymous(rangeexpr, idim)
        ex = quote
            for $(esc(itervar)) = $(esc(rng))
                $(excat(offsetvars))
                $ex
            end
        end
    end
    # Generate the outer loop, which cannot depend on previous loops (it's not nested)
    offsetvars = [offsetexpr(offsetsym, itersym, asym, N) for asym in asyms]
    itervar = namedvar(itersym, N)
    rng = inlineanonymous(rangeexpr, N)
    ex = quote
        for $(esc(itervar)) = $(esc(rng))
            $(excat(offsetvars))
            $ex
        end
    end
    # Generate the stride variables and sliceoffset variables
    headervars = [sliceoffsetexpr(asym) for asym in asyms]
    for i = 1:N
        append!(headervars, Expr[strideexpr(asym, i) for asym in asyms])
    end
    return quote
        $(excat(headervars))
        $ex
    end
end

# In args, the first n-1 are array symbols, the last is the expression
function _forindexes(N, offsetsym, itersym, args...)
    if !isa(N, Integer)
        error("First argument must be the number of dimensions (as an integer)")
    end
    if !isa(offsetsym, Symbol)
        error("Second argument must be the base-name of the offset variable")
    end
    if !isa(itersym, Symbol)
        error("Third argument must be the base-name of the coordinate (iteration) variable")
    end
    if !isodd(length(args)) || length(args) < 3
        error("Final arguments must be I1 A1 I2 A2 ... expr, where Ii is a vector of indexes, Ai is an array, and expr is your function body")
    end
    for i = 1:length(args)-1
        if !isa(args[i], Symbol)
            error("All of the indexes and arrays must be symbols")
        end
    end
    if !isa(args[end], Expr)
        error("The final argument must be the inner-loop expression")
    end
    indexsyms = args[1:2:end-1]
    asyms = args[2:2:end-1]
    ex = Expr(:escape, args[end])
    # Generate N-1 loops, starting with the inner one
    for idim = 1:N-1
        offsetvars = [nestedoffsetexpr(offsetsym, itersym, indexsyms[i], asyms[i], idim) for i = 1:length(indexsyms)]
        itervar = namedvar(itersym, idim)
        ovar = namedvar(offsetsym, asyms[1], idim)
        indexsym = namedvar(indexsyms[1], idim)
        ex = quote
            for $(esc(itervar)) = 1:length($(esc(indexsym)))
                $(excat(offsetvars))
                $ex
            end
        end
    end
    # Generate the outer loop, which cannot depend on previous loops (it's not nested)
    offsetvars = [offsetexpr(offsetsym, itersym, indexsyms[i], asyms[i], N) for i = 1:length(indexsyms)]
    itervar = namedvar(itersym, N)
    ovar = namedvar(offsetsym, asyms[1], N)
    indexsym = namedvar(indexsyms[1], N)
    ex = quote
        for $(esc(itervar)) = 1:length($(esc(indexsym)))
            $(excat(offsetvars))
            $ex
        end
    end
    # Generate the stride variables and sliceoffset variables
    headervars = [sliceoffsetexpr(asym) for asym in asyms]
    for i = 1:N
        append!(headervars, Expr[strideexpr(asym, i) for asym in asyms])
    end
    # Extract each index variable
    for i = 1:length(indexsyms)
        indexessym = indexsyms[i]
        for dim = 1:N
            indexsym = namedvar(indexsyms[i], dim)
            push!(headervars, :($(esc(indexsym)) = $(esc(indexessym))[$dim]))
        end
    end
    return quote
        $(excat(headervars))
        $ex
    end
end

macro forrangearrays(N, offsetsym, itersym, rangeexpr, args...)
    _forrangearrays(N, offsetsym, itersym, rangeexpr, args...)
end

macro forarrays(N, offsetsym, itersym, args...)
    _forrangearrays(N, offsetsym, itersym, :(d->1:size($(args[1]),d)), args...)
end

macro forindexes(N, offsetsym, itersym, args...)
    _forindexes(N, offsetsym, itersym, args...)
end

end
