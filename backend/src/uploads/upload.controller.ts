import { Controller, Post, UseInterceptors, UploadedFile, UseGuards, BadRequestException } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { diskStorage } from 'multer';
import { extname } from 'path';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

// Whitelisted image types. SVG is deliberately EXCLUDED — it can carry script
// and these files are served publicly from the API origin.
const ALLOWED_EXT = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
const ALLOWED_MIME = [
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
];

@Controller('uploads')
export class UploadController {
  @Post('image')
  @UseGuards(JwtAuthGuard)
  @UseInterceptors(FileInterceptor('file', {
    storage: diskStorage({
      destination: './uploads',
      filename: (req, file, callback) => {
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
        // SECURITY FIX: derive the stored extension from the VALIDATED
        // whitelist, never from user input. Previously `extname(originalname)`
        // was trusted, so "x.jpg.html" passed the (unanchored) filter and was
        // stored — and served — as .html from the API origin.
        const ext = ALLOWED_EXT.find((e) =>
          file.originalname.toLowerCase().endsWith(e),
        ) ?? '.jpg';
        callback(null, `${uniqueSuffix}${ext}`);
      },
    }),
    fileFilter: (req, file, callback) => {
      // Anchored extension check AND declared MIME must both be an image.
      const name = file.originalname.toLowerCase();
      const extOk = ALLOWED_EXT.some((e) => name.endsWith(e));
      const mimeOk = ALLOWED_MIME.includes(file.mimetype);
      if (!extOk || !mimeOk) {
        return callback(new BadRequestException('Only image files are allowed!'), false);
      }
      callback(null, true);
    },
    limits: {
      fileSize: 5 * 1024 * 1024, // 5MB limit
    },
  }))
  uploadFile(@UploadedFile() file: Express.Multer.File) {
    if (!file) {
      throw new BadRequestException('File is missing');
    }
    
    // Return the relative URL that can be used to access the file
    // Assumes the application is serving the uploads folder at /uploads
    return {
      url: `/uploads/${file.filename}`,
      filename: file.filename,
    };
  }
}
