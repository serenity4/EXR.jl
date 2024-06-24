abstract type Decompressor end

function (decompressor::Decompressor)(exr::EXRStream, compressed_size, decompressed_size)
  io = decompressor(exr.io, compressed_size, decompressed_size)
  BinaryIO(exr.swap, io)
end

function (decompressor::Decompressor)(io, compressed_size, decompressed_size)
  error("Decompression not implemented for ", typeof(decompressor))
end

struct NoDecompressor <: Decompressor end

(::NoDecompressor)(io::IO, compressed_size, decompressed_size) = io

struct ZipDecompressor <: Decompressor
  codec::LibDeflate.Decompressor
  input::Vector{UInt8}
  output::Vector{UInt8}
end
ZipDecompressor(buffer_size) = ZipDecompressor(LibDeflate.Decompressor(), UInt8[], zeros(UInt8, buffer_size))

function (zip::ZipDecompressor)(io::IO, compressed_size, decompressed_size)
  fill_input_buffer!(zip.input, io, compressed_size)
  @assert length(zip.output) == decompressed_size
  ret = LibDeflate.zlib_decompress!(zip.codec, zip.output, @view(zip.input[1:compressed_size]), decompressed_size)
  isa(ret, LibDeflate.LibDeflateError) && error("An error occured while decompressing data: `$ret`")
  @assert ret == decompressed_size
  reverse_delta_encoding!(zip.output)
  output = interleave(zip.output)
  IOBuffer(output)
end

function fill_input_buffer!(buffer::Vector{UInt8}, io::IO, compressed_size)
  length(buffer) < compressed_size && resize!(buffer, compressed_size)
  for i in 1:compressed_size
    @inbounds buffer[i] = read(io, UInt8)
  end
end

function reverse_delta_encoding!(decompressed_data)
  for i in 2:length(decompressed_data)
    value = Int32(@inbounds decompressed_data[i - 1]) + Int32(@inbounds decompressed_data[i]) - Int32(128)
    @inbounds decompressed_data[i] = value % UInt8
  end
  decompressed_data
end

function interleave(decompressed_data)
  n = length(decompressed_data)
  upper_half = cld(n, 2)
  output = similar(decompressed_data)
  for i in 1:fld(n, 2)
    @inbounds output[2i - 1] = decompressed_data[i]
    @inbounds output[2i] = decompressed_data[upper_half + i]
  end
  n % 2 == 1 && (@inbounds output[end] = decompressed_data[cld(n, 2)])
  output
end
