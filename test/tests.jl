import Cartesian

function testcounter(m, n, N)
    sloop = 0
    tbase = @elapsed begin
        for k = 1:N
            for j = 1:n
                for i = 1:m
                    sloop += 1
                end
            end
        end
    end
    sz = [m,n]
    scounter = 0
    t = @elapsed begin
        for k = 1:N
            @Cartesian.forcartesian c sz begin
                scounter += 1
            end
        end
    end
    @assert scounter == sloop
    tbase, t
end

testcounter(2,2,1)
tbase, t = testcounter(500,300,100)
# @assert t < 10tbase

include("testloops.jl")
