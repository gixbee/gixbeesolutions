import {
  ArgumentsHost,
  BadRequestException,
  HttpStatus,
  NotFoundException,
} from '@nestjs/common';
import { QueryFailedError } from 'typeorm';
import { AllExceptionsFilter } from './all-exceptions.filter';

/**
 * Build a QueryFailedError carrying a Postgres SQLSTATE on its `driverError`,
 * mirroring what the `pg` driver attaches in production. The raw SQL detail
 * (table/column names, offending value) lives in the driver message and must
 * never reach the client envelope.
 */
function makeQueryFailedError(code: string, detail = 'Key (phone)=(+15555550000) already exists.') {
  const driverError: any = new Error(detail);
  driverError.code = code;
  driverError.detail = detail;
  const qfe = new QueryFailedError('INSERT INTO "user" ...', [], driverError);
  // Some typeorm/pg versions also surface the code on the QFE itself.
  (qfe as any).code = code;
  return qfe;
}

describe('AllExceptionsFilter', () => {
  let filter: AllExceptionsFilter;
  let statusMock: jest.Mock;
  let jsonMock: jest.Mock;
  let response: any;
  let request: any;

  const makeHost = (): ArgumentsHost =>
    ({
      switchToHttp: () => ({
        getResponse: () => response,
        getRequest: () => request,
      }),
    }) as unknown as ArgumentsHost;

  beforeEach(() => {
    filter = new AllExceptionsFilter();
    // Silence the logger so test output stays clean.
    jest.spyOn((filter as any).logger, 'error').mockImplementation(() => undefined);
    jest.spyOn((filter as any).logger, 'warn').mockImplementation(() => undefined);

    jsonMock = jest.fn();
    statusMock = jest.fn(() => ({ json: jsonMock }));
    response = { status: statusMock };
    request = { url: '/auth/request-otp', method: 'POST' };
  });

  it('maps an HttpException to its status with a consistent envelope', () => {
    filter.catch(new NotFoundException('Booking not found'), makeHost());

    expect(statusMock).toHaveBeenCalledWith(HttpStatus.NOT_FOUND);
    const body = jsonMock.mock.calls[0][0];
    expect(body.statusCode).toBe(HttpStatus.NOT_FOUND);
    expect(body.message).toBe('Booking not found');
    expect(body.error).toBe('Not Found');
    expect(body.path).toBe('/auth/request-otp');
    expect(typeof body.timestamp).toBe('string');
  });

  it('preserves array messages (ValidationPipe shape)', () => {
    filter.catch(
      new BadRequestException(['phone must not be empty', 'otp is invalid']),
      makeHost(),
    );

    const body = jsonMock.mock.calls[0][0];
    expect(body.statusCode).toBe(HttpStatus.BAD_REQUEST);
    expect(body.message).toEqual(['phone must not be empty', 'otp is invalid']);
  });

  it('collapses unknown errors to a generic 500 without leaking the message', () => {
    filter.catch(new Error('secret db password in connection string'), makeHost());

    expect(statusMock).toHaveBeenCalledWith(HttpStatus.INTERNAL_SERVER_ERROR);
    const body = jsonMock.mock.calls[0][0];
    expect(body.statusCode).toBe(HttpStatus.INTERNAL_SERVER_ERROR);
    expect(body.message).toBe('Internal server error');
    expect(body.error).toBe('Internal Server Error');
    expect(JSON.stringify(body)).not.toContain('secret db password');
  });

  it('logs 5xx as error (with stack) and 4xx as warn (no stack)', () => {
    const errorSpy = (filter as any).logger.error as jest.Mock;
    const warnSpy = (filter as any).logger.warn as jest.Mock;

    filter.catch(new Error('boom'), makeHost());
    expect(errorSpy).toHaveBeenCalledTimes(1);
    expect(warnSpy).not.toHaveBeenCalled();

    errorSpy.mockClear();
    filter.catch(new BadRequestException('bad'), makeHost());
    expect(warnSpy).toHaveBeenCalledTimes(1);
    expect(errorSpy).not.toHaveBeenCalled();
  });

  it('maps a unique-violation (23505) to 409 Conflict without leaking SQL detail', () => {
    filter.catch(makeQueryFailedError('23505'), makeHost());

    expect(statusMock).toHaveBeenCalledWith(HttpStatus.CONFLICT);
    const body = jsonMock.mock.calls[0][0];
    expect(body.statusCode).toBe(HttpStatus.CONFLICT);
    expect(body.error).toBe('Conflict');
    expect(body.message).toBe('Resource already exists.');
    // The raw driver detail (the phone number / column name) must not leak.
    expect(JSON.stringify(body)).not.toContain('+15555550000');
    expect(JSON.stringify(body)).not.toContain('phone');
  });

  it('maps a foreign-key violation (23503) to 400 Bad Request', () => {
    filter.catch(makeQueryFailedError('23503'), makeHost());

    expect(statusMock).toHaveBeenCalledWith(HttpStatus.BAD_REQUEST);
    const body = jsonMock.mock.calls[0][0];
    expect(body.message).toBe('A referenced resource does not exist.');
  });

  it('maps a not-null violation (23502) to 400 Bad Request', () => {
    filter.catch(makeQueryFailedError('23502'), makeHost());

    expect(statusMock).toHaveBeenCalledWith(HttpStatus.BAD_REQUEST);
    const body = jsonMock.mock.calls[0][0];
    expect(body.message).toBe('A required field is missing.');
  });

  it('reads the code from driverError when not copied onto the QFE itself', () => {
    const driverError: any = new Error('duplicate key value violates unique constraint');
    driverError.code = '23505';
    const qfe = new QueryFailedError('INSERT ...', [], driverError);
    // Intentionally do NOT copy `.code` onto the QFE — only driverError has it.
    filter.catch(qfe, makeHost());

    expect(statusMock).toHaveBeenCalledWith(HttpStatus.CONFLICT);
    expect(jsonMock.mock.calls[0][0].message).toBe('Resource already exists.');
  });

  it('lets an unmapped DB constraint code collapse to a generic 500', () => {
    filter.catch(makeQueryFailedError('99999', 'some unexpected pg error'), makeHost());

    expect(statusMock).toHaveBeenCalledWith(HttpStatus.INTERNAL_SERVER_ERROR);
    const body = jsonMock.mock.calls[0][0];
    expect(body.message).toBe('Internal server error');
    expect(JSON.stringify(body)).not.toContain('some unexpected pg error');
  });
});
