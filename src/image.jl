function retrieve_image(::Type{T}, exr::EXRStream, channels = default_channels(T)) where {T}
  is_single_part(exr) || error("Only single-part EXR files are currently supported")
  retrieve_image(T, exr, exr.parts, channels)
end

function retrieve_image(::Type{T}, exr::EXRStream, part::EXRPart, channels) where {T}
  is_single_part(exr) || error("Only single-part EXR files are currently supported")
  check_channels(part.channels, channels)
  is_tiled(part) && return retrieve_image_from_tiles(part, channels)
  retrieve_image_from_scanline(T, exr, part, channels)
end

function check_channels(channels, names)
  if any(name -> isnothing(findfirst(c -> c.name == name, channels)), names)
    unknown = names[findall(name -> isnothing(findfirst(c -> c.name == name, channels)), names)]
    error("""
    The following channels were requested but are not present in the EXR file: $(join(repr.(unknown), ", "))

    Available channels are: $(join([repr(c.name) for c in channels], ", "))
    """)
  end
end

default_channels(::Type{T}) where {T} = (:R, :G, :B, :A)
default_channels(::Type{T}) where {T<:AbstractFloat} = (:D,)

# XXX: Should we really cache that, or could it hold on to
# unreasonably too much memory?
function retrieve_offset_table!(exr::EXRStream, part::EXRPart)
  isdefined(part, :offsets) && return part.offsets
  seek(exr.io, exr.offset_tables_origin)
  part.offsets = [read(exr.io, UInt64) for _ in 1:number_of_chunks(part)]
end

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
  reconstruct!(zip.output)
  output = interleave(zip.output)
  IOBuffer(output)
end

function fill_input_buffer!(buffer::Vector{UInt8}, io::IO, compressed_size)
  length(buffer) < compressed_size && resize!(buffer, compressed_size)
  for i in 1:compressed_size
    @inbounds buffer[i] = read(io, UInt8)
  end
end

function reconstruct!(decompressed_data)
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

function retrieve_image_from_scanline(::Type{T}, exr::EXRStream, part::EXRPart, channels) where {T}
  if part.compression == COMPRESSION_NONE
    retrieve_image_from_scanline(T, exr, part, channels, NoDecompressor())
  elseif part.compression == COMPRESSION_ZIP || part.compression == COMPRESSION_ZIPS
    aggregated_channel_size = sum(channels; init = 0) do channel
      i = findfirst(y -> channel === y.name, part.channels)::Int
      channelsize(part.channels[i])
    end
    (; width) = dimensions(part.data_window)
    buffer_size = aggregated_channel_size * width * scanlines_per_chunk(part.compression)
    retrieve_image_from_scanline(T, exr, part, channels, ZipDecompressor(buffer_size))
  else
    error("Data compression mode `$(part.compression)` is not yet supported for reading")
  end
end

function retrieve_image_from_scanline(::Type{T}, exr::EXRStream, part::EXRPart, channel_selection, decompressor::Decompressor) where {T}
  channel_mask = [findfirst(y -> x === y.name, part.channels)::Int for x in channel_selection]
  channels = part.channels[channel_mask]
  channel_sizes = channelsize.(channels)
  channel_offsets = [sum(@view channel_sizes[begin:(ind - 1)]) for ind in channel_mask]
  CT = component_type(T)
  CT === Any && error("Inferred component type for `$T` is `Any`; you will need to extend `component_type(::Type{$T})` to return the appropriate component type")
  width, height = dimensions(part.data_window)
  channel_data = ntuple(_ -> zeros(CT, width), length(channels))
  data = Matrix{T}(undef, height, width)
  row_data_size = width * sum(channelsize, part.channels; init = 0)
  for (i, offset) in enumerate(retrieve_offset_table!(exr, part))
    seek(exr.io, offset)
    is_multi_part(exr) && (part_number = read(exr.io, UInt64))
    y = read(exr.io, Int32)
    scanline_data_size = read(exr.io, Int32)
    read_scanline_uncompressed!(data, channel_data, decompressor(exr, scanline_data_size, row_data_size), part, i, channels, channel_offsets, channel_sizes)
  end
  data
end

function read_scanline_uncompressed!(data::Matrix{T}, channel_data, io::IO, part::EXRPart, i, channels, channel_offsets, channel_sizes) where {T}
  gather_channels!(channel_data, io, channels, channel_offsets, channel_sizes)
  aggregate_channels!(data, channel_data, i)
end

function gather_channels!(data::NTuple{N,Vector{T}}, io, channels, offsets, sizes) where {N,T}
  width = length(data[1])
  origin = position(io)
  for (channel, chdata, offset, size) in zip(channels, data, offsets, sizes)
    for i in 1:width
      seek(io, origin + offset * width + (i - 1) * size)
      chdata[i] = read_component(io, T, channel)
    end
  end
end

function aggregate_channels!(data::Matrix{T}, channel_data, i) where {T}
  width = size(data, 2)
  for j in 1:width
    data[i, j] = construct(T, ntuple(ni -> channel_data[ni][i], ncomponents(T)))
  end
  data
end

component_type(::Type{T}) where {T} = eltype(T)
construct(::Type{T}, components) where {T} = T(components...)
construct(::Type{T}, components) where {T<:Tuple} = convert(T, components)
ncomponents(::Type{T}) where {T} = length(T)
ncomponents(::Type{T}) where {N,T<:NTuple{N}} = N

function read_component(io::IO, ::Type{CT}, channel::Channel) where {CT}
  channel.pixel_type === PIXEL_TYPE_FLOAT16 && return convert(CT, read(io, LittleEndian{Float16}))
  channel.pixel_type === PIXEL_TYPE_FLOAT32 && return convert(CT, read(io, LittleEndian{Float32}))
  channel.pixel_type === PIXEL_TYPE_UINT32 && return convert(CT, read(io, UInt32))
  error("Unknown pixel type")
end

function retrieve_image_from_tiles(part::EXRPart)
  error("Not implemented yet")
end
