@serializable struct Box2{T}
  xmin::T
  ymin::T
  xmax::T
  ymax::T
end
const Box2I = Box2{Int32}
const Box2F = Box2{Float32}

dimensions(box::Box2) = (; width = 1 + box.xmax - box.xmin, height = 1 + box.ymax - box.ymin)

# Define little-endian reader (for floats).
struct LittleEndian{T} end
Base.read(io::IO, ::Type{LittleEndian{T}}) where {T} = read_little_endian(io, T)
read_little_endian(io::IO, ::Type{T}) where {T} = ltoh(reinterpret(T, ntuple(i -> read(io, UInt8), sizeof(T))))

struct NullTerminatedString end
Base.read(io::IO, ::Type{NullTerminatedString}) = read_null_terminated_string(io)

@enum PixelType::UInt32 begin
  PIXEL_TYPE_UINT32 = 0
  PIXEL_TYPE_FLOAT16 = 1
  PIXEL_TYPE_FLOAT32 = 2
end

function pixelsize(type::PixelType)
  type == PIXEL_TYPE_FLOAT16 && return 2
  4
end

@serializable struct Chromaticities
  red_x::Float32
  red_y::Float32
  green_x::Float32
  green_y::Float32
  blue_x::Float32
  blue_y::Float32
  white_x::Float32
  white_y::Float32
end

@enum Compression::UInt8 begin
  COMPRESSION_NONE = 0
  COMPRESSION_RLE = 1
  COMPRESSION_ZIPS = 2
  COMPRESSION_ZIP = 3
  COMPRESSION_PIZ = 4
  COMPRESSION_PXR24 = 5
  COMPRESSION_B44 = 6
  COMPRESSION_B44A = 7
end

@enum EnvironmentMap::UInt8 begin
  ENVIRONMENT_MAP_LATLONG = 0
  ENVIRONMENT_MAP_CUBE = 1
end

# <-- more types here

struct TimeCode
  time_and_flags::UInt32
  user_data::UInt32
end
