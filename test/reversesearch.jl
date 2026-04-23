@testset "reverse search" begin
    v = Int[]

    ls1(x) = 1
    adj1(x, j, aux) = 1

    ls2(x, y) = 1
    adj2(x, y, j, aux) = 1

    @test_throws ArgumentError RSSystem(ls1, adj2, v; aux=nothing)
    @test_throws ArgumentError RSSystem(ls2, adj1, v; aux=nothing)

    ls3(x::Vector{Int}, y::Vector{Int}) = 1
    adj3(x::Vector{Int}, y::Vector{Int}, j, aux) = 1

    ls4(x::Vector{Integer}) = 1
    adj4(x::Vector{Integer}, j, aux) = 1

    ls5(x::Vector{T}, y::Vector{T}) where T = 1
    adj5(x::Vector{T}, y::Vector{T}, j, aux) where T = 1

    ls6(x::Vector{Integer}) = 1
    adj6(x::Vector{Integer}, j::Integer, aux) = 1

    ls7(x::Vector{Int}) = 1
    adj7(x::Vector{Int}, j::Int, aux) = 1

    ls8(x) = 1
    adj8(x, j, aux::Nothing) = 1

    ls9(x, args...) = 1
    adj9(x, j, aux, args...) = 1

    for (ls, adj) in zip([ls1, ls2, ls3, ls4, ls5, ls6, ls7, ls8, ls9], 
                         [adj1, adj2, adj3, adj4, adj5, adj6, adj7, adj8, adj9])
        @test (RSSystem(ls1, adj1, v; aux=nothing); true)
        @test (RSSystem(ls2, adj2, v; aux=nothing); true)
    end

    ls10(x::Vector{String}) = 1
    adj10(x, j, aux) = 1

    @test_throws ArgumentError RSSystem(ls10, adj10, v; aux=nothing)

    ls11(x) = 1
    adj11(x::Vector{String}, j, aux) = 1

    @test_throws ArgumentError RSSystem(ls11, adj11, v; aux=nothing)

    ls12(x) = 1
    adj12(x, j, aux::Int) = 1

    @test_throws ArgumentError RSSystem(ls12, adj12, v; aux=nothing)
end