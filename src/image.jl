function retrieve_image(exr::EXRStream)
  is_single_part(exr) || error("Only single-part EXR files are currently supported")
  retrieve_image(exr, exr.part)
end

function retrieve_image(exr::EXRStream, part::EXRPart)
  is_single_part(exr) || error("Only single-part EXR files are currently supported")
  is_tiled(part) && return retrieve_image_from_tiles(part)
  retrieve_image_from_scanline(part)
end

function retrieve_image_from_scanline(exr::EXRStream, part::EXRPart)
  n = number_of_chunks(part)
  # XXX: `part.offset` not defined, should we store it?
  # Do we store the offset into the offset table or do we
  # read it eagerly?
  # might be fairly large, probably best not to read the table eagerly.
  seek(exr.io, part.offset)
  offsets = [read(part.io, UInt64) for _ in 1:n]
  # TODO
end

function retrieve_image_from_tiles(part::EXRPart)
  error("Not implemented yet")
end
