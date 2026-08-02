import {
  MAX_BROADCAST_FANOUT,
  type WorkerDto,
} from '../workers/workers.service';

export function selectBroadcastTargets(
  nearby: WorkerDto[],
  preferredLanguages?: string[],
): WorkerDto[] {
  const wanted = (preferredLanguages ?? []).map((language) =>
    language.toLowerCase(),
  );
  const languageEligible =
    wanted.length === 0
      ? nearby
      : nearby.filter((worker) => {
          const spoken = (worker.languages ?? []).map((language) =>
            language.toLowerCase(),
          );
          return (
            spoken.length === 0 ||
            spoken.some((language) => wanted.includes(language))
          );
        });

  return [...languageEligible]
    .sort((a, b) => {
      const distance =
        (a.distance_km ?? Infinity) - (b.distance_km ?? Infinity);
      if (distance !== 0) return distance;
      return (b.rating || 0) - (a.rating || 0);
    })
    .slice(0, MAX_BROADCAST_FANOUT);
}
