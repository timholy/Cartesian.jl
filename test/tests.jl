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
    scounter = 0
    @time begin
        for k = 1:N
            c = ones(Int, 2)
            sz1 = sz[1]
            isdone = false
            while !isdone
                scounter += 1
                if (c[1]+=1) > sz1
                    idim = 1
                    while c[idim] > sz[idim] && idim < 2
                        c[idim] = 1
                        idim += 1
                        c[idim] += 1
                    end
                    isdone = c[end] > sz[end]
                end
            end
        end
    end
    @assert scounter == sloop
    scounter = 0
    @time begin
        for k = 1:N
            @Cartesian.forcartesian c sz begin
                scounter += 1
            end
        end
    end
    @assert scounter == sloop
    scounter = 0
    sz1 = sz[1]
    sz[1] = 1
    @time begin
        for k = 1:N
            @Cartesian.forcartesian c sz begin
                for i = 1:sz1
                    scounter += 1
                end
            end
        end
    end
end

testcounter(2,2,1)
testcounter(500,300,100)
