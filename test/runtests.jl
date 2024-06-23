using EXR
using EXR: interleave, reverse_delta_encoding!
using Test

asset_file(path) = joinpath(@__DIR__, "assets", path)

function test_is_image_valid(data)
  @test isa(data, Matrix)
  @test size(data) == (256, 256)
  @test all(isone ∘ last, data)
  @test all(color -> all(0 .≤ color[1:3] .≤ 1), data)
end

@testset "EXR.jl" begin
  @testset "Decompression utilities" begin
    bytes = [0x01, 0x02, 0x03, 0x04]
    interleaved = interleave(bytes)
    @test interleaved == [0x01, 0x03, 0x02, 0x04]
    bytes = [0x01, 0x02, 0x03, 0x04, 0x05]
    interleaved = interleave(bytes)
    @test interleaved == [0x01, 0x04, 0x02, 0x05, 0x03]
    bytes = UInt8[61, 0x80 - 12, 0x80 + 7]
    reverse_delta_encoding!(bytes)
    @test bytes == UInt8[61, 49, 56]
  end

  @testset "Data retrieval" begin
    file = asset_file("render_uncompressed.exr")
    exr = EXRStream(file)
    @test_throws "channels were requested but are not present" retrieve_image(NTuple{4, Float32}, exr, [:Y, :Cb, :Cr])
    data = retrieve_image(NTuple{4, Float32}, exr)
    test_is_image_valid(data)

    file = asset_file("render_zips.exr")
    exr = EXRStream(file)
    data2 = retrieve_image(NTuple{4, Float32}, exr)
    test_is_image_valid(data)
    @test data2 == data
  end
end;
