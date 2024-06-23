@bitmask EXRFlags::UInt32 begin
  EXR_SINGLE_PART_SCANLINE = 0
  EXR_SINGLE_PART_TILED = 1
  EXR_LONG_NAMES = 2
  EXR_DEEP_DATA = 4
  EXR_MULTIPLE_PARTS = 8
end

struct TiledImage
end

@enum LineOrder::UInt8 begin
  LINE_ORDER_INCREASING_Y = 0
  LINE_ORDER_DECREASING_Y = 1
  LINE_ORDER_RANDOM_Y = 2
end

struct ScanlineImage
  line_order::LineOrder
end

@enum EXRPartType::UInt8 begin
  EXR_PART_SCANLINE_IMAGE = 0
  EXR_PART_TILED_IMAGE = 1
  EXR_PART_SCANLINE_DEEP = 2
  EXR_PART_TILED_DEEP = 3
end

function Base.read(io::IO, ::Type{EXRPartType})
  input = read_null_terminated_string(io)
  startswith(input, 's') && return EXR_PART_SCANLINE_IMAGE
  startswith(input, 't') && return EXR_PART_TILED_IMAGE
  startswith(input, "deeps") && return EXR_PART_SCANLINE_DEEP
  startswith(input, "deept") && return EXR_PART_TILED_DEEP
  error("Unknown EXR part type ", repr(input))
end

@enum LevelMode::UInt8 begin
  LEVEL_MODE_ONE_LEVEL = 0
  LEVEL_MODE_MIPMAP_LEVELS = 1
  LEVEL_MODE_RIPMAP_LEVELS = 2
end

@enum RoundingMode::UInt8 begin
  ROUNDING_MODE_DOWN = 0
  ROUNDING_MODE_UP = 1
end

@serializable struct TileDescription
  @arg mode = UInt8(0)
  size_x::UInt32
  size_y::UInt32
  level_mode::LevelMode << begin
    mode = read(io, UInt8)
    LevelMode((mode << 4) >> 4)
  end
  rounding_mode::RoundingMode << RoundingMode(mode >> 4)
end

struct CompressionInfo
  name::Symbol
  flag::Compression
  scanlines::Int64
  lossy::Bool
  supports_deep_data::Bool
end

const COMPRESSION_INFOS = [
  CompressionInfo(:none, COMPRESSION_NONE, 1, false, true),
  CompressionInfo(:rle, COMPRESSION_RLE, 1, false, true),
  CompressionInfo(:zips, COMPRESSION_ZIPS, 1, false, true),
  CompressionInfo(:zip, COMPRESSION_ZIP, 16, false, false),
  CompressionInfo(:piz, COMPRESSION_PIZ, 32, false, false),
  CompressionInfo(:pxr24, COMPRESSION_PXR24, 16, true, false),
  CompressionInfo(:b44, COMPRESSION_B44, 32, true, false),
  CompressionInfo(:b44a, COMPRESSION_B44A, 32, true, false),
  CompressionInfo(:dwaa, COMPRESSION_NONE, 32, true, false),
  CompressionInfo(:dwab, COMPRESSION_NONE, 256, true, false),
]

mutable struct EXRPart{IO<:Base.IO}
  io::IO
  name::Symbol
  type::EXRPartType
  version::Int32
  display_window::Box2I
  data_window::Box2I
  pixel_aspect_ratio::Float32
  screen_window_width::Float32
  screen_window_center::Tuple{Float32, Float32}
  compression::Compression
  line_order::LineOrder
  chunk_count::Int32
  tiles::Optional{TileDescription}
  channels::Vector{Channel}
  attributes::AttributeIterator{IO}
  offset_table_location::Int64
  "Offsets from the beginning of the stream to each chunk data."
  offsets::Vector{UInt64}
  function EXRPart{IO}(io::IO) where {IO}
    part = new{typeof(io)}(io)
    part.tiles = nothing
    part
  end
end

function scanlines_per_chunk(compression::Compression)
  i = findfirst(x -> x.flag == compression, COMPRESSION_INFOS)
  isnothing(i) && error("No information exists for compression mode `$compression`")
  info = COMPRESSION_INFOS[i]
  info.scanlines
end

is_scanline(part::EXRPart) = part.type in (EXR_PART_SCANLINE_IMAGE, EXR_PART_SCANLINE_DEEP)
is_tiled(part::EXRPart) = !is_scanline(part)

function number_of_chunks(part::EXRPart)
  part.chunk_count > 0 && return part.chunk_count
  part.chunk_count = is_scanline(part) ? number_of_scanline_blocks(part) : number_of_tiles(part)
end

function number_of_scanline_blocks(part::EXRPart)
  scanlines = scanlines_per_chunk(part.compression)
  (; height) = dimensions(part.data_window)
  height ÷ scanlines
end

function number_of_tiles(part::EXRPart)
  # see getTiledChunkOffsetTableSize at openexr/src/lib/OpenEXR/ImfTableMisc.cpp:309
  error("Not implemented yet")
end

Base.show(io::IO, part::EXRPart) = print(io, EXRPart, "($(length(part.attributes)) attributes, $(length(part.channels)) channels)")

mutable struct EXRStream{IO<:Base.IO}
  io::IO
  swap::Bool
  version::UInt32
  flags::EXRFlags
  parts::Union{EXRPart{IO}, Vector{EXRPart{IO}}}
  offset_tables_origin::Int64
  EXRStream{IO}(io::IO) where {IO<:BinaryIO} = finalizer(exr -> close(exr.io), new{IO}(io, io.swap))
end

function Base.show(io::IO, exr::EXRStream)
  nparts = isa(exr.parts, Vector) ? length(exr.parts) : 1
  print(io, EXRStream, "(version = $(Int(exr.version)), flags = $(bitmask_name(exr.flags)), $nparts part$(nparts > 1 ? "s" : ""))")
end

is_single_part(exr::EXRStream) = !is_multi_part(exr)
is_multi_part(exr::EXRStream) = in(EXR_MULTIPLE_PARTS, exr.flags)

is_tiled(exr::EXRStream) = in(EXR_SINGLE_PART_TILED, exr.flags)
