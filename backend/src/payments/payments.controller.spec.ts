import { PaymentsController } from './payments.controller';

/**
 * Unit tests for the PaymentsController HTTP layer — a thin delegation surface
 * over PaymentsService (the Phase-5 credential-blocked gateway stub). Instantiated
 * directly with a jest-mock service (matching this repo's service-spec style — no
 * Nest TestingModule, no network). Asserts:
 *  - getGatewayStatus() returns the service payload verbatim (public route).
 *  - initiateUpi() forwards req.user.userId + the body to the service.
 */

function makeController() {
  const paymentsService: any = {
    getGatewayStatus: jest.fn(() => ({
      wallet: { available: true },
      cash: { available: true },
      upi: {
        available: false,
        provider: 'PHONEPE',
        needsApiKey: true,
        message: 'm',
      },
    })),
    initiateUpiPayment: jest.fn(() => ({
      status: 'UNAVAILABLE',
      needsApiKey: true,
    })),
  };
  const controller = new PaymentsController(paymentsService);
  return { controller, paymentsService };
}

describe('PaymentsController.getGatewayStatus', () => {
  it('returns the service gateway-status payload verbatim', () => {
    const { controller, paymentsService } = makeController();
    const res = controller.getGatewayStatus();
    expect(paymentsService.getGatewayStatus).toHaveBeenCalledTimes(1);
    expect(res).toEqual(paymentsService.getGatewayStatus.mock.results[0].value);
    expect(res.upi.provider).toBe('PHONEPE');
  });
});

describe('PaymentsController.initiateUpi', () => {
  it('forwards the caller id and body to the service', () => {
    const { controller, paymentsService } = makeController();
    const body = { amount: 250, bookingId: 'b1' };
    const res = controller.initiateUpi({ user: { userId: 'u-1' } }, body);
    expect(paymentsService.initiateUpiPayment).toHaveBeenCalledWith(
      'u-1',
      body,
    );
    expect(res).toEqual({ status: 'UNAVAILABLE', needsApiKey: true });
  });
});
