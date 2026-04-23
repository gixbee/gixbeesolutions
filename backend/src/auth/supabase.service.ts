import { Injectable, Global } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';

@Injectable()
export class SupabaseService {
  private client: SupabaseClient;

  constructor(private configService: ConfigService) {
    const url = this.configService.get<string>('SUPABASE_URL');
    const key = this.configService.get<string>('SUPABASE_ANON_KEY');

    if (!url || !key || url.includes('your-project-id')) {
      console.warn('[SupabaseService] Missing or placeholder credentials — Auth will fail!');
    }

    this.client = createClient(url!, key!);
  }

  getClient(): SupabaseClient {
    return this.client;
  }

  /**
   * Verify a Supabase JWT and return the user payload
   */
  async verifyToken(token: string) {
    const { data: { user }, error } = await this.client.auth.getUser(token);
    if (error || !user) {
      throw error || new Error('User not found in Supabase');
    }
    return user;
  }
}
