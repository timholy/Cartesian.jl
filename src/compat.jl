## Extra features not in base. Present for backwards compatibility.

export cartesian_linear, linear, @forcartesian, @indexedvariable, @nlinear, @nlookup, @nrefshift

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
    vars = [ exprresolve(:($(namedvar(sym, i))+$(inlineanonymous(shiftexpr, i)))) for i = 1:N ]
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

namedvar(base::Symbol, ext) = symbol(string(base)*"_"*string(ext))

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
