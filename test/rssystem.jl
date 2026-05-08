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
        println("he")
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
