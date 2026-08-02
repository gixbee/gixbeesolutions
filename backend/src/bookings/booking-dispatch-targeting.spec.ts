import { MAX_BROADCAST_FANOUT } from '../workers/workers.service';
import type { WorkerDto } from '../workers/workers.service';
import { selectBroadcastTargets } from './booking-dispatch-targeting';

const worker = (
  id: string,
  distance_km: number,
  languages?: string[],
  rating = 4,
): WorkerDto =>
  ({
    id,
    distance_km,
    languages,
    rating,
  }) as WorkerDto;

describe('selectBroadcastTargets', () => {
  it('filters languages case-insensitively while retaining unknown languages', () => {
    const targets = selectBroadcastTargets(
      [
        worker('hindi', 2, ['Hindi']),
        worker('english', 1, ['English']),
        worker('unknown', 3, []),
      ],
      ['HINDI'],
    );

    expect(targets.map(({ id }) => id)).toEqual(['hindi', 'unknown']);
  });

  it('sorts by distance, then rating for equal distances', () => {
    const targets = selectBroadcastTargets([
      worker('far', 5),
      worker('near-low', 1, undefined, 3),
      worker('near-high', 1, undefined, 5),
    ]);

    expect(targets.map(({ id }) => id)).toEqual([
      'near-high',
      'near-low',
      'far',
    ]);
  });

  it('caps the fan-out', () => {
    const nearby = Array.from(
      { length: MAX_BROADCAST_FANOUT + 3 },
      (_, index) => worker(`worker-${index}`, index),
    );

    expect(selectBroadcastTargets(nearby)).toHaveLength(MAX_BROADCAST_FANOUT);
  });
});
