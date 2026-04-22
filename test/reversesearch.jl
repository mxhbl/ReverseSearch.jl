@testset "reverse search" begin
    f1(x, y) = 1
    f2(x, args...) = 1

    @test ReverseSearch._isinplace(f1, 2, "f1") == true
    @test ReverseSearch._isinplace(f1, 3, "f1") == false
    @test_throws ArgumentError ReverseSearch._isinplace(f1, 1, "f1")
    @test_throws ArgumentError ReverseSearch._isinplace(f1, 4, "f1")
    @test_throws ArgumentError ReverseSearch._isinplace(f1, 10, "f1")

    @test ReverseSearch._isinplace(f2, 1, "f2") == true
    @test ReverseSearch._isinplace(f2, 2, "f2") == true
    @test ReverseSearch._isinplace(f2, 3, "f2") == true
    @test ReverseSearch._isinplace(f2, 4, "f2") == true
    @test ReverseSearch._isinplace(f2, 10, "f2") == true
end