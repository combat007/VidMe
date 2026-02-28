import ffmpeg from 'fluent-ffmpeg';

export const MIN_DURATION = 60;    // 1 minute
export const MAX_DURATION = 21600; // 6 hours

export function getVideoDuration(filePath: string): Promise<number> {
  return new Promise((resolve, reject) => {
    ffmpeg.ffprobe(filePath, (err, metadata) => {
      if (err) {
        reject(new Error(`Failed to probe video: ${err.message}`));
        return;
      }
      const duration = metadata.format.duration;
      if (duration === undefined || duration === null) {
        reject(new Error('Could not determine video duration'));
        return;
      }
      resolve(Math.round(duration));
    });
  });
}

export function validateDuration(duration: number): string | null {
  if (duration < MIN_DURATION) {
    return `Video must be at least ${MIN_DURATION} seconds (1 minute) long`;
  }
  if (duration > MAX_DURATION) {
    return `Video must be no longer than ${MAX_DURATION} seconds (6 hours)`;
  }
  return null;
}
