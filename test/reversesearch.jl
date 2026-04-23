@testset "reverse search" begin
    f1(x, y) = 1
    f2(x, args...) = 1

    f3(x::Int, y::Float64) = 1
    f4(x::String, args...) = 1

    f5(x::T, y::F) where {T,F} = 1
    f6(x::T, args...) where {T} = 1

    for f in [f1, f3, f5]
        @test ReverseSearch._isinplace(f, 2, "f") == true
        @test ReverseSearch._isinplace(f, 3, "f") == false
        @test_throws ArgumentError ReverseSearch._isinplace(f, 1, "f")
        @test_throws ArgumentError ReverseSearch._isinplace(f, 4, "f")
        @test_throws ArgumentError ReverseSearch._isinplace(f, 10, "f")
    end
    for f in [f2, f4, f6]
        @test ReverseSearch._isinplace(f, 1, "f") == true
        @test ReverseSearch._isinplace(f, 2, "f") == true
        @test ReverseSearch._isinplace(f, 3, "f") == true
        @test ReverseSearch._isinplace(f, 4, "f") == true
        @test ReverseSearch._isinplace(f, 10, "f") == true
    end
end