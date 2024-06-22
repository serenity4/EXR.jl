module EXR

using BinaryParsingTools
using BitMasks

const Optional{T} = Union{Nothing, T}

const MAGIC_NUMBER = 0x01312f76

include("predefined_types.jl")
include("attributes.jl")
include("channels.jl")
include("stream.jl")
include("parse.jl")
include("image.jl")

export EXRStream,
       retrieve_image

end
