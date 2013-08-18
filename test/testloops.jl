import Cartesian

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
