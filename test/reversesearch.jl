struct NoCopyVertex end
struct CopyOnlyVertex end
Base.copy(::CopyOnlyVertex) = CopyOnlyVertex()

@testset "RSSystem" begin
    v = Int[]

    ls_oop(x) = 1
    adj_oop(x, j, aux) = 1
    ls_iip(x, y) = 1
    adj_iip(x, y, j, aux) = 1


    # Mixed in-place / out-of-place
    @test_throws ArgumentError RSSystem(ls_oop, adj_iip, v)
    @test_throws ArgumentError RSSystem(ls_iip, adj_oop, v)

    # Valid ls/adj signature variants
    ls_typed_iip(x::Vector{Int}, y::Vector{Int}) = 1
    adj_typed_iip(x::Vector{Int}, y::Vector{Int}, j, aux) = 1

    ls_param_iip(x::Vector{T}, y::Vector{T}) where T = 1
    adj_param_iip(x::Vector{T}, y::Vector{T}, j, aux) where T = 1

    ls_typed_oop(x::Vector{Int}) = 1
    adj_typed_oop(x::Vector{Int}, j::Int, aux) = 1

    ls_aux_oop(x) = 1
    adj_aux_oop(x, j, aux::Nothing) = 1

    ls_varargs(x, args...) = 1
    adj_varargs(x, j, aux, args...) = 1

    for (ls, adj) in [(ls_oop,       adj_oop),
                      (ls_iip,       adj_iip),
                      (ls_typed_iip, adj_typed_iip),
                      (ls_param_iip, adj_param_iip),
                      (ls_typed_oop, adj_typed_oop),
                      (ls_aux_oop,   adj_aux_oop),
                      (ls_varargs,   adj_varargs)]
        @test (RSSystem(ls, adj, v); true)
    end

    # Wrong vertex type
    ls_wrong(x::Vector{String}) = 1
    @test_throws ArgumentError RSSystem(ls_wrong, adj_oop, v)

    adj_wrong(x::Vector{String}, j, aux) = 1
    @test_throws ArgumentError RSSystem(ls_oop, adj_wrong, v)

    # Vector{Integer} does not match Vector{Int} (invariant type parameters)
    ls_invariant(x::Vector{Integer}) = 1
    adj_invariant(x::Vector{Integer}, j, aux) = 1
    @test_throws ArgumentError RSSystem(ls_invariant, adj_invariant, v)

    # Wrong aux type
    adj_wrong_aux(x, j, aux::Int) = 1
    @test_throws ArgumentError RSSystem(ls_oop, adj_wrong_aux, v)

    # copy not defined
    @test_throws ArgumentError RSSystem(ls_oop, adj_oop, NoCopyVertex())

    # copy! not defined: throws for in-place, fine for out-of-place
    @test_throws ArgumentError RSSystem(ls_iip, adj_iip, CopyOnlyVertex())
    @test (RSSystem(ls_oop, adj_oop, CopyOnlyVertex()); true)

    # custom comparator not defined for the vertex type
    int_compare(a::Int, b::Int) = a == b
    @test_throws ArgumentError RSSystem(ls_oop, adj_oop, 1.0; compare=int_compare)
end

@testset "RSState" begin
    _ls_oop(x::Vector{Int}) = x
    _adj_oop(x::Vector{Int}, j, aux) = x
    _ls_iip(x::Vector{Int}, y::Vector{Int}) = x
    _adj_iip(x::Vector{Int}, y::Vector{Int}, j, aux) = x

    rsys_oop = RSSystem(_ls_oop, _adj_oop, Int[])
    rsys_iip = RSSystem(_ls_iip, _adj_iip, Int[])

    state_oop = ReverseSearch.RSState(rsys_oop)
    state_iip = ReverseSearch.RSState(rsys_iip)

    @test state_oop._temp1 === nothing
    @test state_oop._temp2 === nothing
    @test state_iip._temp1 isa Vector{Int}
    @test state_iip._temp2 isa Vector{Int}
    @test state_iip._temp1 !== state_iip._temp2

    ls_oop(x::Vector{Int}) = x
    adj_oop(x::Vector{Int}, j, aux) = x
    ls_iip(x::Vector{Int}, y::Vector{Int}) = x
    adj_iip(x::Vector{Int}, y::Vector{Int}, j, aux) = x
    my_compare(a::Vector{Int}, b::Vector{Int}) = a == b

    @test repr(RSSystem(ls_oop, adj_oop, Int[]))                          == "RSSystem{!iip}(V=Vector{Int64})"
    @test repr(RSSystem(ls_iip, adj_iip, Int[]))                          == "RSSystem{iip}(V=Vector{Int64})"
    @test repr(RSSystem(ls_oop, adj_oop, Int[]; aux=Int[]))               == "RSSystem{!iip}(V=Vector{Int64}, aux=Vector{Int64})"
    @test repr(RSSystem(ls_oop, adj_oop, Int[]; compare=my_compare))      == "RSSystem{!iip}(V=Vector{Int64}, compare=my_compare)"
    @test repr(RSSystem(ls_oop, adj_oop, Int[]; aux=Int[], compare=my_compare)) == "RSSystem{!iip}(V=Vector{Int64}, aux=Vector{Int64}, compare=my_compare)"
end

@testset "RSResult" begin
    r = RSResult(Finished, 10, 5)
    @test r.status == Finished
    @test r.nvertices == 10
    @test r.depth_reached == 5

    @test RSResult(Finished, 10, 5) == RSResult(Finished, 10, 5)
    @test RSResult(Finished, 10, 5) != RSResult(MaxVerticesReached, 10, 5)
    @test RSResult(Finished, 10, 5) != RSResult(Finished, 99, 5)
    @test RSResult(Finished, 10, 5) != RSResult(Finished, 10, 99)

    @test repr(RSResult(MaxDepthReached, 7, 3)) == "RSResult(MaxDepthReached, nvertices=7, depth_reached=3)"
end
