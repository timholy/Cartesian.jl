module Cartesian

export @forcartesian, @forarrays, parent

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

# Generate expressions like :( sliceA = sliceoffset(A) )
function sliceoffsetexpr(array::Symbol)
    slice = namedvar(:slice, array)
    return :($(esc(slice)) = sliceoffset($(esc(array))))
end

# Generate expressions like :( o3 = :slice3 + (i3-1)*stride3 ), using strides appropriate for a particular array
function offsetexpr(offset::Symbol, iter::Symbol, array::Symbol, dim::Integer)
    ocur = dim == 1 ? namedvar(offset, array) : namedvar(offset, array, dim)
    icur = namedvar(iter, dim)
    scur = namedvar(:stride, array, dim)
    slice = namedvar(:slice, array)
    return :($(esc(ocur)) = $(esc(slice)) + (index($(esc(array)), $dim, $(esc(icur)))-1)*$(esc(scur)))
end

# Generate expressions like :( o2 = o3 + (i2-1)*stride2 ), using strides appropriate for a particular array
function nestedoffsetexpr(offset::Symbol, iter::Symbol, array::Symbol, dim::Integer)
    ocur = dim == 1 ? namedvar(offset, array) : namedvar(offset, array, dim)
    oprev = namedvar(offset, array, dim+1)
    icur = namedvar(iter, dim)
    scur = namedvar(:stride, array, dim)
    if dim == 1
        return :($(esc(ocur)) = $(esc(oprev)) + index($(esc(array)), $dim, $(esc(icur))))
    else
        return :($(esc(ocur)) = $(esc(oprev)) + (index($(esc(array)), $dim, $(esc(icur)))-1)*$(esc(scur)))
    end
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

# Note in args, the first n-1 are array symbols, the last is the expression
macro forarrays(N, offsetsym, itersym, args...)
    if !isa(N, Integer)
        error("First argument must be the number of dimensions (as an integer)")
    end
    if !isa(offsetsym, Symbol)
        error("Second argument must be the base-name of the offset variable")
    end
    if !isa(itersym, Symbol)
        error("Third argument must be the base-name of the coordinate (iteration) variable")
    end
    if length(args) < 2
        error("Supply at least one array and the inner-loop expression")
    end
    if !isa(args[end], Expr)
        error("The final argument must be the inner-loop expression")
    end
    asyms = args[1:end-1]
    ex = Expr(:escape, args[end])
    # Generate N-1 loops, starting with the inner one
    for i = 1:N-1
        offsetvars = [nestedoffsetexpr(offsetsym, itersym, asym, i) for asym in asyms]
        itervar = namedvar(itersym, i)
        ex = quote
            for $(esc(itervar)) = 1:size($(esc(asyms[1])), $i)
                $(excat(offsetvars))
                $ex
            end
        end
    end
    # Generate the outer loop, which cannot depend on previous loops (it's not nested)
    offsetvars = [offsetexpr(offsetsym, itersym, asym, N) for asym in asyms]
    itervar = namedvar(itersym, N)
    ex = quote
        for $(esc(itervar)) = 1:size($(esc(asyms[1])), $N)
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

end
