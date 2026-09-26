import { Process, Processor } from '@nestjs/bull';
import { Logger } from '@nestjs/common';
import type { Job } from 'bull';
import { MatchingService } from './matching.service';

/**
 * BullMQ worker for the Smart Hiring 24 h engine.
 * Jobs are scheduled with fixed jobIds at request creation, so Redis
 * deduplicates them across backend replicas and restarts.
 *   - 'batch'    → staged candidate fan-out (Hour 0 / 8 / 18)
 *   - 'finalize' → 24 h deadline: deliver shortlist to employer
 */
@Processor('hiring')
export class HiringMatchProcessor {
  private readonly logger = new Logger(HiringMatchProcessor.name);

  constructor(private readonly matchingService: MatchingService) {}

  @Process('batch')
  async handleBatch(
    job: Job<{ requestId: string; batchIndex: number }>,
  ): Promise<void> {
    const { requestId, batchIndex } = job.data ?? ({} as any);
    if (!requestId) return;
    try {
      await this.matchingService.sendBatch(requestId, batchIndex ?? 0);
    } catch (e) {
      this.logger.error(
        `batch ${batchIndex} for ${requestId} failed: ${(e as Error)?.message}`,
      );
      throw e; // let Bull retry
    }
  }

  @Process('finalize')
  async handleFinalize(job: Job<{ requestId: string }>): Promise<void> {
    const { requestId } = job.data ?? ({} as any);
    if (!requestId) return;
    try {
      await this.matchingService.finalize(requestId);
    } catch (e) {
      this.logger.error(
        `finalize for ${requestId} failed: ${(e as Error)?.message}`,
      );
      throw e;
    }
  }
}
