#define WUFFS_IMPLEMENTATION

extern "C" {

	#include <png.h>
	#include <pngstruct.h>
	#define PNG_SIG_SIZE 8
}

#define MAX_PNG_SIZE (64 * 1024 * 1024)  // 64 MB
#define MAX_DIMENSION 4096

#include "wuffs-v0.4.c"
#include <stdio.h> // For printf
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <setjmp.h>
#include <graphics/format/PNG.h>
#include <graphics/ImageBuffer.h>
#include <system/System.h>
#include <utils/Bytes.h>
#include <utils/QuickVec.h>


namespace lime {

	class MyCallbacks : public wuffs_aux::DecodeImageCallbacks {
	public:
    wuffs_base__pixel_format SelectPixfmt(const wuffs_base__image_config& image_config) override {
      return wuffs_base__make_pixel_format(WUFFS_BASE__PIXEL_FORMAT__RGBA_NONPREMUL);
    }
  };


	struct ReadBuffer {

		ReadBuffer (const unsigned char* data, int length) : data (data), length (length), position (0) {}

		bool Read (unsigned char* out, int count) {

			if (position >= length) return false;

			if (count > length - position) {

				memcpy (out, data + position, length - position);
				position = length;

			} else {

				memcpy (out, data + position, count);
				position += count;

			}

			return true;

		}

		char unused; // the first byte gets corrupted when passed to libpng?
		const unsigned char* data;
		int length;
		int position;

	};

	static void user_error_fn (png_structp png_ptr, png_const_charp error_msg) {

			longjmp (png_ptr->jmp_buf_local, 1);

		}


	static void user_read_data_fn (png_structp png_ptr, png_bytep data, png_size_t length) {

		ReadBuffer* buffer = (ReadBuffer*)png_get_io_ptr (png_ptr);
		if (!buffer->Read (data, length)) {
			png_error (png_ptr, "Read Error");
		}

	}

	static void user_warning_fn (png_structp png_ptr, png_const_charp warning_msg) {}


	void user_write_data (png_structp png_ptr, png_bytep data, png_size_t length) {

		QuickVec<unsigned char> *buffer = (QuickVec<unsigned char> *)png_get_io_ptr (png_ptr);
		buffer->append ((unsigned char *)data,(int)length);

	}

	void user_flush_data (png_structp png_ptr) {}

	void DecodeImageBuffer(wuffs_aux::DecodeImageResult* result, ImageBuffer* imageBuffer, bool decodeData) {
    // Update ImageBuffer dimensions
		imageBuffer->width = result->pixbuf.pixcfg.width();
	  imageBuffer->height = result->pixbuf.pixcfg.height();

		if (decodeData)
		{
			// Resize ImageBuffer
      imageBuffer->Resize(imageBuffer->width, imageBuffer->height, 32);

      // Copy decoded data to ImageBuffer
      wuffs_base__table_u8 pixels = result->pixbuf.plane(0);
      size_t bytes_per_row = imageBuffer->width * 4;  // 4 bytes per pixel for RGBA
      for (uint32_t y = 0; y < imageBuffer->height; ++y) {
        memcpy(imageBuffer->data->buffer->b + (y * bytes_per_row),
         pixels.ptr + (y * pixels.stride),
         bytes_per_row);
      }

      // No need for color correction if the format already matches your needs
		}
	}

	bool DecodeFile(Resource* resource, ImageBuffer* imageBuffer, bool decodeData) {
	  FILE* file = stdin;
	  const char* filename = resource->path;
	  if (filename) {
	    FILE* f = ::fopen(filename, "rb");
	    if (f == NULL) {
	      printf("%s: could not open file\n", filename);
	      return false;
	    }
	    file = f;
	  }

	  const wuffs_aux::QuirkKeyValuePair wuffs_base__quirk_quality = {
	  	WUFFS_BASE__QUIRK_QUALITY,
	    WUFFS_BASE__QUIRK_QUALITY__VALUE__LOWER_QUALITY,
	  };

	  MyCallbacks callbacks;
	  wuffs_aux::sync_io::FileInput input(file);
	  wuffs_aux::DecodeImageResult result = wuffs_aux::DecodeImage(
	    callbacks,
			input,
	    wuffs_aux::DecodeImageArgQuirks(&wuffs_base__quirk_quality, 1),
	    wuffs_aux::DecodeImageArgFlags::DefaultValue(),
	    wuffs_aux::DecodeImageArgPixelBlend::DefaultValue(),
	    wuffs_aux::DecodeImageArgBackgroundColor::DefaultValue(),
	    wuffs_aux::DecodeImageArgMaxInclDimension(MAX_PNG_SIZE)
		);

	  if (filename) {
	    ::fclose(file);
	  }

	  if (!result.pixbuf.pixcfg.pixel_format().is_interleaved()) {
	    printf("%s: non-interleaved pixbuf\n", filename);
	    return false;
	  }

	  wuffs_base__table_u8 tab = result.pixbuf.plane(0);
	  if (tab.width != tab.stride) {
	    printf("%s: could not allocate tight pixbuf\n", filename);
	    return false;
	  }

    if (!result.error_message.empty()) {
      printf("Failed to decode image from %s: %s\n", filename, result.error_message.c_str());
      return false;
    }

		DecodeImageBuffer(&result, imageBuffer, decodeData);

	  return result.pixbuf.pixcfg.is_valid();
	}

	bool DecodeBytes(Resource* resource, ImageBuffer* imageBuffer, bool decodeData) {
		const wuffs_aux::QuirkKeyValuePair wuffs_base__quirk_quality = {
	    WUFFS_BASE__QUIRK_QUALITY,
	    WUFFS_BASE__QUIRK_QUALITY__VALUE__LOWER_QUALITY,
	  };

	  MyCallbacks callbacks;
    wuffs_aux::sync_io::MemoryInput input(resource->data->b, resource->data->length);
	  wuffs_aux::DecodeImageResult result = wuffs_aux::DecodeImage(
	    callbacks,
			input,
	    wuffs_aux::DecodeImageArgQuirks(&wuffs_base__quirk_quality, 1),
	    wuffs_aux::DecodeImageArgFlags::DefaultValue(),
	    wuffs_aux::DecodeImageArgPixelBlend::DefaultValue(),
	    wuffs_aux::DecodeImageArgBackgroundColor::DefaultValue(),
	    wuffs_aux::DecodeImageArgMaxInclDimension(MAX_PNG_SIZE)
		);

		if (!result.error_message.empty()) {
      printf("Failed to decode image: %s\n", result.error_message.c_str());
     return false;
    }

		DecodeImageBuffer(&result, imageBuffer, decodeData);

	  return result.pixbuf.pixcfg.is_valid();
	}

	bool PNG::Decode(Resource* resource, ImageBuffer* imageBuffer, bool decodeData) {
		if (resource->path)
		{
			return DecodeFile(resource, imageBuffer, decodeData);
		}

		if (resource->data)
		{
			return DecodeBytes(resource, imageBuffer, decodeData);
		}

    return false;
	}

	bool PNG::Encode (ImageBuffer *imageBuffer, Bytes* bytes) {

		png_structp png_ptr = png_create_write_struct (PNG_LIBPNG_VER_STRING, NULL, user_error_fn, user_warning_fn);

		if (!png_ptr) {

			return false;

		}

		png_infop info_ptr = png_create_info_struct (png_ptr);

		if (!info_ptr) {

			return false;

		}

		if (setjmp (png_jmpbuf (png_ptr))) {

			png_destroy_write_struct (&png_ptr, &info_ptr);
			return false;

		}

		QuickVec<unsigned char> out_buffer;

		png_set_write_fn (png_ptr, &out_buffer, user_write_data, user_flush_data);

		int w = imageBuffer->width;
		int h = imageBuffer->height;

		int bit_depth = 8;
		//int color_type = (inSurface->Format () & pfHasAlpha) ? PNG_COLOR_TYPE_RGB_ALPHA : PNG_COLOR_TYPE_RGB;
		int color_type = PNG_COLOR_TYPE_RGB_ALPHA;
		png_set_IHDR (png_ptr, info_ptr, w, h, bit_depth, color_type, PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_BASE, PNG_FILTER_TYPE_BASE);

		png_write_info (png_ptr, info_ptr);

		bool do_alpha = (color_type == PNG_COLOR_TYPE_RGBA);
		unsigned char* imageData = imageBuffer->data->buffer->b;
		int stride = imageBuffer->Stride ();

		{
			QuickVec<unsigned char> row_data (w * 4);
			png_bytep row = &row_data[0];

			for (int y = 0; y < h; y++) {

				unsigned char *buf = &row_data[0];
				const unsigned char *src = (const unsigned char *)(imageData + (stride * y));

				for (int x = 0; x < w; x++) {

					buf[0] = src[0];
					buf[1] = src[1];
					buf[2] = src[2];
					src += 3;
					buf += 3;

					if (do_alpha) {

						*buf++ = *src;

					}

					src++;

				}

				png_write_rows (png_ptr, &row, 1);

			}

		}

		png_write_end (png_ptr, NULL);

		int size = out_buffer.size ();

		if (size > 0) {

			bytes->Resize (size);
			memcpy (bytes->b, &out_buffer[0], size);

		}

		return true;

	}


}