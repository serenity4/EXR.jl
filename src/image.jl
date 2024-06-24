function retrieve_image(::Type{T}, exr::EXRStream, channels = default_channels(T)) where {T}
  is_single_part(exr) || error("Only single-part EXR files are currently supported")
  retrieve_image(T, exr, exr.parts, channels)
end

function retrieve_image(::Type{T}, exr::EXRStream, part::EXRPart, channels) where {T}
  is_single_part(exr) || error("Only single-part EXR files are currently supported")
  check_channels(part.channels, channels)
  is_tiled(part) && return retrieve_image_from_tiles(part, channels)
  retrieve_image_from_scanlines(T, exr, part, channels)
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

function retrieve_image_from_scanlines(::Type{T}, exr::EXRStream, part::EXRPart, channels) where {T}
  if part.compression == COMPRESSION_NONE
    retrieve_image_from_scanlines(T, exr, part, channels, NoDecompressor())
  elseif part.compression == COMPRESSION_ZIP || part.compression == COMPRESSION_ZIPS
    aggregated_channel_size = sum(channels; init = 0) do channel
      i = findfirst(y -> channel === y.name, part.channels)::Int
      channelsize(part.channels[i])
    end
    (; width) = dimensions(part.data_window)
    buffer_size = aggregated_channel_size * width * scanlines_per_chunk(part.compression)
    retrieve_image_from_scanlines(T, exr, part, channels, ZipDecompressor(buffer_size))
  else
    error("Data compression mode `$(part.compression)` is not yet supported for reading")
  end
end

struct ChannelReadInfo
  channel::Channel
  size::Int64
  offset::Int64
end

struct ScanlineBlockReader{N,CT,T,D<:Decompressor}
  offsets::Vector{UInt64}
  scanlines_per_block::Int64
  width::Int64
  height::Int64
  decompressor::D
  channels::Vector{ChannelReadInfo}
  texel_size::Int64
  per_channel_data::NTuple{N, Vector{CT}}
  aggregated_data::Matrix{T}
end

function ScanlineBlockReader(::Type{T}, exr::EXRStream, part::EXRPart, channel_selection, decompressor::Decompressor) where {T}
  offsets = retrieve_offset_table!(exr, part)
  scanlines_per_block = scanlines_per_chunk(part.compression)
  width, height = dimensions(part.data_window)
  CT = component_type(T)
  CT === Any && error("Inferred component type for `$T` is `Any`; you will need to extend `component_type(::Type{$T})` to return the appropriate component type")
  per_channel_data = ntuple(_ -> zeros(CT, width), length(channel_selection))
  channels = ChannelReadInfo[]
  for name in channel_selection
    i = findfirst(c -> name === c.name, part.channels)::Int
    channel = part.channels[i]
    size = channelsize(channel)
    offset = sum(channelsize, @view part.channels[begin:(i - 1)]; init = 0)
    push!(channels, ChannelReadInfo(channel, size, offset))
  end
  texel_size = sum(channelsize, part.channels; init = 0)
  aggregated_data = Matrix{T}(undef, height, width)
  ScanlineBlockReader(offsets, scanlines_per_block, width, height, decompressor, channels, texel_size, per_channel_data, aggregated_data)
end

function retrieve_image_from_scanlines(::Type{T}, exr::EXRStream, part::EXRPart, channel_selection, decompressor::Decompressor) where {T}
  block_reader = ScanlineBlockReader(T, exr, part, channel_selection, decompressor)
  retrieve_image_from_scanlines!(block_reader, exr)
end

function retrieve_image_from_scanlines!(block_reader::ScanlineBlockReader, exr::EXRStream)
  (; width, height, texel_size, scanlines_per_block) = block_reader
  decompressed_scanline_size = width * texel_size
  decompressed_block_size = decompressed_scanline_size * scanlines_per_block
  for (k, offset) in enumerate(block_reader.offsets)
    seek(exr.io, offset)
    is_multi_part(exr) && (part_number = read(exr.io, UInt64))
    y = read(exr.io, Int32)
    compressed_block_size = read(exr.io, Int32)
    io = block_reader.decompressor(exr, compressed_block_size, decompressed_block_size)
    for i in 1:scanlines_per_block
      origin = position(io)
      scanline = i + (k - 1) * scanlines_per_block
      scanline > height && return data
      read_scanline_uncompressed!(block_reader, io, scanline)
      scanlines_per_block > 1 && skip(io, decompressed_scanline_size - (position(io) - origin))
    end
  end
  block_reader.aggregated_data
end

function read_scanline_uncompressed!(block_reader::ScanlineBlockReader, io::IO, scanline)
  gather_channels!(block_reader, io)
  aggregate_channels!(block_reader, scanline)
end

function gather_channels!(block_reader::ScanlineBlockReader{N, CT}, io) where {N, CT}
  (; width, channels, per_channel_data) = block_reader
  origin = position(io)
  for (info, data) in zip(channels, per_channel_data)
    (; channel, offset, size) = info
    for i in 1:width
      seek(io, origin + offset * width + (i - 1) * size)
      data[i] = read_component(io, CT, channel)
    end
  end
end

function aggregate_channels!(block_reader::ScanlineBlockReader{N, CT, T}, scanline) where {N, CT, T}
  (; width, aggregated_data, per_channel_data) = block_reader
  for j in 1:width
    value = construct(T, ntuple(ni -> per_channel_data[ni][scanline], ncomponents(T)))
    aggregated_data[scanline, j] = value
  end
  aggregated_data
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
