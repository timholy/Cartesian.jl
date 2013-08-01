sz = [5,3]
Cartesian.@forcartesian c sz begin
    println(c)
end

function testcounter(m, n, N)
    sloop = 0
    @time begin
        for k = 1:N
            for j = 1:n
                for i = 1:m
                    sloop += 1
                end
            end
        end
    end
    sz = [m,n]
#     scounter = 0
#     @time begin
#         for k = 1:N
#             c = ones(Int, 2)
#             sz1 = sz[1]
#             isdone = false
#             while !isdone
#                 scounter += 1
#                 if (c[1]+=1) > sz1
#                     idim = 1
#                     while c[idim] > sz[idim] && idim < 2
#                         c[idim] = 1
#                         idim += 1
#                         c[idim] += 1
#                     end
#                     isdone = c[end] > sz[end]
#                 end
#             end
#         end
#     end
#     @assert scounter == sloop
    scounter = 0
    @time begin
        for k = 1:N
            @Cartesian.forcartesian c sz begin
                scounter += 1
            end
        end
    end
    @assert scounter == sloop
#     scounter = 0
#     sz1 = sz[1]
#     sz[1] = 1
#     @time begin
#         for k = 1:N
#             @Cartesian.forcartesian c sz begin
#                 for i = 1:sz1
#                     scounter += 1
#                 end
#             end
#         end
#     end
end

testcounter(2,2,1)
testcounter(500,300,100)

# Specializations for low dimensions
for N = 1:4
    @eval begin
        function mysum{T}(A::StridedArray{T,$N})
            s = zero(T)
            Cartesian.@forarrays $N o i A begin
                s += Cartesian.parent(A)[oA]
            end
            s
        end
    end
end

# Function for arbitrary dimensions
let _mysum_defined = Dict{Any, Bool}()
global mysum
function mysum{T,N}(A::StridedArray{T,N})
    def = get(_mysum_defined, typeof(A), false)
    if !def
        ex = quote
            function _mysum{T}(A::StridedArray{T,$N})
                s = zero(T)
                Cartesian.@forarrays $N o i A begin
                    s += Cartesian.parent(A)[oA]
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

A = reshape(1:120, 3, 5, 8)
@assert mysum(A) == sum(A)
subA = sub(A, 1:3, 2:4, 3)
@assert mysum(subA) == sum(subA)

function mysum2{T}(A::StridedArray{T,2}, B::StridedArray{T,2})
    if size(A) != size(B)
        error("dimension mismatch")
    end
    ret = zeros(T, size(A))
    Cartesian.@forarrays 2 o i ret A B begin
        ret[oret] = Cartesian.parent(A)[oA] + Cartesian.parent(B)[oB]
    end
    ret
end

B = reshape(1:400, 20, 20)
subB = sub(B, 8:10, 13:15)
@assert mysum2(subA, subB) == subA+subB

function mydot{T}(A::StridedArray{T,2}, B::StridedArray{T,2})
    if size(A) != size(B)
        error("dimension mismatch")
    end
    s = zero(T)
    Cartesian.@forarrays 2 o i A B begin
        s += Cartesian.parent(A)[oA] * Cartesian.parent(B)[oB]
    end
    s
end

@assert mydot(subA, subB) == sum(subA.*subB) # rhs uses broadcast, which is already fast
