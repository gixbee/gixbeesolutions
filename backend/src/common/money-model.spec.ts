import {
  DEFAULT_BOOKING_PAYMENT_METHOD,
  NEW_USER_WALLET_BONUS,
  WALLET_PAYMENTS_ENABLED,
  WalletPaymentsDisabledError,
  assertWalletPaymentsEnabled,
} from './money-model';

describe('money-model source of truth', () => {
  it('keeps the wallet product off', () => {
    expect(WALLET_PAYMENTS_ENABLED).toBe(false);
  });

  it('defaults new bookings to direct cash collection', () => {
    expect(DEFAULT_BOOKING_PAYMENT_METHOD).toBe('CASH');
  });

  it('does not mint a welcome wallet balance while wallet is off', () => {
    expect(NEW_USER_WALLET_BONUS).toBe(0);
  });

  it('throws a typed error when wallet actions are attempted while off', () => {
    expect(() => assertWalletPaymentsEnabled('recharge')).toThrow(
      WalletPaymentsDisabledError,
    );
    expect(() => assertWalletPaymentsEnabled('recharge')).toThrow(/disabled/);
  });
});
