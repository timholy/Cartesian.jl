import Cartesian

# @nloops with range expression
for N = 1:4
    @eval begin
        function loopsum{T}(A::StridedArray{T,$N})
            s = zero(eltype(A))
            @inbounds Cartesian.@nloops $N i d->1:size(A,d) begin
                s += Cartesian.@nref $N A i
            end
            s
        end
    end
end

# @nloops with size determined by array
for N = 1:4
    @eval begin
        function loopsum2{T}(A::StridedArray{T,$N})
            s = zero(eltype(A))
            @inbounds Cartesian.@nloops $N i A begin
                s += Cartesian.@nref $N A i
            end
            s
        end
    end
end

A = reshape(1:1000*1001, 1000, 1001)
S = sub(A, 2:999, 2:1000)

As = sum(A)
@assert loopsum(A) == As
@assert loopsum2(A) == As
Ss = sum(S)
@assert loopsum(S) == Ss
@assert loopsum2(S) == Ss

tbase = @elapsed (for k = 1:100; sum(A); end)
t = @elapsed (for k = 1:100; loopsum(A); end)
@assert t < 2tbase
t = @elapsed (for k = 1:100; loopsum2(A); end)
@assert t < 2tbase

t = @elapsed (for k = 1:100; loopsum(S); end)
@assert t < 3tbase
t = @elapsed (for k = 1:100; loopsum2(S); end)
@assert t < 3tbase

A = reshape(1:1000*1001*20, 1000, 1001, 20)
S = sub(A, 2:999, 2:1000, 2:19)

As = sum(A)
@assert loopsum(A) == As
@assert loopsum2(A) == As
Ss = sum(S)
@assert loopsum(S) == Ss
@assert loopsum2(S) == Ss

tbase = @elapsed sum(A)
t = @elapsed loopsum(A)
@assert t < 2tbase
t = @elapsed loopsum2(A)
@assert t < 2tbase
t = @elapsed loopsum(S)
@assert t < 3tbase
t = @elapsed loopsum2(S)
@assert t < 3tbase

# @nref, @nrefshift, @nextract, and @nlookup
A = reshape(1:15, 3, 5)
i1 = 2
i2 = 3
@assert (Cartesian.@nref 2 A i) == A[i1, i2]
j1 = -1
j2 = 2
@assert (Cartesian.@nrefshift 2 A i j) == A[i1+j1, i2+j2]
@assert (Cartesian.@nrefshift 2 A i d->(d==2)?1:0) == A[i1, i2+1]
I = ([i1], [i2])
Cartesian.@nextract 2 k I
@assert k1 == [i1]
@assert k2 == [i2]
j1 = 1
j2 = 1
@assert (Cartesian.@nlookup 2 A k j) == A[i1, i2]

# @nlinear
A = reshape(1:120, 3, 4, 10)
i1 = 2
i2 = 2
i3 = 7
p, index = Cartesian.@nlinear 3 A i
@assert index == A[i1, i2, i3]

# The i_d notation
i1 = 2
i2 = -1
pairs = {}
Cartesian.@nloops 2 j d->(1-min(0,i_d):4-max(0,i_d)) begin
    push!(pairs, (j1,j2))
end
@assert pairs == {(1,2),(2,2),(1,3),(2,3),(1,4),(2,4)}

# @nall
pairs = {}
Cartesian.@nloops 2 j d->1:4 begin
    if Cartesian.@nall 2 d->(1 <= j_d+i_d <= 4)
        push!(pairs, (j1,j2))
    end
end
@assert pairs == {(1,2),(2,2),(1,3),(2,3),(1,4),(2,4)}

# @nexprs
println("About to check nexprs")
A = reshape(1:20*7, 20, 7)
indexes = (2:5:20,3:7)
strds = strides(A)
i1 = 2
i2 = 3
ind = 1
@assert (Cartesian.@nexprs 2 d->(ind += (indexes[d][i_d]-1)*strds[d])) == A[indexes[1][i1],indexes[2][i2]])
