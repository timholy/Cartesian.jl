module Cartesian

import Base: replace

export @forcartesian, @nloops, @nref, @nrefshift

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

macro nloops(N, itersym, rangeexpr, ex)
    _nloops(N, itersym, rangeexpr, ex)
end

function _nloops(N::Int, itersym::Symbol, rangeexpr::Expr, body::Expr)
    if rangeexpr.head != :->
        error("Second argument must be an anonymous function expression to compute the range")
    end
    ex = Expr(:escape, body)
    for dim = 1:N
        itervar = namedvar(itersym, dim)
        rng = inlineanonymous(rangeexpr, dim)
        ex = quote
            for $(esc(itervar)) = $(esc(rng))
                $ex
            end
        end
    end
    ex
end

function _nloops(N::Int, itersym::Symbol, arrayforsize::Symbol, body::Expr)
    ex = Expr(:escape, body)
    for dim = 1:N
        itervar = namedvar(itersym, dim)
        ex = quote
            for $(esc(itervar)) = 1:size($(esc(arrayforsize)),$dim)
                $ex
            end
        end
    end
    ex
end

macro nref(N, A, sym)
    _nref(N, A, sym)
end

function _nref(N::Int, A::Symbol, sym::Symbol)
    vars = [ namedvar(sym, i) for i = 1:N ]
    Expr(:escape, Expr(:ref, A, vars...))
end

macro nrefshift(N, A, sym, shiftexpr)
    _nrefshift(N, A, sym, shiftexpr)
end

function _nrefshift(N::Int, A::Symbol, sym::Symbol, shiftexpr::Expr)
    vars = [ :($(namedvar(sym, i))+$(inlineanonymous(shiftexpr, i))) for i = 1:N ]
    Expr(:escape, Expr(:ref, A, vars...))
end

namedvar(base::Symbol, ext) = symbol(string(base)*string(ext))

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

end
