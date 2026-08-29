import { BadRequestException } from '@nestjs/common';
import { WorkerGoLiveService } from './worker-golive.service';

/**
 * ARCH-004: legacy wallet period-fee endpoint must fail closed when wallet OFF.
 */
describe('WorkerGoLiveService.payPeriodFee (wallet OFF)', () => {
  it('rejects wallet charge and points callers at Razorpay order path', async () => {
    const service = Object.create(WorkerGoLiveService.prototype) as WorkerGoLiveService;
    await expect(service.payPeriodFee('user-1')).rejects.toBeInstanceOf(
      BadRequestException,
    );
    await expect(service.payPeriodFee('user-1')).rejects.toThrow(
      '/payments/period-fee/order',
    );
  });
});
