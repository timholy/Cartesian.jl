import Cartesian
using Base.Test

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
# @assert t < 2tbase
t = @elapsed (for k = 1:100; loopsum2(A); end)
# @assert t < 2tbase

t = @elapsed (for k = 1:100; loopsum(S); end)
# @assert t < 3tbase
t = @elapsed (for k = 1:100; loopsum2(S); end)
# @assert t < 3tbase

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
# @assert t < 2tbase
t = @elapsed loopsum2(A)
# @assert t < 2tbase
t = @elapsed loopsum(S)
# @assert t < 3tbase
t = @elapsed loopsum2(S)
# @assert t < 3tbase

# @nloops with pre-expression
for N = 1:4
    @eval begin
        function maxoverdims{T}(A::AbstractArray{T,$N}, region)
            szout = [size(A,d) for d = 1:$N]
            szout[[region...]] = 1
            B = fill(typemin(T), szout...)::Array{T,$N}
            Cartesian.@nextract $N szout szout
            Cartesian.@nloops $N i A d->(j_d = szout_d==1 ? 1 : i_d) begin
                (Cartesian.@nref $N B j) = max((Cartesian.@nref $N B j), (Cartesian.@nref $N A i))
            end
            B
        end
    end
end

A = reshape(1:10,5,2)
A1 = maxoverdims(A, 1)
@assert A1 == [5,10]'
A2 = maxoverdims(A, 2)
@assert A2 == reshape(6:10,5,1)
@assert maxoverdims(A, (1,2)) == reshape([10], 1, 1)

# Curly-brace syntax: sum over the upper-triangle
A = reshape(1:16, 4, 4)
s = 0
Cartesian.@nloops 2 i d->d==2?(1:size(A,d)):(1:i_{d+1}) begin
    s += Cartesian.@nref 2 A i
end
@assert s == sum(triu(A))

# @nref, @nrefshift, @nextract, and @nlookup
A = reshape(1:15, 3, 5)
i_1 = 2
i_2 = 3
@assert (Cartesian.@nref 2 A i) == A[i_1, i_2]
j_1 = -1
j_2 = 2
@assert (Cartesian.@nrefshift 2 A i j) == A[i_1+j_1, i_2+j_2]
@assert (Cartesian.@nrefshift 2 A i d->(d==2)?1:0) == A[i_1, i_2+1]
I = ([i_1], [i_2])
Cartesian.@nextract 2 k I
@assert k_1 == [i_1]
@assert k_2 == [i_2]
j_1 = 1
j_2 = 1
@assert (Cartesian.@nlookup 2 A k j) == A[i_1, i_2]

# @nlinear
A = reshape(1:120, 3, 4, 10)
i_1 = 2
i_2 = 2
i_3 = 7
p, index = Cartesian.@nlinear 3 A i
@assert index == A[i_1, i_2, i_3]

# The i_d notation
i_1 = 2
i_2 = -1
pairs = {}
Cartesian.@nloops 2 j d->(1-min(0,i_d):4-max(0,i_d)) begin
    push!(pairs, (j_1,j_2))
end
@assert pairs == {(1,2),(2,2),(1,3),(2,3),(1,4),(2,4)}

# @nall
pairs = {}
Cartesian.@nloops 2 j d->1:4 begin
    if Cartesian.@nall 2 d->(1 <= j_d+i_d <= 4)
        push!(pairs, (j_1,j_2))
    end
end
@assert pairs == {(1,2),(2,2),(1,3),(2,3),(1,4),(2,4)}

# @nexprs
A = reshape(1:20*7, 20, 7)
indexes = (2:5:20,3:7)
strds = strides(A)
i_1 = 2
i_2 = 3
ind = 1
@assert (Cartesian.@nexprs 2 d->(ind += (indexes[d][i_d]-1)*strds[d])) == A[indexes[1][i_1],indexes[2][i_2]]


# @ngenerate
Cartesian.@ngenerate N T function loopsum3{T,N}(A::StridedArray{T,N})
    s = zero(eltype(A))
    @inbounds Cartesian.@nloops(N, i, A, begin
        s += Cartesian.@nref(N, A, i)
    end)
    s
end
A = reshape(1:8, 2, 2, 2)
@test loopsum3(A) == 36
A = reshape(1:32, 2, 2, 2, 2, 2)
@test loopsum3(A) == 528
